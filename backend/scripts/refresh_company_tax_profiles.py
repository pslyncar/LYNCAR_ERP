from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from sqlalchemy import select  # noqa: E402

from app.api.routes.master_companies import sync_company_fiscal_seed  # noqa: E402
from app.core.master_database import MasterSessionLocal  # noqa: E402
from app.models.company import Company  # noqa: E402
from app.services.company_tax_profile import (  # noqa: E402
    apply_lookup_to_company,
    lookup_company_tax_profile,
    only_digits,
)


def main() -> None:
    updated = 0
    skipped = 0
    failed = 0
    with MasterSessionLocal() as db:
        companies = list(db.scalars(select(Company).order_by(Company.name)).all())
        for company in companies:
            document = only_digits(company.document_number)
            if company.person_type != "PJ" or len(document) != 14:
                skipped += 1
                print(f"SKIP {company.code}: sem CNPJ valido")
                continue
            result = lookup_company_tax_profile(document)
            changed = apply_lookup_to_company(company, result)
            if result.status == "found":
                updated += 1 if changed else 0
                print(
                    f"OK {company.code}: regime={company.tax_regime or '-'} "
                    f"crt={company.crt or '-'} fonte={result.source or '-'}"
                )
            else:
                failed += 1
                print(f"PENDENTE {company.code}: {result.message}")
        db.commit()

    with MasterSessionLocal() as db:
        for company in db.scalars(select(Company)).all():
            try:
                sync_company_fiscal_seed(company)
            except Exception as exc:
                print(f"AVISO {company.code}: nao sincronizou fiscal do tenant: {exc}")

    print(f"Concluido. Atualizados={updated} pulados={skipped} pendentes={failed}")


if __name__ == "__main__":
    main()
