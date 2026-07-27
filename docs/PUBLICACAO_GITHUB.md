# Publicação no GitHub

O projeto está publicado como repositório público em:

```text
https://github.com/francilio-01/menu-teste
```

## Checklist antes do primeiro push

- [ ] trocar a senha/credenciais usadas na implantação da VM;
- [ ] escolher e adicionar `LICENSE` com o titular correto;
- [x] substituir os exemplos pela URL pública do projeto;
- [ ] revisar `README.md`, termos da Ookla e a política de uso do NOC;
- [ ] confirmar que não há relatórios, PCAPs, chaves, cookies ou `.env`;
- [x] executar `./scripts/verify-project.sh`;
- [x] executar `./scripts/package-release.sh` e conferir o checksum;
- [ ] proteger `main` e tags de release no GitHub;
- [ ] revisar permissões do workflow de release (`contents: write`).

Sem `LICENSE`, o GitHub pode armazenar o código, mas terceiros não recebem
permissão automática para reutilizar, modificar ou redistribuir.

## Clonar o repositório

Para obter uma nova cópia:

```bash
git clone https://github.com/francilio-01/menu-teste.git
cd menu-teste
```

Em uma cópia local que ainda não possua remote:

```bash
git remote add origin https://github.com/francilio-01/menu-teste.git
git push -u origin main
```

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
  https://raw.githubusercontent.com/francilio-01/menu-teste/v0.3.2/scripts/install-online.sh |
  sudo bash -s -- francilio-01/menu-teste --ref v0.3.2 --recommended
```

Para maior controle, baixe os dois artefatos da página da release, rode
`sha256sum -c menu-teste-0.3.2.tar.gz.sha256`, extraia, revise e execute
`sudo ./install.sh --recommended`.
