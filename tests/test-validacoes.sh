#!/usr/bin/env bash

set -u
set -o pipefail

PROJECT_DIR=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$PROJECT_DIR/lib/menu-teste/validate.sh"
source "$PROJECT_DIR/lib/menu-teste/common.sh"

PASSED=0
FAILED=0

pass() {
    printf 'OK    %s\n' "$1"
    ((PASSED += 1))
}

fail() {
    printf 'FALHA %s\n' "$1" >&2
    ((FAILED += 1))
}

expect_valid() {
    local function_name=$1
    local value=$2

    if "$function_name" "$value"; then
        pass "$function_name aceita: $value"
    else
        fail "$function_name deveria aceitar: $value"
    fi
}

expect_invalid() {
    local function_name=$1
    local value=$2

    if "$function_name" "$value"; then
        fail "$function_name deveria recusar: $value"
    else
        pass "$function_name recusa: $value"
    fi
}

expect_valid mt_valid_target 192.168.1.10
expect_valid mt_valid_target 10.0.0.1
expect_valid mt_valid_target exemplo.com
expect_valid mt_valid_target srv-noc
expect_valid mt_valid_target ::1
expect_valid mt_valid_target fe80::1%eth0

expect_invalid mt_valid_target 999.1.1.1
expect_invalid mt_valid_target -Pn
expect_invalid mt_valid_target 'host com espaço'
expect_invalid mt_valid_target 'host;id'
expect_invalid mt_valid_target '$(id)'
expect_invalid mt_valid_target '10.0.0.0/24'

expect_valid mt_valid_port 1
expect_valid mt_valid_port 443
expect_valid mt_valid_port 65535
expect_invalid mt_valid_port 0
expect_invalid mt_valid_port 65536
expect_invalid mt_valid_port 22x

expect_valid mt_valid_port_list '22,80,443'
expect_valid mt_valid_port_list ' 22, 443 '
expect_invalid mt_valid_port_list '1-1024'
expect_invalid mt_valid_port_list '22,abc'

expect_valid mt_valid_speedtest_server_id 1
expect_valid mt_valid_speedtest_server_id 12345
expect_valid mt_valid_speedtest_server_id 9999999999
expect_invalid mt_valid_speedtest_server_id 0
expect_invalid mt_valid_speedtest_server_id -1
expect_invalid mt_valid_speedtest_server_id 12345678901
expect_invalid mt_valid_speedtest_server_id '123;id'

expect_valid mt_valid_speedtest_server_host speedtest.exemplo.net
expect_valid mt_valid_speedtest_server_host SPEEDTEST.EXEMPLO.NET.
expect_invalid mt_valid_speedtest_server_host localhost
expect_invalid mt_valid_speedtest_server_host 192.0.2.10
expect_invalid mt_valid_speedtest_server_host '-host.exemplo.net'
expect_invalid mt_valid_speedtest_server_host 'host.exemplo.net;id'

expect_valid mt_valid_url 'https://www.debian.org/'
expect_valid mt_valid_url 'http://192.168.1.1:8080/status'
expect_invalid mt_valid_url 'ftp://example.com/file'
expect_invalid mt_valid_url 'https://usuario:senha@example.com/'
expect_invalid mt_valid_url 'https://example.com/ caminho'

PROMPT_RESULT=
if mt_prompt PROMPT_RESULT 'Teste' '' <<< 'valor-digitado' >/dev/null &&
    [[ $PROMPT_RESULT == valor-digitado ]]; then
    pass 'mt_prompt devolve o valor ao chamador'
else
    fail 'mt_prompt não devolveu o valor ao chamador'
fi

if mt_prompt PROMPT_RESULT 'Teste EOF' '' </dev/null >/dev/null 2>&1; then
    fail 'mt_prompt deveria sinalizar EOF'
else
    pass 'mt_prompt sinaliza EOF sem entrar em loop'
fi

printf '\nPassaram: %d | Falharam: %d\n' "$PASSED" "$FAILED"
((FAILED == 0))
