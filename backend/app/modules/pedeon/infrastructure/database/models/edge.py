from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, JSON, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class PedeOnEdgeNode(Base):
    """Identidade persistente do coordenador local de um estabelecimento.

    O Edge reutiliza a autorização operacional existente, mas cada instalação
    é registrada como um dispositivo PedeOn independente na tela administrativa.
    """

    __tablename__ = "pedeon_edge_nodes"
    __table_args__ = (
        UniqueConstraint("node_key", name="uq_pedeon_edge_node_key"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    store_id: Mapped[int] = mapped_column(
        ForeignKey("pedeon_stores.id", ondelete="CASCADE"), nullable=False, index=True
    )
    pdv_terminal_id: Mapped[int] = mapped_column(
        ForeignKey("pdv_terminals.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    node_key: Mapped[str] = mapped_column(String(80), nullable=False)
    device_label: Mapped[str | None] = mapped_column(String(120))
    device_role: Mapped[str] = mapped_column(String(30), nullable=False, default="cashier")
    app_version: Mapped[str | None] = mapped_column(String(40))
    protocol_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="online", index=True)
    active: Mapped[bool] = mapped_column(nullable=False, default=True, index=True)
    cursors: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    capabilities: Mapped[list[str]] = mapped_column(JSON, nullable=False, default=list)
    last_ip: Mapped[str | None] = mapped_column(String(64))
    last_error: Mapped[str | None] = mapped_column(String(1000))
    registered_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), index=True
    )
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=100)
    updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
