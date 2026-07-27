#!/usr/bin/env python3
"""Headless web speed-test runner used by menu-teste.

Only the ``fast`` provider is currently supported.  Successful execution writes
one canonical JSON object to stdout.  Human-readable progress and errors always
go to stderr so callers can safely parse stdout.

Fast.com does not publish a supported CLI/API.  This is intentionally marked as
an experimental web implementation because it reads the current Fast.com DOM.
"""

from __future__ import annotations

import inspect
import json
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


FAST_URL = "https://fast.com/"
PAGE_LOAD_TIMEOUT_SECONDS = 30
TEST_TIMEOUT_SECONDS = 180
POLL_INTERVAL_SECONDS = 0.25


class RunnerError(RuntimeError):
    """Expected failure that can be reported without a traceback."""


def _progress(message: str) -> None:
    print(f"Fast.com: {message}", file=sys.stderr, flush=True)


def _parse_number(value: str, field_name: str) -> float:
    """Parse a localized numeric value rendered by Fast.com."""

    normalized = value.strip().replace("\u00a0", "").replace(" ", "")
    match = re.search(r"[-+]?\d[\d.,]*", normalized)
    if match is None:
        raise RunnerError(f"campo {field_name!r} não contém um número válido")

    token = match.group(0)
    if "," in token and "." in token:
        # The rightmost punctuation is the decimal separator; the other one is
        # a thousands separator.
        if token.rfind(",") > token.rfind("."):
            token = token.replace(".", "").replace(",", ".")
        else:
            token = token.replace(",", "")
    elif "," in token:
        token = token.replace(",", ".")

    try:
        number = float(token)
    except ValueError as error:
        raise RunnerError(f"campo {field_name!r} não contém um número válido") from error

    if not math.isfinite(number) or number < 0:
        raise RunnerError(f"campo {field_name!r} contém um número inválido")
    return number


def _speed_to_mbps(value: str, unit: str, field_name: str) -> float:
    """Convert the Kbps/Mbps/Gbps units currently rendered by Fast.com."""

    number = _parse_number(value, field_name)
    factors = {
        "kbps": 0.001,
        "mbps": 1.0,
        "gbps": 1000.0,
    }
    normalized_unit = unit.strip().lower()
    try:
        converted = number * factors[normalized_unit]
    except KeyError as error:
        raise RunnerError(
            f"unidade inesperada em {field_name!r}: {unit.strip() or '(vazia)'}"
        ) from error
    return round(converted, 3)


def _clean_server(value: str) -> str:
    """Collapse DOM whitespace while preserving Fast.com's server separator."""

    return " ".join(value.replace("\u00a0", " ").split())


def _load_selenium() -> dict[str, Any]:
    """Import only the Selenium supplied by the operating system."""

    try:
        from selenium import webdriver
        from selenium.common.exceptions import (
            ElementClickInterceptedException,
            ElementNotInteractableException,
            NoSuchElementException,
            StaleElementReferenceException,
            TimeoutException,
        )
        from selenium.webdriver.chrome.options import Options
        from selenium.webdriver.chrome.service import Service
        from selenium.webdriver.common.by import By
    except ImportError as error:
        raise RunnerError(
            "Selenium não está disponível; instale o pacote Debian python3-selenium"
        ) from error

    return {
        "webdriver": webdriver,
        "ElementClickInterceptedException": ElementClickInterceptedException,
        "ElementNotInteractableException": ElementNotInteractableException,
        "NoSuchElementException": NoSuchElementException,
        "StaleElementReferenceException": StaleElementReferenceException,
        "TimeoutException": TimeoutException,
        "Options": Options,
        "Service": Service,
        "By": By,
    }


def _build_service(service_class: Any, driver_path: str) -> Any:
    """Create a quiet ChromeDriver service across Selenium 4.x versions."""

    parameters = inspect.signature(service_class.__init__).parameters
    if "log_output" in parameters:
        return service_class(
            executable_path=driver_path,
            log_output=subprocess.DEVNULL,
        )

    # Debian 12 currently carries Selenium 4.8, whose Service constructor calls
    # this argument ``log_path``.
    return service_class(
        executable_path=driver_path,
        log_path=os.devnull,
    )


def _read_text(driver: Any, by: Any, selector: str) -> str:
    return driver.find_element(by.CSS_SELECTOR, selector).text.strip()


def _has_class(driver: Any, by: Any, selector: str, class_name: str) -> bool:
    element = driver.find_element(by.CSS_SELECTOR, selector)
    classes = (element.get_attribute("class") or "").split()
    return class_name in classes


def _try_show_details(
    driver: Any,
    by: Any,
    ignored_exceptions: tuple[type[BaseException], ...],
) -> bool:
    """Reveal detailed metrics; on Fast.com this also ensures upload is run."""

    try:
        element = driver.find_element(by.CSS_SELECTOR, "#show-more-details-link")
        if element.is_displayed() and element.is_enabled():
            element.click()
            return True
    except ignored_exceptions:
        return False
    return False


