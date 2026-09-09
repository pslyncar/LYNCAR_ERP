from starlette.requests import Request

from app.services.web_sessions import (
    request_origin,
    session_cookie_name,
)


def _request(*, origin: str | None) -> Request:
    headers = [] if origin is None else [(b"origin", origin.encode())]
    scope = {
        "type": "http",
        "method": "GET",
        "path": "/auth/web/session",
        "raw_path": b"/auth/web/session",
        "scheme": "https",
        "server": ("api.lyncar.com.br", 443),
        "client": ("127.0.0.1", 1234),
        "root_path": "",
        "query_string": b"",
        "headers": headers,
    }
    return Request(scope)


def test_web_cookie_names_are_partitioned_by_frontend_origin():
    master = _request(origin="https://erp.lyncar.com.br")
    client = _request(origin="https://padariadrika.lyncar.com.br")

    assert request_origin(master) == "https://erp.lyncar.com.br"
    assert request_origin(client) == "https://padariadrika.lyncar.com.br"
    assert session_cookie_name(master) != session_cookie_name(client)
    assert session_cookie_name(master) == session_cookie_name(master)


def test_local_origins_keep_their_port_in_the_partition_key():
    first = _request(origin="http://127.0.0.1:5000")
    second = _request(origin="http://127.0.0.1:5001")

    assert session_cookie_name(first) != session_cookie_name(second)
