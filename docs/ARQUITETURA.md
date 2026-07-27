# Arquitetura do projeto

```text
bin/menu-teste                         entrada e despacho de comandos
lib/menu-teste/common.sh               terminal, sinais e utilitários
lib/menu-teste/validate.sh             validação de alvos e argumentos
lib/menu-teste/report.sh               texto, JSONL, timestamp e checksum
lib/menu-teste/probes.sh               sondas de rede e integrações de banda
libexec/menu-teste/web_speedtest.py    coletor Chromium/Selenium do Fast.com
install.sh                             instalação local no Debian 12
uninstall.sh                           remoção segura dos arquivos instalados
scripts/install-online.sh              bootstrap de release GitHub verificada
scripts/verify-project.sh              validação offline do código e testes
scripts/package-release.sh             tarball determinístico + SHA-256
tests/                                 testes com fakes e teste de Ctrl+C
docs/                                  operação, instalação e publicação
.github/workflows/                     CI e release sem medições reais
```

O executável em `bin/` localiza primeiro as bibliotecas ao lado do projeto e,
depois, as cópias instaladas em `/usr/local`. Assim é possível testar no clone
sem alterar o sistema e, após a instalação, chamar apenas `menu-teste`.

As sondas não fazem shell remoto com argumentos fornecidos pelo operador.
Entradas são validadas antes de chegar a `ping`, `dig`, `nmap`, `curl`,
`traceroute`, `mtr`, Ookla ou iperf3. O tratamento de `SIGINT` fica no processo
principal; o PID do processo ativo é encerrado antes da saída.

O instalador instala somente arquivos conhecidos, com proprietário `root:root`
e modos explícitos. O navegador opcional tem usuário e home separados. A
verificação final chama apenas `menu-teste --version` e verifica dependências;
ela nunca executa banda.

## Fluxo de desenvolvimento

1. editar o clone;
2. executar `./scripts/verify-project.sh`;
3. revisar um relatório sintético se alterar `report.sh`;
4. gerar `./scripts/package-release.sh`;
5. escolher a licença, revisar segredos e criar a tag;
6. deixar o CI executar os testes antes de publicar.

Os testes de Speedtest/Fast.com simulam os executáveis e o runner web. Nenhum
workflow dispara uma medição externa ou abre um listener iperf3.
