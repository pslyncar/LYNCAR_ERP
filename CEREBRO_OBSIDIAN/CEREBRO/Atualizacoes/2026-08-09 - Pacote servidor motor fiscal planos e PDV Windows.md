# 2026-08-09 - Pacote servidor motor fiscal, planos e PDV Windows

## Objetivo
- Levar ao servidor a atualizacao completa feita em 2026-08-09.
- Escopo principal: motor fiscal NF-e/NFC-e, sincronizacao SEFAZ, cadastro fiscal master/tenant, checklist fiscal, regras RTC IBS/CBS, planos por modulos e separacao PDV Web x PDV Windows.

## Regras de produto decididas
- O motor fiscal deve ir como codigo de producao, com ambiente configuravel por empresa.
- O cadastro master preenche dados fiscais iniciais do cliente e o tenant usa esses dados como base.
- CNPJ no master deve consultar automaticamente fontes gratuitas e preencher o maximo possivel.
- Campos brasileiros devem usar mascara/padrao visual: CPF/CNPJ, telefone, CEP, data, dinheiro, UF.
- Plano controla modulos centralmente.
- Ao salvar um plano, todos os clientes daquele plano recebem exatamente os modulos marcados/desmarcados.
- PDV Web e PDV Windows sao modulos diferentes.
- PDV Web pode estar em todos os planos.
- PDV Windows so fica liberado nos planos/clientes definidos no Master.
- Terminais PDV Windows nao podem gerar codigo quando o cliente nao possui modulo `pdv_windows`.
- Logo da tela OBRIGADO pertence ao PDV Windows.

## Migracao obrigatoria no servidor
Rodar no servidor:

```powershell
cd C:\Lynkar\ERP-PAPEZZOSYNC\backend
.\.venv\Scripts\python.exe -m app.migrate_master
.\.venv\Scripts\python.exe -m app.migrate_local
```

Essas migracoes preservam dados existentes e criam/atualizam colunas/tabelas necessarias.

## Validacoes locais
- `python -m py_compile` dos arquivos fiscais, planos, PDV e migracoes: OK.
- `flutter analyze`: OK.
- `flutter build web --release`: OK.
- `pytest`: nao executado porque a venv local nao tem `pytest` instalado.

## Observacao operacional
Antes de aplicar em producao, fazer backup do banco master e dos bancos tenants.
