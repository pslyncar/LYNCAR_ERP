# 2026-06-27 - PDV offline e NFC-e contingencia

> **Historico/superado em parte:** a retransmissao fiscal nao depende mais da tela aberta. A arquitetura vigente esta em [[2026-08-21 - Fila fiscal transacional e evolucao para broker]].

## Resumo

Foi concluida a entrega do PDV com memoria local/offline e do motor fiscal NFC-e com contingencia offline `tpEmis=9`.

## PDV

Implementado:

- recuperacao de caixa aberto apos queda de energia ou fechamento inesperado;
- persistencia local de carrinho, operador, cliente, CPF, forma de pagamento, descontos, observacoes, totais e movimentos;
- cache local de produtos/precos;
- fila local para venda nao fiscal offline;
- sincronizacao da fila quando a API voltar;
- ajustes visuais, textos e logo do PDV Windows/site.

## Fiscal NFC-e

Implementado:

- NFC-e normal modelo 65 continua funcionando;
- contingencia offline NFC-e com `tpEmis=9`;
- XML assinado em contingencia;
- DANFE NFC-e para autorizada e contingencia;
- endpoint `POST /fiscal/documents/{document_id}/transmit-contingency`;
- acao manual em Notas fiscais para transmitir contingencia;
- tentativa automatica pela tela Notas fiscais ao abrir e a cada 2 minutos.

Observacao: o automatico atual depende da tela Notas fiscais estar aberta/acessada. Ainda nao existe worker/cron de backend rodando sozinho 24h.

## QR Code v3

A contingencia NFC-e foi ajustada para QR Code versao 3 conforme NT 2025.001.

Ponto critico: em contingencia v3, a autenticidade usa assinatura digital RSA-SHA1 com o certificado A1 sobre os campos do QR Code. Nao usar CSC/hash nessa modalidade.

## Testes SEFAZ homologacao

Empresa Drika:

- NFC-e normal autorizada:
  - documento local: 56
  - numero: 31
  - cStat: 100
  - chave: `35260663816719000115650010000000311038567893`

- NFC-e contingencia transmitida depois e autorizada:
  - documento local: 71
  - numero: 46
  - cStat: 100
  - chave: `35260663816719000115650010000000469022161050`

## Arquivos principais alterados

- `backend/app/services/nfce_sp.py`
- `backend/app/services/fiscal_pdf.py`
- `backend/app/api/routes/fiscal.py`
- `admin_app/admin_flutter/lib/screens/pdv_screen.dart`
- `admin_app/admin_flutter/lib/screens/fiscal_documents_screen.dart`
- `admin_app/admin_flutter/lib/services/api_client.dart`

## Entrega

Pacote para servidor:

- `E:\ENTREGAS_CLIENTES\ATUALIZACAO_SERVIDOR_2026-06-27_PDV_OFFLINE_FISCAL_CONTINGENCIA`

Instalador Windows do PDV:

- `E:\ENTREGAS_CLIENTES\PDV_WINDOWS_INSTALADOR\PDV_Lyncar_Setup_1.0.5.exe`
