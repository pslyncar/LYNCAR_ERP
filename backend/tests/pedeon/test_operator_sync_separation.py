from types import SimpleNamespace

from app.api.routes.pdv_sync import _is_legacy_pdv_operator


def test_legacy_pdv_feed_excludes_pedeon_identities() -> None:
    assert _is_legacy_pdv_operator(SimpleNamespace(role="operator"))
    assert _is_legacy_pdv_operator(SimpleNamespace(role="fiscal"))
    assert not _is_legacy_pdv_operator(SimpleNamespace(role="waiter"))
    assert not _is_legacy_pdv_operator(SimpleNamespace(role="pedeon_operator"))
