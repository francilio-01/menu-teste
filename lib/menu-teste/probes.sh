#!/usr/bin/env bash

# Testes de rede. Todas as entradas externas devem chegar validadas.

mt_probe_system_summary() {
    local interface

    mt_run 'Identificação do sistema' 5 uname -a || true
    [[ ! -r /etc/os-release ]] ||
        mt_run 'Versão do sistema operacional' 5 sed -n \
            '1,20p' /etc/os-release || true

    if mt_need_command ip iproute2; then
        mt_run 'Interfaces e endereços' 10 ip -brief address || true
        mt_run 'Estado dos enlaces' 10 ip -brief link || true
        mt_run 'Rotas IPv4' 10 ip -4 route show || true
        mt_run 'Rotas IPv6' 10 ip -6 route show || true
        mt_run 'Vizinhos ARP/NDP' 10 ip neighbor show || true
    fi

    if [[ -r /etc/resolv.conf ]]; then
        mt_run 'Configuração DNS local' 5 sed -n \
            '/^[[:space:]]*#/d; /^[[:space:]]*$/d; 1,40p' \
            /etc/resolv.conf || true
    fi

    interface=$(mt_default_interface)
    if [[ -n $interface ]] && mt_command_available ethtool; then
        mt_run "Link físico: $interface" 10 ethtool "$interface" || true
        mt_run "Contadores: $interface" 10 ip -s link show dev "$interface" || true
    fi
}

mt_probe_link_interactive() {
    local interface
    local default_interface

    mt_need_command ip iproute2 || return 1
    default_interface=$(mt_default_interface)
    mt_run 'Interfaces disponíveis' 10 ip -brief link || true
    mt_prompt interface 'Interface a examinar' "$default_interface" || return 130

    if ! mt_valid_interface_name "$interface" ||
        ! ip link show dev "$interface" >/dev/null 2>&1; then
        mt_error 'Interface inexistente ou inválida.'
        return 1
    fi

    mt_run "Endereços: $interface" 10 ip address show dev "$interface" || true
    mt_run "Contadores: $interface" 10 ip -s link show dev "$interface" || true
    if mt_command_available ethtool; then
        mt_run "Velocidade, duplex e link: $interface" 10 \
            ethtool "$interface" || true
    else
        mt_warn "Instale 'ethtool' para conferir velocidade e duplex."
    fi
}

mt_probe_ping() {
    local target=$1
    local count=${2:-4}
    local total_timeout
    local run_status=0
    local packet_loss=

    mt_need_command ping iputils-ping || return 1
    mt_valid_target "$target" || {
        mt_error 'Alvo inválido.'
        return 1
    }
    mt_valid_integer_range "$count" 1 20 || {
        mt_error 'A quantidade deve estar entre 1 e 20.'
        return 2
    }

    total_timeout=$((count * 3 + 3))
    mt_run "Ping: $target" "$total_timeout" \
        ping -n -c "$count" -W 2 "$target" || run_status=$?

    if [[ -r $MT_LAST_OUTPUT_FILE ]]; then
        packet_loss=$(sed -n \
            's/.* \([0-9.][0-9.]*\)% packet loss.*/\1/p' \
            "$MT_LAST_OUTPUT_FILE" | tail -n 1)
    fi

    if ((run_status != 0)); then
        mt_report_assessment FAIL "Ping $target" \
            'nenhuma resposta suficiente foi recebida; ICMP pode estar bloqueado.'
        return "$run_status"
    fi
    case $packet_loss in
        0 | 0.0 | 0.00 | 0.0000)
            mt_report_assessment PASS "Ping $target" '0% de perda.'
            return 0
            ;;
        '')
            mt_report_assessment WARN "Ping $target" \
                'não foi possível interpretar a perda de pacotes.'
            return 2
            ;;
        *)
            mt_report_assessment WARN "Ping $target" \
                "houve ${packet_loss}% de perda de pacotes."
            return 2
            ;;
    esac
}

mt_probe_ping_interactive() {
    local target
    local count

    mt_require_target target 'IPv4, IPv6 ou hostname' || return
    mt_require_integer count 'Quantidade de pacotes' 4 1 20 || return
    mt_probe_ping "$target" "$count" || true
    mt_warn 'ICMP pode ser bloqueado; ausência de resposta não prova indisponibilidade.'
}

