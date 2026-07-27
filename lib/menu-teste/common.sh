#!/usr/bin/env bash

# Interface de terminal e utilitários compartilhados.

MT_VERSION=${MT_VERSION:-0.3.2}
MT_MAX_OUTPUT_BYTES=${MT_MAX_OUTPUT_BYTES:-1048576}
MT_INTERRUPT_IN_PROGRESS=0
MT_INTERRUPT_PENDING=0

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    MT_COLOR_BLUE=$'\033[1;34m'
    MT_COLOR_GREEN=$'\033[1;32m'
    MT_COLOR_YELLOW=$'\033[1;33m'
    MT_COLOR_RED=$'\033[1;31m'
    MT_COLOR_BOLD=$'\033[1m'
    MT_COLOR_RESET=$'\033[0m'
else
    MT_COLOR_BLUE=
    MT_COLOR_GREEN=
    MT_COLOR_YELLOW=
    MT_COLOR_RED=
    MT_COLOR_BOLD=
    MT_COLOR_RESET=
fi

mt_header() {
    printf '\n%s%smenu-teste%s  v%s\n' \
        "$MT_COLOR_BLUE" "$MT_COLOR_BOLD" "$MT_COLOR_RESET" "$MT_VERSION"
    printf '%s\n\n' 'Diagnóstico de rede para operação e NOC'
}

mt_info() {
    printf '%s[INFO]%s %s\n' "$MT_COLOR_BLUE" "$MT_COLOR_RESET" "$*"
}

mt_ok() {
    printf '%s[OK]%s %s\n' "$MT_COLOR_GREEN" "$MT_COLOR_RESET" "$*"
}

mt_warn() {
    printf '%s[ALERTA]%s %s\n' "$MT_COLOR_YELLOW" "$MT_COLOR_RESET" "$*" >&2
}

mt_error() {
    printf '%s[FALHA]%s %s\n' "$MT_COLOR_RED" "$MT_COLOR_RESET" "$*" >&2
}

mt_stop_active_process() {
    local pid=${MT_ACTIVE_PROCESS_PID:-}
    local attempt

    [[ $pid =~ ^[1-9][0-9]*$ ]] || return 0
    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM -- "-$pid" 2>/dev/null ||
            kill -TERM -- "$pid" 2>/dev/null || true

        for ((attempt = 0; attempt < 40; attempt += 1)); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.05
        done

        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL -- "-$pid" 2>/dev/null ||
                kill -KILL -- "$pid" 2>/dev/null || true
        fi
        wait "$pid" 2>/dev/null || true
    fi
    MT_ACTIVE_PROCESS_PID=
}

mt_handle_interrupt() {
    if ((MT_INTERRUPT_IN_PROGRESS == 1)); then
        exit 130
    fi

    MT_INTERRUPT_IN_PROGRESS=1
    trap - INT
    printf '\n' >&2
    mt_warn 'Operação cancelada pelo operador. Encerrando o menu-teste.'
    mt_stop_active_process

    if declare -F mt_report_interruption >/dev/null 2>&1; then
        mt_report_interruption || true
    fi
    if [[ -n ${MT_REPORT_FILE:-} && -f ${MT_REPORT_FILE:-} ]]; then
        if declare -F mt_report_checksum >/dev/null 2>&1; then
            mt_report_checksum >&2 || true
        fi
        if declare -F mt_report_paths >/dev/null 2>&1; then
            mt_report_paths >&2 || true
        fi
    fi

    exit 130
}

mt_install_signal_handlers() {
    trap mt_handle_interrupt INT
}

mt_pause() {
    [[ -t 0 ]] || return 0
    printf '\nPressione Enter para voltar ao menu...'
    read -r _ || true
}

mt_prompt() {
    local variable_name=$1
    local label=$2
    local default_value=${3:-}
    local __mt_prompt_input=

    if [[ -n $default_value ]]; then
        printf '%s [%s]: ' "$label" "$default_value"
    else
        printf '%s: ' "$label"
    fi

    if ! read -r __mt_prompt_input; then
        printf '\n' >&2
        return 1
    fi
    __mt_prompt_input=${__mt_prompt_input:-$default_value}
    printf -v "$variable_name" '%s' "$__mt_prompt_input"
}

