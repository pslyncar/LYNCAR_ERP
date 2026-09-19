"""Short explanations for common official NF-e return codes."""

from __future__ import annotations

_EXPLANATIONS = {
    "518": "A SEFAZ rejeitou porque o CFOP informado é de entrada em uma NF-e de saída. Revise a natureza da operação e o CFOP de saída; o motor fiscal deve validar antes do novo envio.",
    "519": "A SEFAZ rejeitou porque o CFOP informado é de saída em uma NF-e de entrada. Revise a finalidade/documento e o CFOP correspondente.",
    "531": "A SEFAZ indicou divergência no total da base de cálculo do ICMS. Confira a soma dos itens e os campos de base, redução, frete, seguro e outras despesas.",
}


def explanation_for(code: str | int | None) -> str | None:
    if code is None:
        return None
    digits = "".join(char for char in str(code) if char.isdigit())
    return _EXPLANATIONS.get(digits)
