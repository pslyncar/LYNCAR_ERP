from app.modules.pedeon.application.public_url import public_store_path, public_store_url


def test_store_url_uses_company_subdomain_and_fixed_cardapio_path():
    assert public_store_url("drikapadaria", "https://pedeon.lyncar.com.br") == (
        "https://drikapadaria.lyncar.com.br/cardapio"
    )


def test_store_url_keeps_local_legacy_base_compatible():
    assert public_store_url("drikapadaria", "http://127.0.0.1:5001") == (
        "http://127.0.0.1:5001/drikapadaria"
    )


def test_google_return_path_depends_on_public_host():
    assert public_store_path("https://drikapadaria.lyncar.com.br", "drikapadaria") == "/cardapio"
    assert public_store_path("http://127.0.0.1:5001", "drikapadaria") == "/drikapadaria"
