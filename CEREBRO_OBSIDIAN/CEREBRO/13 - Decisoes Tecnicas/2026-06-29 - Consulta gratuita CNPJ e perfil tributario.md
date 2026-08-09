# 2026-06-29 - Consulta gratuita de CNPJ e perfil tributario

Foi criada uma camada separada para sugerir regime tributario/CRT no cadastro Master de empresas, sem mexer no Motor Fiscal e sem alterar a emissao NF-e/NFC-e.

## Decisao
- Usar modo gratuito no momento.
- Consulta gratuita tenta provedores publicos configurados, por padrao `brasilapi,minhareceita`.
- Se nao retornar Simples/MEI/regime, o sistema nao inventa: marca pendente e exige preenchimento manual.
- Sempre manter aviso de conferencia pelo contador/responsavel fiscal.

## Mapeamento de sugestao
- MEI -> regime `mei`, CRT `4`.
- Simples Nacional -> regime `simples_nacional`, CRT `1`.
- Lucro Presumido/Real devem poder ser informados manualmente e sugerem CRT `3` quando escolhido no cadastro.

## Regra de seguranca
- Atualizacao automatica de CNPJs existentes so preenche `tax_regime` e `crt` se os campos estiverem vazios.
- Dados fiscais ja preenchidos nao devem ser sobrescritos.
- Sincronizacao com o tenant usa COALESCE/NULLIF para preencher apenas fiscal vazio.

## Entrega
E:\ENTREGAS_CLIENTES\ATUALIZACAO_2026-06-29_CNPJ_GRATUITO_REGIME_TRIBUTARIO

## Servidor
Depois de aplicar os arquivos e rodar `python -m app.migrate_master`, executar:

```bash
python scripts/refresh_company_tax_profiles.py
```

Isso consulta os CNPJs atuais cadastrados e registra status/fonte/mensagem para conferencia.
