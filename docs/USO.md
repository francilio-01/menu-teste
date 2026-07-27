# Uso

## Menu interativo

Execute `menu-teste` sem argumentos. As áreas principais são diagnóstico
rápido, resumo do sistema, portas, HTTP/TLS, rota e banda. Em qualquer pergunta
ou submenu, `Ctrl+C` cancela a operação atual e encerra o programa com código
`130`; não é necessário matar processos manualmente.

Use `0` para voltar ou sair quando essa opção estiver disponível. O relatório
da sessão permanece no diretório configurado mesmo quando uma medição é
cancelada.

## Comandos diretos

| Comando | Finalidade |
| --- | --- |
| `rapido` | interface, gateway, Internet, DNS e HTTPS |
| `resumo` | sistema, interfaces, rotas, vizinhos e link |
| `ping ALVO [N]` | N pings para um host |
| `dns NOME [TIPO] [DNS]` | consulta DNS direcionada |
| `porta ALVO PORTAS` | portas TCP separadas por vírgula |
| `http URL` | tempos HTTP/HTTPS |
| `rota ALVO [CICLOS]` | traceroute/MTR |
| `speedtest` | Ookla com servidor automático |
| `speedtest-servidores` | lista servidores Ookla próximos |
| `speedtest ID` | Ookla por ID numérico |
| `speedtest HOSTNAME` | Ookla por hostname |
| `fast` | Fast.com experimental |
| `minhaconexao` | endereço oficial, sem medição SSH |
| `noc ALVO [PORTAS] [URL]` | bloco de evidências para o NOC |
| `verificar` | dependências instaladas |
| `--ultimo-relatorio` | caminho do último relatório `.txt` |

Exemplos:

```bash
menu-teste ping 192.168.1.1 5
menu-teste dns exemplo.com A 1.1.1.1
menu-teste porta servidor.exemplo 22,53,80,443
menu-teste noc servidor.exemplo 22,80,443 https://servidor.exemplo/status
```

Os alvos são validados para impedir opções de ferramentas, espaços e
expansões de shell. Isso não substitui autorização operacional.

## Escolha do servidor Ookla

1. Liste servidores:

   ```bash
   menu-teste speedtest-servidores
   ```

2. Copie o ID ou hostname exibido e execute:

   ```bash
   menu-teste speedtest 12345
   # ou
   menu-teste speedtest servidor.speedtest.exemplo
   ```

Sem argumento, `speedtest` usa a seleção automática da Ookla. A lista e a
disponibilidade dos servidores mudam ao longo do tempo.

## Testes de banda e cautela

Speedtest, Fast.com e iperf3 são testes ativos. Combine horário, duração e
servidor com a equipe responsável pelo link. O Fast.com seleciona uma CDN
Netflix automaticamente e pode não representar o mesmo caminho do provedor
usado pela Ookla.

`iperf3 servidor` abre um listener temporário somente durante a execução e não
altera o firewall. Interrompa com `Ctrl+C` ao terminar. Para um teste entre
duas pontas, autorize a porta no caminho antes de iniciar.

## Relatórios e variáveis

O diretório padrão é `~/.local/state/menu-teste/relatorios/`. Para usar um
local privado diferente:

```bash
MENU_TESTE_REPORT_DIR=/var/lib/relatorios-noc menu-teste noc host 22,443
```

Também podem ser definidos `MENU_TESTE_PING_TARGET`,
`MENU_TESTE_DNS_TARGET`, `MENU_TESTE_HTTP_TARGET` e `NO_COLOR=1`. Consulte
[RELATORIOS.md](RELATORIOS.md) para o formato e a revisão dos dados.

## Códigos de saída

- `0`: comando concluído;
- `1`: falha do teste ou dependência ausente;
- `2`: uso ou argumento inválido;
- `130`: cancelamento por `Ctrl+C`.
