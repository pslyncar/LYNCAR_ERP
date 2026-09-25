from app.core.permissions import PERMISSIONS, ROLE_PERMISSION_CODES


def test_stock_entry_reverse_is_a_separate_explicit_permission() -> None:
    code = "stock:entries:reverse"
    definitions = {permission.code: permission for permission in PERMISSIONS}

    assert definitions[code].label == "Estornar entradas confirmadas"
    assert code in ROLE_PERMISSION_CODES["admin"]
    assert code not in ROLE_PERMISSION_CODES["seller"]
    assert code not in ROLE_PERMISSION_CODES["cashier"]
