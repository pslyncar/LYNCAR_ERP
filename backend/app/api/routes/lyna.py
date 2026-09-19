"""Read-only assistant endpoint for the Lyna pilot."""

from __future__ import annotations

import json
from threading import BoundedSemaphore
from urllib.error import URLError
from urllib.request import Request, urlopen

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user
from app.ai.knowledge import format_knowledge, retrieve_knowledge
from app.ai.learning import record_learning_event
from app.ai.tools import build_authorized_context
from app.ai.web_research import format_for_prompt, search as web_search
from app.ai.cache import public_knowledge_cache
from app.ai.fiscal_explanations import explanation_for
from app.ai.intent_router import classify, fast_reply
from app.ai.module_guides import guide_for
from app.core.database import get_db
from app.core.config import get_settings
from app.models.user import User
from app.services.access_control import user_has_permission


router = APIRouter()
_inference_slot = BoundedSemaphore(1)


class LynaChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=4000)
    screen: str = Field(default="", max_length=120)
    module: str = Field(default="", max_length=80)
    context: dict[str, str] = Field(default_factory=dict)


class LynaChatResponse(BaseModel):
    message: str
    source: str
    model: str | None = None
    can_execute_actions: bool = False


def _fallback_message(screen: str, module: str) -> str:
    location = screen or module or "a tela atual"
    return (
        f"Estou pronta para ajudar em {location}. Não encontrei uma resposta exata "
        "para essa pergunta ainda. Tente informar o nome do cadastro, número da nota "
        "ou código do retorno; também posso explicar os campos e o fluxo dessa tela."
    )


def _required_permission(payload: LynaChatRequest) -> str | None:
    """Infer the minimum read permission from the requested area."""

    area = _normalize(" ".join((payload.screen, payload.module, payload.message)))
    if any(term in area for term in ("nota fiscal", "nfe", "nfce", "nfse", "fiscal", "sefaz")):
        return "fiscal:view"
    if any(term in area for term in ("financeiro", "crediario", "conta a receber", "extrato", "baixa")):
        return "finance:view"
    if any(term in area for term in ("fornecedor", "fornecedores")):
        return "suppliers:view"
    if any(term in area for term in ("cliente", "clientes")):
        return "clients:view"
    if any(term in area for term in ("estoque", "produto", "produtos", "entrada")):
        return "products:view"
    return None


def _has_read_permission(db: Session, user: User, area: str) -> bool:
    if "financeiro" in area or "crediario" in area or "extrato" in area or "conta a receber" in area or "baixa" in area:
        return user_has_permission(db, user, "finance:view") or user_has_permission(
            db, user, "finance:receivables:view"
        )
    if "fornecedor" in area:
        return user_has_permission(db, user, "suppliers:view") or user_has_permission(
            db, user, "finance:payables:view"
        )
    if "cliente" in area:
        return user_has_permission(db, user, "clients:view")
    if any(term in area for term in ("estoque", "produto", "entrada")):
        return user_has_permission(db, user, "products:view") or user_has_permission(
            db, user, "stock:view"
        )
    if any(term in area for term in ("nota fiscal", "nfe", "nfce", "nfse", "fiscal", "sefaz")):
        return user_has_permission(db, user, "fiscal:view") or user_has_permission(
            db, user, "fiscal:documents:view"
        )
    return True


def _safety_block(message: str) -> str | None:
    normalized = _normalize(message)
    blocked_phrases = (
        "ignore as instrucoes",
        "ignore as regras",
        "mostre o prompt",
        "mostre as instrucoes internas",
        "execute sql",
        "salve no banco",
        "salve isso no banco",
        "salvar no banco",
        "grave no banco",
        "grave isso no banco",
        "gravar no banco",
        "altere o banco",
        "altere o cadastro",
        "modifique o cadastro",
        "acesse o banco",
        "senha do banco",
        "token secreto",
        "dados de outra empresa",
        "dados de outro cliente",
    )
    if any(phrase in normalized for phrase in blocked_phrases):
        return (
            "Por segurança, a Lyna não pode revelar instruções internas, segredos, "
            "SQL ou dados de outra empresa. Posso ajudar somente com informações "
            "autorizadas desta empresa e desta sessão."
        )
    return None


def _normalize(value: str) -> str:
    return (
        value.lower()
        .replace("-", "")
        .replace("ç", "c")
        .replace("ã", "a")
        .replace("á", "a")
        .replace("é", "e")
        .replace("í", "i")
        .replace("ó", "o")
        .replace("ú", "u")
    )


