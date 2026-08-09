-- Lyncar - contratos de clientes no banco master
-- Aplicar no banco MASTER.

ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS contract_signed_at DATE,
    ADD COLUMN IF NOT EXISTS contract_expires_at DATE,
    ADD COLUMN IF NOT EXISTS contract_file_url TEXT,
    ADD COLUMN IF NOT EXISTS contract_file_name VARCHAR(220),
    ADD COLUMN IF NOT EXISTS contract_notes TEXT;

CREATE INDEX IF NOT EXISTS ix_companies_contract_expires_at
    ON companies (contract_expires_at);
