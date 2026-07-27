# Publicação no GitHub

A pasta foi preparada para virar um repositório independente, mas não foi
inicializado nem recebeu um remote porque o nome da conta e a URL ainda não
foram informados.

## Checklist antes do primeiro push

- [ ] trocar a senha/credenciais usadas na implantação da VM;
- [ ] escolher e adicionar `LICENSE` com o titular correto;
- [ ] substituir `ORGANIZACAO/menu-teste` nos exemplos, se desejado;
- [ ] revisar `README.md`, termos da Ookla e a política de uso do NOC;
- [ ] confirmar que não há relatórios, PCAPs, chaves, cookies ou `.env`;
- [ ] executar `./scripts/verify-project.sh`;
- [ ] executar `./scripts/package-release.sh` e conferir o checksum;
- [ ] proteger `main` e tags de release no GitHub;
- [ ] revisar permissões do workflow de release (`contents: write`).

Sem `LICENSE`, o GitHub pode armazenar o código, mas terceiros não recebem
permissão automática para reutilizar, modificar ou redistribuir.

## Criar o repositório e enviar

Crie no GitHub um repositório vazio, sem README, licença ou `.gitignore`
gerados pelo site. Depois, no terminal:

```bash
cd "/caminho/para/menu-teste"
git init
git branch -M main
git add .
git diff --cached --check
git commit -m "Initial release v0.3.2"
git remote add origin https://github.com/ORGANIZACAO/menu-teste.git
git push -u origin main
```

Se o repositório já tiver conteúdo, faça `git fetch` e integre-o
deliberadamente; não sobrescreva histórico de outra pessoa.

## Criar uma release

Depois que o CI passar:

```bash
git tag -a v0.3.2 -m "menu-teste v0.3.2"
git push origin v0.3.2
```

O workflow `release.yml` valida a tag contra `VERSION`,
`bin/menu-teste` e `common.sh`, gera o tarball e publica o arquivo de checksum.
A publicação automática deve ser usada apenas com tags protegidas e revisão
humana do diff.

## Instalar uma release

Com a release publicada:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/ORGANIZACAO/menu-teste/v0.3.2/scripts/install-online.sh |
  sudo bash -s -- ORGANIZACAO/menu-teste --ref v0.3.2 --recommended
```

Para maior controle, baixe os dois artefatos da página da release, rode
`sha256sum -c menu-teste-0.3.2.tar.gz.sha256`, extraia, revise e execute
`sudo ./install.sh --recommended`.
