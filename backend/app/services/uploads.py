from pathlib import Path
from re import sub
from urllib.parse import unquote, urlparse
from uuid import uuid4

from fastapi import HTTPException, UploadFile, status
from PIL import Image, ImageOps


PROJECT_ROOT = Path(__file__).resolve().parents[3]
UPLOAD_ROOT = PROJECT_ROOT / "uploads"
MAX_IMAGE_BYTES = 5 * 1024 * 1024
IMAGE_VARIANT_WIDTHS = {"card": 560, "detail": 1120}
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


def safe_scope_name(scope: str) -> str:
    return "".join(
        character if character.isalnum() or character in {"-", "_"} else "-"
        for character in scope.lower()
    ).strip("-") or "geral"


def _variant_path(source_path: Path, variant: str) -> Path:
    width = IMAGE_VARIANT_WIDTHS.get(variant)
    if width is None:
        raise ValueError(f"Variante de imagem desconhecida: {variant}")
    return source_path.with_name(f"{source_path.stem}__{variant}.webp")


def _write_image_variants(source_path: Path) -> None:
    """Cria variantes WebP sem substituir o original nem cortar a proporção."""
    try:
        with Image.open(source_path) as source:
            image = ImageOps.exif_transpose(source)
            if image.mode not in {"RGB", "RGBA"}:
                image = image.convert("RGBA" if "A" in image.getbands() else "RGB")
            for variant, max_width in IMAGE_VARIANT_WIDTHS.items():
                target = _variant_path(source_path, variant)
                if max(image.size) > max_width:
                    ratio = max_width / max(image.size)
                    size = (max(1, round(image.width * ratio)), max(1, round(image.height * ratio)))
                    resized = image.resize(size, Image.Resampling.LANCZOS)
                else:
                    resized = image.copy()
                if resized.mode == "RGBA":
                    resized.save(target, "WEBP", quality=84, method=6)
                else:
                    resized.convert("RGB").save(target, "WEBP", quality=84, method=6)
                resized.close()
    except Exception:
        # O original continua válido mesmo se um arquivo antigo estiver corrompido
        # ou em formato que o Pillow não consiga decodificar.
        return


def image_variant_url(url: str | None, variant: str) -> str | None:
    """Retorna URL da variante local; preserva URLs externas e faz fallback."""
    if not url or variant not in IMAGE_VARIANT_WIDTHS:
        return url
    parsed = urlparse(str(url))
    public_path = unquote(parsed.path or str(url))
    prefix = "/public/"
    if not public_path.startswith(prefix):
        return url
    relative = public_path[len(prefix) :]
    source_path = (UPLOAD_ROOT / relative).resolve()
    upload_root = UPLOAD_ROOT.resolve()
    if upload_root not in source_path.parents or not source_path.is_file():
        return url
    target = _variant_path(source_path, variant)
    if not target.is_file():
        return url
    return f"/public/{target.relative_to(upload_root).as_posix()}"


def delete_public_file_if_safe(url: str | None, expected_scope: str) -> bool:
    if not url:
        return False
    parsed = urlparse(str(url))
    public_path = unquote(parsed.path or str(url))
    prefix = "/public/"
    if not public_path.startswith(prefix):
        return False
    parts = [part for part in public_path[len(prefix) :].split("/") if part]
    if len(parts) != 2:
        return False
    scope, filename = parts
    safe_scope = safe_scope_name(expected_scope)
    if scope != safe_scope or filename in {"", ".", ".."}:
        return False
    target_dir = (UPLOAD_ROOT / safe_scope).resolve()
    target_path = (target_dir / filename).resolve()
    if target_dir not in target_path.parents:
        return False
    if not target_path.is_file():
        return False
    try:
        target_path.unlink()
        for variant in IMAGE_VARIANT_WIDTHS:
            variant_path = _variant_path(target_path, variant)
            if variant_path.is_file():
                variant_path.unlink()
        return True
    except OSError:
        return False


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

    safe_scope = safe_scope_name(scope)
    target_dir = UPLOAD_ROOT / safe_scope
    target_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{uuid4().hex}{extension}"
    target_path = target_dir / filename
    target_path.write_bytes(content)
    _write_image_variants(target_path)
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
    safe_scope = safe_scope_name(scope)
    target_dir = UPLOAD_ROOT / safe_scope
    target_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{uuid4().hex}{extension}"
    target_path = target_dir / filename
    target_path.write_bytes(content)
    return f"/public/{safe_scope}/{filename}"
