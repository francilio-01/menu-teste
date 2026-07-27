#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

usage() {
    cat <<'EOF'
Instala uma versão publicada do menu-teste a partir do GitHub.

Uso:
  install-online.sh ORGANIZACAO/REPOSITORIO --ref vX.Y.Z [opções-do-install.sh]

Exemplo (tag fixada):
  curl -fsSL https://raw.githubusercontent.com/ORGANIZACAO/menu-teste/v0.3.2/scripts/install-online.sh |
    sudo bash -s -- ORGANIZACAO/menu-teste --ref v0.3.2 --recommended

O script baixa o tarball e o checksum da release, confere sha256sum e somente
então chama o install.sh. A revisão por clone continua sendo a opção preferida
para ambientes de produção.
EOF
}

fail() {
    printf '[FALHA] %s\n' "$*" >&2
    exit 1
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    usage
    exit 0
fi

((EUID == 0)) || fail 'Execute como root (sudo bash -s -- ...).'
[[ $# -ge 1 ]] || {
    usage >&2
    exit 2
}

repository=$1
shift
[[ $repository =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
    fail "Repositório inválido: $repository"

[[ ${1:-} == --ref ]] || fail 'Informe uma tag imutável: --ref vX.Y.Z'
[[ $# -ge 2 ]] || fail '--ref precisa de um valor.'
ref=$2
shift 2
[[ $ref =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] ||
    fail "Ref inválida: $ref"
[[ $ref != *..* && $ref != *//* && $ref != */.* && $ref != *./* ]] ||
    fail "Ref rejeitada por segurança: $ref"
[[ $ref =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    fail 'A ref precisa ser uma tag semver no formato vX.Y.Z.'
version=${ref#v}

if (($# == 0)); then
    set -- --recommended
fi

command -v curl >/dev/null 2>&1 || fail 'curl é necessário para baixar a versão.'
command -v tar >/dev/null 2>&1 || fail 'tar é necessário para extrair a versão.'
command -v sha256sum >/dev/null 2>&1 ||
    fail 'sha256sum é necessário para verificar a versão.'

temp_dir=$(mktemp -d /tmp/menu-teste-bootstrap.XXXXXXXX)
cleanup() {
    if [[ -d $temp_dir ]]; then
        find "$temp_dir" -depth -type f -exec unlink {} \; 2>/dev/null || true
        find "$temp_dir" -depth -type d -exec rmdir {} \; 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

checksum="$temp_dir/source.sha256"
archive_name="menu-teste-${version}.tar.gz"
archive="$temp_dir/$archive_name"
url="https://github.com/${repository}/releases/download/${ref}/${archive_name}"
checksum_url="${url}.sha256"
printf '[INFO] Baixando %s@%s\n' "$repository" "$ref"
curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
    "$url" -o "$archive"
curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
    "$checksum_url" -o "$checksum"
(cd "$temp_dir" && sha256sum -c "$(basename -- "$checksum")" >/dev/null)
tar -xzf "$archive" --no-same-owner -C "$temp_dir"

mapfile -t extracted_dirs < <(
    find "$temp_dir" -mindepth 1 -maxdepth 1 -type d -print
)
(( ${#extracted_dirs[@]} == 1 )) ||
    fail 'O arquivo baixado não possui uma única pasta de projeto.'
project_dir=${extracted_dirs[0]}
[[ -f $project_dir/install.sh ]] ||
    fail 'install.sh não foi encontrado na revisão baixada.'

printf '[INFO] Executando o instalador local da revisão baixada.\n'
bash "$project_dir/install.sh" "$@"
