from pathlib import Path
from re import sub
from uuid import uuid4

from fastapi import HTTPException, UploadFile, status


PROJECT_ROOT = Path(__file__).resolve().parents[3]
UPLOAD_ROOT = PROJECT_ROOT / "uploads"
MAX_IMAGE_BYTES = 5 * 1024 * 1024
ALLOWED_IMAGE_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/gif": ".gif",
}
ALLOWED_DOCUMENT_TYPES = {
    **ALLOWED_IMAGE_TYPES,
    "application/pdf": ".pdf",
    "application/msword": ".doc",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": ".docx",
}


def _safe_extension(filename: str | None) -> str:
    suffix = Path(filename or "").suffix.lower()
    if not suffix:
        return ".bin"
    suffix = sub(r"[^a-z0-9.]", "", suffix)
    if not suffix.startswith("."):
        suffix = f".{suffix}"
    return suffix[:20] or ".bin"


async def save_public_image(file: UploadFile, scope: str, max_bytes: int | None = None) -> str:
    content_type = (file.content_type or "").lower()
    extension = ALLOWED_IMAGE_TYPES.get(content_type)
    if extension is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Envie uma imagem JPG, PNG, WEBP ou GIF.",
        )

    content = await file.read()
    if not content:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Arquivo de imagem vazio.",
        )
    upload_limit = max_bytes or MAX_IMAGE_BYTES
    if len(content) > upload_limit:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"Imagem muito grande. Envie arquivo de ate {upload_limit // 1024 // 1024} MB.",
        )

    safe_scope = "".join(
        character if character.isalnum() or character in {"-", "_"} else "-"
        for character in scope.lower()
    ).strip("-") or "geral"
    target_dir = UPLOAD_ROOT / safe_scope
    target_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{uuid4().hex}{extension}"
    target_path = target_dir / filename
    target_path.write_bytes(content)
    return f"/public/{safe_scope}/{filename}"


async def save_public_file(
    file: UploadFile,
    scope: str,
    *,
    allowed_types: dict[str, str] | None = None,
    max_bytes: int = 15 * 1024 * 1024,
) -> str:
    content_type = (file.content_type or "").lower()
    extension = (
        (allowed_types or ALLOWED_DOCUMENT_TYPES).get(content_type)
        if allowed_types is not None
        else _safe_extension(file.filename)
    )
    if extension is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Tipo de arquivo nao permitido.",
        )
    content = await file.read()
    if not content:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Arquivo vazio.",
        )
    if len(content) > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"Arquivo muito grande. Envie arquivo de ate {max_bytes // 1024 // 1024} MB.",
        )
    safe_scope = "".join(
        character if character.isalnum() or character in {"-", "_"} else "-"
        for character in scope.lower()
    ).strip("-") or "geral"
    target_dir = UPLOAD_ROOT / safe_scope
    target_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{uuid4().hex}{extension}"
    target_path = target_dir / filename
    target_path.write_bytes(content)
    return f"/public/{safe_scope}/{filename}"
