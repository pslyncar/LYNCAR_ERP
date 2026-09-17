from app.api import dependencies
from app.api.routes import xml_inbox


def test_xml_inbox_uses_the_cookie_aware_session_dependency():
    """The receiving screen must work after the browser-session migration."""

    assert xml_inbox.bearer_scheme is dependencies.bearer_scheme