mt_probe_dns() {
    local name=$1
    local record_type=${2:-A}
    local dns_server=${3:-}
    local run_status=0
    local dns_status=
    local answer_count=
    local -a command=(dig +time=3 +tries=1)

    mt_need_command dig bind9-dnsutils || return 1
    mt_valid_target "$name" || {
        mt_error 'Nome ou endereço inválido.'
        return 1
    }
    mt_valid_dns_type "$record_type" || {
        mt_error 'Tipo de registro DNS inválido.'
        return 1
    }
    if [[ -n $dns_server ]]; then
        mt_valid_target "$dns_server" || {
            mt_error 'Servidor DNS inválido.'
            return 1
        }
        command+=("@$dns_server")
    fi

    if [[ $record_type == PTR ]]; then
        command+=(-x "$name")
    else
        command+=("$name" "$record_type")
    fi
    mt_run "DNS $record_type: $name" 12 "${command[@]}" || run_status=$?
    if ((run_status != 0)); then
        mt_report_assessment FAIL "DNS $record_type: $name" \
            "a consulta falhou com código $run_status."
        return "$run_status"
    fi

    if [[ -r $MT_LAST_OUTPUT_FILE ]]; then
        dns_status=$(sed -n \
            's/.*status: \([A-Z0-9]*\),.*/\1/p' \
            "$MT_LAST_OUTPUT_FILE" | head -n 1)
        answer_count=$(sed -n \
            's/.*ANSWER: \([0-9][0-9]*\).*/\1/p' \
            "$MT_LAST_OUTPUT_FILE" | head -n 1)
    fi

    if [[ $dns_status != NOERROR ]]; then
        mt_report_assessment FAIL "DNS $record_type: $name" \
            "o servidor respondeu com status ${dns_status:-desconhecido}."
        return 1
    fi
    if [[ $answer_count == 0 || -z $answer_count ]]; then
        mt_report_assessment WARN "DNS $record_type: $name" \
            'a consulta terminou sem registro na seção de resposta.'
        return 2
    fi

    mt_report_assessment PASS "DNS $record_type: $name" \
        "resposta NOERROR com $answer_count registro(s)."
    return 0
}

mt_probe_dns_interactive() {
    local name
    local type_choice
    local record_type
    local dns_server

    mt_require_target name 'Nome ou IP da consulta' || return
    printf '\n1) A   2) AAAA   3) MX   4) NS   5) TXT   6) PTR\n'
    mt_prompt type_choice 'Tipo de registro' 1 || return 130
    case $type_choice in
        1) record_type=A ;;
        2) record_type=AAAA ;;
        3) record_type=MX ;;
        4) record_type=NS ;;
        5) record_type=TXT ;;
        6) record_type=PTR ;;
        *)
            mt_error 'Opção inválida.'
            return 1
            ;;
    esac

    mt_prompt dns_server 'Servidor DNS específico (vazio = padrão)' '' ||
        return 130
    if [[ -n $dns_server ]] && ! mt_valid_target "$dns_server"; then
        mt_error 'Servidor DNS inválido.'
        return 1
    fi

    mt_probe_dns "$name" "$record_type" "$dns_server" || true
}

mt_probe_configured_dns() {
    local name=$1
    local resolver
    local found=0
    local failures=0

    [[ -r /etc/resolv.conf ]] || {
        mt_warn '/etc/resolv.conf não está disponível para comparação.'
        return 1
    }

    while IFS= read -r resolver; do
        mt_valid_target "$resolver" || continue
        found=1
        mt_probe_dns "$name" A "$resolver" || ((failures += 1))
    done < <(
        awk '$1 == "nameserver" { print $2 }' /etc/resolv.conf |
            awk '!seen[$0]++' |
            head -n 3
    )

    if ((found == 0)); then
        mt_warn 'Nenhum nameserver válido foi encontrado em /etc/resolv.conf.'
        mt_report_note \
            'Nenhum nameserver válido foi encontrado em /etc/resolv.conf.'
        return 1
    fi
    ((failures == 0))
}

mt_probe_route() {
    local target=$1
    local cycles=${2:-10}
    local route_target=
    local route_probe_status=1

    mt_valid_target "$target" || {
        mt_error 'Alvo inválido.'
        return 1
    }
    mt_valid_integer_range "$cycles" 3 30 || {
        mt_error 'A quantidade de ciclos deve estar entre 3 e 30.'
        return 2
    }

    route_target=$(mt_first_resolved_ip "$target")
    if mt_command_available ip && [[ -n $route_target ]]; then
        mt_run "Decisão de rota: $target via $route_target" 10 \
            ip route get "$route_target" || true
    elif mt_command_available ip; then
        mt_warn "Não foi possível resolver $target para consultar a rota local."
    fi

    if mt_command_available mtr; then
        if mt_run "MTR: $target" 60 \
            mtr --report --report-wide --no-dns \
            --report-cycles "$cycles" "$target"; then
            route_probe_status=0
        else
            mt_warn 'O MTR falhou; tentando traceroute como alternativa.'
            if mt_command_available traceroute; then
                if mt_run "Traceroute: $target" 60 \
                    traceroute -n -w 2 -q 1 "$target"; then
                    route_probe_status=0
                fi
            fi
        fi
    elif mt_command_available traceroute; then
        if mt_run "Traceroute: $target" 60 \
            traceroute -n -w 2 -q 1 "$target"; then
            route_probe_status=0
        fi
    else
        mt_error "Instale 'mtr-tiny' ou 'traceroute'."
        return 1
    fi

    mt_warn 'Perda em saltos intermediários pode ser apenas limitação de ICMP.'
    return "$route_probe_status"
}

mt_probe_route_interactive() {
    local target
    local cycles

    mt_require_target target 'Destino da rota' || return
    mt_require_integer cycles 'Ciclos do MTR' 10 3 30 || return
    mt_probe_route "$target" "$cycles"
}

