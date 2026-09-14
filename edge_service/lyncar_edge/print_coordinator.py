from __future__ import annotations

from .database import EdgeDatabase
from .printers import production_ticket, raw_print


class PrintCoordinator:
    def __init__(self, database: EdgeDatabase):
        self.database = database

    def process(self, limit: int = 10) -> dict:
        printed = 0
        failures: list[str] = []
        for job in self.database.claim_bound_print_jobs(limit):
            try:
                content = production_ticket(job["payload"])
                for _ in range(max(1, min(int(job["copies"]), 5))):
                    raw_print(
                        str(job["printer_name"]),
                        content,
                        f"PedeOn {job['job_key']}",
                    )
                self.database.finish_local_print_job(
                    int(job["id"]), "edge-auto", "printed", None
                )
                printed += 1
            except Exception as exc:  # spooler errors must return to the durable queue
                message = str(exc)[:1000]
                self.database.finish_local_print_job(
                    int(job["id"]), "edge-auto", "failed", message
                )
                failures.append(message)
        return {"printed": printed, "failures": failures}

    def test(self, printer_name: str, logical_name: str) -> None:
        raw_print(
            printer_name,
            production_ticket(
                {
                    "display_number": "TESTE",
                    "station_name": logical_name,
                    "source_channel": "configuracao_local",
                    "items": [
                        {
                            "quantity": "1",
                            "description": "Impressora configurada com sucesso",
                            "modifiers": [],
                        }
                    ],
                }
            ),
            "PedeOn - teste de impressora",
        )
