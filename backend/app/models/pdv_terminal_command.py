from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class PdvTerminalCommand(Base):
    __tablename__ = "pdv_terminal_commands"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    terminal_id: Mapped[int] = mapped_column(
        ForeignKey("pdv_terminals.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    action: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    status: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="pending",
        index=True,
    )
    message: Mapped[str | None] = mapped_column(String(240))
    payload_json: Mapped[str | None] = mapped_column(Text)
    result_message: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
