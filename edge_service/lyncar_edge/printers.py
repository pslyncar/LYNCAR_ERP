from __future__ import annotations

import ctypes
from ctypes import wintypes
import json
import socket
import subprocess


def installed_printers() -> list[str]:
    """Return Windows printers without requiring pywin32."""
    if not hasattr(ctypes, "windll"):
        return []
    command = (
        "Get-Printer | Select-Object -ExpandProperty Name | "
        "ConvertTo-Json -Compress"
    )
    result = subprocess.run(
        ["powershell", "-NoProfile", "-NonInteractive", "-Command", command],
        capture_output=True,
        text=True,
        timeout=10,
        check=True,
    )
    raw = result.stdout.strip()
    if not raw:
        return []
    parsed = json.loads(raw)
    values = parsed if isinstance(parsed, list) else [parsed]
    printers = {str(value).strip() for value in values if str(value).strip()}
    if _virtual_printer_available():
        printers.add("PedeOn Virtual (TCP 127.0.0.1:9100)")
    return sorted(printers)


def _virtual_printer_available() -> bool:
    try:
        with socket.create_connection(("127.0.0.1", 9100), timeout=0.25):
            return True
    except OSError:
        return False


class _DocInfo1(ctypes.Structure):
    _fields_ = [
        ("pDocName", wintypes.LPWSTR),
        ("pOutputFile", wintypes.LPWSTR),
        ("pDatatype", wintypes.LPWSTR),
    ]


def raw_print(printer_name: str, content: bytes, document_name: str) -> None:
    if printer_name == "PedeOn Virtual (TCP 127.0.0.1:9100)":
        try:
            with socket.create_connection(("127.0.0.1", 9100), timeout=5) as connection:
                connection.sendall(content)
            return
        except OSError as exc:
            raise RuntimeError(f"Impressora virtual indisponível: {exc}") from exc
    if not hasattr(ctypes, "windll"):
        raise RuntimeError("Impressão local está disponível somente no Windows.")
    spooler = ctypes.windll.winspool.drv
    handle = wintypes.HANDLE()
    if not spooler.OpenPrinterW(printer_name, ctypes.byref(handle), None):
        raise ctypes.WinError()
    started_document = False
    started_page = False
    try:
        info = _DocInfo1(document_name, None, "RAW")
        if not spooler.StartDocPrinterW(handle, 1, ctypes.byref(info)):
            raise ctypes.WinError()
        started_document = True
        if not spooler.StartPagePrinter(handle):
            raise ctypes.WinError()
        started_page = True
        buffer = ctypes.create_string_buffer(content)
        written = wintypes.DWORD()
        if not spooler.WritePrinter(
            handle, buffer, len(content), ctypes.byref(written)
        ):
            raise ctypes.WinError()
        if written.value != len(content):
            raise RuntimeError("A impressora não recebeu o cupom completo.")
    finally:
        if started_page:
            spooler.EndPagePrinter(handle)
        if started_document:
            spooler.EndDocPrinter(handle)
        spooler.ClosePrinter(handle)


def production_ticket(payload: dict) -> bytes:
    lines = [
        "\x1b@",
        "PEDIDO DE PRODUCAO",
        "=" * 42,
        f"Pedido: {payload.get('display_number') or '-'}",
    ]
    if payload.get("table_label"):
        lines.append(f"Mesa: {payload['table_label']}")
    if payload.get("command_label"):
        lines.append(f"Comanda: {payload['command_label']}")
    lines.extend(
        [
            f"Origem: {payload.get('source_channel') or '-'}",
            f"Destino: {payload.get('station_name') or '-'}",
            "-" * 42,
        ]
    )
    for item in payload.get("items", []):
        lines.append(f"{item.get('quantity', '1')}x {item.get('description', '')}")
        for modifier in item.get("modifiers", []):
            lines.append(f"  + {modifier.get('option', '')}")
        if item.get("notes"):
            lines.append(f"  OBS: {item['notes']}")
    if payload.get("customer_notes"):
        lines.extend(["-" * 42, f"OBS PEDIDO: {payload['customer_notes']}"])
    lines.extend(["=" * 42, "\n\n\n\x1dV\x00"])
    return "\n".join(lines).encode("cp860", errors="replace")