mt_probe_tcp_ports() {
    local target=$1
    local ports=$2
    local port
    local result=0
    local -a port_items

    mt_valid_target "$target" || {
        mt_error 'Alvo inválido.'
        return 1
    }
    ports=$(mt_normalize_port_list "$ports") || {
        mt_error 'Lista de portas inválida.'
        return 1
    }
    IFS=',' read -r -a port_items <<< "$ports"

    if mt_command_available nc; then
        for port in "${port_items[@]}"; do
            mt_run "TCP $target:$port" 8 \
                nc -z -v -w 3 "$target" "$port" || result=1
        done
    elif mt_command_available nmap; then
        mt_run "Portas TCP em $target" 45 \
            nmap -Pn -sT --reason -p "$ports" --host-timeout 30s "$target" ||
            result=1
    else
        mt_error "Instale 'netcat-openbsd' ou 'nmap'."
        return 1
    fi

    mt_warn 'Conexão TCP confirma o transporte, não a saúde da aplicação.'
    return "$result"
}

mt_probe_tcp_ports_interactive() {
    local target
    local ports

    mt_require_target target 'Host remoto' || return
    mt_require_port_list ports 'Portas TCP, separadas por vírgula' \
        '22,80,443' || return
    mt_probe_tcp_ports "$target" "$ports" || true
}

mt_probe_tcp_services_interactive() {
    local target
    local ports

    mt_need_command nmap nmap || return 1
    mt_require_target target 'Host remoto' || return
    mt_require_port_list ports 'Portas TCP, separadas por vírgula' \
        '22,80,443' || return

    mt_warn 'Execute somente contra equipamentos e sistemas autorizados.'
    mt_confirm 'Você confirma que possui autorização para testar este host?' ||
        return 0

    mt_run "Serviços TCP em $target" 90 \
        nmap -Pn -sT -sV --version-light --reason -p "$ports" \
        --host-timeout 75s "$target" || true
}

mt_probe_udp_interactive() {
    local target
    local ports

    mt_need_command nmap nmap || return 1
    mt_require_target target 'Host remoto' || return
    mt_require_port_list ports 'Portas UDP, separadas por vírgula' \
        '53,123' || return

    mt_warn 'UDP sem resposta pode significar porta aberta ou filtrada.'
    mt_warn 'Execute somente contra equipamentos e sistemas autorizados.'
    if ((EUID != 0)); then
        mt_error 'O nmap exige root para este teste UDP.'
        mt_info 'Saia e execute: sudo menu-teste'
        return 1
    fi
    mt_confirm 'Você confirma que possui autorização para o teste UDP?' ||
        return 0

    mt_run "Portas UDP em $target" 120 \
        nmap -Pn -sU --reason -p "$ports" --host-timeout 100s "$target" ||
        true
}

mt_probe_local_ports() {
    mt_need_command ss iproute2 || return 1
    mt_run 'Portas locais em escuta' 15 ss -lntu || true
    if ((EUID == 0)); then
        mt_run 'Portas locais e processos' 15 ss -lntup || true
    else
        mt_warn 'Processos de outros usuários podem ficar ocultos sem root.'
    fi
}

mt_probe_http() {
    local url=$1
    local format
    local run_status=0
    local http_code=

    mt_need_command curl curl || return 1
    mt_valid_url "$url" || {
        mt_error 'Use uma URL http:// ou https://, sem credenciais embutidas.'
        return 1
    }

    format=$'HTTP: %{http_code}\nIP_remoto: %{remote_ip}\nPorta_remota: %{remote_port}\nDNS_s: %{time_namelookup}\nTCP_s: %{time_connect}\nTLS_s: %{time_appconnect}\nTTFB_s: %{time_starttransfer}\nTotal_s: %{time_total}\nBytes: %{size_download}\n'
    mt_run "HTTP/HTTPS: $(mt_url_for_log "$url")" 40 \
        curl --silent --show-error --output /dev/null --location \
        --max-redirs 3 --proto '=http,https' --proto-redir '=http,https' \
        --connect-timeout 10 --max-time 30 --write-out "$format" "$url" ||
        run_status=$?

    if [[ -r $MT_LAST_OUTPUT_FILE ]]; then
        http_code=$(sed -n 's/^HTTP: \([0-9][0-9][0-9]\)$/\1/p' \
            "$MT_LAST_OUTPUT_FILE" | tail -n 1)
    fi
    if ((run_status != 0)); then
        mt_report_assessment FAIL "HTTP/HTTPS: $(mt_url_for_log "$url")" \
            "falha de transporte ou TLS; curl retornou $run_status."
        return "$run_status"
    fi

    case $http_code in
        2?? | 3??)
            mt_report_assessment PASS \
                "HTTP/HTTPS: $(mt_url_for_log "$url")" \
                "o servidor respondeu com HTTP $http_code."
            return 0
            ;;
        4??)
            mt_report_assessment WARN \
                "HTTP/HTTPS: $(mt_url_for_log "$url")" \
                "o transporte funcionou, mas a aplicação respondeu HTTP $http_code."
            return 2
            ;;
        5??)
            mt_report_assessment FAIL \
                "HTTP/HTTPS: $(mt_url_for_log "$url")" \
                "a aplicação respondeu HTTP $http_code."
            return 1
            ;;
        *)
            mt_report_assessment WARN \
                "HTTP/HTTPS: $(mt_url_for_log "$url")" \
                'não foi possível interpretar o status HTTP.'
            return 2
            ;;
    esac
}

