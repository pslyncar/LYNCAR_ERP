from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class LynaLearningEvent(Base):
    """Sanitized candidate captured for controlled Lyna improvement.

    This table lives in each company's database. It is intentionally not a
    global knowledge table: raw tenant context can never be shared by the
    learning pipeline. Promotion to reusable knowledge requires review.
    """

    __tablename__ = "lyna_learning_events"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), index=True)
    question: Mapped[str] = mapped_column(Text, nullable=False)
    answer: Mapped[str] = mapped_column(Text, nullable=False)
    screen: Mapped[Optional[str]] = mapped_column(String(120))
    module: Mapped[Optional[str]] = mapped_column(String(80))
    source: Mapped[str] = mapped_column(String(40), nullable=False, default="ollama")
    model: Mapped[Optional[str]] = mapped_column(String(100))
    risk_level: Mapped[str] = mapped_column(String(20), nullable=False, default="normal")
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="pending_review", index=True)
    reviewer_notes: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    reviewed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
