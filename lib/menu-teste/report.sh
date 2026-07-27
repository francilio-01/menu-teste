#!/usr/bin/env bash

# Sessões, execução limitada e relatórios.

MT_REPORT_DIR=
MT_REPORT_FILE=
MT_EVENTS_FILE=
MT_SESSION_ID=
MT_TEMP_DIR=
MT_LAST_OUTPUT_FILE=
MT_LAST_EXIT_CODE=0
MT_ACTIVE_TEST_TITLE=
MT_ACTIVE_TEST_COMMAND=
MT_ACTIVE_PROCESS_PID=
MT_REPORT_INTERRUPTED=0

mt_report_base_dir() {
    if [[ -n ${MENU_TESTE_REPORT_DIR:-} ]]; then
        printf '%s\n' "$MENU_TESTE_REPORT_DIR"
    elif [[ -n ${XDG_STATE_HOME:-} ]]; then
        printf '%s/menu-teste/relatorios\n' "$XDG_STATE_HOME"
    elif [[ -n ${HOME:-} ]]; then
        printf '%s/.local/state/menu-teste/relatorios\n' "$HOME"
    else
        printf '/tmp/menu-teste-%s/relatorios\n' "${UID:-desconhecido}"
    fi
}

mt_report_init() {
    local hostname_short
    local os_name=desconhecido

    umask 077
    MT_ACTIVE_TEST_TITLE=
    MT_ACTIVE_TEST_COMMAND=
    MT_ACTIVE_PROCESS_PID=
    MT_REPORT_INTERRUPTED=0
    MT_REPORT_DIR=$(mt_report_base_dir)
    if ! mkdir -p -- "$MT_REPORT_DIR" 2>/dev/null; then
        MT_REPORT_DIR="/tmp/menu-teste-${UID:-desconhecido}/relatorios"
        mkdir -p -- "$MT_REPORT_DIR" || {
            mt_error 'Não foi possível criar o diretório de relatórios.'
            return 1
        }
        mt_warn "Usando diretório temporário: $MT_REPORT_DIR"
    fi
    chmod 0700 -- "$MT_REPORT_DIR" 2>/dev/null || true

    hostname_short=$(hostname -s 2>/dev/null || printf desconhecido)
    hostname_short=${hostname_short//[^A-Za-z0-9_.-]/_}
    MT_SESSION_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
    MT_REPORT_FILE="$MT_REPORT_DIR/${hostname_short}-${MT_SESSION_ID}.txt"
    MT_EVENTS_FILE="$MT_REPORT_DIR/${hostname_short}-${MT_SESSION_ID}.jsonl"
    MT_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/menu-teste.XXXXXXXX") || return 1
    chmod 0700 -- "$MT_TEMP_DIR"

    if [[ -r /etc/os-release ]]; then
        os_name=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | head -n 1)
        os_name=${os_name%\"}
        os_name=${os_name#\"}
    fi

    {
        printf 'menu-teste v%s\n' "$MT_VERSION"
        printf 'Sessão: %s\n' "$MT_SESSION_ID"
        printf 'Início: %s\n' "$(date --iso-8601=seconds)"
        printf 'Início UTC: %s\n' "$(date -u --iso-8601=seconds)"
        printf 'Hostname: %s\n' "$hostname_short"
        printf 'Usuário: %s\n' "$(id -un 2>/dev/null || printf desconhecido)"
        printf 'Sistema: %s\n' "$os_name"
        printf 'Kernel: %s\n' "$(uname -srmo 2>/dev/null || printf desconhecido)"
        printf '%s\n' \
            'Nota: o status de execução e a avaliação do protocolo são registrados separadamente.'
    } > "$MT_REPORT_FILE"
    chmod 0600 -- "$MT_REPORT_FILE"

    if mt_command_available jq; then
        jq -cn \
            --arg event session_start \
            --arg session "$MT_SESSION_ID" \
            --arg timestamp "$(date --iso-8601=seconds)" \
            --arg version "$MT_VERSION" \
            --arg hostname "$hostname_short" \
            --arg user "$(id -un 2>/dev/null || printf desconhecido)" \
            '{event:$event, session:$session, timestamp:$timestamp,
              version:$version, hostname:$hostname, user:$user}' \
            > "$MT_EVENTS_FILE"
        chmod 0600 -- "$MT_EVENTS_FILE"
    else
        : > "$MT_EVENTS_FILE"
        chmod 0600 -- "$MT_EVENTS_FILE"
    fi
}

mt_report_cleanup() {
    if [[ -n ${MT_TEMP_DIR:-} && -d $MT_TEMP_DIR ]]; then
        rm -rf -- "$MT_TEMP_DIR" || true
    fi
    MT_TEMP_DIR=
    return 0
}

mt_report_interruption() {
    local timestamp

    ((MT_REPORT_INTERRUPTED == 0)) || return 0
    MT_REPORT_INTERRUPTED=1
    [[ -n ${MT_REPORT_FILE:-} && -f $MT_REPORT_FILE ]] || return 0

    timestamp=$(date --iso-8601=seconds)
    {
        printf '\nSESSÃO INTERROMPIDA PELO OPERADOR\n'
        printf 'Horário: %s\n' "$timestamp"
        if [[ -n ${MT_ACTIVE_TEST_TITLE:-} ]]; then
            printf 'Teste ativo: %s\n' "$MT_ACTIVE_TEST_TITLE"
        fi
        if [[ -n ${MT_ACTIVE_TEST_COMMAND:-} ]]; then
            printf 'Comando ativo: %s\n' "$MT_ACTIVE_TEST_COMMAND"
        fi
        printf 'Status: INTERRUPTED\n'
        printf 'Código: 130\n'
    } >> "$MT_REPORT_FILE"

    if mt_command_available jq &&
       [[ -n ${MT_EVENTS_FILE:-} && -f $MT_EVENTS_FILE ]]; then
        jq -cn \
            --arg event session_interrupted \
            --arg session "$MT_SESSION_ID" \
            --arg timestamp "$timestamp" \
            --arg active_test "${MT_ACTIVE_TEST_TITLE:-}" \
            --arg active_command "${MT_ACTIVE_TEST_COMMAND:-}" \
            --argjson exit_code 130 \
            '{event:$event, session:$session, timestamp:$timestamp,
              active_test:$active_test, active_command:$active_command,
              exit_code:$exit_code}' \
            >> "$MT_EVENTS_FILE"
    fi
}

