# Relatórios

## Onde ficam

Cada execução inicializa um relatório privado em:

```text
~/.local/state/menu-teste/relatorios/
```

`MENU_TESTE_REPORT_DIR` pode apontar para outro diretório. O programa cria a
pasta com permissões restritas e os arquivos com `0600`, quando o sistema
permite. O caminho do último texto pode ser obtido com:

```bash
menu-teste --ultimo-relatorio
```

## Formato legível

Os resultados são apresentados em blocos. Para uma medição de velocidade, a
identificação do serviço vem primeiro; cada métrica ocupa sua própria linha:

```text
Empresa/servidor: Exemplo Telecom
ID do servidor: 12345
Hostname: speed.example.net
Localização: São Paulo, BR
Seleção solicitada: seleção automática
Download: 500.12 Mbps
Upload: 100.08 Mbps
Perda de pacotes: 0%
Latência (ping): 8.42 ms
Jitter: 1.10 ms
Observação: teste concluído
Data/hora: 14:35 26/07/2026
```

Nem todo provedor retorna todas as métricas. A última linha dos blocos e das
sessões é `Data/hora: HH:MM DD/MM/AAAA`, baseada no relógio e fuso local da
máquina.

Um cancelamento registra a observação de interrupção e termina com código
`130`. Isso permite distinguir cancelamento de falha de conectividade.

## JSON Lines

O arquivo `.jsonl` contém eventos independentes, um objeto JSON por linha. Ele
é adequado para ingestão posterior, mas pode conter os mesmos dados sensíveis
do texto: IP público, hostname do servidor, rota, MAC e detalhes de interface.
Não trate um JSONL de diagnóstico como dado anônimo.

## Checksum e envio ao NOC

O checksum `.sha256` ajuda a provar que um arquivo não mudou depois da coleta.
Ele não cifra nem remove dados. Antes de anexar um relatório:

1. confirme o host, a janela do teste e a autorização;
2. retire credenciais, cookies, tokens e URLs internas que não sejam
   necessários;
3. valide se IPs, MACs, rotas e nomes de clientes podem ser compartilhados;
4. envie por canal aprovado e conserve o original privado.

Não versionar relatórios reais, capturas de pacote, arquivos HAR ou dumps no
GitHub. O `.gitignore` do projeto cobre extensões comuns, mas a revisão humana
continua obrigatória.
