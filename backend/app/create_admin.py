import argparse
import secrets
import string

from sqlalchemy import select

from app.core.database import SessionLocal
from app.core.security import hash_password
from app.models import access_control  # noqa: F401
from app.models import client  # noqa: F401
from app.models import equipment  # noqa: F401
from app.models import monitoring  # noqa: F401
from app.models import ticket  # noqa: F401
from app.models.user import User


def generate_password(length: int = 18) -> str:
    alphabet = string.ascii_letters + string.digits + "!@#$%*-_"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def main() -> None:
    parser = argparse.ArgumentParser(description="Cria usuario administrador inicial.")
    parser.add_argument("--name", default="Administrador PapezzoSync")
    parser.add_argument("--email", default="admin@papezzosync.com.br")
    parser.add_argument("--password", default=None)
    args = parser.parse_args()

    password = args.password or generate_password()
    email = args.email.lower()

    with SessionLocal() as db:
        existing_user = db.scalar(select(User).where(User.email == email))
        if existing_user is not None:
            print(f"Usuario admin ja existe: {email}")
            return

        user = User(
            name=args.name,
            email=email,
            password_hash=hash_password(password),
            role="admin",
            active=True,
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    print("Admin criado com sucesso.")
    print(f"Email: {email}")
    print(f"Senha temporaria: {password}")
    print("Guarde esta senha. Em producao, troque por uma senha exclusiva e forte.")


if __name__ == "__main__":
    main()
