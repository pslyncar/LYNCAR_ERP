from datetime import date, datetime, timedelta
from decimal import Decimal
from types import SimpleNamespace
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Response, UploadFile, status
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.serialization import pkcs12
from lxml import etree
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.api.dependencies import require_any_permission, require_permission
from app.core.database import get_db
from app.models.fiscal import (
    CompanyFiscalSetting,
    FiscalDocument,
    FiscalDocumentItem,
    FiscalDocumentSale,
    FiscalOutputRule,
    FiscalSettingsAuditLog,
    FiscalTransmissionJob,
)
from app.models.client import Client
from app.models.product import Product
from app.models.sale import Sale, SaleItem
from app.models.stock_movement import StockMovement
from app.models.user import User
from app.schemas.fiscal import (
    CompanyFiscalSettingRead,
    CompanyFiscalSettingUpdate,
    FiscalCertificateUploadRead,
    FiscalDocumentPrepare,
    FiscalDocumentPrepareFromSales,
    FiscalDocumentDraftRead,
    FiscalDocumentItemDraftRead,
    FiscalDocumentPrepareWithItems,
    FiscalDocumentPrepareManual,
    FiscalDocumentUpdate,
    FiscalProductLookupRead,
    FiscalDocumentCancel,
    FiscalDocumentRead,
    FiscalOutputRuleCreate,
    FiscalOutputRulePreviewRead,
    FiscalOutputRulePreviewRequest,
    FiscalOutputRuleRead,
    FiscalOutputRuleUpdate,
    FiscalDocumentsRecoveryRead,
    FiscalNumberingStatusRead,
    FiscalSetupChecklistItem,
    FiscalSetupChecklistRead,
    FiscalTransmissionJobRead,
    NfceNumberingSyncRead,
)
from app.services.fiscal_stock import refresh_many_product_fiscal_balances
from app.services.fiscal_certificate import encrypt_certificate_bytes, encrypt_secret, sha256_hex
from app.services.nfce_sp import (
    NfceValidationError,
    authorize_nfce,
    prepare_nfce_offline_contingency,
    transmit_nfce_offline_contingency,
)
from app.services.nfce_listagem_chaves_sp import sync_nfce_next_number_from_sefaz
from app.services.fiscal_recovery import RecoveredFiscalDocument, recover_fiscal_documents
from app.services.nfe_sp import _duplicate_nfe_key, authorize_nfe
from app.services.nfe_protocol_sp import query_nfe_protocol
from app.services.fiscal_xml import build_processed_nfe_xml, is_processed_nfe_xml
from app.services.fiscal_output_rules import effective_crt, resolve_output_rule, resolve_output_tax_profile
from app.services.fiscal_document_policy import should_move_stock_for_fiscal_document
from app.services.rtc_compliance import (
    RTC_HOMOLOGATION_CRT3_MANDATORY_FROM,
    RTC_PRODUCTION_CRT3_MANDATORY_FROM,
    RTC_PRODUCTION_SIMPLE_MEI_MANDATORY_FROM,
    RtcComplianceError,
    is_rtc_mandatory,
    fiscal_product_issues,
    rtc_rates_for,
    validate_rtc_document,
)
from app.services.fiscal_events_sp import send_cancellation_event
from app.services.fiscal_pdf import generate_danfe_pdf
from app.services.fiscal_queue import enqueue_fiscal_job, resume_fiscal_configuration_jobs
from app.services.product_batches import apply_batch_out, return_to_batch
from app.services.product_costs import apply_stock_in, apply_stock_out

router = APIRouter()

FISCAL_PROCESSING_TIMEOUT = timedelta(minutes=15)


def _is_recent_processing(document: FiscalDocument) -> bool:
    if document.status != "processing":
        return False
    updated_at = document.updated_at
    if updated_at is None:
        return True
    return datetime.utcnow() - updated_at.replace(tzinfo=None) < FISCAL_PROCESSING_TIMEOUT


def _fiscal_xml_filename(document: FiscalDocument) -> str:
    document_type = "nfe" if document.document_type == "nfe" else "nfce"
    series = document.series or 1
    number = document.number or document.id
    return f"{document_type}-serie-{series}-numero-{number}.xml"


def _get_or_create_settings(db: Session) -> CompanyFiscalSetting:
    setting = db.scalar(select(CompanyFiscalSetting).order_by(CompanyFiscalSetting.id.asc()))
    if setting is not None:
        return setting
    setting = CompanyFiscalSetting()
    db.add(setting)
    db.commit()
    db.refresh(setting)
    return setting


def _locked_fiscal_setting(db: Session) -> CompanyFiscalSetting:
    setting = db.scalar(
        select(CompanyFiscalSetting)
        .order_by(CompanyFiscalSetting.id.asc())
        .with_for_update()
    )
    if setting is not None:
        return setting
    setting = CompanyFiscalSetting()
    db.add(setting)
    db.flush()
    return setting


def _next_available_fiscal_number(
    db: Session,
    *,
    environment: str,
    document_type: str,
    series: int,
    configured_next_number: int,
) -> int:
    consumed_statuses = (
        "authorized",
        "cancelled",
        "contingency_offline",
        "pending_return",
        "not_found_after_timeout",
    )
    highest_used_number = db.scalar(
        select(func.max(FiscalDocument.number)).where(
            FiscalDocument.environment == environment,
            FiscalDocument.document_type == document_type,
            FiscalDocument.series == series,
            FiscalDocument.status.in_(consumed_statuses),
            FiscalDocument.number.is_not(None),
        )
    )
    next_number = max(int(configured_next_number or 1), int(highest_used_number or 0) + 1)
    owner = db.scalar(
        select(FiscalDocument).where(
            FiscalDocument.environment == environment,
            FiscalDocument.document_type == document_type,
            FiscalDocument.series == series,
            FiscalDocument.number == next_number,
        )
    )
    while owner is not None:
        # Um numero que ja foi associado a um documento nunca volta ao pool.
        # Rejeicoes definitivas conservam o numero para correcao/reenvio, mas
        # nao podem bloquear as vendas seguintes da mesma serie fiscal.
        next_number += 1
        owner = db.scalar(
            select(FiscalDocument).where(
                FiscalDocument.environment == environment,
                FiscalDocument.document_type == document_type,
                FiscalDocument.series == series,
                FiscalDocument.number == next_number,
            )
        )
    return next_number


def _reserve_fiscal_number(
    db: Session,
    document_id: int,
) -> tuple[FiscalDocument, CompanyFiscalSetting]:
    document = db.scalar(
        select(FiscalDocument)
        .where(FiscalDocument.id == document_id)
        .with_for_update()
    )
    if document is None:
        raise HTTPException(status_code=404, detail="Documento fiscal nao encontrado.")
    if document.status == "authorized":
        return document, _locked_fiscal_setting(db)
    if _is_recent_processing(document):
        raise HTTPException(
            status_code=409,
            detail="Documento fiscal ja esta em processamento. Aguarde o retorno da SEFAZ.",
        )
    setting = _locked_fiscal_setting(db)
    if document.document_type == "nfce":
        document.series = document.series or int(setting.nfce_series or 1)
        document.number = document.number or _next_available_fiscal_number(
            db,
            environment=document.environment,
            document_type="nfce",
            series=int(document.series),
            configured_next_number=int(setting.nfce_next_number or 1),
        )
    else:
        document.series = document.series or int(setting.nfe_series or 1)
        document.number = document.number or _next_available_fiscal_number(
            db,
            environment=document.environment,
            document_type="nfe",
            series=int(document.series),
            configured_next_number=int(setting.nfe_next_number or 1),
        )
    document.status = "processing"
    document.sefaz_status_code = "PROCESSING"
    document.sefaz_message = "Documento reservado e em envio para a SEFAZ."
    # A transacao e o bloqueio da configuracao fiscal permanecem ativos durante
    # o envio. Assim dois PDVs nao reservam numeros diferentes enquanto a SEFAZ
    # ainda nao decidiu se o numero atual foi consumido.
    db.flush()
    return document, setting


def _create_timeout_contingency(
    db: Session,
    *,
    document: FiscalDocument,
    setting: CompanyFiscalSetting,
    fiscal_sale,
    requested_by_user_id: int | None,
    error_message: str,
) -> FiscalDocument:
    if document.document_type != "nfce" or document.number is None:
        raise NfceValidationError(
            "Contingencia automatica disponivel somente para NFC-e numerada."
        )
    document.status = "pending_return"
    document.sefaz_status_code = "TIMEOUT_PENDING_RETURN"
    document.sefaz_message = (
        "A SEFAZ nao devolveu uma resposta conclusiva. A chave normal sera "
        f"consultada automaticamente. Falha original: {error_message[:300]}"
    )
    setting.nfce_next_number = max(
        int(setting.nfce_next_number or 1),
        int(document.number) + 1,
    )
    contingency = FiscalDocument(
        origin_document_id=document.id,
        sale_id=document.sale_id,
        fiscal_client_id=document.fiscal_client_id,
        document_type="nfce",
        model="65",
        series=int(document.series or setting.nfce_series or 1),
        environment=document.environment,
        consumer_cpf=document.consumer_cpf,
        recipient_document=document.recipient_document,
        recipient_name=document.recipient_name,
        operation_nature=document.operation_nature,
        finality=document.finality,
        payment_condition=document.payment_condition,
        fiscal_notes=document.fiscal_notes,
        freight_mode=document.freight_mode,
        freight_amount=document.freight_amount,
        insurance_amount=document.insurance_amount,
        other_expenses_amount=document.other_expenses_amount,
        status="draft",
        sefaz_message="Preparando NFC-e em contingencia apos timeout.",
    )
    db.add(contingency)
    db.flush()
    contingency.number = _next_available_fiscal_number(
        db,
        environment=contingency.environment,
        document_type="nfce",
        series=int(contingency.series),
        configured_next_number=int(setting.nfce_next_number),
    )
    if document.sale_id is None:
        for item in document.fiscal_items:
            contingency.fiscal_items.append(
                FiscalDocumentItem(
                    sale_item_id=item.sale_item_id,
                    original_product_id=item.original_product_id,
                    fiscal_product_id=item.fiscal_product_id,
                    original_description=item.original_description,
                    fiscal_description=item.fiscal_description,
                    quantity=item.quantity,
                    unit=item.unit,
                    unit_price=item.unit_price,
                    discount_amount=item.discount_amount,
                    total_price=item.total_price,
                    barcode=item.barcode,
                    included=item.included,
                    adjustment_reason=item.adjustment_reason,
                    ncm=item.ncm,
                    cest=item.cest,
                    cfop=item.cfop,
                    origin=item.origin,
                    cst=item.cst,
                    csosn=item.csosn,
                    pis_cst=item.pis_cst,
                    cofins_cst=item.cofins_cst,
                    cbenef=item.cbenef,
                )
            )
    result = prepare_nfce_offline_contingency(setting, contingency, fiscal_sale)
    contingency.status = result.status
    contingency.sefaz_status_code = result.status_code
    contingency.sefaz_message = result.message
    setting.nfce_next_number = max(
        int(setting.nfce_next_number),
        int(contingency.number) + 1,
    )
    enqueue_fiscal_job(
        db,
        document,
        requested_by_user_id=requested_by_user_id,
        job_type="recover_pending_return",
        delay_seconds=10,
    )
    enqueue_fiscal_job(
        db,
        contingency,
        requested_by_user_id=requested_by_user_id,
        job_type="transmit_contingency",
        delay_seconds=15,
    )
    db.commit()
    db.refresh(contingency)
    return contingency


def _rule_read(rule: FiscalOutputRule) -> FiscalOutputRuleRead:
    return FiscalOutputRuleRead.model_validate(
        {
            **rule.__dict__,
            "product_name": rule.product.name if rule.product is not None else None,
        }
    )


