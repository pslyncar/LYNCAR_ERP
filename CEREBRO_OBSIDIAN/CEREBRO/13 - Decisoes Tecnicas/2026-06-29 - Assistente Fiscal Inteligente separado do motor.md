# 2026-06-29 - Assistente Fiscal Inteligente separado do motor

## Decisao

Foi criado um modulo separado chamado **Assistente Fiscal Inteligente**.

Ele nao altera o Motor Fiscal atual, nao altera emissao de NF-e/NFC-e, nao assina XML, nao transmite para SEFAZ e nao substitui regras fiscais ja funcionando.

O objetivo e apenas sugerir, validar e ajudar o usuario antes da emissao ou durante o cadastro do produto.

## Funcionamento

O assistente cria uma base propria `fiscal_suggestions`, alimentada por:

- produtos salvos com dados fiscais;
- itens de entrada/XML confirmados.

Ele guarda:

- descricao normalizada;
- codigo de barras;
- unidade;
- NCM;
- CEST;
- CFOP;
- origem;
- CST/CSOSN;
- aliquotas antigas;
- IBS/CBS;
- IS;
- quantidade de usos;
- data da ultima utilizacao.

## Uso na tela

No cadastro/edicao de produto, a secao Fiscal atual ganhou o painel **Assistente Fiscal Inteligente**.

O usuario clica em consultar. O sistema mostra sugestoes e alertas, mas nao sobrescreve nada automaticamente. Para usar, o usuario precisa clicar em **Aplicar sugestao** e depois salvar o produto.

## Aviso legal obrigatorio

“As informações fiscais são sugestões automáticas do sistema e devem ser conferidas pelo responsável fiscal ou contador da empresa.”

## Separacao do motor fiscal

Arquivos de emissao/autorizacao fiscal nao foram alterados:

- `nfe_sp.py`
- `nfce_sp.py`
- assinatura XML
- transmissao SEFAZ
- cancelamento

Essa separacao deve ser preservada em proximas evolucoes.

## Entrega

`E:\ENTREGAS_CLIENTES\ATUALIZACAO_2026-06-29_ASSISTENTE_FISCAL_INTELIGENTE`

Zip:

`E:\ENTREGAS_CLIENTES\ATUALIZACAO_2026-06-29_ASSISTENTE_FISCAL_INTELIGENTE.zip`

## Validacao

- Python compileall: OK
- dart format: OK
- flutter analyze: OK
- flutter build web --release: OK
