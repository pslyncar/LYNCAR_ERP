import json
import os
from sqlalchemy import create_engine, text
from app.core.master_database import MasterSessionLocal
from app.models.company import Company

backup_dir = r"E:\LynkarBackups\drika-receivables-20260901-20260915"
os.makedirs(backup_dir, exist_ok=True)
with MasterSessionLocal() as master:
    company = master.query(Company).filter(Company.code == "padariadrika").one()
engine = create_engine(company.database_url)
with engine.begin() as conn:
    rows = conn.execute(text("""
        select * from receivables
        where created_at >= '2026-09-01 00:00:00-03'
          and created_at < '2026-09-16 00:00:00-03'
        order by id
    """)).mappings().all()
    ids = [row["id"] for row in rows]
    payments = []
    if ids:
        payments = conn.execute(
            text("select * from receivable_payments where receivable_id = any(:ids)"),
            {"ids": ids},
        ).mappings().all()
    with open(os.path.join(backup_dir, "before.json"), "w", encoding="utf-8") as f:
        json.dump({"receivables": [dict(row) for row in rows], "payments": [dict(row) for row in payments]}, f, default=str, ensure_ascii=False, indent=2)
    if ids:
        conn.execute(text("delete from receivable_payments where receivable_id = any(:ids)"), {"ids": ids})
        conn.execute(text("delete from receivables where id = any(:ids)"), {"ids": ids})
print(f"deleted receivables={len(rows)} payments={len(payments)} backup={backup_dir}")