mt_sanitize_output() {
    local input_file=$1
    local output_file=$2

    sed $'s/\033\\[[0-9;?]*[ -\\/]*[@-~]//g' "$input_file" |
        LC_ALL=C tr -d '\000-\010\013\014\016-\037\177' > "$output_file"
}

mt_report_event() {
    local title=$1
    local command_display=$2
    local status=$3
    local exit_code=$4
    local started=$5
    local finished=$6
    local duration_ms=$7
    local output_file=$8

    mt_command_available jq || return 0

    jq -cn \
        --arg event test \
        --arg session "$MT_SESSION_ID" \
        --arg title "$title" \
        --arg command "$command_display" \
        --arg status "$status" \
        --arg started "$started" \
        --arg finished "$finished" \
        --argjson exit_code "$exit_code" \
        --argjson duration_ms "$duration_ms" \
        --rawfile output "$output_file" \
        '{event:$event, session:$session, title:$title, command:$command,
          status:$status, exit_code:$exit_code, started:$started,
          finished:$finished, duration_ms:$duration_ms, output:$output}' \
        >> "$MT_EVENTS_FILE"
}

mt_run() {
    local title=$1
    local timeout_seconds=$2
    shift 2

    local raw_file="$MT_TEMP_DIR/run-$RANDOM-$RANDOM.raw"
    local clean_file="$MT_TEMP_DIR/run-$RANDOM-$RANDOM.clean"
    local shown_file="$MT_TEMP_DIR/run-$RANDOM-$RANDOM.shown"
    local command_display
    local started
    local finished
    local started_ns
    local finished_ns
    local duration_ms
    local exit_code
    local status
    local output_size

    command_display=$(mt_command_for_log "$@")
    MT_ACTIVE_TEST_TITLE=$title
    MT_ACTIVE_TEST_COMMAND=$command_display
    started=$(date --iso-8601=seconds)
    started_ns=$(date +%s%N)

    printf '\n%s== %s ==%s\n' "$MT_COLOR_BOLD" "$title" "$MT_COLOR_RESET"
    printf 'Comando: %s\n' "$command_display"
    {
        printf '\n\n== %s ==\n' "$title"
        printf 'Início: %s\n' "$started"
        printf 'Comando: %s\n' "$command_display"
    } >> "$MT_REPORT_FILE"

    MT_INTERRUPT_PENDING=0
    trap 'MT_INTERRUPT_PENDING=1' INT
    timeout --kill-after=2s "${timeout_seconds}s" "$@" \
        > "$raw_file" 2>&1 &
    MT_ACTIVE_PROCESS_PID=$!
    trap mt_handle_interrupt INT
    if ((MT_INTERRUPT_PENDING == 1)); then
        mt_handle_interrupt
    fi

    wait "$MT_ACTIVE_PROCESS_PID"
    exit_code=$?
    MT_ACTIVE_PROCESS_PID=

    mt_sanitize_output "$raw_file" "$clean_file"
    head -c "$MT_MAX_OUTPUT_BYTES" "$clean_file" > "$shown_file"
    tee -a "$MT_REPORT_FILE" < "$shown_file"

    output_size=$(wc -c < "$clean_file")
    if ((output_size > MT_MAX_OUTPUT_BYTES)); then
        printf '\n[Saída truncada após %s bytes]\n' "$MT_MAX_OUTPUT_BYTES" |
            tee -a "$MT_REPORT_FILE"
    elif [[ -s $shown_file ]]; then
        printf '\n' | tee -a "$MT_REPORT_FILE"
    fi

    finished=$(date --iso-8601=seconds)
    finished_ns=$(date +%s%N)
    duration_ms=$(((finished_ns - started_ns) / 1000000))

    case $exit_code in
        0)
            status=PASS
            mt_ok "$title concluído (${duration_ms} ms)."
            ;;
        124 | 137)
            status=TIMEOUT
            mt_warn "$title excedeu o limite de ${timeout_seconds}s."
            ;;
        130)
            status=INTERRUPTED
            ;;
        *)
            status=FAIL
            mt_error "$title terminou com código $exit_code."
            ;;
    esac

    {
        printf 'Fim: %s\n' "$finished"
        printf 'Duração_ms: %s\n' "$duration_ms"
        printf 'Status: %s\n' "$status"
        printf 'Código: %s\n' "$exit_code"
    } >> "$MT_REPORT_FILE"

    mt_report_event "$title" "$command_display" "$status" "$exit_code" \
        "$started" "$finished" "$duration_ms" "$shown_file"
    MT_LAST_OUTPUT_FILE=$shown_file
    MT_LAST_EXIT_CODE=$exit_code
    if ((exit_code == 130)); then
        mt_handle_interrupt
    fi
    MT_ACTIVE_TEST_TITLE=
    MT_ACTIVE_TEST_COMMAND=
    return "$exit_code"
}

