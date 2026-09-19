from app.ai.learning import sanitize_learning_text


def test_learning_sanitizer_removes_sensitive_values() -> None:
    value = sanitize_learning_text(
        "CPF 12345678901, e-mail pessoa@example.com, senha=segredo e R$ 123,45"
    )
    assert "12345678901" not in value
    assert "pessoa@example.com" not in value
    assert "segredo" not in value
    assert "123,45" not in value


def test_learning_sanitizer_keeps_general_procedure() -> None:
    value = sanitize_learning_text("Como consultar uma rejeição 518 na tela fiscal?")
    assert "consultar" in value
    assert "tela fiscal" in value
