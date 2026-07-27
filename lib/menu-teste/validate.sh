#!/usr/bin/env bash

# Funções de validação do menu-teste.
# Este arquivo é carregado pelo executável principal e não deve produzir saída.

mt_valid_ipv4() {
    local address=${1:-}
    local octet
    local -a octets

    [[ $address =~ ^[0-9]+(\.[0-9]+){3}$ ]] || return 1
    IFS='.' read -r -a octets <<< "$address"
    ((${#octets[@]} == 4)) || return 1

    for octet in "${octets[@]}"; do
        ((${#octet} <= 3)) || return 1
        ((10#$octet >= 0 && 10#$octet <= 255)) || return 1
    done
}

mt_valid_ipv6() {
    local address=${1:-}
    local ip_part=$address
    local zone=

    [[ $address == *:* ]] || return 1
    [[ $address != -* && $address != *[[:space:]]* ]] || return 1

    if [[ $address == *%* ]]; then
        ip_part=${address%%%*}
        zone=${address#*%}
        [[ $zone =~ ^[A-Za-z0-9_.:-]+$ ]] || return 1
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 -c \
            'import ipaddress,sys; ipaddress.IPv6Address(sys.argv[1])' \
            "$ip_part" >/dev/null 2>&1
        return
    fi

    # Fallback conservador quando python3 ainda não estiver instalado.
    [[ $ip_part =~ ^[0-9A-Fa-f:.]+$ && $ip_part == *:* ]]
}

mt_valid_hostname() {
    local hostname=${1:-}
    local label
    local -a labels

    [[ -n $hostname && ${#hostname} -le 253 ]] || return 1
    [[ $hostname != -* && $hostname != *[[:space:]]* ]] || return 1

    hostname=${hostname%.}
    [[ -n $hostname ]] || return 1
    IFS='.' read -r -a labels <<< "$hostname"

    for label in "${labels[@]}"; do
        [[ -n $label && ${#label} -le 63 ]] || return 1
        [[ $label =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    done
}

mt_valid_target() {
    local target=${1:-}

    [[ -n $target && ${#target} -le 253 ]] || return 1
    [[ $target != -* && $target != *[[:space:]]* ]] || return 1

    if [[ $target == *:* ]]; then
        mt_valid_ipv6 "$target"
    elif [[ $target =~ ^[0-9.]+$ ]]; then
        mt_valid_ipv4 "$target"
    else
        mt_valid_hostname "$target"
    fi
}

mt_valid_port() {
    local port=${1:-}

    [[ $port =~ ^[0-9]{1,5}$ ]] || return 1
    ((10#$port >= 1 && 10#$port <= 65535))
}

mt_valid_port_list() {
    local ports=${1:-}
    local item
    local count=0
    local -a items

    ports=${ports//[[:space:]]/}
    [[ -n $ports ]] || return 1
    IFS=',' read -r -a items <<< "$ports"

    for item in "${items[@]}"; do
        mt_valid_port "$item" || return 1
        ((count += 1))
        ((count <= 20)) || return 1
    done
}

mt_normalize_port_list() {
    local ports=${1:-}
    local item
    local result=
    local -a items

    mt_valid_port_list "$ports" || return 1
    ports=${ports//[[:space:]]/}
    IFS=',' read -r -a items <<< "$ports"

    for item in "${items[@]}"; do
        item=$((10#$item))
        if [[ -n $result ]]; then
            result+=,
        fi
        result+=$item
    done

    printf '%s\n' "$result"
}

mt_valid_integer_range() {
    local value=${1:-}
    local minimum=${2:-0}
    local maximum=${3:-0}

    [[ $value =~ ^[0-9]+$ ]] || return 1
    ((10#$value >= minimum && 10#$value <= maximum))
}

mt_valid_speedtest_server_id() {
    local server_id=${1:-}

    [[ $server_id =~ ^[1-9][0-9]{0,9}$ ]]
}

mt_valid_speedtest_server_host() {
    local server_host=${1:-}

    server_host=${server_host%.}
    [[ $server_host == *.* ]] || return 1
    mt_valid_hostname "$server_host" || return 1
    ! mt_valid_ipv4 "$server_host"
}

mt_normalize_speedtest_server_host() {
    local server_host=${1:-}

    mt_valid_speedtest_server_host "$server_host" || return 1
    server_host=${server_host%.}
    printf '%s\n' "${server_host,,}"
}

mt_valid_dns_type() {
    case ${1:-} in
        A | AAAA | CNAME | MX | NS | PTR | SOA | TXT) return 0 ;;
        *) return 1 ;;
    esac
}

mt_valid_url() {
    local url=${1:-}
    local authority
    local remainder

    [[ -n $url && ${#url} -le 2048 ]] || return 1
    [[ $url != *[[:space:]]* && $url != *[[:cntrl:]]* ]] || return 1
    [[ $url == http://* || $url == https://* ]] || return 1

    remainder=${url#*://}
    authority=${remainder%%[/?#]*}
    [[ -n $authority && $authority != *@* ]] || return 1
}

mt_valid_interface_name() {
    local interface=${1:-}

    [[ -n $interface && ${#interface} -le 64 ]] || return 1
    [[ $interface =~ ^[A-Za-z0-9_.:@-]+$ ]] || return 1
}

mt_host_and_port() {
    local host=${1:-}
    local port=${2:-}

    if [[ $host == *:* ]]; then
        printf '[%s]:%s\n' "$host" "$port"
    else
        printf '%s:%s\n' "$host" "$port"
    fi
}
