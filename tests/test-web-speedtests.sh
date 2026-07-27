#!/usr/bin/env bash

set -u
set -o pipefail
export LC_ALL=C

PROJECT_DIR=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/menu-teste-test-web-speedtests.XXXXXXXX)
FAKE_BIN="$TEST_DIR/bin"
FAKE_RUNNER="$FAKE_BIN/menu-teste-web-speedtest-fake"
ACTIVITY_LOG="$TEST_DIR/web-activity.log"
OUTPUT_FILE="$TEST_DIR/output.log"
MINHACONEXAO_OUTPUT="$TEST_DIR/minhaconexao.log"
PASSED=0
FAILED=0

cleanup() {
    if [[ ${MENU_TESTE_KEEP_TESTS:-0} == 1 ]]; then
        printf 'Artefatos preservados em: %s\n' "$TEST_DIR"
        return 0
    fi
    find "$TEST_DIR" -depth -type f -exec unlink {} \; 2>/dev/null || true
    find "$TEST_DIR" -depth -type l -exec unlink {} \; 2>/dev/null || true
    find "$TEST_DIR" -depth -type d -exec rmdir {} \; 2>/dev/null || true
}

pass() {
    printf 'OK    %s\n' "$1"
    ((PASSED += 1))
}

fail() {
    printf 'FALHA %s\n' "$1" >&2
    ((FAILED += 1))
}

activity_count() {
    wc -l < "$ACTIVITY_LOG"
}

expect_fast_failure() {
    local mode=$1
    local description=$2
    local calls_before
    local calls_after

    calls_before=$(activity_count)
    export WEB_SPEEDTEST_FAKE_MODE=$mode
    if mt_probe_fast <<< $'s\ns\ns' >> "$OUTPUT_FILE" 2>&1; then
        fail "$description deveria ser recusado"
    else
        pass "$description é recusado"
    fi
    calls_after=$(activity_count)
    if ((calls_after == calls_before + 1)); then
        pass "$description executa somente uma chamada ao runner falso"
    else
        fail "$description executou quantidade inesperada de processos"
    fi
}

expect_exact_line() {
    local input_file=$1
    local expected=$2
    local description=$3

    if awk -v expected="$expected" '
        {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (line == expected) found = 1
        }
        END { exit(found ? 0 : 1) }
        ' "$input_file"; then
        pass "$description"
    else
        fail "$description; linha ausente: $expected"
    fi
}

