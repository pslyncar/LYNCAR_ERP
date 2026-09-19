# Lyna: pesquisa sob demanda

A pesquisa externa só é acionada quando o cliente pede informação atual, recente, vigente ou uma fonte. Não existe radar automático, agendamento, push, alerta proativo ou mensagem de “impacto” para clientes.

- A pesquisa é limitada a assuntos do Lyncar e fontes oficiais/documentação técnica aprovada.
- Tenant, usuário e permissões da sessão continuam valendo.
- Nenhum resultado externo grava no banco ou altera o motor fiscal.
- Para fiscal, o motor determinístico do Lyncar continua sendo a autoridade final.

## Servidor Debian

O recurso fica desligado por padrão. Depois de disponibilizar SearXNG localmente no servidor, configure no `.env` da API:

```env
LYNA_WEB_SEARCH_ENABLED=true
LYNA_SEARCH_URL=http://127.0.0.1:8080
LYNA_SEARCH_TIMEOUT_SECONDS=8
LYNA_SEARCH_MAX_RESULTS=5
```

Se a pesquisa não responder, a Lyna continua usando a base interna e os dados autorizados; não há fallback para uma busca livre.
