-- Ajuste de precisao de preco unitario para PDV/vendas.
-- Rodar em cada banco tenant/cliente.
-- Motivo: ERPs/PDVs trabalham com preco unitario com mais casas decimais,
-- mas total da linha, total da venda e pagamentos continuam com 2 casas.

ALTER TABLE products
    ALTER COLUMN sale_price TYPE NUMERIC(12, 4) USING sale_price::NUMERIC(12, 4),
    ALTER COLUMN offer_price TYPE NUMERIC(12, 4) USING offer_price::NUMERIC(12, 4);

ALTER TABLE sale_items
    ALTER COLUMN unit_price TYPE NUMERIC(12, 4) USING unit_price::NUMERIC(12, 4);

