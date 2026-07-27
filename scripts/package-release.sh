#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

PROJECT_DIR=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$PROJECT_DIR"

fail() {
    printf '[FALHA] %s\n' "$*" >&2
    exit 1
}

version=$(tr -d '[:space:]' < VERSION)
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    fail "Versão inválida em VERSION: $version"
menu_version=$(sed -n 's/^MT_VERSION=//p' bin/menu-teste | head -n 1)
common_version=$(sed -n \
    's/^MT_VERSION=${MT_VERSION:-\([0-9][0-9.]*\)}$/\1/p' \
    lib/menu-teste/common.sh | head -n 1)
[[ $menu_version == "$version" && $common_version == "$version" ]] ||
    fail "Versões divergentes: VERSION=$version bin=$menu_version common=$common_version"

archive_name="menu-teste-${version}.tar.gz"
checksum_name="menu-teste-${version}.tar.gz.sha256"
dist_dir="$PROJECT_DIR/dist"
temp_dir=$(mktemp -d /tmp/menu-teste-package.XXXXXXXX)
staging_dir="$temp_dir/menu-teste-${version}"

cleanup() {
    if [[ -d $temp_dir ]]; then
        find "$temp_dir" -depth -type f -exec unlink {} \; 2>/dev/null || true
        find "$temp_dir" -depth -type l -exec unlink {} \; 2>/dev/null || true
        find "$temp_dir" -depth -type d -exec rmdir {} \; 2>/dev/null || true
    fi
}
trap cleanup EXIT

install -d -m 0755 "$staging_dir"
for entry in \
    .editorconfig .github .gitignore CHANGELOG.md CONTRIBUTING.md \
    Makefile README.md SECURITY.md VERSION bin docs install.sh uninstall.sh \
    lib libexec \
    scripts tests; do
    [[ -e $entry ]] || fail "Entrada ausente para o pacote: $entry"
    cp -a -- "$entry" "$staging_dir/"
done
if [[ -e LICENSE ]]; then
    cp -a -- LICENSE "$staging_dir/"
fi

install -d -m 0755 "$dist_dir"
rm -f -- "$dist_dir/$archive_name" "$dist_dir/$checksum_name"

tar --sort=name --mtime='UTC 1970-01-01' \
    --owner=0 --group=0 --numeric-owner \
    -C "$temp_dir" -cf - "menu-teste-${version}" |
    gzip -n -9 > "$dist_dir/$archive_name"

(cd "$dist_dir" && sha256sum "$archive_name" > "$checksum_name")

printf 'Pacote criado:\n  %s\n  %s\n' \
    "$dist_dir/$archive_name" "$dist_dir/$checksum_name"
