from __future__ import annotations

import logging
import threading

from sqlalchemy import select

from app.core.master_database import MasterSessionLocal
from app.models.company import Company
from app.models.company_billing import CompanyBilling
from app.services.company_billing import (
    apply_overdue_charges_for_company_in_session,
    billing_today,
)
from app.services.mercado_pago import create_pix_for_billing

logger = logging.getLogger(__name__)

BILLING_AUTOMATION_INTERVAL_SECONDS = 30.0


class BillingAutomationWorker:
    """Keeps unpaid billing amounts and Pix charges current without UI access."""

    def __init__(self) -> None:
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._last_processed_date = None
        self._retry_ids: set[int] = set()

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(
            target=self._run,
            name="billing-automation",
            daemon=True,
        )
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        thread = self._thread
        if thread and thread.is_alive():
            thread.join(timeout=5)

    @staticmethod
    def _active_company_ids() -> list[int]:
        with MasterSessionLocal() as db:
            return list(
                db.scalars(
                    select(Company.id).where(
                        Company.active.is_(True),
                        Company.status == "active",
                    )
                ).all()
            )

    def _process_company(
        self,
        company_id: int,
        today,
        apply_policy: bool,
        retry_ids: set[int],
    ) -> tuple[set[int], bool]:
        billing_ids = set(retry_ids)

        try:
            with MasterSessionLocal() as db:
                company = db.get(Company, company_id)
                if company is None:
                    return set(), True

                if apply_policy:
                    changed = apply_overdue_charges_for_company_in_session(
                        db,
                        company,
                        today=today,
                    )
                    billing_ids.update(
                        row.id for row in changed if row.id is not None
                    )

                if billing_ids:
                    billing_ids = set(
                        db.scalars(
                            select(CompanyBilling.id).where(
                                CompanyBilling.company_id == company_id,
                                CompanyBilling.id.in_(billing_ids),
                                CompanyBilling.status != "paid",
                            )
                        ).all()
                    )
                db.commit()
        except Exception:
            logger.exception(
                "Failed to apply billing policy for company %s", company_id
            )
            return billing_ids, False

        failed: set[int] = set()
        for billing_id in billing_ids:
            try:
                with MasterSessionLocal() as db:
                    billing = db.get(CompanyBilling, billing_id)
                    if billing is None or billing.status == "paid":
                        continue
                    create_pix_for_billing(db, billing)
                    db.commit()
            except Exception:
                logger.exception(
                    "Failed to refresh Pix for billing %s", billing_id
                )
                failed.add(billing_id)
        return failed, True

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                today = billing_today()
                apply_policy = self._last_processed_date != today
                company_ids = self._active_company_ids()
                next_retry_ids: set[int] = set()
                all_ok = True

                for company_id in company_ids:
                    failed, ok = self._process_company(
                        company_id,
                        today,
                        apply_policy,
                        self._retry_ids,
                    )
                    next_retry_ids.update(failed)
                    all_ok = all_ok and ok

                self._retry_ids = next_retry_ids
                if all_ok:
                    self._last_processed_date = today
            except Exception:
                logger.exception("Billing automation cycle failed")

            self._stop.wait(BILLING_AUTOMATION_INTERVAL_SECONDS)


billing_automation_worker = BillingAutomationWorker()
