ALTER TABLE pdv_terminals ALTER COLUMN terminal_key TYPE VARCHAR(180);
ALTER TABLE pdv_terminals ADD COLUMN IF NOT EXISTS activation_code_hash VARCHAR(180);
ALTER TABLE pdv_terminals ADD COLUMN IF NOT EXISTS activation_code_expires_at TIMESTAMPTZ;
ALTER TABLE pdv_terminals ADD COLUMN IF NOT EXISTS activated_at TIMESTAMPTZ;
ALTER TABLE pdv_terminals ADD COLUMN IF NOT EXISTS activation_status VARCHAR(30) NOT NULL DEFAULT 'active';
ALTER TABLE pdv_terminals ADD COLUMN IF NOT EXISTS machine_name VARCHAR(120);
ALTER TABLE pdv_terminals ADD COLUMN IF NOT EXISTS windows_user VARCHAR(120);
ALTER TABLE pdv_terminals ADD COLUMN IF NOT EXISTS windows_version VARCHAR(120);
ALTER TABLE pdv_terminals ADD COLUMN IF NOT EXISTS device_fingerprint VARCHAR(180);

CREATE INDEX IF NOT EXISTS ix_pdv_terminals_activation_code_hash
    ON pdv_terminals (activation_code_hash);
