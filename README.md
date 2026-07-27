# menu-teste

Menu de diagnóstico de rede para Debian 12, feito para uma máquina de apoio
de TI/NOC. Ele coleta evidências da própria máquina e executa testes
direcionados; não altera rota, DNS, firewall ou interfaces.

O projeto cancela qualquer operação com `Ctrl+C`, encerra os processos filhos e
sai com código `130`. Relatórios ficam privados por padrão e são escritos em
blocos legíveis, uma métrica por linha.

## O que está incluído

- diagnóstico rápido, resumo do sistema, interfaces, rotas, vizinhos e link;
- ping, DNS, traceroute/MTR, portas TCP/UDP autorizadas e serviços leves;
- tempos HTTP/HTTPS e handshake TLS;
- Ookla Speedtest oficial, com seleção automática, listagem e escolha por ID
  ou hostname;
- Fast.com via Chromium/Selenium, experimental e executado por usuário sem
  privilégios;
- Minha Conexão como atalho informativo para o teste oficial no navegador;
- iperf3 como cliente ou servidor temporário;
- relatório NOC em texto, eventos JSON Lines e checksum SHA-256;
- instalador idempotente, verificação offline, testes, pacote de release e CI.

O menu aceita somente um host por vez e no máximo 20 portas explícitas. Não há
varredura de rede, CIDR, NSE ou alteração automática de firewall.

## Instalação rápida

O caminho recomendado é revisar o código clonado e instalar o perfil completo
para os testes de banda:

```bash
git clone https://github.com/francilio-01/menu-teste.git
cd menu-teste
sudo ./install.sh --recommended
```

`--recommended` instala as ferramentas principais, o cliente oficial da Ookla
e o navegador isolado do Fast.com. A instalação não executa nenhuma medição.
Para incluir ferramentas avançadas de observação, como `tcpdump`:

```bash
sudo ./install.sh --complete
```

Perfis equivalentes, para escolher cada componente:

```bash
sudo ./install.sh                    # ferramentas principais
sudo ./install.sh --with-speedtest  # adiciona Ookla
sudo ./install.sh --with-fast       # adiciona Fast.com experimental
sudo ./install.sh --advanced        # adiciona ferramentas avançadas
sudo ./install.sh --skip-packages   # somente os arquivos do programa
```

O instalador exige Debian 12 e root, é não interativo, não habilita o daemon do
iperf3 e não abre portas no firewall. Ao terminar, ele faz uma verificação
local sem consumir banda:

```bash
menu-teste --version
menu-teste verificar
```

Há um bootstrap remoto para releases publicadas. Prefira uma tag e a
verificação SHA-256 automática; não use uma branch móvel em produção:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/francilio-01/menu-teste/v0.3.2/scripts/install-online.sh |
  sudo bash -s -- francilio-01/menu-teste --ref v0.3.2 --recommended
```

O instalador remoto baixa somente o artefato e o checksum da release indicada.
Para ambientes críticos, faça o clone, revise a tag e execute
`./install.sh` localmente. Consulte [docs/INSTALACAO.md](docs/INSTALACAO.md).

## Uso

Como usuário comum:

```bash
menu-teste
menu-teste rapido
menu-teste resumo
menu-teste speedtest
menu-teste speedtest-servidores
menu-teste speedtest 12345
menu-teste speedtest servidor.exemplo
menu-teste fast
menu-teste minhaconexao
menu-teste noc alvo.exemplo 22,53,80,443 https://alvo.exemplo/
```

`speedtest-servidores` lista os servidores Ookla; depois, o ID ou hostname
pode ser passado ao comando `speedtest`. O Fast.com escolhe a CDN
automaticamente. Minha Conexão apenas apresenta o endereço oficial, porque
não existe uma CLI/API pública documentada para medir a partir de SSH.

Veja a referência completa em [docs/USO.md](docs/USO.md) e a organização
interna em [docs/ARQUITETURA.md](docs/ARQUITETURA.md).

## Relatórios

Por padrão, cada sessão é salva com permissão `0600` em
`~/.local/state/menu-teste/relatorios/`:

- `.txt`: revisão humana e envio controlado ao NOC;
- `.jsonl`: eventos estruturados para automação;
- `.sha256`: checksum quando o relatório é concluído.

Um bloco de velocidade segue esta ordem:

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

A data/hora usa `HH:MM DD/MM/AAAA` no fuso local do sistema. Revise os
relatórios antes de compartilhá-los: resultados de banda podem conter IPs,
identificadores de interface, hostnames e rotas.

## Segurança e limites

Use o menu somente em ativos, portas e serviços autorizados. Ookla, Fast.com e
iperf3 podem consumir uma parcela significativa do link. O Fast.com é
experimental e depende de uma página de terceiros; o cliente Ookla é
distribuído pelo repositório externo da Ookla e deve ser usado conforme os
termos aplicáveis (a página do pacote informa uso pessoal e não comercial).

O perfil `--advanced` instala captura e observação de tráfego, mas não inicia
captura automaticamente. O usuário `menu-teste-web` limita o navegador do
Fast.com. Mais orientações estão em [docs/SEGURANCA.md](docs/SEGURANCA.md) e
[SECURITY.md](SECURITY.md).

## Desenvolvimento

Requisitos de desenvolvimento: Bash, Python 3, `jq` e as ferramentas listadas
no instalador. No Debian 12:

```bash
./scripts/verify-project.sh
make test
make lint                 # requer shellcheck
make package
```

Os testes usam executáveis falsos e não fazem Speedtest, Fast.com, iperf3 ou
varredura real. O workflow em `.github/workflows/ci.yml` repete essa validação
em um container Debian 12. Tags `vX.Y.Z` podem acionar a publicação automática
de um pacote e seu checksum; revise as permissões do repositório antes de
habilitar isso.

## Licença

Nenhuma licença foi escolhida ainda. Antes de publicar este repositório como
software aberto, adicione uma licença (por exemplo, MIT, Apache-2.0 ou
GPL-3.0) com o titular correto. Sem um arquivo `LICENSE`, permanecem
reservados os direitos autorais padrão. Veja o checklist em
[docs/PUBLICACAO_GITHUB.md](docs/PUBLICACAO_GITHUB.md).
