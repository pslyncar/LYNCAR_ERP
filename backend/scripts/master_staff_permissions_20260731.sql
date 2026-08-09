BEGIN;

CREATE TABLE IF NOT EXISTS master_user_permissions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES master_users(id) ON DELETE CASCADE,
    permission_code VARCHAR(80) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_master_user_permission UNIQUE (user_id, permission_code)
);

CREATE INDEX IF NOT EXISTS ix_master_user_permissions_user_id
    ON master_user_permissions (user_id);

CREATE INDEX IF NOT EXISTS ix_master_user_permissions_permission_code
    ON master_user_permissions (permission_code);

COMMIT;
