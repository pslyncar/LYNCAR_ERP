from datetime import datetime

from sqlalchemy import DateTime, Index, String, event, func
from sqlalchemy.engine import Connection
from sqlalchemy.orm import Mapped, Mapper, mapped_column

from app.core.database import Base
from app.models.client import Client
from app.models.product import Product


class PdvSyncEvent(Base):
    __tablename__ = "pdv_sync_events"
    __table_args__ = (
        Index("ix_pdv_sync_events_entity", "entity_type", "entity_id", "id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    entity_type: Mapped[str] = mapped_column(String(20), nullable=False)
    entity_id: Mapped[int] = mapped_column(nullable=False)
    operation: Mapped[str] = mapped_column(String(20), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )


def _record_event(
    connection: Connection,
    *,
    entity_type: str,
    entity_id: int,
    operation: str,
) -> None:
    connection.execute(
        PdvSyncEvent.__table__.insert().values(
            entity_type=entity_type,
            entity_id=entity_id,
            operation=operation,
        )
    )


def _register_entity_events(model: type, entity_type: str) -> None:
    @event.listens_for(model, "after_insert")
    def after_insert(
        mapper: Mapper,
        connection: Connection,
        target: Product | Client,
    ) -> None:
        del mapper
        _record_event(
            connection,
            entity_type=entity_type,
            entity_id=target.id,
            operation="upsert",
        )

    @event.listens_for(model, "after_update")
    def after_update(
        mapper: Mapper,
        connection: Connection,
        target: Product | Client,
    ) -> None:
        del mapper
        _record_event(
            connection,
            entity_type=entity_type,
            entity_id=target.id,
            operation="upsert",
        )

    @event.listens_for(model, "after_delete")
    def after_delete(
        mapper: Mapper,
        connection: Connection,
        target: Product | Client,
    ) -> None:
        del mapper
        _record_event(
            connection,
            entity_type=entity_type,
            entity_id=target.id,
            operation="delete",
        )


_register_entity_events(Product, "product")
_register_entity_events(Client, "client")
