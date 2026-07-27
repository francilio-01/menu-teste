#!/usr/bin/env bash

set -u
set -o pipefail

PROJECT_DIR=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/menu-teste-test-speedtest.XXXXXXXX)
FAKE_BIN="$TEST_DIR/bin"
FAKE_LOG="$TEST_DIR/speedtest-args.log"
OUTPUT_FILE="$TEST_DIR/output.log"
OOKLA_RESULT_OUTPUT="$TEST_DIR/ookla-result.log"
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

trap cleanup EXIT

pass() {
    printf 'OK    %s\n' "$1"
    ((PASSED += 1))
}

fail() {
    printf 'FALHA %s\n' "$1" >&2
    ((FAILED += 1))
}

expect_log_line() {
    local line_number=$1
    local pattern=$2
    local description=$3
    local line

    line=$(sed -n "${line_number}p" "$FAKE_LOG")
    if [[ $line == *"$pattern"* ]]; then
        pass "$description"
    else
        fail "$description; linha recebida: $line"
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
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'server_id=45678' \
    'server_host=externo.speedtest.exemplo' \
    'packet_loss=0' \
    'printf "CALL" >> "$SPEEDTEST_FAKE_LOG"' \
    'for argument in "$@"; do' \
    '    printf "\t%s" "$argument" >> "$SPEEDTEST_FAKE_LOG"' \
    '    case $argument in' \
    '        --server-id=*) server_id=${argument#*=} ;;' \
    '        --host=*) server_host=${argument#*=} ;;' \
    '    esac' \
    'done' \
    'printf "\n" >> "$SPEEDTEST_FAKE_LOG"' \
    'case " $* " in' \
    '    *" --servers "*)' \
    '        if [[ ${SPEEDTEST_FAKE_MODE:-normal} == empty-list ]]; then' \
    '            printf "%s\n" "{\"type\":\"serverList\",\"servers\":[]}"' \
    '        else' \
    '            printf "%s\n" "{\"type\":\"serverList\",\"servers\":[{\"id\":45678,\"host\":\"externo.speedtest.exemplo\",\"port\":8080,\"name\":\"Operadora Externa\",\"location\":\"Outra Cidade\",\"country\":\"Brasil\"}]}"' \
    '        fi' \
    '        ;;' \
    '    *)' \
    '        case ${SPEEDTEST_FAKE_MODE:-normal} in' \
    '            incomplete)' \
    '                printf "%s\n" "{\"type\":\"result\",\"packetLoss\":0,\"server\":{\"id\":$server_id,\"host\":\"$server_host\"}}"' \
    '                exit 0' \
    '                ;;' \
    '            mismatch-id) server_id=99999 ;;' \
    '            positive-loss) packet_loss=1.5 ;;' \
    '            error) exit 7 ;;' \
    '        esac' \
    '        printf "%s\n" "{\"type\":\"result\",\"packetLoss\":$packet_loss,\"ping\":{\"latency\":12.34,\"jitter\":1.23},\"download\":{\"bandwidth\":125000000},\"upload\":{\"bandwidth\":62500000},\"server\":{\"id\":$server_id,\"host\":\"$server_host\",\"name\":\"Operadora Externa\",\"location\":\"Outra Cidade\",\"country\":\"Brasil\"}}"' \
    '        ;;' \
    'esac' \
    > "$FAKE_BIN/speedtest"
chmod 0755 "$FAKE_BIN/speedtest"

export PATH="$FAKE_BIN:/usr/bin:/bin"
export SPEEDTEST_FAKE_LOG="$FAKE_LOG"
export MENU_TESTE_REPORT_DIR="$TEST_DIR/reports"
export TMPDIR="$TEST_DIR/tmp"
export NO_COLOR=1

source "$PROJECT_DIR/lib/menu-teste/validate.sh"
source "$PROJECT_DIR/lib/menu-teste/common.sh"
source "$PROJECT_DIR/lib/menu-teste/report.sh"
source "$PROJECT_DIR/lib/menu-teste/probes.sh"

mt_report_init || {
    fail 'não foi possível iniciar o relatório de teste'
    exit 1
}
trap 'mt_report_cleanup; cleanup' EXIT

if mt_probe_speedtest_servers <<< 's' > "$OUTPUT_FILE" 2>&1; then
    pass 'lista de servidores conclui sem medir banda'
else
    fail 'lista de servidores falhou'
fi

if mt_probe_speedtest auto <<< 's' > "$OOKLA_RESULT_OUTPUT" 2>&1; then
    pass 'Speedtest automático conclui com resultado simulado'
else
    fail 'Speedtest automático falhou'
fi

expect_ordered_labels "$OOKLA_RESULT_OUTPUT" \
    'resultado Ookla apresenta identificação antes das métricas, uma por linha' \
    'Empresa/servidor' \
    'ID do servidor' \
    'Hostname' \
    'Localização' \
    'Seleção solicitada' \
    'Download' \
    'Upload' \
    'Perda de pacotes' \
    'Latência (ping)' \
    'Jitter' \
    'Observação' \
    'Data/hora'
expect_timestamp_after_label "$OOKLA_RESULT_OUTPUT" 'Observação' \
    'resultado Ookla termina com Data/hora no formato HH:MM DD/MM/AAAA'
expect_exact_line "$OOKLA_RESULT_OUTPUT" \
    'Empresa/servidor: Operadora Externa' \
    'resultado Ookla identifica a empresa/servidor'
expect_exact_line "$OOKLA_RESULT_OUTPUT" \
    'ID do servidor: 45678' \
    'resultado Ookla identifica o ID do servidor'
expect_exact_line "$OOKLA_RESULT_OUTPUT" \
    'Download: 1000.00 Mbps' \
    'resultado Ookla mostra download em linha própria'
expect_exact_line "$OOKLA_RESULT_OUTPUT" \
    'Upload: 500.00 Mbps' \
    'resultado Ookla mostra upload em linha própria'
expect_exact_line "$OOKLA_RESULT_OUTPUT" \
    'Perda de pacotes: 0%' \
    'resultado Ookla mostra perda em linha própria'
expect_exact_line "$OOKLA_RESULT_OUTPUT" \
    'Latência (ping): 12.34 ms' \
    'resultado Ookla mostra latência em linha própria'
expect_exact_line "$OOKLA_RESULT_OUTPUT" \
    'Jitter: 1.23 ms' \
    'resultado Ookla mostra jitter em linha própria'

if mt_probe_speedtest id 12345 <<< 's' >> "$OUTPUT_FILE" 2>&1; then
    pass 'Speedtest por ID conclui com resultado simulado'
else
    fail 'Speedtest por ID falhou'
fi

if mt_probe_speedtest host fora.speedtest.exemplo \
    <<< 's' >> "$OUTPUT_FILE" 2>&1; then
    pass 'Speedtest por hostname conclui com resultado simulado'
else
    fail 'Speedtest por hostname falhou'
fi

calls_before=$(wc -l < "$FAKE_LOG")
if mt_probe_speedtest id '123;id' \
    <<< 's' >> "$OUTPUT_FILE" 2>&1; then
    fail 'seleção deveria recusar ID malicioso'
else
    pass 'seleção recusa ID malicioso'
fi
calls_after=$(wc -l < "$FAKE_LOG")
if ((calls_before == calls_after)); then
    pass 'ID inválido não executa o binário Speedtest'
else
    fail 'ID inválido chegou ao binário Speedtest'
fi

calls_before=$(wc -l < "$FAKE_LOG")
if mt_probe_speedtest host 'host.exemplo.net;id' \
    <<< 's' >> "$OUTPUT_FILE" 2>&1; then
    fail 'seleção deveria recusar hostname malicioso'
else
    pass 'seleção recusa hostname malicioso'
fi
calls_after=$(wc -l < "$FAKE_LOG")
if ((calls_before == calls_after)); then
    pass 'hostname inválido não executa o binário Speedtest'
else
    fail 'hostname inválido chegou ao binário Speedtest'
fi

calls_before=$(wc -l < "$FAKE_LOG")
if mt_probe_speedtest id 12345 \
    <<< 'n' >> "$OUTPUT_FILE" 2>&1; then
    pass 'cancelamento do Speedtest retorna normalmente'
else
    fail 'cancelamento do Speedtest retornou erro'
fi
calls_after=$(wc -l < "$FAKE_LOG")
if ((calls_before == calls_after)); then
    pass 'cancelamento não inicia medição'
else
    fail 'cancelamento iniciou o binário Speedtest'
fi

expect_log_line 1 $'--servers' \
    'listagem usa a opção oficial --servers'
expect_log_line 1 $'--format=json' \
    'listagem solicita dados estruturados com hostname'
expect_log_line 2 $'--format=json' \
    'modo automático solicita saída JSON'
expect_log_line 3 $'--server-id=12345' \
    'seleção por ID passa somente o ID validado'
expect_log_line 4 $'--host=fora.speedtest.exemplo' \
    'seleção por hostname passa somente o hostname validado'

if printf 's\n' |
   "$PROJECT_DIR/bin/menu-teste" speedtest 24680 \
       >> "$OUTPUT_FILE" 2>&1; then
    pass 'comando não interativo aceita um ID de servidor'
else
    fail 'comando não interativo falhou ao usar um ID'
fi
expect_log_line 5 $'--server-id=24680' \
    'comando não interativo encaminha o ID validado'

export SPEEDTEST_FAKE_MODE=incomplete
if mt_probe_speedtest auto <<< 's' >> "$OUTPUT_FILE" 2>&1; then
    fail 'resultado JSON incompleto deveria ser recusado'
else
    pass 'resultado JSON incompleto é recusado'
fi

export SPEEDTEST_FAKE_MODE=mismatch-id
if mt_probe_speedtest id 12345 <<< 's' >> "$OUTPUT_FILE" 2>&1; then
    fail 'servidor diferente do ID solicitado deveria gerar alerta'
else
    pass 'divergência entre ID solicitado e usado é detectada'
fi

export SPEEDTEST_FAKE_MODE=positive-loss
if mt_probe_speedtest auto <<< 's' >> "$OUTPUT_FILE" 2>&1; then
    fail 'perda positiva deveria retornar alerta'
else
    pass 'perda positiva é registrada como alerta'
fi

export SPEEDTEST_FAKE_MODE=empty-list
if mt_probe_speedtest_servers <<< 's' >> "$OUTPUT_FILE" 2>&1; then
    fail 'lista vazia deveria retornar alerta'
else
    pass 'lista vazia de servidores é detectada'
fi
unset SPEEDTEST_FAKE_MODE

report_file=$MT_REPORT_FILE
if [[ -n $report_file ]] &&
   grep -Fq 'ID do servidor: 12345' "$report_file" &&
   grep -Fq 'Hostname: fora.speedtest.exemplo' "$report_file" &&
   grep -Fq 'Hostname: externo.speedtest.exemplo' "$report_file" &&
   grep -Fq 'Download: 1000.00 Mbps' "$report_file" &&
   grep -Fq 'Upload: 500.00 Mbps' "$report_file"; then
    pass 'relatório registra seleção, servidor e velocidades em linhas próprias'
else
    fail 'relatório não registrou todos os dados do servidor selecionado'
fi

expect_ordered_labels "$report_file" \
    'relatório TXT preserva o bloco Ookla linha por linha e na ordem contratada' \
    'Empresa/servidor' \
    'ID do servidor' \
    'Hostname' \
    'Localização' \
    'Seleção solicitada' \
    'Download' \
    'Upload' \
    'Perda de pacotes' \
    'Latência (ping)' \
    'Jitter' \
    'Observação' \
    'Data/hora'
expect_timestamp_after_label "$report_file" 'Observação' \
    'relatório TXT Ookla termina com Data/hora após a observação'

if jq -e -s \
    'length > 0 and all(.[]; type == "object")' \
    "$MT_EVENTS_FILE" >/dev/null 2>&1; then
    pass 'JSONL Ookla permanece composto por um objeto JSON válido por linha'
else
    fail 'JSONL Ookla contém linha inválida ou deixou de ser JSONL'
fi

if jq -e -s '
    any(.[];
        .event == "measurement" and
        .title == "Speedtest Ookla - automático" and
        (.values | keys) ==
            (["company", "server_id", "server_hostname",
              "server_location", "selection", "download", "upload",
              "packet_loss", "latency", "jitter", "observation"] |
             sort) and
        .values.company == "Operadora Externa" and
        .values.server_id == "45678" and
        .values.server_hostname == "externo.speedtest.exemplo" and
        .values.server_location == "Outra Cidade / Brasil" and
        .values.selection == "seleção automática" and
        .values.download == "1000.00 Mbps" and
        .values.upload == "500.00 Mbps" and
        .values.packet_loss == "0%" and
        .values.latency == "12.34 ms" and
        .values.jitter == "1.23 ms" and
        (.values.observation | type == "string" and length > 0))
    ' "$MT_EVENTS_FILE" >/dev/null 2>&1; then
    pass 'JSONL Ookla registra o evento measurement com os valores apresentados'
else
    fail 'JSONL Ookla não preservou o contrato do evento measurement'
fi

if jq -e -s '
    any(.[];
        .event == "assessment" and
        .title == "Speedtest Ookla - automático" and
        .status == "PASS")
    ' "$MT_EVENTS_FILE" >/dev/null 2>&1; then
    pass 'evento assessment Ookla continua disponível no JSONL'
else
    fail 'evento assessment Ookla deixou de ser registrado no JSONL'
fi

printf '\nPassaram: %d | Falharam: %d\n' "$PASSED" "$FAILED"
((FAILED == 0))
