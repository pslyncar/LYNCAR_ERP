# Correcao PDV - source teste em vendas - 2026-06-30

## Sintoma
PDV da Drika mostrava:
- Falha ao carregar
- Nao foi possivel carregar vendas
- Nao foi possivel carregar os dados do PDV

## Causa real
Endpoint `GET /sales` retornava 500 por `ResponseValidationError`.
Havia vendas antigas com `source = "teste"`, mas o schema `SaleSource` aceitava apenas `pdv`, `venda`, `os`.

## Correcao
- `backend/app/schemas/sale.py`: `SaleSource` agora tambem tolera `teste`.
- `backend/app/migrate_local.py`: normaliza dados antigos:
  `UPDATE sales SET source = 'pdv' WHERE source = 'teste';`

## Validacao local
- `py_compile` OK.
- `python -m app.migrate_local` OK.
- Banco local ficou com sales source apenas `pdv`.
- API local reiniciada em `127.0.0.1:8000`.

## Entrega
`C:\Users\vpape\Documents\Codex\2026-06-18\files-mentioned-by-the-user-captura\outputs\ATUALIZACAO_BACKEND_2026-06-30_CORRIGE_PDV_SOURCE_TESTE.zip`
