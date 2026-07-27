# Segurança operacional

## Escopo autorizado

Execute sondagens somente em ativos, portas, URLs e servidores sob autorização
da organização. Um ping bloqueado não prova indisponibilidade; uma conexão TCP
aberta não prova que a aplicação está saudável; UDP sem resposta pode ser
filtrado ou simplesmente não responder.

O projeto não faz varredura de CIDR, não aceita scripts NSE e não modifica
firewall, rota, DNS ou interfaces. O limite de 20 portas explícitas reduz
enganos, mas não transforma um teste não autorizado em permitido.

## Privilégios

O instalador exige root porque escreve em `/usr/local` e instala pacotes. O
menu deve ser executado como usuário comum. Sondagens que exigem privilégio
informam isso na tela.

Quando o Fast.com está habilitado, Chromium/Selenium roda com o usuário de
sistema `menu-teste-web`, home separado e shell `nologin`. Não reutilize esse
perfil para outras tarefas nem copie cookies para ele.

## Dados e relatórios

Relatórios podem conter endereços IP, MACs, nomes DNS, rotas, identificadores
de servidores e URLs internas. Mantenha `0600`, use armazenamento criptografado
quando necessário e revise o conteúdo antes de enviá-lo. Nunca publique:

- senhas, chaves privadas, tokens, cookies ou arquivos `.env`;
- relatórios reais, PCAP/HAR, dumps ou logs de produção;
- inventário de clientes, topologia interna ou endereços que não sejam
  necessários para o chamado.

O `.gitignore` é uma rede de proteção, não uma classificação automática de
informação.

## Conexões externas

O perfil Ookla adiciona o repositório APT assinado da Ookla. O pacote é de
terceiro e a página do fornecedor informa uso pessoal e não comercial; avalie
termos, privacidade e aprovação jurídica antes de usá-lo em um NOC.

Fast.com usa a página oficial em Chromium headless. A implementação não
inverte endpoints privados nem apresenta uma consulta HTTP como medição. Uma
mudança na página pode quebrar o coletor; trate o resultado como experimental.
Minha Conexão somente abre a orientação para o teste oficial em navegador.

## Instalação e cadeia de suprimentos

Prefira clonar uma tag, revisar o conteúdo e executar `install.sh` localmente.
O bootstrap online aceita apenas tags semver e valida o SHA-256 do artefato da
release (integridade do download, não uma assinatura criptográfica do
mantenedor); ainda assim, proteja tags e revise o workflow antes de conceder
`contents: write`.

Não execute scripts recebidos por mensagem sem revisar a origem. Troque
credenciais da VM compartilhadas durante a implantação antes de publicar
qualquer documentação.

## Vulnerabilidades

Não abra uma issue pública com detalhes exploráveis. Use o canal privado
descrito em [SECURITY.md](../SECURITY.md) ou o recurso Private Vulnerability
Reporting do GitHub, quando habilitado.
