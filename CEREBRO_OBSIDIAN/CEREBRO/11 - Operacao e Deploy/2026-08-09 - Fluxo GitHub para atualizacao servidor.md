# 2026-08-09 - Fluxo GitHub para atualizacao do servidor

## Repositorio oficial
- GitHub: `https://github.com/pslyncar/LYNCAR_ERP.git`
- Branch principal: `main`
- Repositorio local de desenvolvimento: `C:\erp_build`
- Repositorio servidor: `C:\Lynkar\ERP-PAPEZZOSYNC`

## Estado alinhado em 2026-08-09
- Commit alinhado entre local, GitHub e servidor: `32d6c84 Alinha ajustes do servidor no GitHub`
- Tag do pacote fiscal do dia: `pacote-servidor-2026-08-09`

## Regra oficial
O GitHub passa a ser a fonte central do codigo.

Fluxo correto:

1. Desenvolvimento acontece no notebook/local.
2. Alteracoes sao commitadas no Git local.
3. Alteracoes sao enviadas para GitHub com `git push`.
4. Servidor consulta o GitHub antes de atualizar.
5. Servidor faz backup antes de puxar mudancas.
6. Servidor roda migracoes/build/restart apos `git pull`.

## Como verificar no servidor se existe atualizacao

```powershell
cd C:\Lynkar\ERP-PAPEZZOSYNC
git fetch origin main
git status
git log --oneline HEAD..origin/main
```

Interpretacao:

- Se `git log HEAD..origin/main` nao mostrar nada, o servidor ja esta igual ao GitHub.
- Se mostrar commits, existe atualizacao pendente para puxar.

## Como aplicar atualizacao no servidor

Antes de aplicar:

1. Fazer backup da pasta `C:\Lynkar\ERP-PAPEZZOSYNC`.
2. Se houver alteracao de banco/fiscal/migracao, fazer dump do banco master e dos tenants.

Depois:

```powershell
cd C:\Lynkar\ERP-PAPEZZOSYNC
git pull origin main
.\deploy\windows\server-update.ps1
.\deploy\windows\server-start.ps1
```

## Validacao apos atualizar

- Conferir API.
- Conferir site/app web.
- Conferir favicon/icones.
- Conferir login master.
- Conferir tenant principal.
- Se houver fiscal, validar tela fiscal, checklist, certificado/configuracao e emissao/sincronizacao em homologacao antes de producao.

## Observacoes importantes

- Nao passar senha do GitHub para o Codex.
- Autenticacao deve ser feita via Git Credential Manager, navegador ou conector autorizado.
- Atualizacao automatica sem aprovacao nao e recomendada neste momento, porque o sistema tem ERP fiscal, banco de dados e NF-e/NFC-e.
- Para producao, sempre atualizar com autorizacao e backup.
