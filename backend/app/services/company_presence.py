from datetime import UTC, datetime, timedelta

from sqlalchemy import create_engine, func, select, text

from app.core.master_database import MasterSessionLocal
from app.models.company import Company
from app.models.company_presence import CompanyPresence
from app.models.user import User
from app.services.tenancy import get_company_by_code, normalize_company_code


ONLINE_WINDOW = timedelta(minutes=3)


def touch_company_presence(
    *,
    company_code: str,
    user: User,
    client_type: str = "web",
) -> None:
    normalized_code = normalize_company_code(company_code)
    if normalized_code == "master":
        return
    company = get_company_by_code(normalized_code)
    now = datetime.now(UTC)
    with MasterSessionLocal() as db:
        presence = db.scalar(
            select(CompanyPresence).where(
                CompanyPresence.company_code == normalized_code,
                CompanyPresence.user_id == user.id,
                CompanyPresence.client_type == client_type,
            )
        )
        if presence is None:
            presence = CompanyPresence(
                company_code=normalized_code,
                company_name=company.name if company else normalized_code,
                user_id=user.id,
                user_name=user.name,
                user_email=user.email,
                user_role=user.role,
                client_type=client_type,
                first_seen_at=now,
                last_seen_at=now,
            )
            db.add(presence)
        else:
            presence.company_name = company.name if company else normalized_code
            presence.user_name = user.name
            presence.user_email = user.email
            presence.user_role = user.role
            presence.last_seen_at = now
        db.commit()


def _tenant_user_access_summary(company: Company) -> dict:
    engine = create_engine(company.database_url, pool_pre_ping=True)
    try:
        with engine.connect() as connection:
            row = connection.execute(
                text(
                    """
                    SELECT
                        count(*)::int AS total_users,
                        count(*) FILTER (WHERE active = true)::int AS active_users,
                        count(*) FILTER (
                            WHERE active = true
                              AND coalesce(must_change_password, false) = true
                        )::int AS pending_first_access_users,
                        count(*) FILTER (
                            WHERE active = true
                              AND coalesce(must_change_password, false) = false
                        )::int AS changed_password_users,
                        min(created_at) AS first_user_created_at,
                        max(password_changed_at) AS last_password_changed_at
                    FROM users
                    """
                )
            ).mappings().first()
        return dict(row or {})
    except Exception as exc:
        return {
            "total_users": 0,
            "active_users": 0,
            "pending_first_access_users": 0,
            "changed_password_users": 0,
            "first_user_created_at": None,
            "last_password_changed_at": None,
            "access_error": str(exc),
        }
    finally:
        engine.dispose()


def list_master_access_status() -> dict:
    now = datetime.now(UTC)
    online_since = now - ONLINE_WINDOW
    with MasterSessionLocal() as db:
        companies = list(db.scalars(select(Company).order_by(Company.name)).all())
        online_rows = list(
            db.scalars(
                select(CompanyPresence).where(
                    CompanyPresence.last_seen_at >= online_since
                )
            ).all()
        )
        online_by_company: dict[str, list[CompanyPresence]] = {}
        for row in online_rows:
            online_by_company.setdefault(row.company_code, []).append(row)

        items = []
        for company in companies:
            code = normalize_company_code(company.code)
            users_online = online_by_company.get(code, [])
            access_summary = _tenant_user_access_summary(company)
            active_users = int(access_summary.get("active_users") or 0)
            pending_first_access = int(
                access_summary.get("pending_first_access_users") or 0
            )
            changed_password = int(access_summary.get("changed_password_users") or 0)
            first_access_completed = active_users > 0 and changed_password > 0
            items.append(
                {
                    "company_id": company.id,
                    "company_code": code,
                    "company_name": company.name,
                    "plan": company.plan,
                    "status": company.status,
                    "online": bool(users_online),
                    "online_users": len(users_online),
                    "last_seen_at": max(
                        (row.last_seen_at for row in users_online),
                        default=None,
                    ),
                    "active_users": active_users,
                    "total_users": int(access_summary.get("total_users") or 0),
                    "pending_first_access_users": pending_first_access,
                    "changed_password_users": changed_password,
                    "first_access_completed": first_access_completed,
                    "last_password_changed_at": access_summary.get(
                        "last_password_changed_at"
                    ),
                    "access_error": access_summary.get("access_error"),
                    "users_online_details": [
                        {
                            "user_id": row.user_id,
                            "name": row.user_name,
                            "email": row.user_email,
                            "role": row.user_role,
                            "client_type": row.client_type,
                            "last_seen_at": row.last_seen_at,
                        }
                        for row in sorted(
                            users_online,
                            key=lambda item: item.last_seen_at,
                            reverse=True,
                        )
                    ],
                }
            )

        return {
            "generated_at": now,
            "online_window_seconds": int(ONLINE_WINDOW.total_seconds()),
            "total_companies": len(items),
            "online_companies": sum(1 for item in items if item["online"]),
            "online_users": sum(int(item["online_users"]) for item in items),
            "first_access_completed_companies": sum(
                1 for item in items if item["first_access_completed"]
            ),
            "pending_first_access_companies": sum(
                1
                for item in items
                if int(item["active_users"]) > 0
                and int(item["pending_first_access_users"]) > 0
            ),
            "items": items,
        }