def _clean_rule_payload(data: dict) -> dict:
    cleaned = {}
    for key, value in data.items():
        if isinstance(value, str):
            value = " ".join(value.split())
            cleaned[key] = value or None
        else:
            cleaned[key] = value
    if cleaned.get("document_model") in {"", "todos", "all"}:
        cleaned["document_model"] = None
    if cleaned.get("operation_type") in {None, ""}:
        cleaned["operation_type"] = "sale"
    return cleaned


def _only_digits(value: str | None) -> str:
    return "".join(char for char in str(value or "") if char.isdigit())


def _validate_output_rule_payload(data: dict) -> None:
    document_model = str(data.get("document_model") or "").strip()
    if document_model and document_model not in {"55", "65"}:
        raise HTTPException(status_code=400, detail="Modelo da regra fiscal deve ser 55, 65 ou vazio.")
    operation_type = str(data.get("operation_type") or "sale").strip().lower()
    allowed_operations = {"sale", "venda", "return", "devolucao", "transfer", "transferencia", "bonus", "bonificacao", "remittance", "remessa"}
    if operation_type not in allowed_operations:
        raise HTTPException(status_code=400, detail="Tipo de operacao fiscal nao reconhecido.")
    for field_name, label in [("uf_origin", "UF origem"), ("uf_destination", "UF destino")]:
        value = str(data.get(field_name) or "").strip()
        if value and (len(value) != 2 or not value.isalpha()):
            raise HTTPException(status_code=400, detail=f"{label} deve ter 2 letras.")
        if value:
            data[field_name] = value.upper()
    ncm = _only_digits(data.get("ncm"))
    if data.get("ncm") and len(ncm) != 8:
        raise HTTPException(status_code=400, detail="NCM exato deve ter 8 digitos.")
    if ncm:
        data["ncm"] = ncm
    ncm_prefix = _only_digits(data.get("ncm_prefix"))
    if data.get("ncm_prefix") and not (1 <= len(ncm_prefix) <= 8):
        raise HTTPException(status_code=400, detail="Prefixo NCM deve ter de 1 a 8 digitos.")
    if ncm_prefix:
        data["ncm_prefix"] = ncm_prefix
    cfop = _only_digits(data.get("cfop"))
    if data.get("cfop") and len(cfop) != 4:
        raise HTTPException(status_code=400, detail="CFOP deve ter 4 digitos.")
    if cfop:
        data["cfop"] = cfop
    if data.get("csosn") and data.get("cst"):
        raise HTTPException(status_code=400, detail="Informe CSOSN ou CST ICMS, nao os dois na mesma regra.")
    if data.get("ibs_cbs_cst") and len(_only_digits(data.get("ibs_cbs_cst"))) != 3:
        raise HTTPException(status_code=400, detail="CST IBS/CBS deve ter 3 digitos.")
    if data.get("ibs_cbs_classification") and len(_only_digits(data.get("ibs_cbs_classification"))) != 6:
        raise HTTPException(status_code=400, detail="cClassTrib IBS/CBS deve ter 6 digitos.")


def _load_active_output_rules(db: Session) -> list[FiscalOutputRule]:
    return list(
        db.scalars(
            select(FiscalOutputRule)
            .options(selectinload(FiscalOutputRule.product))
            .where(FiscalOutputRule.active.is_(True))
            .order_by(FiscalOutputRule.priority.desc(), FiscalOutputRule.id.desc())
        ).all()
    )


def _attach_output_rules(setting: CompanyFiscalSetting, db: Session) -> CompanyFiscalSetting:
    setattr(setting, "output_rules", _load_active_output_rules(db))
    return setting


SECRET_FISCAL_FIELDS = {
    "certificate_encrypted_blob",
    "certificate_password_encrypted",
    "certificate_storage_key",
    "certificate_password_secret_key",
    "nfce_csc_secret_key",
}


def _audit_value(field: str, value) -> str | None:
    if field in SECRET_FISCAL_FIELDS:
        return "***" if value else None
    if value is None:
        return None
    return str(value)


def _add_fiscal_audit(
    db: Session,
    user: User | None,
    *,
    action: str,
    field_name: str | None = None,
    old_value=None,
    new_value=None,
    notes: str | None = None,
) -> None:
    db.add(
        FiscalSettingsAuditLog(
            user_id=user.id if user is not None else None,
            action=action,
            field_name=field_name,
            old_value=_audit_value(field_name or "", old_value),
            new_value=_audit_value(field_name or "", new_value),
            notes=notes,
        )
    )


def _present(value: str | int | None) -> bool:
    return value is not None and str(value).strip() != ""


def _checklist_item(
    code: str,
    title: str,
    ok: bool,
    *,
    owner: str,
    ok_message: str,
    pending_message: str,
    blocks_nfe: bool = False,
    blocks_nfce: bool = False,
    attention: bool = False,
) -> FiscalSetupChecklistItem:
    return FiscalSetupChecklistItem(
        code=code,
        title=title,
        status="ok" if ok else "attention" if attention else "pending",
        owner=owner,
        message=ok_message if ok else pending_message,
        blocks_nfe=blocks_nfe and not ok,
        blocks_nfce=blocks_nfce and not ok,
    )


def _build_fiscal_setup_checklist(db: Session, setting: CompanyFiscalSetting) -> FiscalSetupChecklistRead:
    setting = _attach_output_rules(setting, db)
    items: list[FiscalSetupChecklistItem] = []
    has_company_identity = all(
        _present(value)
        for value in (setting.legal_name, setting.cnpj, setting.uf, setting.city_code)
    )
    has_address = all(
        _present(value)
        for value in (
            setting.address_line,
            setting.address_number,
            setting.neighborhood,
            setting.city,
            setting.zip_code,
        )
    )
    has_regime = _present(setting.crt) and _present(setting.tax_regime)
    has_certificate = bool(setting.certificate_encrypted_blob and setting.certificate_password_encrypted)
    certificate_expired = bool(setting.certificate_expires_at and setting.certificate_expires_at < date.today())
    has_nfce_numbering = bool(setting.nfce_series and setting.nfce_next_number)
    has_nfe_numbering = bool(setting.nfe_series and setting.nfe_next_number)
    has_csc = bool(setting.nfce_csc_id and setting.nfce_csc_secret_key)
    products_missing_basic = db.scalar(
        select(func.count(Product.id)).where(
            Product.active.is_(True),
            or_(Product.ncm.is_(None), Product.ncm == "", Product.origin.is_(None), Product.origin == ""),
        )
    ) or 0
    rtc_nfce = get_rtc_compliance(model="65", db=db, current_user=None)  # type: ignore[arg-type]
    rtc_nfe = get_rtc_compliance(model="55", db=db, current_user=None)  # type: ignore[arg-type]

    items.extend(
        [
            _checklist_item(
                "company_identity",
                "Cadastro da empresa",
                has_company_identity,
                owner="master",
                ok_message="Razao social, CNPJ, UF e cidade IBGE preenchidos.",
                pending_message="Preencha razao social, CNPJ, UF e codigo IBGE da cidade.",
                blocks_nfe=True,
                blocks_nfce=True,
            ),
            _checklist_item(
                "company_address",
                "Endereco fiscal",
                has_address,
                owner="master",
                ok_message="Endereco fiscal completo.",
                pending_message="Complete logradouro, numero, bairro, cidade e CEP.",
                blocks_nfe=True,
                blocks_nfce=True,
            ),
            _checklist_item(
                "tax_regime",
                "Regime/CRT",
                has_regime,
                owner="contador",
                ok_message=f"CRT {setting.crt} e regime {setting.tax_regime} configurados.",
                pending_message="Defina CRT e regime tributario com o contador.",
                blocks_nfe=True,
                blocks_nfce=True,
            ),
            _checklist_item(
                "certificate",
                "Certificado A1",
                has_certificate and not certificate_expired,
                owner="cliente",
                ok_message="Certificado A1 cadastrado e dentro da validade.",
                pending_message="Cadastre um certificado A1 valido para assinatura e comunicacao SEFAZ.",
                blocks_nfe=True,
                blocks_nfce=True,
                attention=certificate_expired,
            ),
            _checklist_item(
                "nfce_csc",
                "CSC/ID NFC-e",
                has_csc or not setting.nfce_enabled,
                owner="cliente",
                ok_message="CSC/ID configurado ou NFC-e desabilitada.",
                pending_message="Para emitir NFC-e, informe ID do CSC e token CSC.",
                blocks_nfce=bool(setting.nfce_enabled),
            ),
            _checklist_item(
                "nfce_numbering",
                "Serie e numero NFC-e",
                has_nfce_numbering or not setting.nfce_enabled,
                owner="contador",
                ok_message="Serie e proximo numero de NFC-e configurados.",
                pending_message="Informe serie e proximo numero de NFC-e ou sincronize com a SEFAZ.",
                blocks_nfce=bool(setting.nfce_enabled),
            ),
            _checklist_item(
                "nfe_numbering",
                "Serie e numero NF-e",
                has_nfe_numbering or not setting.nfe_enabled,
                owner="contador",
                ok_message="Serie e proximo numero de NF-e configurados.",
                pending_message="Informe serie e proximo numero de NF-e.",
                blocks_nfe=bool(setting.nfe_enabled),
            ),
            _checklist_item(
                "products_basic_tax",
                "Produtos fiscais",
                products_missing_basic == 0,
                owner="contador",
                ok_message="Produtos ativos com NCM e origem preenchidos.",
                pending_message=f"{products_missing_basic} produto(s) ativo(s) sem NCM ou origem.",
                blocks_nfe=True,
                blocks_nfce=True,
            ),
            _checklist_item(
                "rtc_nfce",
                "IBS/CBS NFC-e",
                bool(rtc_nfce["ready"]),
                owner="contador",
                ok_message=str(rtc_nfce["message"]),
                pending_message=str(rtc_nfce["message"]),
                blocks_nfce=bool(rtc_nfce["mandatory"]),
            ),
            _checklist_item(
                "rtc_nfe",
                "IBS/CBS NF-e",
                bool(rtc_nfe["ready"]),
                owner="contador",
                ok_message=str(rtc_nfe["message"]),
                pending_message=str(rtc_nfe["message"]),
                blocks_nfe=bool(rtc_nfe["mandatory"]),
            ),
        ]
    )
    ready_for_nfe = not any(item.blocks_nfe for item in items)
    ready_for_nfce = not any(item.blocks_nfce for item in items)
    return FiscalSetupChecklistRead(
        ready_for_nfe=ready_for_nfe,
        ready_for_nfce=ready_for_nfce,
        environment=setting.environment,
        crt=effective_crt(setting),
        tax_regime=setting.tax_regime,
        items=items,
    )


def _is_sefaz_connection_failure(exc: Exception) -> bool:
    name = type(exc).__name__.lower()
    message = str(exc).lower()
    markers = (
        "connection",
        "connect",
        "timeout",
        "timed out",
        "dns",
        "ssl",
        "max retries",
        "temporarily unavailable",
        "remote end closed",
    )
    return any(marker in name or marker in message for marker in markers)


def _line_total(quantity: Decimal, unit_price: Decimal, discount: Decimal) -> Decimal:
    total = (quantity or Decimal("0")) * (unit_price or Decimal("0")) - (discount or Decimal("0"))
    return total if total > 0 else Decimal("0")


SEFAZ_REJECTION_HINTS: dict[str, str] = {
    "204": "Duplicidade de NF-e/NFC-e. Verifique se a nota ja foi autorizada antes de reenviar.",
    "215": "Falha no XML/schema. Revise campos obrigatorios, formato de numeros, datas e grupos fiscais.",
    "225": "XML rejeitado pelo schema da SEFAZ. Geralmente e campo obrigatorio ausente ou formato invalido.",
    "232": "IE do destinatario nao informada ou invalida para a operacao.",
    "234": "IE do destinatario nao vinculada ao CNPJ/CPF informado.",
    "245": "CNPJ do emitente nao cadastrado/autorizado na UF para emitir este documento.",
    "302": "Uso denegado. Conferir situacao fiscal do emitente/destinatario.",
    "327": "CFOP invalido para NFC-e. NFC-e normalmente exige operacao interna/consumidor final.",
    "386": "CFOP nao permitido para o CST/CSOSN informado. Revise CFOP e tributacao do produto.",
    "391": "Pagamento com cartao exige dados do cartao/credenciadora. Informe bandeira, autorizacao e/ou CNPJ da credenciadora conforme a forma de pagamento.",
    "508": "CST incompatível com o CSOSN/regime tributario. Revise CRT, CST e CSOSN do produto.",
    "539": "Duplicidade com diferenca na chave. Verifique numeracao, serie e ambiente antes de reenviar.",
    "610": "Total da nota difere da soma dos itens/impostos. Revise valores, descontos e totais.",
    "778": "NFC-e com NCM inexistente/invalido. Revise o NCM do produto.",
    "806": "Operacao com ICMS-ST exige CEST quando aplicavel. Revise NCM/CEST do produto.",
}


