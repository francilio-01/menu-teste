#!/usr/bin/env bash

set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

REMOVE_OOKLA=0

usage() {
    cat <<'EOF'
Remove os arquivos instalados pelo menu-teste.

Uso:
  sudo ./uninstall.sh [--remove-ookla-repository]

Por segurança, as dependências Debian, o Chromium e o usuário
menu-teste-web não são removidos automaticamente. A opção extra remove apenas
o arquivo de fonte e o keyring da Ookla; confirme a remoção dos pacotes
separadamente, conforme a política do servidor.
EOF
}

fail() {
    printf '[FALHA] %s\n' "$*" >&2
    exit 1
}

for argument in "$@"; do
    case $argument in
        --remove-ookla-repository) REMOVE_OOKLA=1 ;;
        --help | -h)
            usage
            exit 0
            ;;
        *) fail "Opção desconhecida: $argument" ;;
    esac
done

((EUID == 0)) || fail 'Execute como root: sudo ./uninstall.sh'

for file in \
    /usr/local/bin/menu-teste \
    /usr/local/libexec/menu-teste/web_speedtest.py \
    /usr/local/lib/menu-teste/common.sh \
    /usr/local/lib/menu-teste/validate.sh \
    /usr/local/lib/menu-teste/report.sh \
    /usr/local/lib/menu-teste/probes.sh; do
    if [[ -f $file && ! -L $file ]]; then
        rm -f -- "$file"
        printf '[INFO] Removido: %s\n' "$file"
    fi
done

rmdir /usr/local/libexec/menu-teste 2>/dev/null || true
rmdir /usr/local/lib/menu-teste 2>/dev/null || true

if ((REMOVE_OOKLA == 1)); then
    rm -f -- \
        /etc/apt/sources.list.d/ookla-speedtest.list \
        /etc/apt/keyrings/ookla-speedtest-archive-keyring.gpg
    printf '%s\n' '[INFO] Fonte e keyring da Ookla removidos.'
    printf '%s\n' '[INFO] Rode apt-get update se a fonte não for mais usada.'
fi

printf '%s\n' 'Arquivos do menu-teste removidos; dependências do sistema foram preservadas.'
