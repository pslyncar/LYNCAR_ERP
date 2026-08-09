# 2026-07-01 - Notas fiscais: trocar cliente somente na emissao fiscal

## Pedido
Na tela de Notas fiscais, ao emitir nota a partir de uma venda, permitir trocar o cliente/destinatario se necessario, mas sem alterar a venda original/notinha.

## Implementado
- Na montagem da nota fiscal, adicionado bloco **Cliente/destinatario fiscal**.
- Botao **Trocar cliente** abre janela com clientes cadastrados.
- Janela permite buscar por:
  - nome;
  - CPF/CNPJ;
  - telefone;
  - e-mail;
  - cidade.
- Botao **Usar** seleciona o cliente para aquela nota.
- Botao **Usar da venda** limpa a troca e volta para o cliente original da venda.

## Regra de negocio
- A troca nao altera a venda.
- A troca nao altera cupom/notinha original.
- A troca vale apenas para a nota fiscal preparada/autorizada naquele momento.
- Se nenhum cliente fiscal for selecionado, continua usando o cliente da venda.

## Backend
- Criado campo opcional `fiscal_client_id` em `fiscal_documents`.
- API `prepare` e `prepare-with-items` aceitam `fiscal_client_id`.
- Ao autorizar, o motor monta a visao fiscal da venda usando `document.fiscal_client` quando existir; senao usa `sale.client`.
- Para NF-e, continuam valendo as validacoes de destinatario completo.

## Banco
Aplicar em cada banco de cliente/tenant:

```sql
ALTER TABLE fiscal_documents
  ADD COLUMN IF NOT EXISTS fiscal_client_id INTEGER;

CREATE INDEX IF NOT EXISTS ix_fiscal_documents_fiscal_client_id
  ON fiscal_documents (fiscal_client_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_fiscal_documents_fiscal_client_id_clients'
  ) THEN
    ALTER TABLE fiscal_documents
      ADD CONSTRAINT fk_fiscal_documents_fiscal_client_id_clients
      FOREIGN KEY (fiscal_client_id)
      REFERENCES clients(id)
      ON DELETE SET NULL;
  END IF;
END $$;
```

## Validacao
- `python -m compileall`: ok
- `dart format`: ok
- `flutter analyze`: sem erros
- `flutter build web --release --no-pub`: ok

## Entrega
- `C:\Users\vpape\Documents\Codex\2026-06-18\files-mentioned-by-the-user-captura\outputs\ERP_NOTAS_FISCAIS_TROCAR_CLIENTE_FISCAL_2026-07-01`
- `C:\Users\vpape\Documents\Codex\2026-06-18\files-mentioned-by-the-user-captura\outputs\ERP_NOTAS_FISCAIS_TROCAR_CLIENTE_FISCAL_2026-07-01.zip`
