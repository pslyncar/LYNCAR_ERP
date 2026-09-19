from app.ai.web_research import category_for, format_for_prompt, search, should_search


def test_only_current_lyncar_question_triggers_search():
    assert should_search("Pesquise a regra atual de IBS para NF-e")
    assert not should_search("Quantos clientes estão com crediário aberto?")
    assert not should_search("Me conte uma notícia sobre futebol")


def test_categories_are_narrow():
    assert category_for("Qual a regra vigente da NFSe?") == "nfse"
    assert category_for("Tem novidade oficial da SEFAZ para NF-e?") == "fiscal_updates"
    assert category_for("Pesquise a documentação atual do Debian") == "infrastructure"


def test_search_is_disabled_without_network_configuration():
    result = search("Pesquise a regra atual de IBS para NF-e", enabled=False, base_url=None)
    assert result.status == "unavailable"
    assert "não configurada" in format_for_prompt(result)
