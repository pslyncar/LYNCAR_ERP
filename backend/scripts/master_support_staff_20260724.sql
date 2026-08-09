-- Lyncar - suporte interno e funcionarios master
-- Aplicar no banco MASTER, nao nos bancos das empresas.

CREATE TABLE IF NOT EXISTS master_user_permissions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES master_users(id) ON DELETE CASCADE,
    permission_code VARCHAR(80) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_master_user_permission UNIQUE (user_id, permission_code)
);

CREATE INDEX IF NOT EXISTS ix_master_user_permissions_user_id
    ON master_user_permissions (user_id);

CREATE INDEX IF NOT EXISTS ix_master_user_permissions_permission_code
    ON master_user_permissions (permission_code);

CREATE TABLE IF NOT EXISTS master_support_tickets (
    id SERIAL PRIMARY KEY,
    company_id INTEGER NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    company_code VARCHAR(80) NOT NULL,
    company_name VARCHAR(180) NOT NULL,
    module VARCHAR(40) NOT NULL DEFAULT 'outro',
    priority VARCHAR(20) NOT NULL DEFAULT 'normal',
    status VARCHAR(30) NOT NULL DEFAULT 'aberto',
    subject VARCHAR(180) NOT NULL,
    description TEXT NOT NULL,
    requester_user_id INTEGER,
    requester_name VARCHAR(150),
    requester_email VARCHAR(180),
    assigned_master_user_id INTEGER REFERENCES master_users(id) ON DELETE SET NULL,
    first_response_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,
    last_message_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_master_support_tickets_company_id
    ON master_support_tickets (company_id);

CREATE INDEX IF NOT EXISTS ix_master_support_tickets_company_code
    ON master_support_tickets (company_code);

CREATE INDEX IF NOT EXISTS ix_master_support_tickets_status
    ON master_support_tickets (status);

CREATE INDEX IF NOT EXISTS ix_master_support_tickets_priority
    ON master_support_tickets (priority);

CREATE INDEX IF NOT EXISTS ix_master_support_tickets_assigned_master_user_id
    ON master_support_tickets (assigned_master_user_id);

CREATE TABLE IF NOT EXISTS master_support_messages (
    id SERIAL PRIMARY KEY,
    ticket_id INTEGER NOT NULL REFERENCES master_support_tickets(id) ON DELETE CASCADE,
    author_type VARCHAR(20) NOT NULL,
    author_user_id INTEGER,
    author_name VARCHAR(150),
    author_email VARCHAR(180),
    body TEXT NOT NULL,
    attachment_url TEXT,
    attachment_name VARCHAR(220),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_master_support_messages_ticket_id
    ON master_support_messages (ticket_id);
