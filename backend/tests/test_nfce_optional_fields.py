from app.services.nfce_sp import _optional_cest


def test_optional_cest_accepts_only_seven_digits() -> None:
    assert _optional_cest("17.010.00") == "1701000"
    assert _optional_cest("1") is None
    assert _optional_cest("") is None
    assert _optional_cest(None) is None
