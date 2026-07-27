#!/usr/bin/env python3

import errno
import hashlib
import os
import pty
import select
import shutil
import signal
import sys
import tempfile
import time
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent.parent
MENU_TESTE = PROJECT_DIR / "bin" / "menu-teste"
PASSED = 0
FAILED = 0


def passed(message):
    global PASSED
    PASSED += 1
    print(f"OK    {message}")


def failed(message):
    global FAILED
    FAILED += 1
    print(f"FALHA {message}", file=sys.stderr)


def read_available(fd, timeout):
    output = b""
    readable, _, _ = select.select([fd], [], [], timeout)
    if not readable:
        return output
    try:
        output = os.read(fd, 65536)
    except OSError as error:
        if error.errno != errno.EIO:
            raise
    return output


def wait_for_marker(fd, marker, deadline):
    output = b""
    while time.monotonic() < deadline:
        output += read_available(fd, 0.05)
        if marker in output:
            return True, output
    return False, output


def wait_for_child(pid, fd, initial_output, timeout=8):
    output = initial_output
    deadline = time.monotonic() + timeout
    status = None

    while time.monotonic() < deadline:
        output += read_available(fd, 0.05)
        completed_pid, child_status = os.waitpid(pid, os.WNOHANG)
        if completed_pid == pid:
            status = child_status
            break

    if status is None:
        try:
            os.killpg(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        time.sleep(0.2)
        completed_pid, child_status = os.waitpid(pid, os.WNOHANG)
        if completed_pid == 0:
            try:
                os.killpg(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            _, child_status = os.waitpid(pid, 0)
        status = child_status

    for _ in range(10):
        chunk = read_available(fd, 0.02)
        if not chunk:
            break
        output += chunk
    group_alive = False
    for _ in range(20):
        try:
            os.killpg(pid, 0)
            group_alive = True
        except ProcessLookupError:
            group_alive = False
            break
        time.sleep(0.025)

    os.close(fd)
    return (
        os.waitstatus_to_exitcode(status),
        output.decode("utf-8", errors="replace"),
        group_alive,
    )


def run_and_interrupt(case_dir, arguments, marker, path_prefix=None):
    reports_dir = case_dir / "reports"
    temp_dir = case_dir / "tmp"
    reports_dir.mkdir(parents=True)
    temp_dir.mkdir()

    environment = os.environ.copy()
    environment.update(
        {
            "NO_COLOR": "1",
            "TMPDIR": str(temp_dir),
            "MENU_TESTE_REPORT_DIR": str(reports_dir),
        }
    )
    if path_prefix:
        environment["PATH"] = f"{path_prefix}:/usr/bin:/bin"

    pid, fd = pty.fork()
    if pid == 0:
        os.execve(
            "/usr/bin/bash",
            ["bash", str(MENU_TESTE), *arguments],
            environment,
        )

    found, output = wait_for_marker(
        fd, marker.encode(), time.monotonic() + 5
    )
    if found:
        # Garante que o processo já entrou no prompt ou no comando indicado,
        # em vez de sinalizar no intervalo entre imprimir o marcador e esperar.
        time.sleep(0.05)
        os.write(fd, b"\x03")
    else:
        try:
            os.killpg(pid, signal.SIGINT)
        except ProcessLookupError:
            pass

    exit_code, complete_output, group_alive = wait_for_child(
        pid, fd, output
    )
    return found, exit_code, complete_output, group_alive


def check_session(case_dir, output, exit_code, group_alive, label):
    if exit_code == 130:
        passed(f"{label} encerra com código 130")
    else:
        failed(f"{label} deveria encerrar com 130; recebeu {exit_code}")

    cancel_message = (
        "Operação cancelada pelo operador. Encerrando o menu-teste."
    )
    message_count = output.count(cancel_message)
    if message_count == 1:
        passed(f"{label} mostra uma única mensagem de cancelamento")
    else:
        failed(f"{label} mostrou {message_count} mensagens de cancelamento")

    report_files = list((case_dir / "reports").glob("*.txt"))
    report_file = report_files[0] if len(report_files) == 1 else None
    report_text = (
        report_file.read_text(encoding="utf-8", errors="replace")
        if report_file
        else ""
    )
    if (
        "SESSÃO INTERROMPIDA PELO OPERADOR" in report_text
        and "Código: 130" in report_text
    ):
        passed(f"{label} registra a interrupção no relatório")
    else:
        failed(f"{label} não registrou corretamente a interrupção")

    event_files = list((case_dir / "reports").glob("*.jsonl"))
    event_text = (
        event_files[0].read_text(encoding="utf-8", errors="replace")
        if len(event_files) == 1
        else ""
    )
    if not event_text or '"event":"session_interrupted"' in event_text:
        passed(f"{label} registra o evento estruturado quando disponível")
    else:
        failed(f"{label} não registrou o evento estruturado")

    checksum_file = (
        Path(f"{report_file}.sha256") if report_file is not None else None
    )
    if checksum_file is not None and checksum_file.is_file() and report_file:
        expected_hash = checksum_file.read_text(
            encoding="utf-8", errors="replace"
        ).split()[0]
        actual_hash = hashlib.sha256(report_file.read_bytes()).hexdigest()
        if expected_hash == actual_hash:
            passed(f"{label} gera checksum final válido")
        else:
            failed(
                f"{label} gerou checksum final inválido "
                f"({expected_hash} != {actual_hash})"
            )
    else:
        failed(f"{label} não gerou checksum final")

    remaining_temp_dirs = list((case_dir / "tmp").glob("menu-teste.*"))
    if remaining_temp_dirs:
        failed(f"{label} deixou diretório temporário")
    else:
        passed(f"{label} remove os arquivos temporários")

    if group_alive:
        failed(f"{label} deixou processo do grupo em execução")
    else:
        passed(f"{label} encerra todo o grupo de processos")

    return report_text


def main():
    test_dir = Path(
        tempfile.mkdtemp(prefix="menu-teste-test-sigint.", dir="/tmp")
    )
    try:
        prompt_dir = test_dir / "prompt"
        found, exit_code, output, group_alive = run_and_interrupt(
            prompt_dir, [], "Escolha:"
        )
        if found:
            passed("Ctrl+C durante pergunta alcança o prompt")
        else:
            failed("Ctrl+C durante pergunta não alcançou o prompt")
        check_session(
            prompt_dir,
            output,
            exit_code,
            group_alive,
            "Ctrl+C durante pergunta",
        )

        active_dir = test_dir / "teste-ativo"
        fake_bin = active_dir / "bin"
        fake_bin.mkdir(parents=True)
        fake_ping = fake_bin / "ping"
        fake_ping.write_text(
            "#!/usr/bin/env bash\n"
            "trap 'exit 130' INT\n"
            "while true; do sleep 1; done\n",
            encoding="utf-8",
        )
        fake_ping.chmod(0o755)

        found, exit_code, output, group_alive = run_and_interrupt(
            active_dir,
            ["ping", "127.0.0.1", "4"],
            "== Ping: 127.0.0.1 ==",
            fake_bin,
        )
        if found:
            passed("Ctrl+C durante teste alcança o comando em execução")
        else:
            failed("Ctrl+C durante teste não alcançou o comando em execução")
        report_text = check_session(
            active_dir,
            output,
            exit_code,
            group_alive,
            "Ctrl+C durante teste",
        )
        if "Teste ativo: Ping: 127.0.0.1" in report_text:
            passed("Ctrl+C identifica o teste que estava ativo")
        else:
            failed("Ctrl+C não identificou o teste que estava ativo")
    finally:
        if os.environ.get("MENU_TESTE_KEEP_TESTS") == "1":
            print(f"Artefatos preservados em: {test_dir}")
        else:
            shutil.rmtree(test_dir, ignore_errors=True)

    print(f"\nPassaram: {PASSED} | Falharam: {FAILED}")
    return 0 if FAILED == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
