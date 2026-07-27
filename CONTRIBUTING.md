# Contribuindo

## Antes de enviar uma alteração

1. mantenha o escopo em diagnóstico autorizado e somente leitura;
2. não inclua relatórios reais, PCAPs, HAR, credenciais ou topologia de
   produção;
3. atualize a documentação quando mudar um comando, dependência ou formato;
4. incremente a versão apenas em uma release planejada.

Execute no clone:

```bash
./scripts/verify-project.sh
make lint
```

Os testes devem continuar sem acesso a banda, sem DNS externo obrigatório e
sem listener persistente. Use os executáveis falsos já presentes em `tests/`
para novas integrações.

## Estilo

- Bash com `set -euo pipefail` em scripts de instalação/apoio;
- valide toda entrada que chega a uma ferramenta externa;
- use aspas em caminhos e argumentos;
- mantenha mensagens e documentação em português claro;
- preserve `Ctrl+C` com saída `130`;
- não registre segredos em stdout, relatórios ou logs.

Abra um pull request com descrição do risco operacional, testes executados e
eventuais mudanças de dependência. O CI roda em Debian 12 e não executa
Speedtest, Fast.com, iperf3 ou varreduras reais.
