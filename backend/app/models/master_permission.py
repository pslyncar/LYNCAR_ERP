from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.master_database import MasterBase


class MasterUserPermission(MasterBase):
    __tablename__ = "master_user_permissions"
    __table_args__ = (
        UniqueConstraint("user_id", "permission_code", name="uq_master_user_permission"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("master_users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    permission_code: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    user = relationship("MasterUser", back_populates="permissions")
