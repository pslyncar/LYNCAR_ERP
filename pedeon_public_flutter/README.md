# PedeOn público

Aplicativo Flutter Web público do **PedeOn by Lyncar**. Ele é separado do ERP
autenticado e abre cada estabelecimento pelo subdomínio da loja, por exemplo
`https://drikapadaria.lyncar.com.br/cardapio`. As rotas antigas
`/public_slug` continuam aceitas para compatibilidade e desenvolvimento local.

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

O servidor de produção precisa encaminhar `/{cardapio,salao}` e as demais rotas
sem extensão para `index.html`, preservando arquivos estáticos normalmente.
O DNS deve apontar `*.lyncar.com.br` para o proxy que hospeda este build, com
HTTPS e certificado curinga. O slug é validado no índice global
`pedeon_public_stores` do banco master; os dados operacionais continuam no
banco isolado de cada empresa.
