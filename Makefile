SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

.PHONY: help test verify lint package install-recommended install-complete

help:
	@printf '%s\n' \
	  'make test               Executa a suíte sem testes reais de banda' \
	  'make verify             Valida estrutura, sintaxe e suíte completa' \
	  'make lint               Executa ShellCheck (se instalado)' \
	  'make package            Gera dist/menu-teste-VERSAO.tar.gz + SHA256' \
	  'make install-recommended Instala Ookla + Fast.com (como root)' \
	  'make install-complete   Inclui também ferramentas avançadas (como root)'

test:
	@./scripts/run-tests.sh

verify:
	@./scripts/verify-project.sh

lint:
	@command -v shellcheck >/dev/null 2>&1 || { \
	  printf '%s\n' 'ShellCheck não está instalado. No Debian: apt-get install shellcheck.' >&2; \
	  exit 1; \
	}
	@shellcheck -S warning -e SC2128,SC2178 -x -P SCRIPTDIR \
	  install.sh bin/menu-teste scripts/*.sh
	@shellcheck -S warning -e SC2016 -x -P SCRIPTDIR tests/*.sh

package:
	@./scripts/package-release.sh

install-recommended:
	@[ "$$(id -u)" -eq 0 ] || { printf '%s\n' 'Execute como root: sudo ./install.sh --recommended' >&2; exit 1; }
	@./install.sh --recommended

install-complete:
	@[ "$$(id -u)" -eq 0 ] || { printf '%s\n' 'Execute como root: sudo ./install.sh --complete' >&2; exit 1; }
	@./install.sh --complete
