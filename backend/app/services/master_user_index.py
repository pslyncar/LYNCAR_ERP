from fastapi import HTTPException, status
from sqlalchemy import select

from app.core.master_database import MasterSessionLocal
from app.models.company import Company
from app.models.master_user_index import MasterUserIndex
from app.services.tenancy import normalize_company_code


def access_url_for_company(company_code: str) -> str:
    normalized = normalize_company_code(company_code)
    if normalized == "master":
        return "https://erp.lyncar.com.br"
    return f"https://{normalized}.lyncar.com.br"


def find_user_companies(email: str, exclude_company_code: str | None = None) -> list[MasterUserIndex]:
    normalized_email = email.strip().lower()
    normalized_exclude = (
        normalize_company_code(exclude_company_code) if exclude_company_code else None
    )
    with MasterSessionLocal() as db:
        query = select(MasterUserIndex).where(MasterUserIndex.email == normalized_email)
        if normalized_exclude is not None:
            query = query.where(MasterUserIndex.company_code != normalized_exclude)
        return list(db.scalars(query.order_by(MasterUserIndex.company_name)).all())


def duplicate_email_detail(email: str, matches: list[MasterUserIndex]) -> dict:
    return {
        "code": "email_exists_other_companies",
        "message": "Este e-mail ja existe em outro cliente do sistema.",
        "email": email.strip().lower(),
        "companies": [
            {
                "company_code": match.company_code,
                "company_name": match.company_name,
                "user_name": match.name,
                "role": match.role,
                "access_url": access_url_for_company(match.company_code),
            }
            for match in matches
        ],
    }


def require_duplicate_authorization(
    email: str,
    company_code: str,
    allow_cross_company_duplicate: bool,
) -> None:
    matches = find_user_companies(email, exclude_company_code=company_code)
    if matches:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=duplicate_email_detail(email, matches),
        )


def upsert_user_index(
    *,
    company_code: str,
    company_name: str,
    user_id: int | None,
    name: str,
    email: str,
    role: str,
    active: bool,
) -> None:
    normalized_company = normalize_company_code(company_code)
    normalized_email = email.strip().lower()
    with MasterSessionLocal() as db:
        entry = db.scalar(
            select(MasterUserIndex).where(
                MasterUserIndex.company_code == normalized_company,
                MasterUserIndex.email == normalized_email,
            )
        )
        if entry is None:
            entry = MasterUserIndex(
                company_code=normalized_company,
                company_name=company_name,
                user_id=user_id,
                name=name,
                email=normalized_email,
                role=role,
                active=active,
            )
            db.add(entry)
        else:
            entry.company_name = company_name
            entry.user_id = user_id
            entry.name = name
            entry.role = role
            entry.active = active
        db.commit()


def remove_user_index(company_code: str, email: str) -> None:
    normalized_company = normalize_company_code(company_code)
    normalized_email = email.strip().lower()
    with MasterSessionLocal() as db:
        entry = db.scalar(
            select(MasterUserIndex).where(
                MasterUserIndex.company_code == normalized_company,
                MasterUserIndex.email == normalized_email,
            )
        )
        if entry is not None:
            db.delete(entry)
            db.commit()


def redirect_detail_for_email(email: str) -> dict | None:
    matches = find_user_companies(email)
    active_matches = [match for match in matches if match.active]
    if len(active_matches) != 1:
        return None
    match = active_matches[0]
    return {
        "code": "login_wrong_domain",
        "message": "Este usuario pertence a outro link do sistema.",
        "company_code": match.company_code,
        "company_name": match.company_name,
        "access_url": access_url_for_company(match.company_code),
    }


def company_name_for_code(company_code: str) -> str:
    normalized_company = normalize_company_code(company_code)
    with MasterSessionLocal() as db:
        company = db.scalar(select(Company).where(Company.code == normalized_company))
        return company.name if company is not None else normalized_company
