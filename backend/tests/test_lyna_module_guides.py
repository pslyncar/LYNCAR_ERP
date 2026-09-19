from app.ai.module_guides import guide_for


def test_module_guide_answers_common_system_questions_without_model():
    guide = guide_for("como funciona o crediário aberto?", "Financeiro")
    assert guide is not None
    assert guide.name == "Financeiro"


def test_module_guide_covers_fiscal_area():
    guide = guide_for("onde vejo uma rejeição da NFe?")
    assert guide is not None
    assert guide.name == "Notas fiscais"
