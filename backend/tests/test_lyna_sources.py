from app.ai.intent_router import classify, speech_acts
from app.ai.knowledge_sources import official_sources_for, sources_for


def test_catalog_prioritizes_official_fiscal_sources():
    fiscal = official_sources_for("fiscal")
    assert any(source.key == "classif_ncm" for source in fiscal)
    assert any(source.key == "nfe_portal" for source in fiscal)


def test_nlu_handles_informal_pt_br_variants_and_multiple_acts():
    assert classify("eae lyna").name == "greeting"
    assert classify("obg, me ajuda").name in {"thanks", "help"}
    assert "greeting" in speech_acts("Bom dia, pode me ajudar?")
    assert "request" in speech_acts("Bom dia, pode me ajudar?")


def test_open_datasets_are_cataloged_separately_from_authoritative_rules():
    nlu_sources = sources_for("nlu")
    assert nlu_sources
    assert all(source.authority == "open_dataset" for source in nlu_sources)