def _friendly_sefaz_message(status_code: str | None, message: str | None) -> str:
    original = " ".join((message or "Retorno SEFAZ sem mensagem.").split())
    code = (status_code or "").strip()
    hint = SEFAZ_REJECTION_HINTS.get(code)
    if hint:
        return f"SEFAZ {code}: {original}. O que verificar: {hint}"
    if code:
        return f"SEFAZ {code}: {original}. Confira os dados destacados na mensagem e valide com o contador/responsavel fiscal."
    return f"{original}. Confira os dados da nota e valide com o contador/responsavel fiscal."


def _sale_or_404(db: Session, sale_id: int | None = None, sale_number: str | None = None) -> Sale:
    query = (
        select(Sale)
        .options(
            selectinload(Sale.items).selectinload(SaleItem.product),
            selectinload(Sale.payments),
            selectinload(Sale.client),
        )
    )
    if sale_id is not None:
        query = query.where(Sale.id == sale_id)
    elif sale_number:
        query = query.where(Sale.number == sale_number)
    else:
        raise HTTPException(status_code=400, detail="Informe o numero da venda.")
    sale = db.scalar(query)
    if sale is None:
        raise HTTPException(status_code=404, detail="Venda nao encontrada.")
    return sale


def _draft_item_from_sale_item(item: SaleItem) -> FiscalDocumentItemDraftRead:
    product = item.product
    return FiscalDocumentItemDraftRead(
        sale_item_id=item.id,
        original_product_id=item.product_id,
        original_product_name=product.name if product is not None else None,
        fiscal_product_id=item.product_id,
        fiscal_product_name=product.name if product is not None else None,
        original_description=item.description,
        fiscal_description=product.name if product is not None else item.description,
        quantity=Decimal(item.quantity or 0),
        unit=item.unit,
        unit_price=Decimal(item.unit_price or 0),
        discount_amount=Decimal(item.discount_amount or 0),
        total_price=Decimal(item.total_price or 0),
        barcode=item.barcode,
        included=True,
    )


def _draft_read_from_sale(sale: Sale) -> FiscalDocumentDraftRead:
    items = [_draft_item_from_sale_item(item) for item in sale.items]
    return FiscalDocumentDraftRead(
        sale_id=sale.id,
        sale_number=sale.number,
        sale_total=Decimal(sale.total_amount or 0),
        fiscal_total=sum((item.total_price for item in items), Decimal("0")),
        consumer_cpf=sale.consumer_cpf,
        items=items,
    )


def _document_item_to_sale_item_view(item: FiscalDocumentItem) -> SimpleNamespace:
    product = item.fiscal_product
    return SimpleNamespace(
        id=item.sale_item_id,
        product_id=item.fiscal_product_id,
        product=product,
        description=item.fiscal_description,
        quantity=item.quantity,
        unit=item.unit,
        unit_price=item.unit_price,
        discount_amount=item.discount_amount,
        total_price=item.total_price,
        barcode=item.barcode or (product.barcode if product is not None else None),
        ncm=item.ncm,
        cest=item.cest,
        cfop=item.cfop,
        origin=item.origin,
        cst=item.cst,
        csosn=item.csosn,
        pis_cst=item.pis_cst,
        cofins_cst=item.cofins_cst,
        cbenef=item.cbenef,
    )


def _fiscal_sale_view(document: FiscalDocument, sale: Sale) -> Sale | SimpleNamespace:
    fiscal_client = document.fiscal_client or sale.client
    included_items = [
        _document_item_to_sale_item_view(item)
        for item in document.fiscal_items
        if item.included
    ]
    if not included_items and fiscal_client is None:
        return sale
    effective_items = included_items if included_items else list(sale.items)
    fiscal_total = sum(
        (Decimal(item.total_price or 0) for item in effective_items),
        Decimal("0"),
    )
    payment_method = sale.payments[0].method if sale.payments else "dinheiro"
    authorization_code = sale.payments[0].authorization_code if sale.payments else None
    payment = SimpleNamespace(
        method=payment_method,
        amount=fiscal_total,
        authorization_code=authorization_code,
        notes="Pagamento fiscal ajustado automaticamente ao total da pre-nota.",
    )
    return SimpleNamespace(
        id=sale.id,
        number=sale.number,
        status=sale.status,
        items=effective_items,
        payments=[payment],
        client=fiscal_client,
        consumer_cpf=document.consumer_cpf
        or (fiscal_client.document_number if fiscal_client is not None else None)
        or sale.consumer_cpf,
        total_amount=fiscal_total,
        discount_amount=Decimal("0"),
        change_amount=Decimal("0"),
    )


def _manual_fiscal_sale_view(document: FiscalDocument) -> SimpleNamespace:
    included_items = [
        _document_item_to_sale_item_view(item)
        for item in document.fiscal_items
        if item.included
    ]
    fiscal_total = sum(
        (Decimal(item.total_price or 0) for item in included_items),
        Decimal("0"),
    )
    payment = SimpleNamespace(
        method="dinheiro",
        amount=fiscal_total,
        authorization_code=None,
        notes="Pagamento informado na nota manual.",
    )
    return SimpleNamespace(
        id=document.id,
        number=f"NF-MANUAL-{document.id}",
        status="finalizada",
        items=included_items,
        payments=[payment],
        client=document.fiscal_client,
        consumer_cpf=document.consumer_cpf
        or (document.fiscal_client.document_number if document.fiscal_client is not None else None),
        total_amount=fiscal_total,
        discount_amount=Decimal("0"),
        change_amount=Decimal("0"),
    )


def _resolve_fiscal_client(db: Session, client_id: int | None) -> Client | None:
    if client_id is None:
        return None
    client = db.get(Client, client_id)
    if client is None:
        raise HTTPException(status_code=404, detail="Cliente fiscal nao encontrado.")
    if not client.active:
        raise HTTPException(status_code=400, detail="Cliente fiscal esta inativo.")
    return client


def _clean_item_tax_overrides(item: FiscalDocumentItemOverride) -> dict[str, str | None]:
    """Campos tributarios informados no rascunho prevalecem sobre o motor."""
    return {
        name: ("".join(value.split()) if name in {"ncm", "cest", "cfop"} else value.strip()) or None
        for name in ("ncm", "cest", "cfop", "origin", "cst", "csosn", "pis_cst", "cofins_cst", "cbenef")
        if (value := getattr(item, name, None)) is not None
    }


def _replace_document_items(
    db: Session,
    document: FiscalDocument,
    items: list[FiscalDocumentItemOverride],
    current_user: User,
) -> None:
    included_count = 0
    document.fiscal_items.clear()
    db.flush()
    for override in items:
        product = db.get(Product, override.fiscal_product_id) if override.fiscal_product_id else None
        if override.included and product is None:
            raise HTTPException(status_code=400, detail="Item incluido precisa ter produto fiscal vinculado.")
        included_count += int(override.included)
        quantity, unit_price, discount = (Decimal(override.quantity), Decimal(override.unit_price), Decimal(override.discount_amount))
        total_price = (
            Decimal(override.total_price)
            if override.total_price is not None
            else _line_total(quantity, unit_price, discount)
        )
        description = " ".join((override.fiscal_description or "").split()) or (product.name if product else "Item fiscal")
        document.fiscal_items.append(FiscalDocumentItem(
            fiscal_product_id=product.id if product else None, fiscal_description=description[:220],
            quantity=quantity, unit=(" ".join((override.unit or "").split()) or (product.unit if product else "un"))[:20],
            unit_price=unit_price, discount_amount=discount, total_price=total_price,
            barcode=product.barcode if product else None, included=override.included,
            adjustment_reason=override.adjustment_reason, created_by_user_id=current_user.id,
            **_clean_item_tax_overrides(override),
        ))
    if not included_count:
        raise HTTPException(status_code=400, detail="A nota precisa ter pelo menos um item incluido.")


def _refresh_document_fiscal_balances(db: Session, document: FiscalDocument) -> None:
    product_ids = {
        item.fiscal_product_id
        for item in document.fiscal_items
        if item.fiscal_product_id is not None
    }
    refresh_many_product_fiscal_balances(db, product_ids)


def _document_source_number(document: FiscalDocument) -> str:
    if document.number:
        return f"{document.document_type.upper()} {document.series or '-'}-{document.number}"
    return f"PRE-NOTA {document.id}"


def _post_manual_document_stock_out(db: Session, document: FiscalDocument, user_id: int | None) -> None:
    for item in document.fiscal_items:
        if not item.included or item.fiscal_product_id is None:
            continue
        product = item.fiscal_product or db.get(Product, item.fiscal_product_id)
        if product is None:
            continue
        quantity = Decimal(item.quantity or 0)
        if quantity <= 0:
            continue
        quantity_before = product.stock_quantity
        unit_cost, total_cost = apply_stock_out(product, quantity)
        apply_batch_out(
            db,
            product,
            quantity,
            source_type="fiscal_manual",
            source_id=document.id,
            source_number=_document_source_number(document),
        )
        db.add(
            StockMovement(
                product_id=product.id,
                user_id=user_id,
                movement_type="fiscal_manual_out",
                source_type="fiscal_document",
                source_id=document.id,
                source_number=_document_source_number(document),
                quantity_delta=-quantity,
                quantity_before=quantity_before,
                quantity_after=product.stock_quantity,
                unit=item.unit or product.unit,
                unit_price=unit_cost,
                total_value=total_cost,
                reason="Baixa de estoque por nota fiscal manual autorizada.",
                notes=f"Item fiscal: {item.fiscal_description}",
            )
        )


def _post_manual_document_stock_return(db: Session, document: FiscalDocument, user_id: int | None) -> None:
    for item in document.fiscal_items:
        if not item.included or item.fiscal_product_id is None:
            continue
        product = item.fiscal_product or db.get(Product, item.fiscal_product_id)
        if product is None:
            continue
        quantity = Decimal(item.quantity or 0)
        if quantity <= 0:
            continue
        quantity_before = product.stock_quantity
        unit_cost, total_cost = apply_stock_in(product, quantity, None)
        return_to_batch(
            db,
            product,
            quantity,
            source_type="fiscal_manual_cancel",
            source_id=document.id,
            source_number=_document_source_number(document),
        )
        db.add(
            StockMovement(
                product_id=product.id,
                user_id=user_id,
                movement_type="fiscal_manual_cancel_return",
                source_type="fiscal_document",
                source_id=document.id,
                source_number=_document_source_number(document),
                quantity_delta=quantity,
                quantity_before=quantity_before,
                quantity_after=product.stock_quantity,
                unit=item.unit or product.unit,
                unit_price=unit_cost,
                total_value=total_cost,
                reason="Estorno de estoque por cancelamento de nota fiscal manual.",
                notes=f"Item fiscal: {item.fiscal_description}",
            )
        )


