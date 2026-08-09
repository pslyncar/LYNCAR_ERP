# Caixa de XML por e-mail

Este Worker recebe e-mails enviados para:

`xml+<empresa>-<token>@lyncar.com.br`

Ele extrai anexos XML e envia cada arquivo ao endpoint seguro do ERP.

## Publicacao

Requisitos:

- Node.js LTS.
- Acesso a conta Cloudflare do dominio `lyncar.com.br`.

Comandos:

```powershell
cd C:\Lynkar\ERP-PAPEZZOSYNC\deploy\cloudflare\xml-email-worker
npm install
npx wrangler login
$envText = Get-Content -Raw C:\Lynkar\ERP-PAPEZZOSYNC\backend\.env
$secret = [regex]::Match($envText, '(?m)^XML_INBOUND_SECRET=(.*)$').Groups[1].Value.Trim()
$secret | npx wrangler secret put XML_INBOUND_SECRET
npm run deploy
```

O valor informado em `wrangler secret put` deve ser exatamente o mesmo de
`XML_INBOUND_SECRET` no `backend\.env` do servidor.

Depois, no painel Cloudflare:

1. Abra **Compute > Email Service > Email Routing**.
2. Para cada empresa, crie uma regra literal para o endereco XML exibido no ERP.
3. Configure a acao da regra para enviar ao Worker `lyncar-xml-email-inbound`.

O catch-all da Cloudflare nao aceita Worker como acao. Por isso cada empresa
precisa de uma regra literal para seu endereco individual.