expect_ordered_labels() {
    local input_file=$1
    local description=$2
    shift 2

    local label
    local line_number
    local previous_line=0

    for label in "$@"; do
        line_number=$(awk -v prefix="$label: " \
            -v minimum="$previous_line" '
            {
                line = $0
                sub(/^[[:space:]]+/, "", line)
                if (NR > minimum && index(line, prefix) == 1) {
                    print NR
                    exit
                }
            }
            ' "$input_file")
        if [[ ! $line_number =~ ^[1-9][0-9]*$ ]]; then
            fail "$description; rótulo ausente: $label"
            return
        fi
        if ((line_number <= previous_line)); then
            fail "$description; rótulo fora de ordem: $label"
            return
        fi
        previous_line=$line_number
    done

    pass "$description"
}

expect_timestamp_after_label() {
    local input_file=$1
    local preceding_label=$2
    local description=$3
    local timestamp_line
    local timestamp_pattern

    timestamp_line=$(awk -v prefix="$preceding_label: " '
        {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (index(line, prefix) == 1) {
                if (getline next_line) {
                    sub(/^[[:space:]]+/, "", next_line)
                    print next_line
                }
                exit
            }
        }
        ' "$input_file")
    timestamp_pattern='^Data/hora: ([01][0-9]|2[0-3]):[0-5][0-9] (0[1-9]|[12][0-9]|3[01])/(0[1-9]|1[0-2])/[0-9]{4}$'

    if [[ $timestamp_line =~ $timestamp_pattern ]]; then
        pass "$description"
    else
        fail "$description; linha recebida: ${timestamp_line:-ausente}"
    fi
}

mkdir -p "$FAKE_BIN" "$TEST_DIR/reports" "$TEST_DIR/tmp"
: > "$ACTIVITY_LOG"
: > "$OUTPUT_FILE"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "runner" >> "$WEB_SPEEDTEST_FAKE_LOG"' \
    'for argument in "$@"; do' \
    '    printf "\t%s" "$argument" >> "$WEB_SPEEDTEST_FAKE_LOG"' \
    'done' \
    'printf "\n" >> "$WEB_SPEEDTEST_FAKE_LOG"' \
    'case ${WEB_SPEEDTEST_FAKE_MODE:-normal} in' \
    '    normal)' \
    '        printf "%s\n" "progresso simulado do Chromium" >&2' \
    '        printf "%s\n" '\''{"schema":1,"provider":"fast.com","implementation":"web-experimental","download_mbps":1000.25,"upload_mbps":500.5,"latency_ms":12.3,"loaded_latency_ms":34.5,"jitter_ms":null,"server":"Sao Paulo, BR","downloaded_mb":1234.5,"uploaded_mb":456.25}'\''' \
    '        ;;' \
    '    invalid-json)' \
    '        printf "%s\n" "<html>resultado indisponivel</html>"' \
    '        ;;' \
    '    incomplete)' \
    '        printf "%s\n" '\''{"schema":1,"provider":"fast.com","download_mbps":1000.25}'\''' \
    '        ;;' \
    '    absurd-range)' \
    '        printf "%s\n" '\''{"schema":1,"provider":"fast.com","implementation":"web-experimental","download_mbps":1000000001,"upload_mbps":-1,"latency_ms":9999999,"loaded_latency_ms":34.5,"jitter_ms":null,"server":"Sao Paulo, BR","downloaded_mb":1234.5,"uploaded_mb":456.25}'\''' \
    '        ;;' \
    '    exit7)' \
    '        printf "%s\n" "falha simulada do runner" >&2' \
    '        exit 7' \
    '        ;;' \
    '    *)' \
    '        printf "%s\n" "modo falso desconhecido" >&2' \
    '        exit 64' \
    '        ;;' \
    'esac' \
    > "$FAKE_RUNNER"
chmod 0755 "$FAKE_RUNNER"

