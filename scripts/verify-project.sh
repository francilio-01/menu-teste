#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

PROJECT_DIR=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$PROJECT_DIR"

fail() {
    printf '[FALHA] %s\n' "$*" >&2
    exit 1
}

EXPECTED_FILES=(
    .editorconfig
    .gitignore
    CHANGELOG.md
    CONTRIBUTING.md
    Makefile
    README.md
    SECURITY.md
    VERSION
    install.sh
    uninstall.sh
    bin/menu-teste
    lib/menu-teste/common.sh
    lib/menu-teste/validate.sh
    lib/menu-teste/report.sh
    lib/menu-teste/probes.sh
    libexec/menu-teste/web_speedtest.py
    scripts/install-online.sh
    scripts/package-release.sh
    scripts/run-tests.sh
    scripts/verify-project.sh
    .github/workflows/ci.yml
    .github/workflows/release.yml
)

for path in "${EXPECTED_FILES[@]}"; do
    [[ -f $path ]] || fail "Arquivo obrigatório ausente: $path"
    [[ ! -L $path ]] || fail "Arquivo obrigatório não pode ser link simbólico: $path"
done

for path in \
    install.sh uninstall.sh bin/menu-teste \
    libexec/menu-teste/web_speedtest.py \
    scripts/*.sh tests/*.sh; do
    [[ -x $path ]] || fail "Arquivo que deveria ser executável: $path"
done

version_file=$(tr -d '[:space:]' < VERSION)
[[ $version_file =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    fail "VERSION inválida: $version_file"

menu_version=$(sed -n 's/^MT_VERSION=//p' bin/menu-teste | head -n 1)
common_version=$(sed -n \
    's/^MT_VERSION=${MT_VERSION:-\([0-9][0-9.]*\)}$/\1/p' \
    lib/menu-teste/common.sh | head -n 1)
[[ $menu_version == "$version_file" ]] ||
    fail "Versão divergente em bin/menu-teste: $menu_version != $version_file"
[[ $common_version == "$version_file" ]] ||
    fail "Versão divergente em common.sh: $common_version != $version_file"

mapfile -t shell_files < <(find . -type f -name '*.sh' -not -path './.git/*' -print | sort)
(( ${#shell_files[@]} > 0 )) || fail 'Nenhum script Bash foi encontrado.'
bash -n "${shell_files[@]}"

python3 - <<'PY'
from pathlib import Path

for path in sorted(Path(".").rglob("*.py")):
    if any(part in {".git", "__pycache__"} for part in path.parts):
        continue
    compile(path.read_bytes(), str(path), "exec")
PY

./scripts/run-tests.sh

printf 'Validação do projeto concluída para menu-teste v%s.\n' "$version_file"