def _post_sale_stock_return(db: Session, document: FiscalDocument, user_id: int | None) -> None:
    if document.sale_id is None:
        return
    already_returned = db.scalar(
        select(StockMovement.id)
        .where(
            StockMovement.movement_type == "sale_cancel_return",
            StockMovement.source_type == "fiscal_document",
            StockMovement.source_id == document.id,
        )
        .limit(1)
    )
    if already_returned is not None:
        return
    sale = db.get(Sale, document.sale_id)
    if sale is None:
        return
    for item in sale.items:
        if item.product_id is None or item.quantity <= 0:
            continue
        product = db.get(Product, item.product_id)
        if product is None or product.product_type == "servico":
            continue
        quantity_before = product.stock_quantity
        unit_cost, total_cost = apply_stock_in(product, item.quantity, None)
        return_to_batch(
            db,
            product,
            item.quantity,
            source_type="fiscal_cancel",
            source_id=document.id,
            source_number=_document_source_number(document),
        )
        db.add(
            StockMovement(
                product_id=product.id,
                user_id=user_id,
                movement_type="sale_cancel_return",
                source_type="fiscal_document",
                source_id=document.id,
                source_number=_document_source_number(document),
                quantity_delta=item.quantity,
                quantity_before=quantity_before,
                quantity_after=product.stock_quantity,
                unit=item.unit,
                unit_price=unit_cost,
                total_value=total_cost,
                reason="Estorno de estoque por cancelamento da nota fiscal.",
                notes=f"Estorno automatico da venda {sale.number} apos cancelamento fiscal.",
            )
        )


@router.get("/settings", response_model=CompanyFiscalSettingRead)
def get_fiscal_settings(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:view")),
) -> CompanyFiscalSetting:
    return _get_or_create_settings(db)


@router.get("/settings/numbering-status", response_model=FiscalNumberingStatusRead)
def get_fiscal_numbering_status(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:view")),
) -> FiscalNumberingStatusRead:
    setting = _get_or_create_settings(db)

    def last_authorized(document_type: str, series: int) -> int | None:
        return db.scalar(
            select(func.max(FiscalDocument.number)).where(
                FiscalDocument.environment == setting.environment,
                FiscalDocument.document_type == document_type,
                FiscalDocument.series == series,
                FiscalDocument.status.in_(("authorized", "cancelled")),
                FiscalDocument.number.is_not(None),
            )
        )

    nfce_series = int(setting.nfce_series or 1)
    nfe_series = int(setting.nfe_series or 1)
    local_nfce = last_authorized("nfce", nfce_series)
    local_nfe = last_authorized("nfe", nfe_series)
    stored_nfce = setting.nfce_last_authorized_number
    stored_nfe = setting.nfe_last_authorized_number
    return FiscalNumberingStatusRead(
        environment=setting.environment,
        nfce_series=nfce_series,
        nfce_last_authorized_number=max(
            (value for value in (local_nfce, stored_nfce) if value is not None),
            default=None,
        ),
        nfce_next_number=int(setting.nfce_next_number or 1),
        nfe_series=nfe_series,
        nfe_last_authorized_number=max(
            (value for value in (local_nfe, stored_nfe) if value is not None),
            default=None,
        ),
        nfe_next_number=int(setting.nfe_next_number or 1),
    )


@router.get("/settings/pdv-logo", response_model=CompanyFiscalSettingRead)
def get_pdv_logo_settings(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("pdv_operators:manage", "sales:create")),
) -> CompanyFiscalSetting:
    return _get_or_create_settings(db)


@router.get("/settings/checklist", response_model=FiscalSetupChecklistRead)
def get_fiscal_setup_checklist(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:view")),
) -> FiscalSetupChecklistRead:
    return _build_fiscal_setup_checklist(db, _get_or_create_settings(db))


@router.post("/settings/sync-nfce-numbering", response_model=NfceNumberingSyncRead)
def sync_nfce_numbering(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:settings")),
) -> NfceNumberingSyncRead:
    setting = _get_or_create_settings(db)
    try:
        result = sync_nfce_next_number_from_sefaz(setting)
    except NfceValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Falha ao consultar NFCeListagemChaves na SEFAZ: {type(exc).__name__}: {str(exc)[:300]}",
        ) from exc
    setting.nfce_next_number = max(int(setting.nfce_next_number or 1), result.updated_next_number)
    if result.highest_authorized_number is not None:
        setting.nfce_last_authorized_number = max(
            int(setting.nfce_last_authorized_number or 0),
            int(result.highest_authorized_number),
        )
    db.commit()
    return NfceNumberingSyncRead(**result.__dict__)


def _upsert_recovered_document(db: Session, recovered: RecoveredFiscalDocument) -> tuple[str, FiscalDocument | None]:
    if not recovered.access_key:
        return "skipped", None
    document = db.scalar(select(FiscalDocument).where(FiscalDocument.access_key == recovered.access_key))
    action = "updated" if document is not None else "imported"
    if document is None:
        document = FiscalDocument(
            document_type=recovered.document_type,
            model=recovered.model,
            environment=recovered.environment,
            access_key=recovered.access_key,
            status=recovered.status,
            sefaz_message=recovered.message,
        )
        db.add(document)
    document.document_type = recovered.document_type
    document.model = recovered.model
    document.environment = recovered.environment
    document.series = recovered.series or document.series
    document.number = recovered.number or document.number
    document.status = recovered.status or document.status
    document.sefaz_protocol = recovered.protocol or document.sefaz_protocol
    document.sefaz_status_code = recovered.status_code or document.sefaz_status_code
    document.sefaz_message = recovered.message or document.sefaz_message
    document.issued_at = recovered.issued_at or document.issued_at
    if recovered.status == "authorized" and document.authorized_at is None:
        document.authorized_at = recovered.issued_at or datetime.utcnow()
    if recovered.authorized_xml:
        document.xml_authorized = recovered.authorized_xml
    return action, document


@router.post("/documents/recover-from-sefaz", response_model=FiscalDocumentsRecoveryRead)
def recover_documents_from_sefaz(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:settings")),
) -> FiscalDocumentsRecoveryRead:
    setting = _get_or_create_settings(db)
    existing_nfce_xml_keys = set(
        db.scalars(
            select(FiscalDocument.access_key).where(
                FiscalDocument.document_type == "nfce",
                FiscalDocument.access_key.is_not(None),
                FiscalDocument.xml_authorized.is_not(None),
            )
        )
    )
    issued_nfe_documents = list(
        db.scalars(
            select(FiscalDocument).where(
                FiscalDocument.document_type == "nfe",
                FiscalDocument.status.in_(("authorized", "cancelled")),
            )
        )
    )
    existing_nfe_documents = [
        document
        for document in issued_nfe_documents
        if is_processed_nfe_xml(document.xml_authorized)
    ]
    missing_nfe_documents = [
        document
        for document in issued_nfe_documents
        if not is_processed_nfe_xml(document.xml_authorized)
    ]
    try:
        recovery = recover_fiscal_documents(
            setting,
            existing_nfce_xml_keys=existing_nfce_xml_keys,
        )
    except NfceValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Falha ao recuperar documentos fiscais na SEFAZ: {type(exc).__name__}: {str(exc)[:300]}",
        ) from exc

    counts = {"imported": 0, "updated": 0, "skipped": 0}
    messages = list(recovery.messages)
    nfe_repaired = 0
    nfe_unrecoverable = 0
    for document in missing_nfe_documents:
        if not document.access_key or not document.xml_signed:
            nfe_unrecoverable += 1
            continue
        if document.xml_authorized:
            try:
                document.xml_authorized = build_processed_nfe_xml(
                    document.xml_signed,
                    document.xml_authorized,
                )
                nfe_repaired += 1
                counts["updated"] += 1
                continue
            except (ValueError, etree.XMLSyntaxError):
                pass
        try:
            protocol = query_nfe_protocol(setting, document.access_key)
        except Exception as exc:
            messages.append(
                f"NF-e {document.number or document.id}: falha na consulta de protocolo: "
                f"{type(exc).__name__}: {str(exc)[:180]}"
            )
            nfe_unrecoverable += 1
            continue
        if not protocol.authorized:
            messages.append(
                f"NF-e {document.number or document.id}: "
                f"{protocol.status_code or '-'} {protocol.message}"
            )
            nfe_unrecoverable += 1
            continue
        document.xml_authorized = build_processed_nfe_xml(
            document.xml_signed,
            protocol.response_xml,
        )
        document.sefaz_protocol = protocol.protocol or document.sefaz_protocol
        nfe_repaired += 1
        counts["updated"] += 1
    max_nfce = int(setting.nfce_next_number or 1) - 1
    max_nfe = int(setting.nfe_next_number or 1) - 1
    for recovered in recovery.documents:
        action, document = _upsert_recovered_document(db, recovered)
        counts[action] += 1
        if document is None or document.number is None:
            continue
        if document.document_type == "nfce":
            max_nfce = max(max_nfce, int(document.number))
        elif document.document_type == "nfe":
            max_nfe = max(max_nfe, int(document.number))
    setting.nfce_next_number = max(int(setting.nfce_next_number or 1), max_nfce + 1)
    setting.nfe_next_number = max(int(setting.nfe_next_number or 1), max_nfe + 1)
    if max_nfce > 0:
        setting.nfce_last_authorized_number = max(
            int(setting.nfce_last_authorized_number or 0),
            max_nfce,
        )
    if max_nfe > 0:
        setting.nfe_last_authorized_number = max(
            int(setting.nfe_last_authorized_number or 0),
            max_nfe,
        )
    db.commit()
    return FiscalDocumentsRecoveryRead(
        **counts,
        nfce_keys=recovery.nfce_keys,
        nfce_existing=recovery.nfce_existing,
        nfce_downloaded=recovery.nfce_downloaded,
        nfe_docs=len(existing_nfe_documents) + nfe_repaired,
        nfe_existing=len(existing_nfe_documents),
        nfe_repaired=nfe_repaired,
        nfe_unrecoverable=nfe_unrecoverable,
        incomplete=recovery.incomplete,
        ult_nsu=recovery.ult_nsu,
        max_nsu=recovery.max_nsu,
        messages=messages,
    )


@router.get("/rtc-compliance")
def get_rtc_compliance(
    model: str = Query(default="65", pattern="^(55|65)$"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:view")),
) -> dict:
    setting = _attach_output_rules(_get_or_create_settings(db), db)
    today = date.today()
    crt = effective_crt(setting)
    mandatory = is_rtc_mandatory(setting, today)
    products = list(
        db.scalars(
            select(Product)
            .where(Product.active.is_(True))
            .order_by(Product.name.asc(), Product.id.asc())
        ).all()
    )
    incomplete_products = []
    for product in products:
        issues = fiscal_product_issues(
            setting,
            product,
            model=model,
            issue_date=today,
        )
        if issues:
            matched_rule = resolve_output_rule(setting, product, model=model)
            profile = resolve_output_tax_profile(setting, product, model=model)
            incomplete_products.append(
                {
                    "id": product.id,
                    "name": product.name,
                    "internal_code": product.internal_code,
                    "ncm": product.ncm,
                    "rule_source": profile.source,
                    "rule_name": getattr(matched_rule, "name", None),
                    "missing_fields": issues,
                }
            )

    rates = None
    if today.year == 2026:
        current_rates = rtc_rates_for(today)
        rates = {
            "cbs": float(current_rates.cbs),
            "ibs_uf": float(current_rates.ibs_uf),
            "ibs_mun": float(current_rates.ibs_mun),
        }

    mandatory_from = (
        RTC_HOMOLOGATION_CRT3_MANDATORY_FROM
        if str(setting.environment or "").lower() == "homologacao" and crt == "3"
        else RTC_PRODUCTION_CRT3_MANDATORY_FROM
        if crt == "3"
        else RTC_PRODUCTION_SIMPLE_MEI_MANDATORY_FROM
        if crt in {"1", "2", "4"}
        else None
    )

    if incomplete_products:
        message = (
            "Existem produtos com dados fiscais exigíveis ainda não resolvidos. "
            "Complete o cadastro ou crie uma regra para o grupo correspondente."
        )
    elif mandatory:
        message = "Produtos prontos para emissão, inclusive IBS/CBS obrigatório."
    else:
        message = (
            f"CRT {crt} preservado pelo cronograma atual. IBS/CBS não é "
            "obrigatório para este emitente nesta data."
        )

    return {
        "effective_crt": crt,
        "mandatory": mandatory,
        "mandatory_from": mandatory_from.isoformat() if mandatory_from else None,
        "ready": not incomplete_products,
        "message": message,
        "document_model": model,
        "rates": rates,
        "products_total": len(products),
        "products_incomplete": len(incomplete_products),
        "incomplete_products": incomplete_products,
    }


@router.put("/settings", response_model=CompanyFiscalSettingRead)
def update_fiscal_settings(
    payload: CompanyFiscalSettingUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:settings")),
) -> CompanyFiscalSetting:
    setting = _get_or_create_settings(db)
    data = payload.model_dump(exclude_unset=True)
    if "nfce_csc_secret_key" in data and data["nfce_csc_secret_key"]:
        data["nfce_csc_secret_key"] = encrypt_secret(data["nfce_csc_secret_key"])
    for key, value in data.items():
        old_value = getattr(setting, key)
        setattr(setting, key, value)
        if old_value != value:
            _add_fiscal_audit(
                db,
                current_user,
                action="settings_update",
                field_name=key,
                old_value=old_value,
                new_value=value,
            )
    if data.get("certificate_storage_key") and data.get("certificate_password_secret_key"):
        setting.certificate_uploaded_at = datetime.utcnow()
    db.commit()
    db.refresh(setting)
    return setting


@router.put("/settings/pdv-logo", response_model=CompanyFiscalSettingRead)
def update_pdv_logo_settings(
    payload: CompanyFiscalSettingUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_any_permission("pdv_operators:manage")),
) -> CompanyFiscalSetting:
    setting = _get_or_create_settings(db)
    old_value = setting.logo_url
    setting.logo_url = payload.logo_url
    if old_value != setting.logo_url:
        _add_fiscal_audit(
            db,
            current_user,
            action="pdv_logo_update",
            field_name="logo_url",
            old_value="stored" if old_value else None,
            new_value="stored" if setting.logo_url else None,
        )
    db.commit()
    db.refresh(setting)
    return setting


