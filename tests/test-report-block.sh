#!/usr/bin/env bash

set -u
set -o pipefail
export LC_ALL=C

PROJECT_DIR=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/menu-teste-test-report-block.XXXXXXXX)
OUTPUT_FILE="$TEST_DIR/output.log"
PASSED=0
FAILED=0

cleanup() {
    if [[ ${MENU_TESTE_KEEP_TESTS:-0} == 1 ]]; then
        printf 'Artefatos preservados em: %s\n' "$TEST_DIR"
        return 0
    fi
    find "$TEST_DIR" -depth -type f -exec unlink {} \; 2>/dev/null || true
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

expect_timestamp_string() {
    local timestamp_line=$1
    local description=$2
    local timestamp_pattern

    timestamp_line=${timestamp_line#"${timestamp_line%%[![:space:]]*}"}
    timestamp_pattern='^Data/hora: ([01][0-9]|2[0-3]):[0-5][0-9] (0[1-9]|[12][0-9]|3[01])/(0[1-9]|1[0-2])/[0-9]{4}$'

    if [[ $timestamp_line =~ $timestamp_pattern ]]; then
        pass "$description"
    else
        fail "$description; linha recebida: ${timestamp_line:-ausente}"
    fi
}

expect_all_timestamps_strict() {
    local input_file=$1
    local expected_count=$2
    local description=$3
    local line
    local normalized
    local timestamp_pattern
    local count=0
    local invalid=0

    timestamp_pattern='^Data/hora: ([01][0-9]|2[0-3]):[0-5][0-9] (0[1-9]|[12][0-9]|3[01])/(0[1-9]|1[0-2])/[0-9]{4}$'
    while IFS= read -r line; do
        normalized=${line#"${line%%[![:space:]]*}"}
        [[ $normalized == 'Data/hora:'* ]] || continue
        ((count += 1))
        [[ $normalized =~ $timestamp_pattern ]] || invalid=1
    done < "$input_file"

    if ((count == expected_count && invalid == 0)); then
        pass "$description"
    else
        fail "$description; datas encontradas: $count, inválidas: $invalid"
    fi
}

expect_report_blocks_end_with_timestamp() {
    local input_file=$1
    local expected_count=$2
    local description=$3

    if awk -v expected="$expected_count" '
        BEGIN {
            pattern = "^Data/hora: ([01][0-9]|2[0-3]):[0-5][0-9] (0[1-9]|[12][0-9]|3[01])/(0[1-9]|1[0-2])/[0-9][0-9][0-9][0-9]$"
        }
        /^RESULTADO \[/ {
            if (inside && !timestamp_seen) invalid = 1
            inside = 1
            timestamp_seen = 0
            block_count += 1
            next
        }
        inside && /^Data\/hora:/ {
            if (timestamp_seen || $0 !~ pattern) invalid = 1
            timestamp_seen = 1
            next
        }
        inside && /^$/ {
            if (!timestamp_seen) invalid = 1
            inside = 0
            next
        }
        inside && timestamp_seen {
            invalid = 1
        }
        END {
            if (inside && !timestamp_seen) invalid = 1
            exit(invalid || block_count != expected)
        }
        ' "$input_file"; then
        pass "$description"
    else
        fail "$description"
    fi
}

expect_rejected_without_block() {
    local title=$1
    local description=$2
    shift 2

    local report_size_before
    local events_size_before
    local report_size_after
    local events_size_after
    local status=0

    report_size_before=$(wc -c < "$MT_REPORT_FILE")
    events_size_before=$(wc -c < "$MT_EVENTS_FILE")
    mt_report_result_block "$@" >> "$OUTPUT_FILE" 2>&1 || status=$?
    report_size_after=$(wc -c < "$MT_REPORT_FILE")
    events_size_after=$(wc -c < "$MT_EVENTS_FILE")

    if ((status == 2)); then
        pass "$description retorna código 2"
    else
        fail "$description deveria retornar 2; recebeu $status"
    fi
    if ((report_size_after == report_size_before &&
         events_size_after == events_size_before)) &&
       ! grep -Fq "$title" "$OUTPUT_FILE"; then
        pass "$description não deixa bloco parcial"
    else
        fail "$description alterou o relatório ou deixou bloco parcial"
    fi
}

mkdir -p "$TEST_DIR/reports" "$TEST_DIR/tmp"
: > "$OUTPUT_FILE"

export MENU_TESTE_REPORT_DIR="$TEST_DIR/reports"
export TMPDIR="$TEST_DIR/tmp"
export NO_COLOR=1

# shellcheck source=../lib/menu-teste/common.sh
source "$PROJECT_DIR/lib/menu-teste/common.sh"
# shellcheck source=../lib/menu-teste/report.sh
source "$PROJECT_DIR/lib/menu-teste/report.sh"

mt_report_init || {
    fail 'não foi possível iniciar o relatório de teste'
    printf '\nPassaram: %d | Falharam: %d\n' "$PASSED" "$FAILED"
    exit 1
}
trap 'mt_report_cleanup; cleanup' EXIT

success_title='Speedtest formatado'
if mt_report_result_block PASS "$success_title" \
    company 'Empresa/servidor' 'Operadora Externa' \
    server_id 'ID do servidor' '45678' \
    download 'Download' '1000.00 Mbps' \
    upload 'Upload' '500.00 Mbps' \
    packet_loss 'Perda de pacotes' '0%' \
    > "$OUTPUT_FILE" 2>&1; then
    pass 'bloco válido retorna sucesso'
else
    fail 'bloco válido retornou erro'
fi

expected_lines=$(
    printf '%s\n' \
        'Empresa/servidor: Operadora Externa' \
        'ID do servidor: 45678' \
        'Download: 1000.00 Mbps' \
        'Upload: 500.00 Mbps' \
        'Perda de pacotes: 0%'
)
actual_terminal_block=$(sed -n \
    '/^  Empresa\/servidor: /,/^  Data\/hora: /p' \
    "$OUTPUT_FILE" | sed 's/^  //')
actual_report_block=$(sed -n \
    '/^Empresa\/servidor: /,/^Data\/hora: /p' \
    "$MT_REPORT_FILE")
actual_terminal_timestamp=$(printf '%s\n' "$actual_terminal_block" |
    tail -n 1)
actual_report_timestamp=$(printf '%s\n' "$actual_report_block" |
    tail -n 1)
actual_terminal_lines=$(printf '%s\n' "$actual_terminal_block" |
    sed '$d')
actual_report_lines=$(printf '%s\n' "$actual_report_block" |
    sed '$d')

if [[ $actual_terminal_lines == "$expected_lines" ]]; then
    pass 'terminal preserva a ordem dos campos antes da data/hora'
else
    fail 'terminal não preservou a ordem esperada dos campos'
fi
if [[ $actual_report_lines == "$expected_lines" ]]; then
    pass 'TXT preserva a ordem dos campos antes da data/hora'
else
    fail 'TXT não preservou a ordem esperada dos campos'
fi
expect_timestamp_string "$actual_terminal_timestamp" \
    'terminal encerra o bloco com Data/hora em formato estrito'
expect_timestamp_string "$actual_report_timestamp" \
    'TXT encerra o bloco com Data/hora em formato estrito'

expect_rejected_without_block 'Titulo status invalido' \
    'status inválido' \
    INVALID 'Titulo status invalido' \
    company Empresa Operadora

expect_rejected_without_block 'Titulo chave invalida' \
    'chave inválida' \
    PASS 'Titulo chave invalida' \
    company Empresa Operadora \
    'Bad-Key' Download '100 Mbps'

expect_rejected_without_block 'Titulo chave duplicada' \
    'chave duplicada' \
    PASS 'Titulo chave duplicada' \
    company Empresa Operadora \
    company Servidor Externo

control_title=$'Titulo seguro\nLINHA FALSA TITULO\r\t\e[31m'
control_label=$'Empresa\nLINHA FALSA ROTULO'
control_value=$'Operadora\nStatus: FAIL\r\t\e[31m'
if mt_report_result_block PASS "$control_title" \
    company "$control_label" "$control_value" \
    >> "$OUTPUT_FILE" 2>&1; then
    pass 'bloco com controles é normalizado'
else
    fail 'bloco com controles deveria ser normalizado'
fi

if ! grep -Eq \
       '^(LINHA FALSA TITULO|LINHA FALSA ROTULO|Status: FAIL)$' \
       "$OUTPUT_FILE" "$MT_REPORT_FILE" &&
   ! LC_ALL=C grep -q $'[\r\t\033]' "$OUTPUT_FILE" "$MT_REPORT_FILE"; then
    pass 'LF, CR, TAB e ESC não criam linha falsa'
else
    fail 'um controle criou linha falsa ou permaneceu na saída'
fi

long_title=$(printf '%0300d' 0 | tr 0 T)
long_label=$(printf '%0200d' 0 | tr 0 L)
long_value=$(printf '%03000d' 0 | tr 0 V)
expected_title=${long_title:0:256}
expected_label=${long_label:0:128}
expected_value=${long_value:0:2048}

if mt_report_result_block INFO "$long_title" \
    limited "$long_label" "$long_value" \
    >> "$OUTPUT_FILE" 2>&1; then
    pass 'bloco aplica limites sem falhar'
else
    fail 'bloco com campos longos retornou erro'
fi

if grep -Fxq "RESULTADO [INFO] $expected_title" "$MT_REPORT_FILE" &&
   grep -Fxq "$expected_label: $expected_value" "$MT_REPORT_FILE" &&
   ! grep -Fq "${expected_title}T" "$MT_REPORT_FILE" &&
   jq -se --arg title "$expected_title" --arg value "$expected_value" \
       'any(.event == "measurement" and
            .title == $title and .values.limited == $value)' \
       "$MT_EVENTS_FILE" >/dev/null; then
    pass 'título, rótulo e valor respeitam os limites'
else
    fail 'os limites do bloco não foram respeitados'
fi

if jq -e . "$MT_EVENTS_FILE" >/dev/null 2>&1; then
    pass 'JSONL inteiro contém somente JSON válido'
else
    fail 'JSONL contém linha inválida'
fi

if jq -se --arg title "$success_title" \
       'any(.event == "measurement" and .title == $title and
            .values.company == "Operadora Externa" and
            .values.server_id == "45678" and
            .values.download == "1000.00 Mbps" and
            .values.upload == "500.00 Mbps" and
            .values.packet_loss == "0%")' \
       "$MT_EVENTS_FILE" >/dev/null; then
    pass 'JSONL contém o evento measurement completo'
else
    fail 'JSONL não contém o evento measurement esperado'
fi

if jq -se --arg title "$success_title" \
       'any(.event == "assessment" and .title == $title and
            .status == "PASS")' \
       "$MT_EVENTS_FILE" >/dev/null; then
    pass 'JSONL contém o evento assessment correspondente'
else
    fail 'JSONL não contém o evento assessment esperado'
fi

expect_all_timestamps_strict "$OUTPUT_FILE" 3 \
    'todos os blocos do terminal têm uma única Data/hora válida'
expect_all_timestamps_strict "$MT_REPORT_FILE" 3 \
    'todos os blocos do TXT têm uma única Data/hora válida'
expect_report_blocks_end_with_timestamp "$MT_REPORT_FILE" 3 \
    'Data/hora é o último campo de todos os blocos do TXT'

printf '\nPassaram: %d | Falharam: %d\n' "$PASSED" "$FAILED"
((FAILED == 0))
