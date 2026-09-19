# Biblioteca e NLU da Lyna

## Princípios

- Fontes oficiais e versionadas vencem material educativo ou dataset conversacional.
- NCM, CFOP, CEST, CST, IBS/CBS e regras de emissão continuam sob responsabilidade do motor fiscal determinístico.
- Datasets conversacionais servem para reconhecer linguagem, informalidade, erros de digitação e atos de fala; não definem tributação nem dão acesso a dados.
- Conteúdo de clientes é isolado por empresa e permissão. Aprendizado fica pendente de revisão e não grava instruções do usuário automaticamente.

## Camadas

1. `knowledge_sources.py` mantém o catálogo de fontes, autoridade, categoria, formato e frequência de atualização.
2. A base interna fornece explicações curadas com URL e contexto.
3. O NLU local reconhece variações PT-BR e múltiplos atos de fala antes do Qwen.
4. Consultas de ERP passam pelo gateway autorizado; dados operacionais não entram no catálogo público.
5. A pesquisa externa é sob demanda e filtrada para fontes seguras.

## Datasets conversacionais

MASSIVE, SID, TalkEx, Brazilian Customer Service Conversations e Atos de Fala PT-BR estão catalogados como fontes de NLU. Eles não são baixados automaticamente para o ERP neste momento: isso evita aumentar o servidor sem necessidade e exige conferir licença, tamanho e qualidade antes de gerar um classificador. O classificador atual já cobre variações frequentes; uma futura importação deve gerar apenas um artefato pequeno e versionado.