def _wait_for_fast_result(
    driver: Any,
    by: Any,
    ignored_exceptions: tuple[type[BaseException], ...],
) -> None:
    deadline = time.monotonic() + TEST_TIMEOUT_SECONDS
    details_clicked = False

    while time.monotonic() < deadline:
        try:
            download_started = _parse_number(
                _read_text(driver, by, "#speed-value"),
                "download",
            ) > 0
            if download_started and not details_clicked:
                details_clicked = _try_show_details(
                    driver,
                    by,
                    ignored_exceptions,
                )

            download_done = _has_class(
                driver,
                by,
                "#speed-value",
                "succeeded",
            )
            upload_done = _has_class(
                driver,
                by,
                "#upload-value",
                "succeeded",
            )
            if download_done and upload_done:
                return
        except (RunnerError, *ignored_exceptions):
            # Fast.com updates these nodes while measuring.  A missing/stale
            # value during polling is expected; final extraction is strict.
            pass

        time.sleep(POLL_INTERVAL_SECONDS)

    raise RunnerError(
        f"o teste não terminou dentro de {TEST_TIMEOUT_SECONDS} segundos"
    )


def _extract_result(driver: Any, by: Any) -> dict[str, Any]:
    """Extract only the non-identifying fields accepted by our schema."""

    download_value = _read_text(driver, by, "#speed-value")
    download_unit = _read_text(driver, by, "#speed-units")
    upload_value = _read_text(driver, by, "#upload-value")
    upload_unit = _read_text(driver, by, "#upload-units")

    result = {
        "schema": 1,
        "provider": "fast.com",
        "implementation": "web-experimental",
        "download_mbps": _speed_to_mbps(
            download_value,
            download_unit,
            "download",
        ),
        "upload_mbps": _speed_to_mbps(
            upload_value,
            upload_unit,
            "upload",
        ),
        "latency_ms": round(
            _parse_number(
                _read_text(driver, by, "#latency-value"),
                "latência sem carga",
            ),
            3,
        ),
        "loaded_latency_ms": round(
            _parse_number(
                _read_text(driver, by, "#bufferbloat-value"),
                "latência com carga",
            ),
            3,
        ),
        "server": _clean_server(
            _read_text(driver, by, "#server-locations")
        ),
        "downloaded_mb": round(
            _parse_number(
                _read_text(driver, by, "#down-mb-value"),
                "volume baixado",
            ),
            3,
        ),
        "uploaded_mb": round(
            _parse_number(
                _read_text(driver, by, "#up-mb-value"),
                "volume enviado",
            ),
            3,
        ),
    }

    if not result["server"]:
        raise RunnerError("Fast.com não informou o servidor utilizado")
    return result


def _run_fast() -> dict[str, Any]:
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        raise RunnerError(
            "execute este teste como usuário sem privilégios para manter "
            "o sandbox do Chromium ativo"
        )

    selenium = _load_selenium()
    chromium_path = shutil.which("chromium")
    driver_path = shutil.which("chromedriver")
    if chromium_path is None:
        raise RunnerError("Chromium não encontrado; instale o pacote Debian chromium")
    if driver_path is None:
        raise RunnerError(
            "ChromeDriver não encontrado; instale o pacote Debian chromium-driver"
        )

    options = selenium["Options"]()
    options.binary_location = str(Path(chromium_path).resolve())
    options.add_argument("--headless=new")
    options.add_argument("--window-size=1280,900")
    options.add_argument("--lang=en-US")
    # The test loads remote JavaScript, so Chromium's process sandbox and
    # normal certificate validation must remain enabled.
    options.set_capability("acceptInsecureCerts", False)

    service = _build_service(selenium["Service"], driver_path)
    driver = None
    try:
        _progress("iniciando Chromium headless")
        driver = selenium["webdriver"].Chrome(service=service, options=options)
        driver.set_page_load_timeout(PAGE_LOAD_TIMEOUT_SECONDS)

        _progress("abrindo o site e iniciando a medição")
        try:
            driver.get(FAST_URL)
        except selenium["TimeoutException"] as error:
            raise RunnerError(
                f"Fast.com não carregou em {PAGE_LOAD_TIMEOUT_SECONDS} segundos"
            ) from error

        ignored_exceptions = (
            selenium["ElementClickInterceptedException"],
            selenium["ElementNotInteractableException"],
            selenium["NoSuchElementException"],
            selenium["StaleElementReferenceException"],
        )
        _progress("aguardando download, upload e latências")
        _wait_for_fast_result(
            driver,
            selenium["By"],
            ignored_exceptions,
        )
        result = _extract_result(driver, selenium["By"])
        _progress("medição concluída")
        return result
    finally:
        if driver is not None:
            try:
                driver.quit()
            except Exception as error:  # Browser cleanup must not corrupt stdout.
                _progress(f"aviso ao encerrar o Chromium: {error}")
        else:
            # If startup was interrupted after ChromeDriver spawned but before
            # WebDriver returned, there is no driver object to quit.
            try:
                service.stop()
            except Exception:
                pass


def _handle_termination(_signum: int, _frame: Any) -> None:
    """Turn SIGTERM into normal Python unwinding so finally calls driver.quit."""

    raise KeyboardInterrupt


def main(argv: list[str]) -> int:
    if argv != ["fast"]:
        print(
            "Uso: web_speedtest.py fast",
            file=sys.stderr,
            flush=True,
        )
        return 2

    signal.signal(signal.SIGTERM, _handle_termination)

    try:
        result = _run_fast()
    except KeyboardInterrupt:
        _progress("teste cancelado")
        return 130
    except RunnerError as error:
        _progress(f"erro: {error}")
        return 1
    except Exception as error:
        # Keep webdriver/library diagnostics out of stdout while still giving
        # the operator a concise failure reason.
        _progress(f"erro inesperado: {error}")
        return 1

    # Stable key order and compact separators make this a deterministic,
    # machine-readable single-line JSON document.
    print(
        json.dumps(
            result,
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        ),
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
