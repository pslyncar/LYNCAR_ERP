from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.master_database import MasterBase


class PdvAppVersion(MasterBase):
    __tablename__ = "pdv_app_versions"

    id: Mapped[int] = mapped_column(primary_key=True)
    version: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    build_number: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    platform: Mapped[str] = mapped_column(String(30), nullable=False, default="windows")
    channel: Mapped[str] = mapped_column(String(30), nullable=False, default="stable")
    file_url: Mapped[str] = mapped_column(Text, nullable=False)
    file_sha256: Mapped[str] = mapped_column(String(128), nullable=False)
    file_size: Mapped[int | None] = mapped_column(Integer)
    required: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    min_supported_version: Mapped[str | None] = mapped_column(String(40))
    release_notes: Mapped[str | None] = mapped_column(Text)
    created_by: Mapped[str | None] = mapped_column(String(120))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    released_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    rollouts: Mapped[list["PdvAppVersionRollout"]] = relationship(
        back_populates="version",
        cascade="all, delete-orphan",
    )


class PdvAppVersionRollout(MasterBase):
    __tablename__ = "pdv_app_version_rollouts"

    id: Mapped[int] = mapped_column(primary_key=True)
    version_id: Mapped[int] = mapped_column(
        ForeignKey("pdv_app_versions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    company_id: Mapped[int | None] = mapped_column(ForeignKey("companies.id"))
    company_code: Mapped[str | None] = mapped_column(String(64), index=True)
    plan: Mapped[str | None] = mapped_column(String(40), index=True)
    channel: Mapped[str] = mapped_column(String(30), nullable=False, default="stable")
    percent: Mapped[int | None] = mapped_column(Integer)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    mandatory: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    version: Mapped[PdvAppVersion] = relationship(back_populates="rollouts")


class PdvTerminalUpdateLog(MasterBase):
    __tablename__ = "pdv_terminal_update_logs"
    __table_args__ = (
        UniqueConstraint(
            "company_code",
            "terminal_id",
            "target_version",
            "status",
            name="uq_pdv_update_log_terminal_version_status",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    company_id: Mapped[int | None] = mapped_column(ForeignKey("companies.id"))
    company_code: Mapped[str | None] = mapped_column(String(64), index=True)
    terminal_id: Mapped[str | None] = mapped_column(String(180), index=True)
    current_version: Mapped[str | None] = mapped_column(String(40))
    target_version: Mapped[str | None] = mapped_column(String(40), index=True)
    status: Mapped[str] = mapped_column(String(40), nullable=False, default="available")
    error_message: Mapped[str | None] = mapped_column(Text)
    checked_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    downloaded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    installed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