mt_probe_http_interactive() {
    local url

    while true; do
        mt_prompt url 'URL completa' 'https://www.debian.org/' || return 130
        if mt_valid_url "$url"; then
            break
        fi
        mt_error 'Use uma URL http:// ou https://, sem espaços ou credenciais.'
    done
    mt_probe_http "$url" || true
}

mt_probe_tls_interactive() {
    local target
    local port
    local endpoint
    local -a command

    mt_need_command openssl openssl || return 1
    mt_require_target target 'Hostname ou IP do serviço TLS' || return
    mt_require_port port 'Porta TLS' 443 || return
    endpoint=$(mt_host_and_port "$target" "$port")
    command=(openssl s_client -brief -verify_return_error -connect "$endpoint")
    if ! mt_valid_ipv4 "$target" && ! mt_valid_ipv6 "$target"; then
        command+=(-servername "$target")
    fi

    mt_run "Handshake TLS: $endpoint" 25 "${command[@]}" < /dev/null || true
}

mt_speedtest_terms_notice() {
    printf '\nO Speedtest usa um serviço externo da Ookla.\n'
    printf 'Confirme se a licença atende ao contexto de uso da sua organização.\n'
    printf 'Termos: https://www.speedtest.net/about/eula\n'
    printf 'Privacidade: https://www.speedtest.net/about/privacy\n\n'
}

mt_speedtest_json_string() {
    local filter=$1
    local input_file=$2

    jq -r \
        "$filter | if . == null then \"\" else tostring end" \
        "$input_file" 2>/dev/null |
        LC_ALL=C tr -d '\000-\037\177'
}