# Estes comandos representam qualquer tentativa indevida de abrir navegador,
# acessar API ou iniciar outro medidor durante o teste informativo.
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s" "${0##*/}" >> "$WEB_SPEEDTEST_FAKE_LOG"' \
    'for argument in "$@"; do' \
    '    printf "\t%s" "$argument" >> "$WEB_SPEEDTEST_FAKE_LOG"' \
    'done' \
    'printf "\n" >> "$WEB_SPEEDTEST_FAKE_LOG"' \
    'exit 97' \
    > "$FAKE_BIN/blocked-web-command"
chmod 0755 "$FAKE_BIN/blocked-web-command"
for command_name in \
    curl wget chromium chromium-browser chromedriver xdg-open sensible-browser; do
    ln -s blocked-web-command "$FAKE_BIN/$command_name"
done

export PATH="$FAKE_BIN:/usr/bin:/bin"
export MENU_TESTE_TESTING=1
export MENU_TESTE_WEB_SPEEDTEST_RUNNER="$FAKE_RUNNER"
export WEB_SPEEDTEST_FAKE_LOG="$ACTIVITY_LOG"
export MENU_TESTE_REPORT_DIR="$TEST_DIR/reports"
export TMPDIR="$TEST_DIR/tmp"
export NO_COLOR=1

source "$PROJECT_DIR/lib/menu-teste/validate.sh"
source "$PROJECT_DIR/lib/menu-teste/common.sh"
source "$PROJECT_DIR/lib/menu-teste/report.sh"
source "$PROJECT_DIR/lib/menu-teste/probes.sh"

mt_report_init || {
    fail 'não foi possível iniciar o relatório de teste'
    printf '\nPassaram: %d | Falharam: %d\n' "$PASSED" "$FAILED"
    exit 1
}
trap 'mt_report_cleanup; cleanup' EXIT

missing_contract=0
if ! declare -F mt_probe_fast >/dev/null 2>&1; then
    fail 'função contratual mt_probe_fast ainda não foi implementada'
    missing_contract=1
fi
if ! declare -F mt_probe_minhaconexao_info >/dev/null 2>&1; then
    fail 'função contratual mt_probe_minhaconexao_info ainda não foi implementada'
    missing_contract=1
fi
if ((missing_contract == 1)); then
    printf '\nPassaram: %d | Falharam: %d\n' "$PASSED" "$FAILED"
    exit 1
fi

export WEB_SPEEDTEST_FAKE_MODE=normal
if mt_probe_fast <<< $'s\ns\ns' > "$OUTPUT_FILE" 2>&1; then
    pass 'Fast aceita o resultado JSON canônico simulado'
else
    fail 'Fast recusou o resultado JSON canônico simulado'
fi
if (( $(activity_count) == 1 )); then
    pass 'Fast executa uma única chamada ao runner no caso de sucesso'
else
    fail 'Fast executou quantidade inesperada de processos no caso de sucesso'
fi
if grep -Fq '"provider":"fast.com"' "$OUTPUT_FILE" &&
   grep -Fq '"download_mbps":1000.25' "$OUTPUT_FILE" &&
   grep -Fq '"upload_mbps":500.5' "$OUTPUT_FILE"; then
    pass 'saída do Fast preserva provedor, download e upload canônicos'
else
    fail 'saída do Fast não contém todas as métricas canônicas'
fi
expect_ordered_labels "$OUTPUT_FILE" \
    'resultado Fast apresenta empresa/servidor antes das métricas, uma por linha' \
    'Empresa/serviço' \
    'Servidor(es)' \
    'Seleção do servidor' \
    'Download' \
    'Upload' \
    'Perda de pacotes' \
    'Latência sem carga' \
    'Latência com carga' \
    'Diferença (bufferbloat)' \
    'Dados recebidos' \
    'Dados enviados' \
    'Observação' \
    'Data/hora'
expect_timestamp_after_label "$OUTPUT_FILE" 'Observação' \
    'resultado Fast termina com Data/hora no formato HH:MM DD/MM/AAAA'
expect_exact_line "$OUTPUT_FILE" \
    'Empresa/serviço: Netflix / Fast.com' \
    'resultado Fast identifica a empresa/serviço'
expect_exact_line "$OUTPUT_FILE" \
    'Servidor(es): Sao Paulo, BR' \
    'resultado Fast identifica os servidores informados'
expect_exact_line "$OUTPUT_FILE" \
    'Download: 1000.25 Mbps' \
    'resultado Fast mostra download em linha própria'
expect_exact_line "$OUTPUT_FILE" \
    'Upload: 500.5 Mbps' \
    'resultado Fast mostra upload em linha própria'
expect_exact_line "$OUTPUT_FILE" \
    'Perda de pacotes: Não informada pelo Fast.com' \
    'resultado Fast explicita a indisponibilidade da perda'
expect_exact_line "$OUTPUT_FILE" \
    'Latência sem carga: 12.3 ms' \
    'resultado Fast mostra latência sem carga em linha própria'
expect_exact_line "$OUTPUT_FILE" \
    'Latência com carga: 34.5 ms' \
    'resultado Fast mostra latência com carga em linha própria'
expect_exact_line "$OUTPUT_FILE" \
    'Diferença (bufferbloat): 22.20 ms' \
    'resultado Fast mostra bufferbloat em linha própria'

calls_before=$(activity_count)
if mt_probe_fast <<< 'n' >> "$OUTPUT_FILE" 2>&1; then
    pass 'recusa do Fast retorna normalmente'
else
    fail 'recusa do Fast deveria retornar normalmente'
fi
calls_after=$(activity_count)
if ((calls_after == calls_before)); then
    pass 'recusa do Fast não chama runner, navegador nem API'
else
    fail 'recusa do Fast iniciou atividade externa'
fi

expect_fast_failure invalid-json 'JSON inválido do Fast'
expect_fast_failure incomplete 'JSON incompleto do Fast'
expect_fast_failure absurd-range 'resultado fora da faixa do Fast'
expect_fast_failure exit7 'erro 7 do runner Fast'
unset WEB_SPEEDTEST_FAKE_MODE

calls_before=$(activity_count)
if mt_probe_minhaconexao_info > "$MINHACONEXAO_OUTPUT" 2>&1; then
    pass 'informação do Minha Conexão retorna normalmente'
else
    fail 'informação do Minha Conexão retornou erro'
fi
calls_after=$(activity_count)
if ((calls_after == calls_before)); then
    pass 'Minha Conexão não inicia medição, navegador nem chamada de API'
else
    fail 'Minha Conexão iniciou atividade externa indevida'
fi
if grep -Fq 'https://www.minhaconexao.com.br/' "$MINHACONEXAO_OUTPUT"; then
    pass 'Minha Conexão mostra a URL oficial'
else
    fail 'Minha Conexão não mostrou a URL oficial'
fi
if grep -Eiq 'navegador' "$MINHACONEXAO_OUTPUT"; then
    pass 'Minha Conexão explica que o teste exige navegador'
else
    fail 'Minha Conexão não informou a necessidade de navegador'
fi

report_file=$MT_REPORT_FILE
expect_ordered_labels "$report_file" \
    'relatório TXT preserva o bloco Fast linha por linha e na ordem contratada' \
    'Empresa/serviço' \
    'Servidor(es)' \
    'Seleção do servidor' \
    'Download' \
    'Upload' \
    'Perda de pacotes' \
    'Latência sem carga' \
    'Latência com carga' \
    'Diferença (bufferbloat)' \
    'Dados recebidos' \
    'Dados enviados' \
    'Observação' \
    'Data/hora'
expect_timestamp_after_label "$report_file" 'Observação' \
    'relatório TXT Fast termina com Data/hora após a observação'

if jq -e -s \
    'length > 0 and all(.[]; type == "object")' \
    "$MT_EVENTS_FILE" >/dev/null 2>&1; then
    pass 'JSONL Fast permanece composto por um objeto JSON válido por linha'
else
    fail 'JSONL Fast contém linha inválida ou deixou de ser JSONL'
fi

if jq -e -s '
    any(.[];
        .event == "measurement" and
        .title == "Fast.com - automático (web experimental)" and
        (.values | keys) ==
            (["company", "servers", "selection", "download", "upload",
              "packet_loss", "unloaded_latency", "loaded_latency",
              "bufferbloat", "downloaded_data", "uploaded_data",
              "observation"] | sort) and
        .values.company == "Netflix / Fast.com" and
        .values.servers == "Sao Paulo, BR" and
        .values.selection == "Automática pelo Fast.com" and
        .values.download == "1000.25 Mbps" and
        .values.upload == "500.5 Mbps" and
        .values.packet_loss == "Não informada pelo Fast.com" and
        .values.unloaded_latency == "12.3 ms" and
        .values.loaded_latency == "34.5 ms" and
        .values.bufferbloat == "22.20 ms" and
        .values.downloaded_data == "1234.5 MB" and
        .values.uploaded_data == "456.25 MB" and
        (.values.observation | type == "string" and length > 0))
    ' "$MT_EVENTS_FILE" >/dev/null 2>&1; then
    pass 'JSONL Fast registra o evento measurement com os valores apresentados'
else
    fail 'JSONL Fast não preservou o contrato do evento measurement'
fi

if jq -e -s '
    any(.[];
        .event == "assessment" and
        .title == "Fast.com - automático (web experimental)" and
        .status == "PASS")
    ' "$MT_EVENTS_FILE" >/dev/null 2>&1; then
    pass 'evento assessment Fast continua disponível no JSONL'
else
    fail 'evento assessment Fast deixou de ser registrado no JSONL'
fi

printf '\nPassaram: %d | Falharam: %d\n' "$PASSED" "$FAILED"
((FAILED == 0))
