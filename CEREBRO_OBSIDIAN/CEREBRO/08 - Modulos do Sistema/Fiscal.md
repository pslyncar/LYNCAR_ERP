# Fiscal

Modulo responsavel por documentos fiscais, configuracao fiscal da empresa emissora e preparacao para NFC-e/NF-e.

## Escopo

- Configuracao fiscal por empresa/tenant.
- Certificado Digital A1 por empresa emissora.
- NFC-e para venda ao consumidor.
- NF-e para vendas e operacoes que exigirem modelo 55.
- XML gerado, XML assinado e XML autorizado.
- Chave de acesso, protocolo e status de autorizacao SEFAZ.
- DANFE NFC-e/NF-e.
- Envio por e-mail e WhatsApp.
- Consulta e download de XML.
- Regras tributarias por produto, incluindo Reforma Tributaria IBS/CBS.

## Regras principais

- O SAT nao e o caminho principal para novos clientes.
- CPF do consumidor no PDV e opcional.
- Ausencia de CPF nao bloqueia NFC-e.
- O certificado usado e sempre o da empresa emissora.
- O consumidor nao precisa certificado.
- Documento fiscal e venda sao registros separados.
- Venda pode existir antes da emissao fiscal, mas o status fiscal deve mostrar claramente se esta pendente, autorizado, rejeitado, cancelado ou inutilizado.
- A habilitacao geral da NFC-e e o uso fiscal no PDV sao controles separados.
- Com `Fiscal no PDV` desligado, o caixa continua vendendo, recebendo e baixando estoque normalmente, sem solicitar CPF/CNPJ e sem emitir NFC-e automaticamente.
- Nesse modo, a venda gera um cupom comercial nao fiscal para o cliente, sem chave, protocolo ou autorizacao SEFAZ.
- O controle `Fiscal no PDV` inicia desligado em instalacoes atualizadas e so pode ser ligado quando a NFC-e geral estiver habilitada.

## Estado atual

O sistema possui estrutura de configuracao, documentos fiscais, permissoes e cadastro de Certificado Digital A1 criptografado por tenant. O motor atual gera, assina e envia NFC-e modelo 65 e NF-e modelo 55 para homologacao em SP, com XML assinado, chave, protocolo e status de autorizacao retornados pela SEFAZ.

No app administrativo Flutter, `Configuracoes > Fiscal` guarda somente certificado A1, CSC/ID, series, numeracao e cadastro tributario. A operacao diaria fica na tela propria `Notas fiscais`, no menu lateral, condicionada a permissao `fiscal:documents:view`.

A tela `Notas fiscais` possui resumo por status, pesquisa, filtros, historico, detalhes, preparacao/emissao de NFC-e por venda, preparacao/emissao de NF-e por venda, impressao de DANFE e cancelamento real por evento SEFAZ. Cancelamento nunca deve ser simulado alterando apenas status local.

## Motor SEFAZ implementado em homologacao

- NFC-e modelo 65: implementada para SP, com assinatura A1, QR Code/suplemento e autorizacao real pela SEFAZ.
- NF-e modelo 55: implementada para SP, com assinatura A1 e autorizacao real pela SEFAZ.
- Cancelamento: implementado por evento `tpEvento=110111` em `NFeRecepcaoEvento4`; o documento so muda para `cancelled` quando a SEFAZ aceita o evento, por exemplo `cStat=135` ou `cStat=155`.
- Rejeicao de cancelamento deve manter o status fiscal original. Exemplo validado em homologacao: NFC-e antiga rejeitada com `cStat=501` por prazo superior ao permitido e continuou autorizada.
- DANFE NF-e: gerado em PDF A4 a partir do XML/protocolo autorizado.
- DANFE NFC-e: gerado em PDF 80 mm com QR Code.
- Documento cancelado gera impressao com marca d'agua de cancelamento.
- Escopo atual do motor real: SEFAZ-SP. Outros estados exigem URLs/regras estaduais antes de liberar producao.

## Validacao real em homologacao

- NF-e 55 homologacao autorizada: venda `V35`, documento fiscal `30`, numero `1`, chave `35260663816719000115550010000000011054393258`, protocolo `135260005946781`, `cStat=100`.
- Cancelamento real da NF-e aceito: protocolo `135260005946817`, `cStat=135`, mensagem `Evento registrado e vinculado a NF-e`.
- NFC-e homologacao fresca autorizada e cancelada: venda `V31`, documento fiscal `31`, numero `14`, cancelamento aceito com `cStat=135`.
- Tentativa de cancelar NFC-e antiga validou regra de prazo: SEFAZ retornou `cStat=501`; o sistema nao alterou o documento para cancelado.

A configuracao fiscal possui o campo `pdv_nfce_enabled`. Ele permite manter certificado, CSC, numeracao e estrutura fiscal cadastrados enquanto a emissao automatica do PDV permanece desativada ate a empresa completar os dados obrigatorios de produtos e tributacao.

## Certificado A1

- Upload de `.pfx/.p12` pelo modulo Fiscal.
- Senha obrigatoria no envio.
- Arquivo e senha criptografados no banco separado da empresa.
- API nao expõe arquivo, senha nem chaves internas.
- Entradas por chave NF-e verificam se existe certificado antes de avancar.
- Cadastro de CSC/Token NFC-e e ID do CSC pelo modulo Fiscal.
- O token CSC nao deve voltar para o frontend depois de salvo; a tela mostra apenas se esta cadastrado.