@router.get("/output-rules", response_model=list[FiscalOutputRuleRead])
def list_fiscal_output_rules(
    active: bool | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:view")),
) -> list[FiscalOutputRuleRead]:
    query = (
        select(FiscalOutputRule)
        .options(selectinload(FiscalOutputRule.product))
        .order_by(FiscalOutputRule.priority.desc(), FiscalOutputRule.id.desc())
    )
    if active is not None:
        query = query.where(FiscalOutputRule.active.is_(active))
    return [_rule_read(rule) for rule in db.scalars(query).all()]


@router.post("/output-rules", response_model=FiscalOutputRuleRead, status_code=status.HTTP_201_CREATED)
def create_fiscal_output_rule(
    payload: FiscalOutputRuleCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:settings")),
) -> FiscalOutputRuleRead:
    data = _clean_rule_payload(payload.model_dump())
    _validate_output_rule_payload(data)
    product_id = data.get("product_id")
    if product_id is not None and db.get(Product, product_id) is None:
        raise HTTPException(status_code=404, detail="Produto da regra fiscal nao encontrado.")
    if data.get("effective_from") and data.get("effective_to") and data["effective_to"] < data["effective_from"]:
        raise HTTPException(status_code=400, detail="Vigencia final nao pode ser anterior a inicial.")
    rule = FiscalOutputRule(**data)
    db.add(rule)
    resume_fiscal_configuration_jobs(db)
    db.commit()
    db.refresh(rule)
    rule = db.scalar(
        select(FiscalOutputRule)
        .options(selectinload(FiscalOutputRule.product))
        .where(FiscalOutputRule.id == rule.id)
    )
    return _rule_read(rule)


@router.put("/output-rules/{rule_id}", response_model=FiscalOutputRuleRead)
def update_fiscal_output_rule(
    rule_id: int,
    payload: FiscalOutputRuleUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:settings")),
) -> FiscalOutputRuleRead:
    rule = db.get(FiscalOutputRule, rule_id)
    if rule is None:
        raise HTTPException(status_code=404, detail="Regra fiscal nao encontrada.")
    data = _clean_rule_payload(payload.model_dump(exclude_unset=True))
    _validate_output_rule_payload(data)
    product_id = data.get("product_id")
    if product_id is not None and db.get(Product, product_id) is None:
        raise HTTPException(status_code=404, detail="Produto da regra fiscal nao encontrado.")
    effective_from = data.get("effective_from", rule.effective_from)
    effective_to = data.get("effective_to", rule.effective_to)
    if effective_from and effective_to and effective_to < effective_from:
        raise HTTPException(status_code=400, detail="Vigencia final nao pode ser anterior a inicial.")
    for key, value in data.items():
        setattr(rule, key, value)
    resume_fiscal_configuration_jobs(db)
    db.commit()
    db.refresh(rule)
    rule = db.scalar(
        select(FiscalOutputRule)
        .options(selectinload(FiscalOutputRule.product))
        .where(FiscalOutputRule.id == rule.id)
    )
    return _rule_read(rule)


@router.delete("/output-rules/{rule_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_fiscal_output_rule(
    rule_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:settings")),
) -> Response:
    rule = db.get(FiscalOutputRule, rule_id)
    if rule is None:
        raise HTTPException(status_code=404, detail="Regra fiscal nao encontrada.")
    db.delete(rule)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/output-rules/preview", response_model=FiscalOutputRulePreviewRead)
def preview_fiscal_output_rule(
    payload: FiscalOutputRulePreviewRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:view")),
) -> FiscalOutputRulePreviewRead:
    setting = _attach_output_rules(_get_or_create_settings(db), db)
    product = db.get(Product, payload.product_id) if payload.product_id is not None else None
    if payload.product_id is not None and product is None:
        raise HTTPException(status_code=404, detail="Produto nao encontrado para simular regra fiscal.")
    origin_uf = str(setting.uf or "").upper() or None
    destination_uf = str(payload.uf_destination or origin_uf or "").upper() or None
    interstate = bool(origin_uf and destination_uf and destination_uf != origin_uf)
    warnings = []
    document_allowed = True
    document_warning = None
    if payload.document_model == "65" and interstate:
        document_allowed = False
        document_warning = "NFC-e nao deve ser usada em venda interestadual. Use NF-e modelo 55."
        warnings.append(document_warning)
    if payload.document_model == "55" and not product and payload.operation_type in {"sale", "venda"}:
        warnings.append("Simulacao sem produto usa apenas o padrao geral do motor.")
    rule = resolve_output_rule(
        setting,
        product,
        model=payload.document_model,
        operation_type=payload.operation_type,
        uf_destination=destination_uf,
    )
    profile = resolve_output_tax_profile(
        setting,
        product,
        model=payload.document_model,
        operation_type=payload.operation_type,
        uf_destination=destination_uf,
    )
    if profile.cfop is None:
        warnings.append("Nenhum CFOP resolvido. Cadastre CFOP no produto ou em uma regra fiscal.")
    elif interstate and str(profile.cfop).startswith("5"):
        warnings.append("CFOP iniciado por 5 nao combina com operacao interestadual.")
    elif not interstate and str(profile.cfop).startswith("6"):
        warnings.append("CFOP iniciado por 6 nao combina com operacao interna.")
    if product is not None and not getattr(product, "ncm", None):
        warnings.append("Produto sem NCM cadastrado.")
    return FiscalOutputRulePreviewRead(
        product_id=getattr(product, "id", None),
        product_name=getattr(product, "name", None),
        document_model=payload.document_model,
        operation_type=payload.operation_type,
        origin_uf=origin_uf,
        destination_uf=destination_uf,
        interstate=interstate,
        document_allowed=document_allowed,
        document_warning=document_warning,
        rule_source=profile.source,
        rule_id=getattr(rule, "id", None),
        rule_name=getattr(rule, "name", None),
        cfop=profile.cfop,
        origin=profile.origin,
        cst=profile.cst,
        csosn=profile.csosn,
        pis_cst=profile.pis_cst,
        cofins_cst=profile.cofins_cst,
        ibs_cbs_cst=profile.ibs_cbs_cst,
        ibs_cbs_classification=profile.ibs_cbs_classification,
        cbs_rate=profile.cbs_rate,
        ibs_state_rate=profile.ibs_state_rate,
        ibs_city_rate=profile.ibs_city_rate,
        warnings=list(dict.fromkeys(warnings)),
    )