mt_confirm() {
    local question=$1
    local answer=

    printf '%s [s/N]: ' "$question"
    read -r answer || answer=
    case $answer in
        s | S | sim | SIM | Sim) return 0 ;;
        *) return 1 ;;
    esac
}

mt_require_target() {
    local variable_name=$1
    local label=${2:-Alvo}
    local default_value=${3:-}
    local value=

    while true; do
        mt_prompt value "$label" "$default_value" || return 130
        if mt_valid_target "$value"; then
            printf -v "$variable_name" '%s' "$value"
            return 0
        fi
        mt_error 'Informe um IPv4, IPv6 ou hostname válido, sem espaços ou opções.'
    done
}

mt_require_port() {
    local variable_name=$1
    local label=${2:-Porta}
    local default_value=${3:-}
    local value=

    while true; do
        mt_prompt value "$label" "$default_value" || return 130
        if mt_valid_port "$value"; then
            printf -v "$variable_name" '%d' "$((10#$value))"
            return 0
        fi
        mt_error 'A porta deve ser um número entre 1 e 65535.'
    done
}

mt_require_port_list() {
    local variable_name=$1
    local label=${2:-Portas separadas por vírgula}
    local default_value=${3:-}
    local value=
    local normalized=

    while true; do
        mt_prompt value "$label" "$default_value" || return 130
        if normalized=$(mt_normalize_port_list "$value"); then
            printf -v "$variable_name" '%s' "$normalized"
            return 0
        fi
        mt_error 'Use de 1 a 20 portas válidas, separadas por vírgula.'
    done
}

mt_require_integer() {
    local variable_name=$1
    local label=$2
    local default_value=$3
    local minimum=$4
    local maximum=$5
    local value=

    while true; do
        mt_prompt value "$label" "$default_value" || return 130
        if mt_valid_integer_range "$value" "$minimum" "$maximum"; then
            printf -v "$variable_name" '%d' "$((10#$value))"
            return 0
        fi
        mt_error "Informe um número entre $minimum e $maximum."
    done
}

mt_command_available() {
    command -v "$1" >/dev/null 2>&1
}

mt_need_command() {
    local command_name=$1
    local package_name=${2:-$1}

    if mt_command_available "$command_name"; then
        return 0
    fi

    mt_error "O comando '$command_name' não está instalado."
    mt_info "Instale o pacote '$package_name' ou execute o instalador do menu-teste."
    return 1
}

mt_default_gateway() {
    ip -4 route show default 2>/dev/null |
        awk 'NR == 1 { print $3; exit }'
}

mt_default_interface() {
    ip -4 route show default 2>/dev/null |
        awk 'NR == 1 { print $5; exit }'
}

mt_default_interface_ip() {
    local interface=${1:-}

    [[ -n $interface ]] || return 1
    ip -o -4 address show dev "$interface" scope global 2>/dev/null |
        awk 'NR == 1 { split($4, value, "/"); print value[1]; exit }'
}

mt_first_resolved_ip() {
    local target=${1:-}

    if mt_valid_ipv4 "$target" || mt_valid_ipv6 "$target"; then
        printf '%s\n' "$target"
        return 0
    fi
    mt_command_available getent || return 1
    getent ahosts "$target" 2>/dev/null |
        awk 'NR == 1 { print $1; exit }'
}

mt_url_for_log() {
    local value=$1

    if [[ $value == http://* || $value == https://* ]]; then
        value=${value%%\?*}
        value=${value%%\#*}
    fi
    printf '%s' "$value"
}

mt_command_for_log() {
    local argument
    local safe_argument
    local output=
    local quoted

    for argument in "$@"; do
        safe_argument=$(mt_url_for_log "$argument")
        printf -v quoted '%q' "$safe_argument"
        output+="${output:+ }$quoted"
    done
    printf '%s' "$output"
}
