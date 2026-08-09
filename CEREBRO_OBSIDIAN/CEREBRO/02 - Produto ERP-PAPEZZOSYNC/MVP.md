# MVP

## MVP recomendado na documentacao inicial

Conforme `README.md` e `docs/papezzosync-visao-inicial.md`, o MVP recomendado contem:

- Backend FastAPI.
- Banco PostgreSQL.
- Login basico.
- Cadastro de clientes.
- Cadastro de equipamentos.
- Cadastro de chamados.
- Agente simples coletando CPU, memoria e disco.
- Dashboard basico via API.

## Estado encontrado no codigo

### Implementado no backend

- API FastAPI.
- Configuracao de banco via SQLAlchemy e `DATABASE_URL`.
- Login com JWT em `/auth/login`.
- Usuario atual em `/auth/me`.
- Clientes com CRUD.
- Equipamentos com CRUD e geracao de token de agente.
- Chamados com CRUD e filtros.
- Monitoramento por usuario autenticado e por agente com `X-Agent-Token`.
- Dashboard em `/dashboard/summary`.
- Produtos com CRUD e busca por codigo.
- Ordens de servico com CRUD, itens, calculo de totais e impressao termica.
- Vendas com itens, pagamentos, baixa de estoque e cancelamento.
- Operadores PDV com PIN e autorizacoes.
- Usuarios, perfis, permissoes e overrides por usuario.

### Implementado no app Flutter

- Login e restauracao de sessao.
- Expiracao por inatividade de 10 minutos.
- Navegacao por permissoes.
- Telas para dashboard, clientes, maquinas, OS, vendas, PDV, produtos, operadores PDV e usuarios.
- Cliente HTTP para as rotas principais do backend.

### Implementado no agente

- Coleta de CPU, memoria, disco, volumes, temperatura, hostname, sistema operacional, IP e versao.
- Envio para `/monitoring/agent/snapshots`.
- Avisos locais para CPU, memoria e armazenamento altos.
- Instalador Windows com tarefa agendada.
- Script de remocao.

## Conclusao do MVP

Pelos arquivos analisados, o projeto ja contem os elementos principais do MVP inicial e tambem funcionalidades alem do MVP, como produtos, OS, vendas, PDV, operadores PDV e permissoes detalhadas.

## Nao determinado

- Nao foi verificado se o banco local esta criado ou populado.
- Nao foi executada a aplicacao.
- Nao foi executada suite de testes.
- Nao foi encontrada documentacao de criterios formais de aceite do MVP.