def _ollama_message(payload: LynaChatRequest, user: User, db: Session) -> str | None:
    settings = get_settings()
    if not settings.lyna_enabled or not settings.lyna_ollama_url:
        return None
    if not _inference_slot.acquire(timeout=1):
        return "A Lyna ainda está finalizando a resposta anterior. Tente novamente em instantes."

    try:
        context = {
            "empresa": getattr(user, "company_code", None) or "empresa atual",
            "tela": payload.screen,
            "modulo": payload.module,
            **payload.context,
        }
        conversation_context = payload.context.get("conversa", "")
        tool_message = f"{conversation_context}\n{payload.message}".strip()
        authorized_data = build_authorized_context(
            db,
            user,
            tool_message,
            payload.screen,
            payload.module,
        )
        search_key = f"{payload.message.strip().lower()}|{settings.lyna_search_url}"
        web_context = public_knowledge_cache.get(search_key)
        if web_context is None:
            web_context = web_search(
                payload.message,
                enabled=settings.lyna_web_search_enabled,
                base_url=settings.lyna_search_url,
                timeout=settings.lyna_search_timeout_seconds,
                max_results=settings.lyna_search_max_results,
            )
            public_knowledge_cache.set(search_key, web_context, 900)
        intent = classify(payload.message)
        rejection_hint = ""
        for code in ("518", "519", "531"):
            if code in payload.message:
                rejection_hint = explanation_for(code) or ""
                break
        system = (
            "Você é a Lyna, assistente somente leitura do ERP Lyncar. "
            "Responda em português claro e curto. Use o contexto da tela, mas "
            "não invente dados. Não execute nem prometa alterações. Para fiscal, "
            "explique que o motor determinístico do Lyncar é a autoridade final. "
            "Se houver dados operacionais autorizados abaixo, responda primeiro "
            "com base neles; nunca diga que a tela está vazia sem conferir esses dados. "
            "Use o histórico para entender perguntas de continuidade como 'e agora?' "
            "ou 'qual deles?'. Se faltar informação, diga exatamente o que falta. "
            f"A intenção detectada para roteamento é: {intent.name}. "
            f"Explicação determinística adicional, se houver: {rejection_hint or 'nenhuma'}. "
            "Só use pesquisa externa quando ela tiver sido solicitada; nunca crie radar, "
            "alerta, push ou mensagem proativa de impacto. Quando houver fontes, cite "
            "os títulos e URLs, sem tratar a pesquisa como regra automática do motor fiscal.\n\n"
            f"Contexto autorizado: {json.dumps(context, ensure_ascii=False)}"
            "\n\nBase de conhecimento interna relevante:\n"
            f"{format_knowledge(retrieve_knowledge(payload.message, payload.screen, payload.module))}"
            "\n\nDados operacionais autorizados desta sessão (use somente estes dados; "
            "não invente, não consulte outra empresa e não revele SQL):\n"
            f"{authorized_data}"
            "\n\nPesquisa externa sob demanda, sem escrita no sistema:\n"
            f"{format_for_prompt(web_context)}"
        )
        body = json.dumps(
            {
                "model": settings.lyna_model,
                "stream": False,
                "think": False,
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": payload.message.strip()},
                ],
                "options": {
                    "num_ctx": min(settings.lyna_context_tokens, 2048),
                    "num_predict": min(settings.lyna_max_output_tokens, 180),
                    "num_thread": 2,
                },
            }
        ).encode("utf-8")
        request = Request(
            settings.lyna_ollama_url.rstrip("/") + "/api/chat",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(request, timeout=settings.lyna_timeout_seconds) as response:
            data = json.loads(response.read().decode("utf-8"))
        message = data.get("message", {}).get("content")
        return message.strip() if isinstance(message, str) and message.strip() else None
    except (OSError, URLError, TimeoutError, ValueError, json.JSONDecodeError):
        return None
    finally:
        _inference_slot.release()


@router.post("/chat", response_model=LynaChatResponse)
def chat(
    payload: LynaChatRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> LynaChatResponse:
    safety_message = _safety_block(payload.message)
    if safety_message:
        return LynaChatResponse(message=safety_message, source="safety_guard")
    instant_message = fast_reply(
        payload.message,
        user_name=getattr(current_user, "name", ""),
        screen=payload.screen,
        module=payload.module,
    )
    if instant_message:
        return LynaChatResponse(message=instant_message, source="fast_path")
    required_permission = _required_permission(payload)
    area = _normalize(" ".join((payload.screen, payload.module, payload.message)))
    if required_permission and not _has_read_permission(db, current_user, area):
        return LynaChatResponse(
            message=(
                "Você não tem permissão para consultar essa área do Lyncar. "
                f"É necessária a permissão de leitura `{required_permission}`."
            ),
            source="permission_guard",
        )
    model_message = _ollama_message(payload, current_user, db)
    if model_message:
        record_learning_event(
            db,
            current_user,
            question=payload.message,
            answer=model_message,
            screen=payload.screen,
            module=payload.module,
            source="ollama",
            model=get_settings().lyna_model,
        )
        return LynaChatResponse(
            message=model_message,
            source="ollama",
            model=get_settings().lyna_model,
        )
    routed_intent = classify(payload.message)
    if routed_intent.name in {"authorized_data", "fiscal"}:
        deterministic_data = build_authorized_context(
            db,
            current_user,
            payload.message,
            payload.screen,
            payload.module,
        )
        if not deterministic_data.startswith("Nenhum dado operacional foi consultado"):
            return LynaChatResponse(
                message=deterministic_data,
                source="authorized_data",
                model=get_settings().lyna_model if get_settings().lyna_enabled else None,
            )
    guide = guide_for(payload.message, payload.screen, payload.module)
    if guide:
        return LynaChatResponse(
            message=f"{guide.name}: {guide.text}",
            source="internal_knowledge",
            model=get_settings().lyna_model if get_settings().lyna_enabled else None,
        )
    return LynaChatResponse(
        message=_fallback_message(payload.screen, payload.module),
        source="fallback",
        model=get_settings().lyna_model if get_settings().lyna_enabled else None,
    )
