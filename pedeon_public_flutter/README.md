# PedeOn público

Aplicativo Flutter Web público do **PedeOn by Lyncar**. Ele é separado do ERP
autenticado e abre cada estabelecimento pela rota `/{public_slug}`.

## Desenvolvimento local

```powershell
flutter run -d web-server --web-port 5001 `
  --dart-define=PEDEON_API_URL=http://127.0.0.1:8000
```

## Build

```powershell
flutter build web --release `
  --dart-define=PEDEON_API_URL=https://api.lyncar.com.br
```

O servidor de produção precisa encaminhar rotas sem extensão para
`index.html`, preservando arquivos estáticos normalmente.
