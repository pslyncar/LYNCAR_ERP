import importlib
import json
import pkgutil
from datetime import datetime
from decimal import Decimal
from pathlib import Path

import requests

import app.models
from app.core.security import create_access_token
from app.models.product import Product
from app.models.user import User
from app.services.access_control import get_user_permission_codes
from app.services.tenancy import (
    get_enabled_modules_for_company,
    session_for_company,
)


BASE_URL = "http://127.0.0.1:8000"
COMPANY_CODE = "drika_padaria"
RESULT_FILE = Path(r"C:\erp_build\fiscal_homologation_results.json")


def import_models() -> None:
    for module in pkgutil.iter_modules(app.models.__path__):
        importlib.import_module(f"app.models.{module.name}")


def make_token() -> str:
    with session_for_company(COMPANY_CODE) as db:
        user = db.get(User, 1)
        if user is None:
            raise RuntimeError("Usuario 1 nao encontrado no tenant da Drika")
        permissions = sorted(
            get_user_permission_codes(
                db,
                user,
                get_enabled_modules_for_company(COMPANY_CODE),
            )
        )
        role = user.role
    return create_access_token(
        subject="1",
        extra_claims={
            "role": role,
            "permissions": permissions,
            "company_code": COMPANY_CODE,
            "company_name": "Drika",
            "plan_code": "enterprise",
        },
    )


def compact_document(data: dict) -> dict:
    keys = (
        "id",
        "document_type",
        "status",
        "number",
        "series",
        "access_key",
        "sefaz_status_code",
        "sefaz_message",
        "contingency_mode",
        "created_at",
        "authorized_at",
    )
    return {key: data.get(key) for key in keys if key in data}


def submit(headers: dict, document_type: str, with_rtc: bool) -> dict:
    label = f"{document_type.upper()} {'com' if with_rtc else 'sem'} IBS/CBS"
    payload = {
        "fiscal_client_id": 1 if document_type == "nfe" else None,
        "document_type": document_type,
        "consumer_cpf": None,
        "operation_nature": "VENDA",
        "payment_condition": "vista",
        "fiscal_notes": f"Homologacao automatizada {label} {datetime.now().isoformat()}",
        "stock_deduction_on_authorize": False,
        "items": [
            {
                "fiscal_product_id": 5,
                "fiscal_description": "Acucar Refinado 1kg",
                "quantity": "1.0000",
                "unit": "UN",
                "unit_price": "6.99",
                "discount_amount": "0.00",
                "included": True,
            }
        ],
    }
    prepared = requests.post(
        f"{BASE_URL}/fiscal/documents/prepare-manual",
        headers=headers,
        json=payload,
        timeout=90,
    )
    result = {
        "test": label,
        "prepare_http": prepared.status_code,
    }
    try:
        prepared_data = prepared.json()
    except ValueError:
        result["prepare_error"] = prepared.text[:1000]
        return result
    if prepared.status_code >= 400:
        result["prepare_error"] = prepared_data
        return result
    result["prepared"] = compact_document(prepared_data)
    document_id = prepared_data.get("id")
    authorized = requests.post(
        f"{BASE_URL}/fiscal/documents/{document_id}/authorize",
        headers=headers,
        timeout=180,
    )
    result["authorize_http"] = authorized.status_code
    try:
        authorized_data = authorized.json()
    except ValueError:
        result["authorize_error"] = authorized.text[:1500]
        return result
    if authorized.status_code >= 400:
        result["authorize_error"] = authorized_data
    else:
        result["authorized"] = compact_document(authorized_data)
    return result


def main() -> None:
    import_models()
    token = make_token()
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    health = requests.get(f"{BASE_URL}/health", timeout=15)
    results = {
        "started_at": datetime.now().isoformat(),
        "api_health_http": health.status_code,
        "company": COMPANY_CODE,
        "tests": [],
    }

    with session_for_company(COMPANY_CODE) as db:
        product = db.get(Product, 5)
        if product is None:
            raise RuntimeError("Produto fiscal 5 nao encontrado")
        original = {
            "ibs_cbs_cst": product.ibs_cbs_cst,
            "ibs_cbs_classification": product.ibs_cbs_classification,
            "cbs_rate": product.cbs_rate,
            "ibs_state_rate": product.ibs_state_rate,
            "ibs_city_rate": product.ibs_city_rate,
        }

    try:
        with session_for_company(COMPANY_CODE) as db:
            product = db.get(Product, 5)
            product.ibs_cbs_cst = None
            product.ibs_cbs_classification = None
            product.cbs_rate = None
            product.ibs_state_rate = None
            product.ibs_city_rate = None
            db.commit()
        results["tests"].append(submit(headers, "nfce", False))
        results["tests"].append(submit(headers, "nfe", False))

        with session_for_company(COMPANY_CODE) as db:
            product = db.get(Product, 5)
            product.ibs_cbs_cst = "000"
            product.ibs_cbs_classification = "000001"
            product.cbs_rate = Decimal("0.9000")
            product.ibs_state_rate = Decimal("0.1000")
            product.ibs_city_rate = Decimal("0.0000")
            db.commit()
        results["tests"].append(submit(headers, "nfce", True))
        results["tests"].append(submit(headers, "nfe", True))
    finally:
        with session_for_company(COMPANY_CODE) as db:
            product = db.get(Product, 5)
            for key, value in original.items():
                setattr(product, key, value)
            db.commit()
        results["product_rtc_restored"] = True
        results["finished_at"] = datetime.now().isoformat()
        RESULT_FILE.write_text(
            json.dumps(results, ensure_ascii=False, indent=2, default=str),
            encoding="utf-8",
        )


if __name__ == "__main__":
    main()
