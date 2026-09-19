# 2026-09-17 - Entradas: compatibilidade com sessão web

## Sintoma

Na tela **Entradas**, a Caixa de XML interrompia todo o carregamento com
`Token de acesso ausente.` mesmo com o usuário autenticado no ERP web.

## Causa

Depois da migração para sessão web por cookie HttpOnly, a rota
`/xml-inbox/settings` ainda usava `HTTPBearer` diretamente. Esse componente
só procura `Authorization: Bearer ...` e ignora a sessão por cookie. Como a
tela carrega as configurações da Caixa de XML junto de produtos, fornecedores e
recebimentos, essa única falha derrubava o painel inteiro.

## Correção

- A rota de Caixa de XML passou a usar `bearer_scheme` de
  `app.api.dependencies`, o autenticador compartilhado que aceita tanto o
  bearer legado quanto a sessão web por cookie.
- Não houve mudança em estoque, notas, XMLs ou permissões.
- Criado teste de regressão garantindo que a Caixa de XML use a dependência de
  sessão compatível.

## Arquivos

- `backend/app/api/routes/xml_inbox.py`
- `backend/tests/test_xml_inbox_web_session.py`

## Verificação

- `pytest tests/test_xml_inbox_web_session.py tests/test_web_session_cookie_isolation.py -q`
- Resultado: **3 passed**.

## Publicação pendente

O domínio `padariadrika.lyncar.com.br` é servido por outra máquina em
`C:\Lynkar\ERP-PAPEZZOSYNC`; esta estação não possui essa cópia do servidor.
Depois de o código chegar ao repositório oficial, aplicar no servidor com backup,
`git pull`, `server-update.ps1` e `server-start.ps1`.