mt_report_note() {
    local note=$1

    printf '\nNOTA: %s\n' "$note" >> "$MT_REPORT_FILE"
}

mt_report_assessment() {
    local status=$1
    local title=$2
    local detail=$3

    case $status in
        PASS) mt_ok "$title: $detail" ;;
        WARN) mt_warn "$title: $detail" ;;
        FAIL) mt_error "$title: $detail" ;;
        *) mt_info "$title: $detail" ;;
    esac

    printf '\nAVALIAÇÃO [%s] %s: %s\n' "$status" "$title" "$detail" \
        >> "$MT_REPORT_FILE"

    if mt_command_available jq; then
        jq -cn \
            --arg event assessment \
            --arg session "$MT_SESSION_ID" \
            --arg timestamp "$(date --iso-8601=seconds)" \
            --arg status "$status" \
            --arg title "$title" \
            --arg detail "$detail" \
            '{event:$event, session:$session, timestamp:$timestamp,
              status:$status, title:$title, detail:$detail}' \
            >> "$MT_EVENTS_FILE"
    fi
}

mt_report_result_block() {
    local status=$1
    local title=$2
    shift 2

    local key
    local label
    local value
    local display_status
    local color
    local values_json='{}'
    local display_timestamp
    local index
    local -a fields=("$@")
    local -A seen_keys=()

    (( $# > 0 && $# % 3 == 0 )) || {
        mt_error 'Bloco de resultado recebeu campos incompletos.'
        return 2
    }
    [[ $status == PASS || $status == WARN ||
       $status == FAIL || $status == INFO ]] || {
        mt_error "Status inválido no bloco de resultado: $status"
        return 2
    }
    for ((index = 0; index < ${#fields[@]}; index += 3)); do
        key=${fields[index]}
        [[ $key =~ ^[a-z][a-z0-9_]{0,63}$ ]] || {
            mt_error "Chave inválida no bloco de resultado: $key"
            return 2
        }
        if [[ -v "seen_keys[$key]" ]]; then
            mt_error "Chave duplicada no bloco de resultado: $key"
            return 2
        fi
        seen_keys["$key"]=1
    done
    title=$(printf '%s' "$title" |
        LC_ALL=C tr '\000-\037\177' ' ')
    title=${title:0:256}
    display_timestamp=$(date '+%H:%M %d/%m/%Y')

    case $status in
        PASS)
            display_status=OK
            color=$MT_COLOR_GREEN
            ;;
        WARN)
            display_status=ALERTA
            color=$MT_COLOR_YELLOW
            ;;
        FAIL)
            display_status=FALHA
            color=$MT_COLOR_RED
            ;;
        *)
            display_status=INFO
            color=$MT_COLOR_BLUE
            ;;
    esac

    printf '\n%s[%s]%s %s\n' \
        "$color" "$display_status" "$MT_COLOR_RESET" "$title"
    {
        printf '\nRESULTADO [%s] %s\n' "$status" "$title"
    } >> "$MT_REPORT_FILE"

    while (($# > 0)); do
        key=$1
        label=$2
        value=$3
        shift 3

        label=$(printf '%s' "$label" |
            LC_ALL=C tr '\000-\037\177' ' ')
        value=$(printf '%s' "$value" |
            LC_ALL=C tr '\000-\037\177' ' ')
        label=${label:0:128}
        value=${value:0:2048}

        printf '  %s: %s\n' "$label" "$value"
        printf '%s: %s\n' "$label" "$value" >> "$MT_REPORT_FILE"

        if mt_command_available jq; then
            values_json=$(jq -cn \
                --argjson current "$values_json" \
                --arg key "$key" \
                --arg value "$value" \
                '$current + {($key): $value}')
        fi
    done
    printf '  Data/hora: %s\n' "$display_timestamp"
    printf 'Data/hora: %s\n' "$display_timestamp" >> "$MT_REPORT_FILE"
    printf '\n' >> "$MT_REPORT_FILE"

    if mt_command_available jq &&
       [[ -n ${MT_EVENTS_FILE:-} && -f ${MT_EVENTS_FILE:-} ]]; then
        jq -cn \
            --arg event measurement \
            --arg session "$MT_SESSION_ID" \
            --arg timestamp "$(date --iso-8601=seconds)" \
            --arg status "$status" \
            --arg title "$title" \
            --argjson values "$values_json" \
            '{event:$event, session:$session, timestamp:$timestamp,
              status:$status, title:$title, values:$values}' \
            >> "$MT_EVENTS_FILE"
        jq -cn \
            --arg event assessment \
            --arg session "$MT_SESSION_ID" \
            --arg timestamp "$(date --iso-8601=seconds)" \
            --arg status "$status" \
            --arg title "$title" \
            --arg detail 'Resultado detalhado registrado em bloco.' \
            --argjson values "$values_json" \
            '{event:$event, session:$session, timestamp:$timestamp,
              status:$status, title:$title, detail:$detail, values:$values}' \
            >> "$MT_EVENTS_FILE"
    fi
}

mt_report_paths() {
    printf '\nRelatório desta sessão:\n  %s\n' "$MT_REPORT_FILE"
    if [[ -s $MT_EVENTS_FILE ]]; then
        printf '  %s\n' "$MT_EVENTS_FILE"
    fi
}

mt_report_checksum() {
    local checksum_file="${MT_REPORT_FILE}.sha256"

    [[ -n ${MT_REPORT_FILE:-} && -f $MT_REPORT_FILE ]] || return 0
    if mt_command_available sha256sum; then
        (
            cd -- "$MT_REPORT_DIR" &&
                sha256sum -- "$(basename -- "$MT_REPORT_FILE")" \
                    > "$(basename -- "$checksum_file")"
        )
        chmod 0600 -- "$checksum_file"
        mt_ok "Checksum gerado: $checksum_file"
    fi
}
