from app.ai.tools import _ncm_query_term


def test_ncm_query_extracts_product_without_packaging_noise():
    assert _ncm_query_term("qual ncm da coca cola 2l original?") == "coca cola"


def test_ncm_query_requires_a_product_description():
    assert _ncm_query_term("qual o ncm?") is None
