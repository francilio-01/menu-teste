#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

PROJECT_DIR=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$PROJECT_DIR"

./tests/test-validacoes.sh
./tests/test-sigint.sh
./tests/test-speedtest.sh
./tests/test-web-speedtests.sh
./tests/test-report-block.sh
