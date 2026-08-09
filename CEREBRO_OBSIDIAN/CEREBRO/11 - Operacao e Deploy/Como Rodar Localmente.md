# Como Rodar Localmente

## Backend

```powershell
cd D:\BACKUP_ERP_PAPEZZOSYNC_2026-06-12_06-40-11\01_SISTEMA_COMPLETO\ERP-PAPEZZOSYNC\backend
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

API:

```text
http://127.0.0.1:8000/docs
```

## App administrativo web

```powershell
cd D:\BACKUP_ERP_PAPEZZOSYNC_2026-06-12_06-40-11\01_SISTEMA_COMPLETO\ERP-PAPEZZOSYNC\admin_app\admin_flutter
C:\Users\vpape\Documents\DevTools\flutter\bin\flutter.bat run -d web-server --web-hostname 127.0.0.1 --web-port 5000
```

## Caminhos operacionais

- Sistema local/teste: `D:\BACKUP_ERP_PAPEZZOSYNC_2026-06-12_06-40-11\01_SISTEMA_COMPLETO\ERP-PAPEZZOSYNC`.
- Vault/CEREBRO do Obsidian: `D:\BACKUP_ERP_PAPEZZOSYNC_2026-06-12_06-40-11\03_CEREBRO_OBSIDIAN\CEREBRO`.
- HD externo de pacotes para servidor: `E:\`.

O `E:` deve ser usado para gerar/guardar pacotes de atualizacao e roteiros de servidor, como `E:\ATUALIZACAO_PAPEZZOSYNC_*`. Nao editar o sistema tomando o pacote do `E:` como fonte principal.

App:

```text
http://127.0.0.1:5000
```

## Site comercial Lyncar

Projeto separado do ERP:

```powershell
cd C:\Users\vpape\Documents\lyncarsite
D:\BACKUP_ERP_PAPEZZOSYNC_2026-06-12_06-40-11\04_FERRAMENTAS_SDKS\flutter\bin\flutter.bat build web --release
cd C:\Users\vpape\Documents\lyncarsite\build\web
python -m http.server 5050 --bind 127.0.0.1
```

Site:

```text
http://127.0.0.1:5050
```

Uso: landing page publica para `lyncar.com.br`, com planos e solicitacao via WhatsApp `(19) 93503-1782` ou email `pslyncar@gmail.com`. Nao misturar com a porta `5000` do ERP administrativo.
