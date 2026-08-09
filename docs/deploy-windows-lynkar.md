# Deploy Windows 11 Pro - Lynkar

Este guia e para usar um computador Windows 11 Pro como servidor de testes/producao inicial.

## Estrutura recomendada no servidor

```text
C:\Lynkar\
  ERP-PAPEZZOSYNC\
  backups\
  logs\
```

## Funcoes de cada maquina

Maquina de desenvolvimento:

- Codex.
- Flutter/Dart.
- Edicao do sistema.
- Testes locais.

Servidor Windows:

- PostgreSQL.
- Backend FastAPI.
- Build web Flutter.
- Dominio/DDNS.
- Backups.

## Dominio

Dominio comprado: `lynkar.com.br`.

Sugestao:

- `lynkar.com.br`: site institucional.
- `app.lynkar.com.br`: sistema web.
- `api.lynkar.com.br`: API.

Enquanto o IP for dinamico, usar DuckDNS/No-IP para apontar para o IP publico da sua rede e depois criar CNAME no DNS do dominio.

## Portas

Para teste interno:

- Web: `5000`.
- API: `8000`.

Para publicar na internet de forma correta:

- Usar proxy reverso na porta `443` com HTTPS.
- Evitar expor diretamente `5000` e `8000` ao publico.

## Primeira instalacao no servidor

1. Instale no servidor:
   - Git.
   - Python 3.12+.
   - PostgreSQL.
   - Flutter, se o build web for feito no servidor.

2. Copie ou clone o projeto para:

```text
C:\Lynkar\ERP-PAPEZZOSYNC
```

3. Rode:

```powershell
cd C:\Lynkar\ERP-PAPEZZOSYNC
.\deploy\windows\server-install.ps1
```

4. Edite:

```text
C:\Lynkar\ERP-PAPEZZOSYNC\backend\.env
```

Troque:

- senha do PostgreSQL.
- `SECRET_KEY`.
- senha do master admin.
- dominio/CORS quando estiver publicando.

5. Rode novamente:

```powershell
.\deploy\windows\server-install.ps1
.\deploy\windows\server-update.ps1
.\deploy\windows\server-start.ps1
```

## Login master

No `.env` de producao, definir:

```text
MASTER_COMPANY_CODE=master
MASTER_ADMIN_EMAIL=admin@lynkar.com.br
MASTER_ADMIN_PASSWORD=senha_forte
```

Login:

```text
Empresa: master
E-mail: admin@lynkar.com.br
Senha: senha_forte
```

## Atualizacao do servidor

Depois de desenvolver nesta maquina:

1. Enviar atualizacao via Git ou copia controlada.
2. No servidor:

```powershell
cd C:\Lynkar\ERP-PAPEZZOSYNC
.\deploy\windows\server-update.ps1
.\deploy\windows\server-start.ps1
```

## Ponte por pasta compartilhada

Use a pasta compartilhada apenas para transferencia.

Na maquina de desenvolvimento:

```powershell
cd C:\Users\vpape\Documents\ERP-PAPEZZOSYNC
.\deploy\windows\export-to-transfer-share.ps1 -SharePath "\\NOME-DO-SERVIDOR\LynkarTransfer" -IncludeVault
```

Sem copiar o Vault:

```powershell
.\deploy\windows\export-to-transfer-share.ps1 -SharePath "\\NOME-DO-SERVIDOR\LynkarTransfer"
```

O script cria uma pasta como:

```text
\\NOME-DO-SERVIDOR\LynkarTransfer\lynkar-export-AAAAMMDD-HHMMSS
```

Dentro dela ficam:

- ZIP do projeto.
- ZIP opcional do Vault Obsidian.
- `LEIA-ME-SERVIDOR.txt` com os passos para extrair no servidor.

No servidor, extrair o projeto para:

```text
C:\Lynkar\ERP-PAPEZZOSYNC
```

Nao rodar o sistema diretamente pela pasta compartilhada.

## Obsidian/Cerebro

Nao editar o mesmo Vault simultaneamente em duas maquinas por pasta de rede.

Recomendado:

- Vault principal fica na maquina de desenvolvimento.
- Fazer backup/copia para o servidor.
- Quando trabalhar direto no servidor, usar uma copia sincronizada com cuidado ou registrar as decisoes depois no Vault principal.

## Proximo passo

Configurar no servidor:

- PostgreSQL.
- DuckDNS/No-IP.
- DNS do `lynkar.com.br`.
- HTTPS.
- rotina de backup automatico do PostgreSQL.
