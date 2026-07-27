#!/usr/bin/env bash

set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

CORE_PACKAGES=(
    ca-certificates
    coreutils
    curl
    jq
    iproute2
    iputils-ping
    bind9-dnsutils
    traceroute
    mtr-tiny
    netcat-openbsd
    nmap
    iperf3
    ethtool
    openssl
    python3-minimal
    util-linux
    passwd
    hostname
    mawk
)

ADVANCED_PACKAGES=(
    tcpdump
    iputils-arping
    iputils-tracepath
    fping
    tcptraceroute
    socat
    iftop
    bmon
    nload
    whois
)

FAST_PACKAGES=(
    chromium
    chromium-driver
    chromium-sandbox
    python3-selenium
)

WITH_SPEEDTEST=0
WITH_FAST=0
WITH_ADVANCED=0
SKIP_PACKAGES=0
KEY_TEMP=
KEYRING_TEMP=
INSTALL_LOCK_FD=

usage() {
    cat <<'EOF'
Instalador do menu-teste para Debian 12

Uso:
  sudo ./install.sh [opções]

Opções:
  --recommended     Instala o perfil recomendado: Ookla + Fast.com
  --complete        Instala o perfil recomendado e ferramentas avançadas
  --with-speedtest  Adiciona o repositório oficial da Ookla e instala speedtest
  --with-fast       Instala Chromium/Selenium para o Fast.com experimental
  --advanced        Instala ferramentas avançadas, incluindo tcpdump
  --skip-packages   Instala somente os arquivos do menu-teste
  --help            Mostra esta ajuda

Instalação recomendada, sem perguntas:
  sudo ./install.sh --recommended

O instalador não habilita iperf3 como daemon e não altera o firewall.
EOF
}

fail() {
    printf '[FALHA] %s\n' "$*" >&2
    exit 1
}

info() {
    printf '[INFO] %s\n' "$*"
}

cleanup() {
    if [[ -n ${KEY_TEMP:-} && -f $KEY_TEMP ]]; then
        rm -f -- "$KEY_TEMP"
    fi
    if [[ -n ${KEYRING_TEMP:-} && -f $KEYRING_TEMP ]]; then
        rm -f -- "$KEYRING_TEMP"
    fi
}

package_installed() {
    dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null |
        grep -qx 'install ok installed'
}

verify_command() {
    local command_name=$1

    command -v "$command_name" >/dev/null 2>&1 ||
        fail "Verificação final: comando ausente: $command_name"
}

verify_installation() {
    local installed_version
    local installed_file
    local command_name

    info 'Verificando a instalação sem executar testes de rede ou de banda...'

    for installed_file in \
        /usr/local/bin/menu-teste \
        /usr/local/lib/menu-teste/common.sh \
        /usr/local/lib/menu-teste/validate.sh \
        /usr/local/lib/menu-teste/report.sh \
        /usr/local/lib/menu-teste/probes.sh \
        /usr/local/libexec/menu-teste/web_speedtest.py; do
        [[ -r $installed_file ]] ||
            fail "Verificação final: arquivo ausente: $installed_file"
    done
    [[ -x /usr/local/bin/menu-teste ]] ||
        fail 'Verificação final: /usr/local/bin/menu-teste não é executável.'
    [[ -x /usr/local/libexec/menu-teste/web_speedtest.py ]] ||
        fail 'Verificação final: o coletor web não é executável.'

    installed_version=$(/usr/local/bin/menu-teste --version) ||
        fail 'Verificação final: não foi possível iniciar o menu-teste.'
    [[ $installed_version == menu-teste\ * ]] ||
        fail "Verificação final: versão inesperada: $installed_version"

    if ((SKIP_PACKAGES == 0)); then
        for command_name in \
            ip ss ping dig curl nc traceroute mtr nmap iperf3 ethtool \
            openssl jq python3 timeout runuser flock useradd getent \
            hostname awk; do
            verify_command "$command_name"
        done
    fi

    if ((WITH_SPEEDTEST == 1)); then
        package_installed speedtest ||
            fail "Verificação final: o pacote oficial 'speedtest' não está instalado."
        verify_command speedtest
    fi

    if ((WITH_FAST == 1)); then
        verify_command chromium
        verify_command chromedriver
        python3 -c 'import selenium' >/dev/null 2>&1 ||
            fail 'Verificação final: o módulo Python selenium não está disponível.'
        getent passwd menu-teste-web >/dev/null 2>&1 ||
            fail "Verificação final: o usuário isolado 'menu-teste-web' não existe."
        [[ -d /var/lib/menu-teste-web ]] ||
            fail 'Verificação final: o diretório do navegador isolado não existe.'
    fi

    info "Verificação concluída: $installed_version"
}