mt_speedtest_mbps() {
    local bytes_per_second=${1:-}

    [[ $bytes_per_second =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
    awk -v value="$bytes_per_second" \
        'BEGIN { printf "%.2f", value * 8 / 1000000 }'
}

mt_speedtest_render_server_list() {
    local input_file=$1
    local server_id
    local server_name
    local server_location
    local server_host

    {
        printf '\n%-10s %-28s %-26s %s\n' ID NOME LOCAL HOSTNAME
        printf '%-10s %-28s %-26s %s\n' \
            '----------' '----------------------------' \
            '--------------------------' '------------------------------'
        jq -r \
            '.servers[] |
             [(.id | tostring),
              ((.name // "") | tostring),
              ((((.location // "") | tostring) + " / " +
                ((.country // "") | tostring))),
              ((.host // "") | tostring)] | @tsv' \
            "$input_file" 2>/dev/null |
            while IFS=$'\t' read -r \
                server_id server_name server_location server_host; do
                server_id=$(printf '%s' "$server_id" |
                    LC_ALL=C tr -d '\000-\037\177')
                server_name=$(printf '%s' "$server_name" |
                    LC_ALL=C tr -d '\000-\037\177')
                server_location=$(printf '%s' "$server_location" |
                    LC_ALL=C tr -d '\000-\037\177')
                server_host=$(printf '%s' "$server_host" |
                    LC_ALL=C tr -d '\000-\037\177')
                printf '%-10.10s %-28.28s %-26.26s %s\n' \
                    "$server_id" "$server_name" \
                    "$server_location" "$server_host"
            done
    } | tee -a "$MT_REPORT_FILE"
}

mt_probe_speedtest_servers() {
    mt_need_command speedtest speedtest || return 1
    mt_need_command jq jq || return 1

    mt_speedtest_terms_notice
    if ! mt_confirm \
        'Consultar a lista de servidores e aceitar os termos da Ookla?'; then
        mt_info 'Consulta de servidores cancelada.'
        return 0
    fi

    mt_report_note \
        'Consulta da lista de servidores próximos disponibilizada pela Ookla.'
    mt_run 'Servidores Speedtest disponíveis' 45 \
        speedtest --accept-license --accept-gdpr --progress=no \
        --format=json --servers || return $?

    if [[ ! -r $MT_LAST_OUTPUT_FILE ]] ||
       ! jq -e \
           '.type == "serverList" and
            (.servers | type == "array" and length > 0)' \
           "$MT_LAST_OUTPUT_FILE" >/dev/null 2>&1; then
        mt_report_assessment WARN 'Servidores Speedtest disponíveis' \
            'a Ookla não retornou uma lista JSON utilizável.'
        return 2
    fi

    mt_speedtest_render_server_list "$MT_LAST_OUTPUT_FILE"
    mt_info \
        'Use o ID ou hostname exibido nas opções 3 e 4 do submenu de banda.'
}

mt_probe_speedtest() {
    local selection_type=${1:-auto}
    local selection_value=${2:-}
    local run_status=0
    local packet_loss=
    local download_bandwidth=
    local upload_bandwidth=
    local download=
    local upload=
    local latency=
    local jitter=
    local latency_display=
    local jitter_display=
    local server_id=
    local server_host=
    local server_name=
    local server_location=
    local server_country=
    local location_display=
    local selection_description=
    local title=
    local status=PASS
    local result_code=0
    local loss_display=
    local observation='Medição concluída.'
    local mismatch=0
    local -a command=(
        speedtest
        --accept-license
        --accept-gdpr
        --progress=no
        --format=json
    )

    mt_need_command speedtest speedtest || return 1
    mt_need_command jq jq || return 1

    case $selection_type in
        auto)
            selection_description='seleção automática'
            title='Speedtest Ookla - automático'
            ;;
        id)
            mt_valid_speedtest_server_id "$selection_value" || {
                mt_error 'O ID do servidor deve conter de 1 a 10 dígitos e ser maior que zero.'
                return 2
            }
            selection_description="ID $selection_value"
            title="Speedtest Ookla - ID $selection_value"
            command+=("--server-id=$selection_value")
            ;;
        host)
            selection_value=$(mt_normalize_speedtest_server_host \
                "$selection_value") || {
                mt_error 'Hostname de servidor Speedtest inválido.'
                return 2
            }
            selection_description="hostname $selection_value"
            title="Speedtest Ookla - $selection_value"
            command+=("--host=$selection_value")
            ;;
        *)
            mt_error 'Modo de seleção Speedtest inválido.'
            return 2
            ;;
    esac

    mt_speedtest_terms_notice
    printf 'Seleção solicitada: %s\n' "$selection_description"
    printf 'Em links rápidos, uma única medição pode transferir vários GB.\n\n'
    if [[ $selection_type != auto ]]; then
        mt_warn \
            'Escolher outra operadora/cidade não comprova sozinho que a rota saiu da rede; confirme com MTR ao hostname.'
    fi
    if ! mt_confirm \
        "Iniciar com $selection_description e aceitar os termos/privacidade da Ookla?"; then
        mt_info 'Speedtest cancelado.'
        return 0
    fi

    mt_report_note "Speedtest solicitado com $selection_description."
    mt_run "$title" 240 "${command[@]}" ||
        run_status=$?
    if ((run_status != 0)); then
        mt_report_assessment FAIL "$title" \
            "a medição falhou com código $run_status."
        return "$run_status"
    fi

    if [[ ! -r $MT_LAST_OUTPUT_FILE ]] ||
       ! jq -e \
           '.type == "result" and
            (.download.bandwidth |
                type == "number" and . >= 0) and
            (.upload.bandwidth |
                type == "number" and . >= 0) and
            (.server.id |
                type == "number" and . > 0) and
            (.server.host |
                type == "string" and length > 0) and
            (.packetLoss == null or
                (.packetLoss | type == "number" and . >= 0)) and
            (.ping.latency == null or
                (.ping.latency | type == "number" and . >= 0)) and
            (.ping.jitter == null or
                (.ping.jitter | type == "number" and . >= 0))' \
           "$MT_LAST_OUTPUT_FILE" >/dev/null 2>&1; then
        mt_report_assessment WARN "$title" \
            'a medição terminou, mas o resultado JSON está incompleto ou inválido.'
        return 2
    fi

    download_bandwidth=$(mt_speedtest_json_string \
        '.download.bandwidth' "$MT_LAST_OUTPUT_FILE")
    upload_bandwidth=$(mt_speedtest_json_string \
        '.upload.bandwidth' "$MT_LAST_OUTPUT_FILE")
    packet_loss=$(mt_speedtest_json_string \
        '.packetLoss' "$MT_LAST_OUTPUT_FILE")
    latency=$(mt_speedtest_json_string \
        '.ping.latency' "$MT_LAST_OUTPUT_FILE")
    jitter=$(mt_speedtest_json_string \
        '.ping.jitter' "$MT_LAST_OUTPUT_FILE")
    server_id=$(mt_speedtest_json_string \
        '.server.id' "$MT_LAST_OUTPUT_FILE")
    server_host=$(mt_speedtest_json_string \
        '.server.host' "$MT_LAST_OUTPUT_FILE")
    server_name=$(mt_speedtest_json_string \
        '.server.name' "$MT_LAST_OUTPUT_FILE")
    server_location=$(mt_speedtest_json_string \
        '.server.location' "$MT_LAST_OUTPUT_FILE")
    server_country=$(mt_speedtest_json_string \
        '.server.country' "$MT_LAST_OUTPUT_FILE")

    mt_valid_speedtest_server_id "$server_id" || {
        mt_report_assessment WARN "$title" \
            'o resultado retornou um ID de servidor inválido.'
        return 2
    }
    server_host=$(mt_normalize_speedtest_server_host "$server_host") || {
        mt_report_assessment WARN "$title" \
            'o resultado retornou um hostname de servidor inválido.'
        return 2
    }

    download=$(mt_speedtest_mbps "$download_bandwidth" 2>/dev/null || true)
    upload=$(mt_speedtest_mbps "$upload_bandwidth" 2>/dev/null || true)
    if [[ -n $latency ]]; then
        latency_display="$latency ms"
    else
        latency_display='Não informada pela Ookla'
    fi
    if [[ -n $jitter ]]; then
        jitter_display="$jitter ms"
    else
        jitter_display='Não informado pela Ookla'
    fi
    location_display=${server_location:-não informada}
    if [[ -n $server_country ]]; then
        if [[ $location_display == 'não informada' ]]; then
            location_display=$server_country
        else
            location_display+=" / $server_country"
        fi
    fi

    if [[ $selection_type == id &&
          -n $server_id && $server_id != "$selection_value" ]]; then
        mismatch=1
    elif [[ $selection_type == host &&
            -n $server_host &&
            ${server_host,,} != "${selection_value,,}" ]]; then
        mismatch=1
    fi

    if ((mismatch == 1)); then
        status=WARN
        result_code=2
        observation="O servidor retornado não corresponde à seleção solicitada: $selection_description."
    fi

    case $packet_loss in
        0 | 0.0 | 0.00 | 0.000)
            loss_display='0%'
            ;;
        '')
            loss_display='Não informada pela Ookla'
            status=WARN
            result_code=2
            if ((mismatch == 0)); then
                observation='A Ookla não informou a perda de pacotes.'
            fi
            ;;
        *)
            loss_display="${packet_loss}%"
            status=WARN
            result_code=2
            if ((mismatch == 0)); then
                observation='Foi detectada perda de pacotes.'
            fi
            ;;
    esac

    mt_report_result_block "$status" "$title" \
        company 'Empresa/servidor' "${server_name:-não informado}" \
        server_id 'ID do servidor' "$server_id" \
        server_hostname 'Hostname' "$server_host" \
        server_location 'Localização' "$location_display" \
        selection 'Seleção solicitada' "$selection_description" \
        download 'Download' "${download:-não informado} Mbps" \
        upload 'Upload' "${upload:-não informado} Mbps" \
        packet_loss 'Perda de pacotes' "$loss_display" \
        latency 'Latência (ping)' "$latency_display" \
        jitter 'Jitter' "$jitter_display" \
        observation 'Observação' "$observation" || return $?
    return "$result_code"
}

mt_probe_speedtest_by_id_interactive() {
    local server_id

    mt_prompt server_id \
        'ID do servidor Speedtest (consulte primeiro a opção 2)' '' ||
        return 130
    mt_valid_speedtest_server_id "$server_id" || {
        mt_error 'O ID deve conter de 1 a 10 dígitos e ser maior que zero.'
        return 2
    }
    mt_probe_speedtest id "$server_id"
}

mt_probe_speedtest_by_host_interactive() {
    local server_host

    mt_prompt server_host 'Hostname do servidor Speedtest' '' || return 130
    server_host=$(mt_normalize_speedtest_server_host "$server_host") || {
        mt_error 'Hostname de servidor Speedtest inválido.'
        return 2
    }
    mt_probe_speedtest host "$server_host"
}

mt_fast_runner_path() {
    local candidate

    if [[ ${MENU_TESTE_TESTING:-0} == 1 &&
          -n ${MENU_TESTE_WEB_SPEEDTEST_RUNNER:-} &&
          -x ${MENU_TESTE_WEB_SPEEDTEST_RUNNER:-} ]]; then
        printf '%s\n' "$MENU_TESTE_WEB_SPEEDTEST_RUNNER"
        return 0
    fi

    for candidate in \
        /usr/local/libexec/menu-teste/web_speedtest.py \
        "${MT_LIBRARY_DIR:-/nonexistent}/../../libexec/menu-teste/web_speedtest.py"; do
        if [[ -f $candidate && -x $candidate ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

mt_fast_dependencies_available() {
    local runner

    runner=$(mt_fast_runner_path) || return 1
    if [[ ${MENU_TESTE_TESTING:-0} == 1 &&
          $runner == "${MENU_TESTE_WEB_SPEEDTEST_RUNNER:-}" ]]; then
        return 0
    fi

    mt_command_available chromium &&
        mt_command_available chromedriver &&
        mt_command_available python3 &&
        python3 -c 'import selenium' >/dev/null 2>&1
}

mt_fast_notice() {
    printf '\nFast.com será executado no site da Netflix por um navegador '
    printf 'Chromium sem interface.\n'
    printf '%s\n' \
        'Esta integração é experimental: a Netflix não publica um cliente CLI oficial.'
    printf '%s\n' \
        'O servidor é escolhido automaticamente e pode estar dentro da rede/CDN do provedor.'
    printf '%s\n' \
        'Uma medição completa de download e upload pode transferir vários GB.'
    printf 'Serviço: https://fast.com/\n'
    printf 'Privacidade: https://help.netflix.com/legal/privacy\n\n'
}

mt_probe_fast() {
    local runner
    local run_status=0
    local download
    local upload
    local latency
    local loaded_latency
    local downloaded
    local uploaded
    local server
    local bufferbloat
    local result_file
    local title='Fast.com - automático (web experimental)'
    local -a command

    mt_need_command jq jq || return 1
    runner=$(mt_fast_runner_path) || {
        mt_error 'O coletor web do Fast.com não foi encontrado.'
        mt_info 'Reinstale com: sudo ./install.sh --with-fast'
        return 1
    }
    if ! mt_fast_dependencies_available; then
        mt_error 'As dependências do Fast.com não estão instaladas.'
        mt_info 'No projeto, execute: sudo ./install.sh --with-fast'
        return 1
    fi

    mt_fast_notice
    if ! mt_confirm \
        'Iniciar Fast.com e aceitar o uso do serviço/privacidade da Netflix?'; then
        mt_info 'Fast.com cancelado.'
        return 0
    fi

    command=("$runner" fast)
    if [[ ${MENU_TESTE_TESTING:-0} != 1 && ${EUID:-0} -eq 0 ]]; then
        mt_need_command runuser util-linux || return 1
        if ! getent passwd menu-teste-web >/dev/null 2>&1; then
            mt_error "O usuário isolado 'menu-teste-web' não existe."
            mt_info 'Reinstale com: sudo ./install.sh --with-fast'
            return 1
        fi
        command=(runuser -u menu-teste-web -- "$runner" fast)
    fi

    mt_report_note \
        'Fast.com solicitado; integração web experimental e seleção automática.'
    mt_run "$title" 300 "${command[@]}" || run_status=$?
    if ((run_status != 0)); then
        mt_report_assessment FAIL "$title" \
            "a medição web falhou com código $run_status."
        return "$run_status"
    fi

    result_file="$MT_TEMP_DIR/fast-result-$RANDOM-$RANDOM.json"
    tail -n 1 "$MT_LAST_OUTPUT_FILE" > "$result_file"
    if [[ ! -s $result_file ]] ||
       ! jq -e '
           def bounded($maximum):
               type == "number" and . >= 0 and . <= $maximum;
           .schema == 1 and
           .provider == "fast.com" and
           .implementation == "web-experimental" and
           (.download_mbps | bounded(1000000) and . > 0) and
           (.upload_mbps | bounded(1000000) and . > 0) and
           (.latency_ms | bounded(600000)) and
           (.loaded_latency_ms | bounded(600000)) and
           (.downloaded_mb == null or
               (.downloaded_mb | bounded(100000000))) and
           (.uploaded_mb == null or
               (.uploaded_mb | bounded(100000000))) and
           (.server | type == "string" and length <= 512 and
               (test("[\u0000-\u001f\u007f]") | not))
       ' "$result_file" >/dev/null 2>&1; then
        mt_report_assessment WARN "$title" \
            'o navegador terminou, mas o JSON recebido é inválido ou incompatível.'
        return 2
    fi

    download=$(mt_speedtest_json_string \
        '.download_mbps' "$result_file")
    upload=$(mt_speedtest_json_string \
        '.upload_mbps' "$result_file")
    latency=$(mt_speedtest_json_string \
        '.latency_ms' "$result_file")
    loaded_latency=$(mt_speedtest_json_string \
        '.loaded_latency_ms' "$result_file")
    downloaded=$(mt_speedtest_json_string \
        '.downloaded_mb' "$result_file")
    uploaded=$(mt_speedtest_json_string \
        '.uploaded_mb' "$result_file")
    server=$(mt_speedtest_json_string \
        '.server' "$result_file")
    bufferbloat=$(awk -v loaded="$loaded_latency" -v idle="$latency" \
        'BEGIN {
            difference = loaded - idle
            if (difference < 0) difference = 0
            printf "%.2f", difference
        }')

    mt_report_result_block PASS "$title" \
        company 'Empresa/serviço' 'Netflix / Fast.com' \
        servers 'Servidor(es)' "${server:-não informado}" \
        selection 'Seleção do servidor' 'Automática pelo Fast.com' \
        download 'Download' "$download Mbps" \
        upload 'Upload' "$upload Mbps" \
        packet_loss 'Perda de pacotes' 'Não informada pelo Fast.com' \
        unloaded_latency 'Latência sem carga' "$latency ms" \
        loaded_latency 'Latência com carga' "$loaded_latency ms" \
        bufferbloat 'Diferença (bufferbloat)' "$bufferbloat ms" \
        downloaded_data 'Dados recebidos' "${downloaded:-não informado} MB" \
        uploaded_data 'Dados enviados' "${uploaded:-não informado} MB" \
        observation 'Observação' \
            'Integração web experimental; o Fast.com não fornece ID de servidor.' ||
        return $?
}

mt_probe_minhaconexao_info() {
    local url='https://www.minhaconexao.com.br/teste-de-velocidade/velocimetro'

    printf '\nMinha Conexão não publica cliente CLI nem API documentada para '
    printf 'um servidor SSH.\n'
    printf '%s\n' \
        'O teste oficial precisa ser aberto em um navegador e mede a conexão do dispositivo que abriu a página, não desta VM.'
    printf 'Teste oficial: %s\n' "$url"
    printf 'Termos: https://www.minhaconexao.com.br/termos-de-uso\n'
    printf '%s\n' \
        'Por segurança, o menu não acessa APIs internas nem apresenta uma simples consulta HTTP como teste de banda.'

    if [[ -n ${MT_REPORT_FILE:-} ]]; then
        mt_report_note \
            'Minha Conexão: somente orientação para o teste oficial em navegador; nenhuma medição foi executada na VM.'
        mt_report_assessment INFO 'Minha Conexão' \
            'teste de banda indisponível no terminal; use o navegador no endereço oficial.'
    fi
}

mt_probe_iperf_client_interactive() {
    local target
    local port
    local duration
    local streams
    local reverse_answer
    local -a command

    mt_need_command iperf3 iperf3 || return 1
    mt_require_target target 'Servidor iperf3' || return
    mt_require_port port 'Porta do servidor' 5201 || return
    mt_require_integer duration 'Duração em segundos' 10 1 30 || return
    mt_require_integer streams 'Fluxos paralelos' 1 1 8 || return

    command=(iperf3 -c "$target" -p "$port" -t "$duration" -P "$streams")
    mt_prompt reverse_answer 'Sentido reverso, servidor → cliente? (s/N)' N ||
        return 130
    case $reverse_answer in
        s | S | sim | SIM | Sim) command+=(-R) ;;
    esac

    mt_warn 'O iperf3 procura saturar o enlace durante o período configurado.'
    mt_confirm 'Deseja iniciar o teste de banda controlado?' || return 0
    mt_run "iperf3 cliente: $target:$port" "$((duration + 20))" \
        "${command[@]}" || true
}

mt_probe_iperf_server_interactive() {
    local interface
    local bind_address
    local port

    mt_need_command iperf3 iperf3 || return 1
    interface=$(mt_default_interface)
    bind_address=$(mt_default_interface_ip "$interface")

    while true; do
        mt_prompt bind_address 'IP local para escuta' "$bind_address" ||
            return 130
        if mt_valid_ipv4 "$bind_address" || mt_valid_ipv6 "$bind_address"; then
            break
        fi
        mt_error 'Informe um endereço IP local válido.'
    done
    mt_require_port port 'Porta de escuta' 5201 || return

    mt_warn 'O servidor aceitará somente um teste e aguardará por até 5 minutos.'
    mt_warn 'O menu não abrirá portas no firewall.'
    mt_confirm "Iniciar iperf3 em $bind_address:$port?" || return 0

    mt_run "iperf3 servidor temporário: $bind_address:$port" 300 \
        iperf3 -s -1 -B "$bind_address" -p "$port" || true
}

mt_probe_quick() {
    local gateway
    local ping_target=${MENU_TESTE_PING_TARGET:-1.1.1.1}
    local dns_target=${MENU_TESTE_DNS_TARGET:-www.debian.org}
    local http_target=${MENU_TESTE_HTTP_TARGET:-https://www.debian.org/}

    mt_info 'Executando diagnóstico em camadas; nenhuma configuração será alterada.'
    mt_probe_system_summary

    gateway=$(mt_default_gateway)
    if [[ -n $gateway ]]; then
        mt_probe_ping "$gateway" 3 || true
    else
        mt_warn 'Nenhum gateway IPv4 padrão foi encontrado.'
        mt_report_note 'Nenhum gateway IPv4 padrão foi encontrado.'
    fi

    if mt_valid_target "$ping_target"; then
        mt_probe_ping "$ping_target" 3 || true
    fi
    if mt_valid_target "$dns_target"; then
        mt_probe_dns "$dns_target" A '' || true
        mt_probe_configured_dns "$dns_target" || true
    fi
    if mt_valid_url "$http_target"; then
        mt_probe_http "$http_target" || true
    fi

    mt_report_paths
}

mt_probe_noc() {
    local target=$1
    local ports=${2:-22,53,80,443}
    local url=${3:-}

    mt_valid_target "$target" || {
        mt_error 'Alvo inválido para o relatório NOC.'
        return 1
    }
    ports=$(mt_normalize_port_list "$ports") || {
        mt_error 'Lista de portas inválida para o relatório NOC.'
        return 1
    }
    if [[ -n $url ]] && ! mt_valid_url "$url"; then
        mt_error 'URL inválida para o relatório NOC.'
        return 1
    fi

    mt_report_note "Relatório direcionado ao NOC. Alvo: $target; TCP: $ports"
    mt_probe_system_summary

    if mt_command_available getent; then
        mt_run "Resolução pelo sistema: $target" 10 getent ahosts "$target" ||
            true
    fi
    mt_probe_ping "$target" 5 || true
    mt_probe_route "$target" 5 || true
    mt_probe_tcp_ports "$target" "$ports" || true
    [[ -z $url ]] || mt_probe_http "$url" || true

    mt_report_checksum
    mt_report_paths
}

mt_probe_noc_interactive() {
    local target
    local ports
    local url

    mt_require_target target 'Sistema solicitado pelo NOC' || return
    mt_require_port_list ports 'Portas TCP solicitadas' \
        '22,53,80,443' || return
    mt_prompt url 'URL HTTP/HTTPS relacionada (opcional)' '' || return 130
    if [[ -n $url ]] && ! mt_valid_url "$url"; then
        mt_error 'URL inválida; prossiga novamente sem URL ou corrija-a.'
        return 1
    fi
    mt_probe_noc "$target" "$ports" "$url"
}
