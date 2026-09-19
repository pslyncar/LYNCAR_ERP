"""Deterministic intent routing and instant, non-sensitive replies for Lyna."""

from __future__ import annotations

from dataclasses import dataclass
import re
import unicodedata


@dataclass(frozen=True)
class Intent:
    name: str
    confidence: float


def normalize(value: str) -> str:
    value = unicodedata.normalize("NFKD", value.lower())
    value = "".join(char for char in value if not unicodedata.combining(char))
    return re.sub(r"[^a-z0-9]+", " ", value).strip()


def classify(message: str) -> Intent:
    text = normalize(message)
    if not text:
        return Intent("unknown", 0.0)
    greeting_words = {"oi", "ola", "oie", "opa", "eae", "fala", "blz"}
    if re.fullmatch(r"(oi|ola|oie|opa|eae|e ai|fala|bom dia|boa tarde|boa noite|tudo bem|tudo bem com voce|blz)[!.? ]*", text):
        return Intent("greeting", 0.99)
    if text.split() and text.split()[0] in greeting_words and len(text.split()) <= 3:
        return Intent("greeting", 0.96)
    if any(term in text for term in ("obrigado", "obrigada", "obg", "valeu", "vlw", "agradeco")):
        return Intent("thanks", 0.95)
    if any(term in text for term in ("quem e voce", "o que voce faz", "como voce pode ajudar", "o que vc pode fazer", "me ajuda", "pode me ajudar")):
        return Intent("help", 0.95)
    if any(term in text for term in ("onde estou", "qual tela", "que tela estou", "tela atual")):
        return Intent("current_screen", 0.95)
    if any(term in text for term in ("permissao", "acesso", "posso consultar")):
        return Intent("permission", 0.75)
    if any(term in text for term in ("pesquise", "pesquisar", "fonte oficial", "mudou", "vigente", "atual")):
        return Intent("external_research", 0.9)
    if any(term in text for term in ("rejeicao", "rejeitada", "sefaz", "cfop", "cst", "ncm", "ib s", "ibs", "cbs", "nota fiscal")):
        return Intent("fiscal", 0.86)
    if any(term in text for term in ("crediario", "conta a receber", "extrato", "cliente", "fornecedor", "estoque", "produto")):
        return Intent("authorized_data", 0.8)
    return Intent("general_help", 0.45)


def speech_acts(message: str) -> tuple[str, ...]:
    """Recognize conversational acts without replacing ERP intent routing."""
    text = normalize(message)
    acts: list[str] = []
    if any(term in text for term in ("oi", "ola", "bom dia", "boa tarde", "boa noite", "eae")):
        acts.append("greeting")
    if "?" in message or any(term in text for term in ("como", "qual", "onde", "por que", "porque", "tem", "pode")):
        acts.append("question")
    if any(term in text for term in ("por favor", "preciso", "quero", "pode", "me ajuda")):
        acts.append("request")
    if any(term in text for term in ("obrigado", "obrigada", "obg", "valeu")):
        acts.append("thanks")
    return tuple(dict.fromkeys(acts))


def fast_reply(message: str, *, user_name: str, screen: str = "", module: str = "") -> str | None:
    intent = classify(message)
    name = (user_name or "").strip().split(" ")[0] or ""
    location = screen or module or "esta tela"
    greeting_name = f", {name}" if name else ""
    if intent.name == "greeting":
        return f"Olá{greeting_name}! Espero que esteja bem. Estou aqui na {location} para ajudar. O que você precisa?"
    if intent.name == "thanks":
        return f"Por nada{greeting_name}! Se precisar de algo no Lyncar, é só me chamar."
    if intent.name == "help":
        return "Posso explicar a tela atual, consultar dados permitidos da sua empresa, orientar financeiro, estoque e notas fiscais, interpretar retornos da SEFAZ e pesquisar fontes oficiais quando você pedir. Não altero o banco nem consulto outra empresa."
    if intent.name == "current_screen":
        return f"Você está na {location}. Posso explicar os campos, filtros e ações disponíveis nessa tela."
    return None