trap cleanup EXIT
trap 'printf "[FALHA] Instalação interrompida na linha %s.\\n" "$LINENO" >&2' ERR

for argument in "$@"; do
    case $argument in
        --recommended)
            WITH_SPEEDTEST=1
            WITH_FAST=1
            ;;
        --complete)
            WITH_SPEEDTEST=1
            WITH_FAST=1
            WITH_ADVANCED=1
            ;;
        --with-speedtest) WITH_SPEEDTEST=1 ;;
        --with-fast) WITH_FAST=1 ;;
        --advanced) WITH_ADVANCED=1 ;;
        --skip-packages) SKIP_PACKAGES=1 ;;
        --help | -h)
            usage
            exit 0
            ;;
        *)
            fail "Opção desconhecida: $argument"
            ;;
    esac
done

if ((WITH_SPEEDTEST == 1 && SKIP_PACKAGES == 1)); then
    fail '--with-speedtest não pode ser combinado com --skip-packages.'
fi
if ((WITH_FAST == 1 && SKIP_PACKAGES == 1)); then
    fail '--with-fast não pode ser combinado com --skip-packages.'
fi
if ((WITH_ADVANCED == 1 && SKIP_PACKAGES == 1)); then
    fail '--advanced não pode ser combinado com --skip-packages.'
fi

((EUID == 0)) || fail 'Execute este instalador como root: sudo ./install.sh'

SCRIPT_DIR=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[[ -r "$SCRIPT_DIR/bin/menu-teste" ]] ||
    fail 'Arquivo bin/menu-teste não encontrado.'
[[ -r "$SCRIPT_DIR/libexec/menu-teste/web_speedtest.py" ]] ||
    fail 'Arquivo libexec/menu-teste/web_speedtest.py não encontrado.'
for library in common.sh validate.sh report.sh probes.sh; do
    [[ -r "$SCRIPT_DIR/lib/menu-teste/$library" ]] ||
        fail "Biblioteca ausente: lib/menu-teste/$library"
done

