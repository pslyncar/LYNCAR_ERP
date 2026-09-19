from app.ai.fiscal_explanations import explanation_for
from app.ai.intent_router import classify, fast_reply
from app.ai.knowledge import format_knowledge, retrieve_knowledge


def test_greeting_is_instant_and_personalized():
    assert classify("Oi") .name == "greeting"
    reply = fast_reply("Olá", user_name="Maria Silva", screen="Financeiro")
    assert reply is not None
    assert "Maria" in reply
    assert "Financeiro" in reply


def test_data_and_fiscal_questions_are_not_hidden_as_greetings():
    assert classify("Tenho clientes com crediário aberto?").name == "authorized_data"
    assert classify("Explique a rejeição 518 da NF-e").name == "fiscal"


def test_knowledge_contains_official_sources_without_tenant_data():
    notes = retrieve_knowledge("qual NCM devo revisar no produto")
    text = format_knowledge(notes)
    assert "NCM oficial" in text
    assert "gov.br" in text


def test_common_fiscal_rejections_have_safe_explanations():
    assert "CFOP" in (explanation_for("518") or "")
    assert explanation_for("999") is None