@router.post("/certificate", response_model=FiscalCertificateUploadRead)
async def upload_fiscal_certificate(
    certificate: UploadFile = File(...),
    password: str = Form(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:settings")),
) -> FiscalCertificateUploadRead:
    filename = certificate.filename or "certificado-a1.pfx"
    lower_name = filename.lower()
    if not (lower_name.endswith(".pfx") or lower_name.endswith(".p12")):
        raise HTTPException(status_code=400, detail="Envie um certificado A1 .pfx ou .p12.")
    raw = await certificate.read()
    if not raw:
        raise HTTPException(status_code=400, detail="Arquivo do certificado vazio.")
    if len(raw) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Certificado maior que o limite de 10 MB.")
    if not password.strip():
        raise HTTPException(status_code=400, detail="Informe a senha do certificado.")
    try:
        private_key, certificate_data, extra_certificates = pkcs12.load_key_and_certificates(
            raw,
            password.encode("utf-8"),
        )
    except Exception as exc:
        raise HTTPException(
            status_code=400,
            detail="Nao foi possivel abrir o certificado A1. Confira se o arquivo e a senha estao corretos.",
        ) from exc
    if private_key is None or certificate_data is None:
        raise HTTPException(status_code=400, detail="Certificado A1 sem certificado valido.")
    raw = pkcs12.serialize_key_and_certificates(
        name=filename.encode("utf-8"),
        key=private_key,
        cert=certificate_data,
        cas=extra_certificates,
        encryption_algorithm=serialization.BestAvailableEncryption(
            password.encode("utf-8")
        ),
    )

    setting = _get_or_create_settings(db)
    file_hash = sha256_hex(raw)
    setting.certificate_name = filename
    setting.certificate_storage_key = f"tenant-db:a1:{uuid4()}"
    setting.certificate_password_secret_key = f"tenant-db:a1-password:{uuid4()}"
    setting.certificate_encrypted_blob = encrypt_certificate_bytes(raw)
    setting.certificate_password_encrypted = encrypt_secret(password)
    setting.certificate_file_sha256 = file_hash
    setting.certificate_expires_at = certificate_data.not_valid_after_utc.date()
    setting.certificate_uploaded_at = datetime.utcnow()
    _add_fiscal_audit(
        db,
        current_user,
        action="certificate_upload",
        field_name="certificate_encrypted_blob",
        old_value=None,
        new_value="uploaded",
        notes=f"Arquivo {filename}, hash {file_hash}.",
    )
    db.commit()
    return FiscalCertificateUploadRead(
        certificate_name=filename,
        certificate_file_sha256=file_hash,
        has_certificate=True,
        message="Certificado A1 armazenado criptografado no banco separado desta empresa.",
    )


@router.delete("/certificate")
def delete_fiscal_certificate(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:settings")),
) -> dict[str, str]:
    setting = _get_or_create_settings(db)
    setting.certificate_name = None
    setting.certificate_storage_key = None
    setting.certificate_password_secret_key = None
    setting.certificate_encrypted_blob = None
    setting.certificate_password_encrypted = None
    setting.certificate_file_sha256 = None
    setting.certificate_expires_at = None
    setting.certificate_uploaded_at = None
    _add_fiscal_audit(
        db,
        current_user,
        action="certificate_delete",
        field_name="certificate_encrypted_blob",
        old_value="stored",
        new_value=None,
    )
    db.commit()
    return {"message": "Certificado fiscal removido desta empresa."}


@router.get("/documents", response_model=list[FiscalDocumentRead])
def list_fiscal_documents(
    status_filter: str | None = Query(default=None, alias="status"),
    limit: int = Query(default=50, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:documents:view")),
) -> list[FiscalDocument]:
    query = (
        select(FiscalDocument)
        .options(
            selectinload(FiscalDocument.fiscal_items).selectinload(FiscalDocumentItem.fiscal_product),
            selectinload(FiscalDocument.fiscal_items).selectinload(FiscalDocumentItem.original_product),
        )
        .order_by(FiscalDocument.created_at.desc())
        .limit(limit)
    )
    if status_filter:
        query = query.where(FiscalDocument.status == status_filter)
    return list(db.scalars(query).all())


@router.get("/sales/{sale_number}/draft", response_model=FiscalDocumentDraftRead)
def get_fiscal_sale_draft(
    sale_number: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:emit")),
) -> FiscalDocumentDraftRead:
    sale = _sale_or_404(db, sale_number=sale_number.strip())
    if sale.status != "finalizada":
        raise HTTPException(status_code=400, detail="Somente venda finalizada pode emitir nota.")
    return _draft_read_from_sale(sale)


@router.get("/products/lookup", response_model=list[FiscalProductLookupRead])
def lookup_fiscal_products(
    q: str = Query(default=""),
    limit: int = Query(default=200, ge=1, le=300),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:emit")),
) -> list[Product]:
    query_text = q.strip()
    query = select(Product).where(Product.active.is_(True))
    if query_text:
        like = f"%{query_text.lower()}%"
        query = query.where(
            (Product.name.ilike(like))
            | (Product.internal_code == query_text)
            | (Product.barcode == query_text)
            | (Product.purchase_package_barcode == query_text)
        )
    query = query.order_by(Product.name).limit(limit)
    products = list(db.scalars(query).all())
    refresh_many_product_fiscal_balances(db, {product.id for product in products})
    return products


@router.post("/documents/prepare", response_model=FiscalDocumentRead, status_code=status.HTTP_201_CREATED)
def prepare_fiscal_document(
    payload: FiscalDocumentPrepare,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:emit")),
) -> FiscalDocument:
    sale = db.scalar(
        select(Sale)
        .options(
            selectinload(Sale.items).selectinload(SaleItem.product),
            selectinload(Sale.payments),
            selectinload(Sale.client),
        )
        .where(Sale.id == payload.sale_id)
        .with_for_update()
    )
    if sale is None:
        raise HTTPException(status_code=404, detail="Venda nao encontrada.")
    existing_document = db.scalar(
        select(FiscalDocument)
        .where(
            FiscalDocument.sale_id == sale.id,
            FiscalDocument.document_type == payload.document_type,
            FiscalDocument.status != "cancelled",
        )
        .order_by(FiscalDocument.id.desc())
    )
    if existing_document is not None:
        return existing_document
    setting = _get_or_create_settings(db)
    if payload.document_type == "nfce" and not setting.nfce_enabled:
        raise HTTPException(status_code=400, detail="NFC-e nao esta habilitada para esta empresa.")
    if payload.document_type == "nfe" and not setting.nfe_enabled:
        raise HTTPException(status_code=400, detail="NF-e não está habilitada para esta empresa.")

    fiscal_client = _resolve_fiscal_client(db, payload.fiscal_client_id)
    recipient_document = fiscal_client.document_number if fiscal_client is not None else None
    recipient_name = fiscal_client.name if fiscal_client is not None else None
    consumer_cpf = payload.consumer_cpf or recipient_document
    operation_nature = " ".join((payload.operation_nature or "").split()) or "VENDA DE MERCADORIA"
    fiscal_notes = " ".join((payload.fiscal_notes or "").split()) or None
    status_value = (
        "draft"
        if setting.certificate_encrypted_blob and setting.certificate_password_encrypted
        else "pending_certificate"
    )
    document = FiscalDocument(
        sale_id=sale.id,
        fiscal_client_id=fiscal_client.id if fiscal_client is not None else None,
        document_type=payload.document_type,
        model="65" if payload.document_type == "nfce" else "55",
        environment=setting.environment,
        consumer_cpf=consumer_cpf,
        recipient_document=recipient_document,
        recipient_name=recipient_name,
        operation_nature=operation_nature[:120],
        payment_condition=payload.payment_condition,
        fiscal_notes=fiscal_notes,
        stock_deduction_on_authorize=False,
        status=status_value,
        sefaz_message="Documento preparado para assinatura A1 e envio a SEFAZ.",
    )
    db.add(document)
    db.commit()
    db.refresh(document)
    return document


@router.post("/documents/prepare-with-items", response_model=FiscalDocumentRead, status_code=status.HTTP_201_CREATED)
def prepare_fiscal_document_with_items(
    payload: FiscalDocumentPrepareWithItems,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:emit")),
) -> FiscalDocument:
    sale = _sale_or_404(db, sale_id=payload.sale_id)
    if sale.status != "finalizada":
        raise HTTPException(status_code=400, detail="Somente venda finalizada pode emitir nota.")
    setting = _get_or_create_settings(db)
    if payload.document_type == "nfce" and not setting.nfce_enabled:
        raise HTTPException(status_code=400, detail="NFC-e nao esta habilitada para esta empresa.")
    if payload.document_type == "nfe" and not setting.nfe_enabled:
        raise HTTPException(status_code=400, detail="NF-e nao esta habilitada para esta empresa.")

    fiscal_client = _resolve_fiscal_client(db, payload.fiscal_client_id)
    recipient_document = fiscal_client.document_number if fiscal_client is not None else None
    recipient_name = fiscal_client.name if fiscal_client is not None else None
    consumer_cpf = payload.consumer_cpf or recipient_document
    sale_items_by_id = {item.id: item for item in sale.items}
    operation_nature = " ".join((payload.operation_nature or "").split()) or "VENDA DE MERCADORIA"
    fiscal_notes = " ".join((payload.fiscal_notes or "").split()) or None
    status_value = (
        "draft"
        if setting.certificate_encrypted_blob and setting.certificate_password_encrypted
        else "pending_certificate"
    )
    document = FiscalDocument(
        sale_id=sale.id,
        fiscal_client_id=fiscal_client.id if fiscal_client is not None else None,
        document_type=payload.document_type,
        model="65" if payload.document_type == "nfce" else "55",
        environment=setting.environment,
        consumer_cpf=consumer_cpf,
        recipient_document=recipient_document,
        recipient_name=recipient_name,
        operation_nature=operation_nature[:120],
        payment_condition=payload.payment_condition,
        fiscal_notes=fiscal_notes,
        stock_deduction_on_authorize=False,
        status=status_value,
        sefaz_message="Documento preparado com rascunho fiscal ajustavel. Venda original preservada.",
    )
    db.add(document)
    db.flush()

    included_count = 0
    for override in payload.items:
        sale_item = sale_items_by_id.get(override.sale_item_id) if override.sale_item_id is not None else None
        product = db.get(Product, override.fiscal_product_id) if override.fiscal_product_id is not None else None
        if override.included and product is None:
            raise HTTPException(status_code=400, detail="Item incluido precisa ter produto fiscal vinculado.")
        if override.included:
            included_count += 1
        quantity = Decimal(override.quantity or 0)
        unit_price = Decimal(override.unit_price or 0)
        discount = Decimal(override.discount_amount or 0)
        total = _line_total(quantity, unit_price, discount)
        fiscal_description = " ".join((override.fiscal_description or "").split())
        if not fiscal_description:
            fiscal_description = product.name if product is not None else (
                sale_item.description if sale_item is not None else "Item fiscal"
            )
        unit = " ".join((override.unit or "").split()) or (
            product.unit if product is not None else (sale_item.unit if sale_item is not None else "un")
        )
        db.add(
            FiscalDocumentItem(
                fiscal_document_id=document.id,
                sale_item_id=sale_item.id if sale_item is not None else None,
                original_product_id=sale_item.product_id if sale_item is not None else None,
                fiscal_product_id=product.id if product is not None else None,
                original_description=sale_item.description if sale_item is not None else None,
                fiscal_description=fiscal_description[:220],
                quantity=quantity,
                unit=unit[:20],
                unit_price=unit_price,
                discount_amount=discount,
                total_price=total,
                barcode=product.barcode if product is not None else (sale_item.barcode if sale_item is not None else None),
                included=override.included,
                adjustment_reason=override.adjustment_reason,
                created_by_user_id=current_user.id,
                **_clean_item_tax_overrides(override),
            )
        )
    if included_count == 0:
        raise HTTPException(status_code=400, detail="A nota precisa ter pelo menos um item incluido.")
    db.commit()
    db.refresh(document)
    return document


@router.post(
    "/documents/prepare-from-sales",
    response_model=FiscalDocumentRead,
    status_code=status.HTTP_201_CREATED,
)
def prepare_fiscal_document_from_sales(
    payload: FiscalDocumentPrepareFromSales,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:emit")),
) -> FiscalDocument:
    sale_ids = list(dict.fromkeys(payload.sale_ids))
    sales = list(
        db.scalars(
            select(Sale)
            .options(
                selectinload(Sale.items).selectinload(SaleItem.product),
                selectinload(Sale.payments),
                selectinload(Sale.client),
                selectinload(Sale.fiscal_documents),
                selectinload(Sale.fiscal_document_links).selectinload(FiscalDocumentSale.document),
            )
            .where(Sale.id.in_(sale_ids))
            .order_by(Sale.id)
            .with_for_update()
        ).all()
    )
    if len(sales) != len(sale_ids):
        raise HTTPException(status_code=404, detail="Uma ou mais vendas nao foram encontradas.")
    if any(sale.status != "finalizada" for sale in sales):
        raise HTTPException(status_code=400, detail="Somente vendas finalizadas podem emitir nota.")
    if any(sale.client_id != payload.fiscal_client_id for sale in sales):
        raise HTTPException(status_code=400, detail="Todas as vendas precisam pertencer ao mesmo cliente.")
    for sale in sales:
        active_documents = [
            *sale.fiscal_documents,
            *(link.document for link in sale.fiscal_document_links if link.document is not None),
        ]
        if any(document.status != "cancelled" for document in active_documents):
            raise HTTPException(
                status_code=409,
                detail=f"A venda {sale.number or sale.id} ja possui documento fiscal.",
            )

    setting = _get_or_create_settings(db)
    if payload.document_type == "nfce" and not setting.nfce_enabled:
        raise HTTPException(status_code=400, detail="NFC-e nao esta habilitada para esta empresa.")
    if payload.document_type == "nfe" and not setting.nfe_enabled:
        raise HTTPException(status_code=400, detail="NF-e nao esta habilitada para esta empresa.")
    fiscal_client = _resolve_fiscal_client(db, payload.fiscal_client_id)
    if fiscal_client is None:
        raise HTTPException(status_code=400, detail="Selecione o cliente/destinatario fiscal.")
    status_value = (
        "draft"
        if setting.certificate_encrypted_blob and setting.certificate_password_encrypted
        else "pending_certificate"
    )
    document = FiscalDocument(
        sale_id=sales[0].id if len(sales) == 1 else None,
        fiscal_client_id=fiscal_client.id,
        document_type=payload.document_type,
        model="65" if payload.document_type == "nfce" else "55",
        environment=setting.environment,
        # For NF-e the recipient document is stored separately. Do not copy a
        # formatted CPF/CNPJ into consumer_cpf (VARCHAR(14)); that field is
        # only meaningful for NFC-e consumers.
        consumer_cpf=(payload.consumer_cpf if payload.document_type == "nfce" else None),
        recipient_document=fiscal_client.document_number,
        recipient_name=fiscal_client.name,
        operation_nature=(" ".join((payload.operation_nature or "").split()) or "VENDA DE MERCADORIA")[:120],
        payment_condition=payload.payment_condition,
        fiscal_notes=" ".join((payload.fiscal_notes or "").split()) or None,
        stock_deduction_on_authorize=False,
        status=status_value,
        sefaz_message=(
            f"Documento preparado a partir de {len(sales)} venda(s) ja concluida(s). "
            "A emissao fiscal nao movimentara o estoque novamente."
        ),
    )
    db.add(document)
    db.flush()
    aggregated_items: dict[tuple[int | None, str], FiscalDocumentItem] = {}
    for sale in sales:
        db.add(FiscalDocumentSale(fiscal_document_id=document.id, sale_id=sale.id))
        for item in sale.items:
            product = item.product
            key = (item.product_id, (item.unit or "un").strip().lower())
            existing = aggregated_items.get(key)
            quantity = Decimal(item.quantity or 0)
            total_price = Decimal(item.total_price or 0)
            discount_amount = Decimal(item.discount_amount or 0)
            if existing is not None:
                existing.quantity += quantity
                existing.total_price += total_price
                existing.discount_amount += discount_amount
                existing.unit_price = (
                    existing.total_price / existing.quantity
                    if existing.quantity
                    else Decimal("0")
                ).quantize(Decimal("0.01"))
                existing.adjustment_reason = f"Origem: {existing.adjustment_reason}; venda {sale.number or sale.id}."
                continue
            fiscal_item = FiscalDocumentItem(
                fiscal_document_id=document.id,
                sale_item_id=item.id,
                original_product_id=item.product_id,
                fiscal_product_id=item.product_id,
                original_description=item.description,
                fiscal_description=(product.name if product is not None else item.description)[:220],
                quantity=quantity,
                unit=item.unit,
                unit_price=Decimal(item.unit_price or 0),
                discount_amount=discount_amount,
                total_price=total_price,
                barcode=item.barcode or (product.barcode if product is not None else None),
                included=True,
                adjustment_reason=f"Origem: venda {sale.number or sale.id}.",
                ncm=product.ncm if product is not None else None,
                cest=product.cest if product is not None else None,
                cfop=product.cfop_sale if product is not None else None,
                origin=product.origin if product is not None else None,
                cst=product.cst if product is not None else None,
                csosn=product.csosn if product is not None else None,
                created_by_user_id=current_user.id,
            )
            aggregated_items[key] = fiscal_item
            db.add(fiscal_item)
    db.commit()
    return db.scalar(
        select(FiscalDocument)
        .options(
            selectinload(FiscalDocument.sale),
            selectinload(FiscalDocument.fiscal_items).selectinload(FiscalDocumentItem.fiscal_product),
            selectinload(FiscalDocument.source_sale_links).selectinload(FiscalDocumentSale.sale),
        )
        .where(FiscalDocument.id == document.id)
    )


@router.post("/documents/prepare-manual", response_model=FiscalDocumentRead, status_code=status.HTTP_201_CREATED)
def prepare_manual_fiscal_document(
    payload: FiscalDocumentPrepareManual,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:emit")),
) -> FiscalDocument:
    setting = _get_or_create_settings(db)
    if payload.document_type == "nfce" and not setting.nfce_enabled:
        raise HTTPException(status_code=400, detail="NFC-e nao esta habilitada para esta empresa.")
    if payload.document_type == "nfe" and not setting.nfe_enabled:
        raise HTTPException(status_code=400, detail="NF-e nao esta habilitada para esta empresa.")

    fiscal_client = _resolve_fiscal_client(db, payload.fiscal_client_id)
    if payload.document_type == "nfe" and fiscal_client is None:
        raise HTTPException(status_code=400, detail="NF-e manual precisa de cliente/destinatario cadastrado.")
    recipient_document = fiscal_client.document_number if fiscal_client is not None else None
    recipient_name = fiscal_client.name if fiscal_client is not None else None
    consumer_cpf = payload.consumer_cpf or recipient_document
    operation_nature = " ".join((payload.operation_nature or "").split()) or "VENDA DE MERCADORIA"
    fiscal_notes = " ".join((payload.fiscal_notes or "").split()) or None
    status_value = (
        "draft"
        if setting.certificate_encrypted_blob and setting.certificate_password_encrypted
        else "pending_certificate"
    )
    document = FiscalDocument(
        sale_id=None,
        fiscal_client_id=fiscal_client.id if fiscal_client is not None else None,
        document_type=payload.document_type,
        model="65" if payload.document_type == "nfce" else "55",
        environment=setting.environment,
        consumer_cpf=consumer_cpf,
        recipient_document=recipient_document,
        recipient_name=recipient_name,
        operation_nature=operation_nature[:120],
        payment_condition=payload.payment_condition,
        fiscal_notes=fiscal_notes,
        stock_deduction_on_authorize=payload.stock_deduction_on_authorize,
        status=status_value,
        sefaz_message=(
            "Nota fiscal manual preparada. Ao autorizar, o estoque sera baixado pelos itens informados."
            if payload.stock_deduction_on_authorize
            else "Nota fiscal manual preparada sem baixa automatica de estoque."
        ),
    )
    db.add(document)
    db.flush()

    included_count = 0
    for override in payload.items:
        product = db.get(Product, override.fiscal_product_id) if override.fiscal_product_id is not None else None
        if override.included and product is None:
            raise HTTPException(status_code=400, detail="Item manual precisa ter produto do estoque vinculado.")
        if override.included:
            included_count += 1
        quantity = Decimal(override.quantity or 0)
        unit_price = Decimal(override.unit_price or 0)
        discount = Decimal(override.discount_amount or 0)
        total = _line_total(quantity, unit_price, discount)
        fiscal_description = " ".join((override.fiscal_description or "").split())
        if not fiscal_description:
            fiscal_description = product.name if product is not None else "Item fiscal manual"
        unit = " ".join((override.unit or "").split()) or (product.unit if product is not None else "un")
        db.add(
            FiscalDocumentItem(
                fiscal_document_id=document.id,
                sale_item_id=None,
                original_product_id=None,
                fiscal_product_id=product.id if product is not None else None,
                original_description=None,
                fiscal_description=fiscal_description[:220],
                quantity=quantity,
                unit=unit[:20],
                unit_price=unit_price,
                discount_amount=discount,
                total_price=total,
                barcode=product.barcode if product is not None else None,
                included=override.included,
                adjustment_reason=override.adjustment_reason or "Item incluido em nota fiscal manual.",
                created_by_user_id=current_user.id,
                **_clean_item_tax_overrides(override),
            )
        )
    if included_count == 0:
        raise HTTPException(status_code=400, detail="A nota manual precisa ter pelo menos um item incluido.")
    db.commit()
    db.refresh(document)
    return document


@router.put("/documents/{document_id}", response_model=FiscalDocumentRead)
def update_fiscal_document(
    document_id: int,
    payload: FiscalDocumentUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:emit")),
) -> FiscalDocument:
    document = db.scalar(
        select(FiscalDocument)
        .options(selectinload(FiscalDocument.fiscal_items).selectinload(FiscalDocumentItem.fiscal_product))
        .where(FiscalDocument.id == document_id)
    )
    if document is None:
        raise HTTPException(status_code=404, detail="Documento fiscal nao encontrado.")
    if document.status in {"authorized", "cancelled", "contingency_offline"}:
        raise HTTPException(status_code=400, detail="Documento autorizado ou cancelado nao pode ser alterado.")
    if payload.fiscal_client_id is not None:
        client = _resolve_fiscal_client(db, payload.fiscal_client_id)
        document.fiscal_client_id = client.id
        document.recipient_document, document.recipient_name = client.document_number, client.name
    sent_fields = payload.model_fields_set
    for name in ("consumer_cpf", "operation_nature", "finality", "payment_condition", "fiscal_notes", "freight_mode", "freight_amount", "insurance_amount", "other_expenses_amount", "carrier_name", "carrier_document", "carrier_state_registration", "carrier_address", "carrier_city", "carrier_uf", "volume_quantity", "volume_species", "volume_brand", "volume_numbering", "net_weight", "gross_weight"):
        if name in sent_fields:
            setattr(document, name, getattr(payload, name))
    if payload.items is not None:
        _replace_document_items(db, document, payload.items, current_user)
    # Se a SEFAZ ja recebeu esta tentativa, o numero permanece no documento.
    # A edicao apenas recompõe o rascunho para um reenvio idempotente da mesma
    # serie/numero; documentos ainda sem numero receberao o proximo disponivel.
    document.status = "draft"
    document.sefaz_status_code = None
    document.sefaz_message = "Rascunho fiscal atualizado e pronto para revisao."
    document.sefaz_protocol = None
    document.xml_generated = None
    document.xml_signed = None
    document.xml_authorized = None
    document.authorized_at = None
    db.commit()
    db.refresh(document)
    return document


@router.post(
    "/documents/{document_id}/enqueue",
    response_model=FiscalTransmissionJobRead,
    status_code=status.HTTP_202_ACCEPTED,
)
def enqueue_fiscal_document(
    document_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:emit")),
) -> FiscalTransmissionJob:
    document = db.get(FiscalDocument, document_id)
    if document is None:
        raise HTTPException(status_code=404, detail="Documento fiscal nao encontrado.")
    job = enqueue_fiscal_job(
        db,
        document,
        requested_by_user_id=current_user.id,
        job_type="authorize",
    )
    if document.status in {"authorized", "cancelled", "contingency_offline"}:
        job.status = "completed"
        job.result_document_id = document.id
        job.completed_at = datetime.utcnow()
        job.next_attempt_at = None
    db.commit()
    return db.scalar(
        select(FiscalTransmissionJob)
        .options(
            selectinload(FiscalTransmissionJob.document),
            selectinload(FiscalTransmissionJob.result_document),
        )
        .where(FiscalTransmissionJob.id == job.id)
    )


@router.get("/jobs/{job_id}", response_model=FiscalTransmissionJobRead)
def get_fiscal_transmission_job(
    job_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:emit")),
) -> FiscalTransmissionJob:
    job = db.scalar(
        select(FiscalTransmissionJob)
        .options(
            selectinload(FiscalTransmissionJob.document),
            selectinload(FiscalTransmissionJob.result_document),
        )
        .where(FiscalTransmissionJob.id == job_id)
    )
    if job is None:
        raise HTTPException(status_code=404, detail="Trabalho fiscal nao encontrado.")
    return job


@router.post("/documents/{document_id}/authorize", response_model=FiscalDocumentRead)
def authorize_fiscal_document(
    document_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:emit")),
) -> FiscalDocument:
    document = db.scalar(
        select(FiscalDocument)
        .options(
            selectinload(FiscalDocument.sale).selectinload(Sale.items).selectinload(SaleItem.product),
            selectinload(FiscalDocument.sale).selectinload(Sale.payments),
            selectinload(FiscalDocument.sale).selectinload(Sale.client),
            selectinload(FiscalDocument.fiscal_client),
            selectinload(FiscalDocument.fiscal_items).selectinload(FiscalDocumentItem.fiscal_product),
            selectinload(FiscalDocument.fiscal_items).selectinload(FiscalDocumentItem.original_product),
        )
        .where(FiscalDocument.id == document_id)
        .with_for_update()
    )
    if document is None:
        raise HTTPException(status_code=404, detail="Documento fiscal nao encontrado.")
    if document.status == "authorized":
        return document
    if _is_recent_processing(document):
        raise HTTPException(
            status_code=409,
            detail="Documento fiscal ja esta em processamento. Aguarde o retorno da SEFAZ.",
        )
    if document.sale is None and not any(item.included for item in document.fiscal_items):
        raise HTTPException(status_code=400, detail="Nota manual precisa ter pelo menos um item fiscal incluido.")
    setting = _attach_output_rules(_get_or_create_settings(db), db)
    if document.document_type == "nfce" and not setting.nfce_enabled:
        raise HTTPException(status_code=400, detail="NFC-e nao esta habilitada para esta empresa.")
    if document.document_type == "nfe" and not setting.nfe_enabled:
        raise HTTPException(status_code=400, detail="NF-e nao esta habilitada para esta empresa.")
    fiscal_sale = (
        _fiscal_sale_view(document, document.sale)
        if document.sale is not None
        else _manual_fiscal_sale_view(document)
    )
    try:
        validate_rtc_document(
            setting,
            fiscal_sale,
            model="65" if document.document_type == "nfce" else "55",
            issue_date=datetime.now().date(),
        )
        try:
            document, setting = _reserve_fiscal_number(db, document_id)
            setting = _attach_output_rules(setting, db)
        except IntegrityError as exc:
            db.rollback()
            raise HTTPException(
                status_code=409,
                detail="Nao foi possivel reservar a numeracao fiscal. Tente novamente.",
            ) from exc
        document = db.scalar(
            select(FiscalDocument)
            .options(
                selectinload(FiscalDocument.sale).selectinload(Sale.items).selectinload(SaleItem.product),
                selectinload(FiscalDocument.sale).selectinload(Sale.payments),
                selectinload(FiscalDocument.sale).selectinload(Sale.client),
                selectinload(FiscalDocument.fiscal_client),
                selectinload(FiscalDocument.fiscal_items).selectinload(FiscalDocumentItem.fiscal_product),
                selectinload(FiscalDocument.fiscal_items).selectinload(FiscalDocumentItem.original_product),
            )
            .where(FiscalDocument.id == document_id)
        )
        if document is None:
            raise HTTPException(status_code=404, detail="Documento fiscal nao encontrado.")
        fiscal_sale = (
            _fiscal_sale_view(document, document.sale)
            if document.sale is not None
            else _manual_fiscal_sale_view(document)
        )
        # NFC-e e NF-e seguem a mesma regra: rejeicao comum conserva o numero.
        # Somente a rejeicao 539, cuja resposta traz a chave que a SEFAZ ja
        # conhece, comprova que outro emissor/PDV consumiu aquele numero.
        model = "65" if document.document_type == "nfce" else "55"
        authorize_document = authorize_nfce if document.document_type == "nfce" else authorize_nfe
        for _ in range(10):
            result = authorize_document(setting, document, fiscal_sale)
            duplicate_key = (
                _duplicate_nfe_key(result.message)
                if result.status_code == "539"
                else None
            )
            if duplicate_key is None or duplicate_key[20:22] != model:
                break
            duplicate_series = int(duplicate_key[22:25])
            duplicate_number = int(duplicate_key[25:34])
            configured_series = int(
                document.series
                or (setting.nfce_series if document.document_type == "nfce" else setting.nfe_series)
                or 1
            )
            if duplicate_series != configured_series:
                break
            if document.document_type == "nfce":
                setting.nfce_next_number = max(
                    int(setting.nfce_next_number or 1), duplicate_number + 1
                )
                configured_next_number = int(setting.nfce_next_number)
            else:
                setting.nfe_next_number = max(
                    int(setting.nfe_next_number or 1), duplicate_number + 1
                )
                configured_next_number = int(setting.nfe_next_number)
            document.number = None
            document.access_key = None
            document.xml_generated = None
            document.xml_signed = None
            document.xml_authorized = None
            db.flush()
            document.number = _next_available_fiscal_number(
                db,
                environment=document.environment,
                document_type=document.document_type,
                series=configured_series,
                configured_next_number=configured_next_number,
            )
        else:
            raise NfceValidationError(
                "A SEFAZ informou dez numeros fiscais consecutivos ja utilizados. "
                "Confira a numeracao fiscal antes de continuar."
            )
    except HTTPException:
        db.rollback()
        raise
    except RtcComplianceError as exc:
        # A venda já foi concluída. Uma lacuna cadastral não deve transformá-la
        # em erro nem consumir numeração: a transmissão aguarda configuração.
        document.status = "pending_configuration"
        document.sefaz_status_code = "CONFIGURACAO_FISCAL"
        document.sefaz_message = str(exc)
        db.commit()
        db.refresh(document)
        return document
    except NfceValidationError as exc:
        document.status = "rejected"
        document.sefaz_status_code = "VALIDACAO"
        document.sefaz_message = _friendly_sefaz_message("VALIDACAO", str(exc))
        db.commit()
        db.refresh(document)
        return document
    except Exception as exc:
        if document.document_type == "nfce" and _is_sefaz_connection_failure(exc):
            try:
                return _create_timeout_contingency(
                    db,
                    document=document,
                    setting=setting,
                    fiscal_sale=fiscal_sale,
                    requested_by_user_id=current_user.id,
                    error_message=f"{type(exc).__name__}: {str(exc)}",
                )
            except NfceValidationError as validation_exc:
                document.status = "rejected"
                document.sefaz_status_code = "VALIDACAO_CONTINGENCIA"
                document.sefaz_message = _friendly_sefaz_message("VALIDACAO_CONTINGENCIA", str(validation_exc))
                db.commit()
                db.refresh(document)
                return document
        document.status = "rejected"
        document.sefaz_status_code = "ERRO_ENVIO"
        document.sefaz_message = _friendly_sefaz_message(
            "ERRO_ENVIO",
            f"Falha ao enviar para a SEFAZ: {type(exc).__name__}: {str(exc)[:400]}",
        )
        db.commit()
        db.refresh(document)
        return document

    document.status = result.status
    document.sefaz_status_code = result.status_code
    document.sefaz_message = _friendly_sefaz_message(result.status_code, result.message) if result.status != "authorized" else result.message
    document.sefaz_protocol = result.protocol
    document.xml_authorized = result.authorized_xml
    if result.status == "authorized":
        document.authorized_at = datetime.utcnow()
        if should_move_stock_for_fiscal_document(document):
            _post_manual_document_stock_out(db, document, current_user.id)
        _refresh_document_fiscal_balances(db, document)
        if document.document_type == "nfce":
            setting.nfce_next_number = max(setting.nfce_next_number, int(document.number or 0) + 1)
            setting.nfce_last_authorized_number = max(
                int(setting.nfce_last_authorized_number or 0),
                int(document.number or 0),
            )
        else:
            setting.nfe_next_number = max(setting.nfe_next_number, int(document.number or 0) + 1)
            setting.nfe_last_authorized_number = max(
                int(setting.nfe_last_authorized_number or 0),
                int(document.number or 0),
            )
            recipient = document.fiscal_client or (document.sale.client if document.sale is not None else None)
            if recipient is not None:
                document.recipient_document = recipient.document_number
                document.recipient_name = recipient.name
    db.commit()
    db.refresh(document)
    return document


@router.post("/documents/{document_id}/transmit-contingency", response_model=FiscalDocumentRead)
def transmit_contingency_fiscal_document(
    document_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:emit")),
) -> FiscalDocument:
    document = db.scalar(
        select(FiscalDocument)
        .options(
            selectinload(FiscalDocument.sale).selectinload(Sale.items).selectinload(SaleItem.product),
            selectinload(FiscalDocument.sale).selectinload(Sale.payments),
            selectinload(FiscalDocument.sale).selectinload(Sale.client),
            selectinload(FiscalDocument.fiscal_client),
            selectinload(FiscalDocument.fiscal_items).selectinload(FiscalDocumentItem.fiscal_product),
        )
        .where(FiscalDocument.id == document_id)
        .with_for_update()
    )
    if document is None:
        raise HTTPException(status_code=404, detail="Documento fiscal nao encontrado.")
    if document.document_type != "nfce":
        raise HTTPException(status_code=400, detail="Contingencia offline disponivel somente para NFC-e.")
    if document.status == "authorized":
        return document
    if document.status != "contingency_offline":
        raise HTTPException(status_code=400, detail="Somente NFC-e em contingencia offline pode ser transmitida.")
    setting = _locked_fiscal_setting(db)
    try:
        result = transmit_nfce_offline_contingency(setting, document)
    except NfceValidationError as exc:
        document.sefaz_status_code = "VALIDACAO"
        document.sefaz_message = _friendly_sefaz_message("VALIDACAO", str(exc))
        db.commit()
        db.refresh(document)
        return document
    except Exception as exc:
        document.sefaz_status_code = "ERRO_ENVIO"
        document.sefaz_message = _friendly_sefaz_message(
            "ERRO_ENVIO",
            f"Falha ao transmitir contingencia para a SEFAZ: {type(exc).__name__}: {str(exc)[:400]}",
        )
        db.commit()
        db.refresh(document)
        return document

    document.status = result.status
    document.sefaz_status_code = result.status_code
    document.sefaz_message = _friendly_sefaz_message(result.status_code, result.message) if result.status != "authorized" else result.message
    document.sefaz_protocol = result.protocol
    document.xml_authorized = result.authorized_xml
    if result.status == "authorized":
        document.authorized_at = datetime.utcnow()
        if should_move_stock_for_fiscal_document(document):
            _post_manual_document_stock_out(db, document, current_user.id)
        _refresh_document_fiscal_balances(db, document)
        setting.nfce_last_authorized_number = max(
            int(setting.nfce_last_authorized_number or 0),
            int(document.number or 0),
        )
    db.commit()
    db.refresh(document)
    return document


@router.post("/documents/{document_id}/cancel", response_model=FiscalDocumentRead)
def cancel_fiscal_document(
    document_id: int,
    payload: FiscalDocumentCancel,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:cancel")),
) -> FiscalDocument:
    document = db.get(FiscalDocument, document_id)
    if document is None:
        raise HTTPException(status_code=404, detail="Documento fiscal nao encontrado.")
    if document.status == "cancelled":
        return document
    if document.status != "authorized":
        raise HTTPException(status_code=400, detail="Somente nota autorizada pode ser cancelada.")
    setting = _get_or_create_settings(db)
    try:
        result = send_cancellation_event(setting, document, payload.reason)
    except NfceValidationError as exc:
        raise HTTPException(status_code=400, detail=_friendly_sefaz_message("VALIDACAO_CANCELAMENTO", str(exc))) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Falha ao transmitir cancelamento para a SEFAZ: {type(exc).__name__}: {str(exc)[:300]}",
        ) from exc
    document.cancellation_reason = " ".join(payload.reason.split())
    document.cancellation_status_code = result.status_code
    document.cancellation_message = (
        result.message if result.accepted else _friendly_sefaz_message(result.status_code, result.message)
    )
    document.cancellation_protocol = result.protocol
    document.cancellation_xml = result.response_xml
    if result.accepted:
        document.status = "cancelled"
        document.cancelled_at = datetime.utcnow()
        document.sefaz_message = result.message
        if should_move_stock_for_fiscal_document(document):
            _post_manual_document_stock_return(db, document, current_user.id)
        _refresh_document_fiscal_balances(db, document)
    db.commit()
    db.refresh(document)
    if not result.accepted:
        raise HTTPException(
            status_code=409,
            detail={
                "message": "A SEFAZ nao aceitou o cancelamento.",
                "status_code": result.status_code,
                "sefaz_message": result.message,
            },
        )
    return document


@router.get("/documents/{document_id}/danfe")
def get_fiscal_document_danfe(
    document_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:documents:view")),
) -> Response:
    document = db.get(FiscalDocument, document_id)
    if document is None:
        raise HTTPException(status_code=404, detail="Documento fiscal nao encontrado.")
    setting = _get_or_create_settings(db)
    try:
        pdf = generate_danfe_pdf(setting, document)
    except NfceValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    number = document.number or document.id
    filename = f"danfe-{document.document_type}-{number}.pdf"
    return Response(
        content=pdf,
        media_type="application/pdf",
        headers={"Content-Disposition": f'inline; filename="{filename}"'},
    )


@router.get("/documents/{document_id}/xml")
def download_fiscal_document_xml(
    document_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_permission("fiscal:documents:view")),
) -> Response:
    document = db.get(FiscalDocument, document_id)
    if document is None:
        raise HTTPException(status_code=404, detail="Documento fiscal nao encontrado.")
    if document.status not in {"authorized", "cancelled"}:
        raise HTTPException(
            status_code=409,
            detail="O XML autorizado fica disponivel somente depois da autorizacao da nota.",
        )
    if not document.xml_authorized or not document.xml_authorized.strip():
        raise HTTPException(
            status_code=404,
            detail="XML autorizado nao encontrado. Use Recuperar notas da SEFAZ e tente novamente.",
        )
    return Response(
        content=document.xml_authorized.encode("utf-8"),
        media_type="application/xml",
        headers={
            "Content-Disposition": f'attachment; filename="{_fiscal_xml_filename(document)}"',
        },
    )