if [[ -r /etc/os-release ]]; then
    OS_ID=$(sed -n 's/^ID=//p' /etc/os-release | head -n 1)
    OS_ID=${OS_ID%\"}
    OS_ID=${OS_ID#\"}
    OS_VERSION=$(sed -n 's/^VERSION_ID=//p' /etc/os-release | head -n 1)
    OS_VERSION=${OS_VERSION%\"}
    OS_VERSION=${OS_VERSION#\"}
else
    fail '/etc/os-release não foi encontrado.'
fi

if [[ $OS_ID != debian || $OS_VERSION != 12 ]]; then
    fail "Este instalador foi preparado para Debian 12; detectado: $OS_ID $OS_VERSION."
fi

for source_file in \
    "$SCRIPT_DIR/bin/menu-teste" \
    "$SCRIPT_DIR/libexec/menu-teste/web_speedtest.py" \
    "$SCRIPT_DIR/lib/menu-teste/common.sh" \
    "$SCRIPT_DIR/lib/menu-teste/validate.sh" \
    "$SCRIPT_DIR/lib/menu-teste/report.sh" \
    "$SCRIPT_DIR/lib/menu-teste/probes.sh"; do
    [[ -f $source_file && ! -L $source_file ]] ||
        fail "A origem precisa ser um arquivo regular (sem link): $source_file"
done

command -v flock >/dev/null 2>&1 ||
    fail 'O comando flock não está disponível; instale util-linux antes de continuar.'
install -d -m 0755 /run/lock
exec {INSTALL_LOCK_FD}>/run/lock/menu-teste-install.lock
flock -n "$INSTALL_LOCK_FD" ||
    fail 'Já existe outra instalação do menu-teste em andamento.'

if ((WITH_SPEEDTEST == 1)) && package_installed speedtest-cli; then
    fail "O pacote Python 'speedtest-cli' está instalado e conflita com o cliente oficial. Remova-o explicitamente antes de repetir a instalação."
fi

if ((SKIP_PACKAGES == 0)); then
    info 'Atualizando o índice de pacotes...'
    apt-get update

    info 'Garantindo que o iperf3 não seja configurado como daemon...'
    DEBIAN_FRONTEND=noninteractive apt-get install -y debconf
    printf '%s\n' 'iperf3 iperf3/start_daemon boolean false' |
        debconf-set-selections

    info 'Instalando ferramentas principais de diagnóstico...'
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${CORE_PACKAGES[@]}"

    if ((WITH_ADVANCED == 1)); then
        info 'Instalando ferramentas avançadas...'
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${ADVANCED_PACKAGES[@]}"
    fi

    if ((WITH_FAST == 1)); then
        info 'Instalando o navegador isolado do Fast.com...'
        DEBIAN_FRONTEND=noninteractive apt-get install -y \
            --no-install-recommends "${FAST_PACKAGES[@]}"
    fi
fi

if ((WITH_SPEEDTEST == 1)); then
    info 'Configurando o repositório assinado da Ookla para Debian 12...'
    DEBIAN_FRONTEND=noninteractive apt-get install -y gnupg ca-certificates curl
    install -d -m 0755 /etc/apt/keyrings

    KEY_TEMP=$(mktemp /tmp/menu-teste-ookla-key.XXXXXXXX)
    KEYRING_TEMP=$(mktemp /tmp/menu-teste-ookla-keyring.XXXXXXXX)
    curl -fsSL \
        https://packagecloud.io/ookla/speedtest-cli/gpgkey \
        -o "$KEY_TEMP"
    gpg --batch --yes --dearmor \
        --output "$KEYRING_TEMP" \
        "$KEY_TEMP"
    install -o root -g root -m 0644 \
        "$KEYRING_TEMP" /etc/apt/keyrings/ookla-speedtest-archive-keyring.gpg
    rm -f -- "$KEYRING_TEMP"
    KEYRING_TEMP=

    printf '%s\n' \
        'deb [signed-by=/etc/apt/keyrings/ookla-speedtest-archive-keyring.gpg] https://packagecloud.io/ookla/speedtest-cli/debian/ bookworm main' \
        > /etc/apt/sources.list.d/ookla-speedtest.list
    chmod 0644 /etc/apt/sources.list.d/ookla-speedtest.list

    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y speedtest
    package_installed speedtest ||
        fail "O pacote oficial 'speedtest' não ficou instalado."
    rm -f -- "$KEY_TEMP"
    KEY_TEMP=
    info 'Speedtest oficial instalado e repositório configurado.'
fi

if ((WITH_FAST == 1)); then
    if ! getent passwd menu-teste-web >/dev/null 2>&1; then
        info "Criando o usuário sem privilégios 'menu-teste-web'..."
        useradd --system --home-dir /var/lib/menu-teste-web \
            --create-home --shell /usr/sbin/nologin menu-teste-web
    fi
    install -d -o menu-teste-web -g menu-teste-web -m 0700 \
        /var/lib/menu-teste-web
fi

info 'Instalando os arquivos do menu-teste...'
install -d -o root -g root -m 0755 /usr/local/lib/menu-teste
install -d -o root -g root -m 0755 /usr/local/libexec/menu-teste
install -o root -g root -m 0644 \
    "$SCRIPT_DIR/lib/menu-teste/common.sh" \
    "$SCRIPT_DIR/lib/menu-teste/validate.sh" \
    "$SCRIPT_DIR/lib/menu-teste/report.sh" \
    "$SCRIPT_DIR/lib/menu-teste/probes.sh" \
    /usr/local/lib/menu-teste/
install -o root -g root -m 0755 \
    "$SCRIPT_DIR/bin/menu-teste" \
    /usr/local/bin/menu-teste
install -o root -g root -m 0755 \
    "$SCRIPT_DIR/libexec/menu-teste/web_speedtest.py" \
    /usr/local/libexec/menu-teste/web_speedtest.py

verify_installation

info 'Instalação concluída.'
printf '\nExecute como usuário comum:\n  menu-teste\n\n'
printf 'Verifique as ferramentas:\n  menu-teste verificar\n'
