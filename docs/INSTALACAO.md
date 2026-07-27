# Instalação

## Requisitos

- Debian 12 (Bookworm), com acesso de root;
- repositórios Debian configurados e resolução DNS funcional;
- espaço livre para os pacotes escolhidos;
- acesso HTTPS ao repositório da Ookla quando `--with-speedtest` ou
  `--recommended` for usado.

O instalador não configura SSH, não cria regras de firewall e não inicia
serviços de escuta. O pacote `iperf3` é configurado para não iniciar como
daemon.

## Perfis

| Perfil | Inclui |
| --- | --- |
| padrão | ferramentas principais de diagnóstico |
| `--with-speedtest` | cliente oficial Ookla e sua fonte APT assinada |
| `--with-fast` | Chromium, driver e Selenium; Fast.com experimental |
| `--advanced` | tcpdump, fping, socat, iftop, bmon, nload e utilitários |
| `--recommended` | padrão + Ookla + Fast.com |
| `--complete` | recomendado + avançado |
| `--skip-packages` | somente arquivos em `/usr/local` |

O perfil recomendado é uma escolha explícita para habilitar os serviços de
terceiros. A instalação em si não aceita uma licença nem executa o teste; a
primeira execução do cliente pode exibir os termos da Ookla. A página do pacote
Ookla informa uso pessoal e não comercial. Confirme a política da organização
antes de usar o cliente em uma operação comercial.

## Instalação local

Depois de obter o código por clone, tarball ou mídia removível:

```bash
cd /caminho/menu-teste
chmod +x install.sh bin/menu-teste libexec/menu-teste/web_speedtest.py \
  scripts/*.sh tests/*.sh uninstall.sh
sudo ./install.sh --recommended
```

Se a VM ainda não tiver `git`, transfira a pasta por SSH a partir da sua
estação e execute o mesmo instalador:

```bash
scp -r menu-teste root@SERVIDOR:/opt/
ssh root@SERVIDOR 'cd /opt/menu-teste && ./install.sh --recommended'
```

Em uma máquina sem `sudo`, abra um shell root e execute os mesmos comandos.
O instalador é idempotente: repetir a mesma opção atualiza os arquivos e
reutiliza o usuário `menu-teste-web` quando ele já existe.

Ao final, a verificação confirma os arquivos instalados, a versão e, quando
solicitado, os executáveis do Speedtest/Chromium/Selenium. Nenhum comando de
medição é chamado nessa etapa.

## Instalação de uma release do GitHub

O caminho mais auditável é baixar uma release, conferir o checksum e executar
o instalador local. Depois de uma release publicada, o bootstrap abaixo faz
essa conferência automaticamente:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/ORGANIZACAO/menu-teste/v0.3.2/scripts/install-online.sh |
  sudo bash -s -- ORGANIZACAO/menu-teste --ref v0.3.2 --recommended
```

`--ref` deve ser uma tag semver (`vX.Y.Z`). O script baixa o tarball e o
arquivo `.sha256` da mesma release, verifica `sha256sum` e só então executa o
`install.sh`. Para ambientes críticos, ainda é preferível clonar e revisar os
arquivos antes de usar root. Não troque a tag por `main`.

## Atualização

```bash
git -C /caminho/menu-teste pull --ff-only
cd /caminho/menu-teste
sudo ./install.sh --recommended
```

Para atualizar por release, baixe uma nova tag e repita a instalação. Pacotes
APT não são removidos quando um perfil é reduzido; isso evita apagar
ferramentas que possam ser usadas por outros diagnósticos.

## Desinstalação

Para remover somente o programa instalado:

```bash
sudo ./uninstall.sh
```

Dependências Debian, Chromium, o usuário isolado e a fonte da Ookla são
preservados por segurança. Se a fonte da Ookla não for mais necessária:

```bash
sudo ./uninstall.sh --remove-ookla-repository
sudo apt-get update
```

Remova pacotes individualmente apenas depois de confirmar que nenhum outro
serviço os utiliza.

## Ambientes com proxy ou sem Internet

Configure o proxy do APT e as variáveis de proxy do `curl` antes de executar o
instalador, conforme a política local. Em ambiente sem saída HTTPS, instale os
pacotes a partir de um mirror interno e use `--skip-packages` somente se as
dependências já estiverem disponíveis. O Fast.com e o Ookla ainda precisarão
de conectividade externa para medir.

## Problemas comuns

- **“Debian 12” recusado:** confirme `ID=debian` e `VERSION_ID=12` em
  `/etc/os-release`.
- **`speedtest-cli` em conflito:** é o cliente Python antigo; remova-o
  explicitamente ou instale sem `--with-speedtest`.
- **Fast.com indisponível:** confirme `chromium`, `chromedriver` e
  `python3-selenium` com `menu-teste verificar`.
- **fonte Ookla indisponível:** valide DNS/HTTPS e a chave APT; o perfil básico
  continua instalável sem o Speedtest.
- **instalação concorrente:** aguarde o outro processo terminar; o lock fica em
  `/run/lock/menu-teste-install.lock`.
