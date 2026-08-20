from app.core.database import Base, engine

# Import models so SQLAlchemy registers the tables.
from app.models import access_control  # noqa: F401
from app.models import client  # noqa: F401
from app.models import equipment  # noqa: F401
from app.models import equipment_status  # noqa: F401
from app.models import monitoring  # noqa: F401
from app.models import product  # noqa: F401
from app.models import pdv_sync_event  # noqa: F401
from app.models import sale  # noqa: F401
from app.models import service_order  # noqa: F401
from app.models import ticket  # noqa: F401
from app.models import user  # noqa: F401


def main() -> None:
    Base.metadata.create_all(bind=engine)
    print("Tabelas criadas com sucesso.")


if __name__ == "__main__":
    main()
