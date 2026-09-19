"""Gera variantes WebP para imagens públicas já existentes.

O arquivo original nunca é alterado. O comando é idempotente e pode ser
reexecutado após uma restauração de uploads.
"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.services.uploads import ALLOWED_IMAGE_TYPES, UPLOAD_ROOT, _write_image_variants


def main() -> None:
    generated = 0
    skipped = 0
    for path in sorted(UPLOAD_ROOT.rglob("*")):
        if not path.is_file() or path.stem.endswith(("__card", "__detail")):
            continue
        if path.suffix.lower() not in set(ALLOWED_IMAGE_TYPES.values()):
            continue
        card = path.with_name(f"{path.stem}__card.webp")
        detail = path.with_name(f"{path.stem}__detail.webp")
        if card.is_file() and detail.is_file():
            skipped += 1
            continue
        _write_image_variants(path)
        if card.is_file() and detail.is_file():
            generated += 1
    print(f"generated={generated} skipped={skipped}")


if __name__ == "__main__":
    main()
