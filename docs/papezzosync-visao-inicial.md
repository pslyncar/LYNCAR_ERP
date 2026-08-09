# PapezzoSync - Visao Inicial do Projeto

## Objetivo

Criar uma plataforma completa para a empresa de informatica PapezzoSync, funcionando como um ERP/CRM operacional para gerenciar clientes, suporte tecnico, chamados, ordens de servico, manutencoes, equipamentos, produtos, contratos e monitoramento basico de computadores.

O sistema deve ser acessado por login e servir como centro principal de operacao da empresa. Ele deve ajudar a organizar atendimentos, acompanhar a saude das maquinas dos clientes, controlar ordens de servico, registrar manutencoes, cadastrar produtos, gerar relatorios e futuramente apoiar o controle financeiro.

## Principios importantes

- O monitoramento deve coletar apenas dados de desempenho e saude da maquina.
- O agente nao deve capturar tela.
- O agente nao deve acessar arquivos pessoais.
- O agente nao deve coletar senhas.
- O agente nao deve coletar dados privados do usuario.
- Cada maquina monitorada deve estar vinculada a um cliente.
- O sistema deve ser dividido em partes independentes para facilitar manutencao e crescimento.

## Modulos iniciais

### 0. Login e controle de usuarios

Campos e recursos previstos:

- Login com e-mail e senha
- Usuarios administradores
- Usuarios tecnicos
- Permissoes por perfil
- Usuario ativo ou inativo

### 1. Cadastro de clientes

Campos previstos:

- Nome do cliente ou empresa
- Telefone
- E-mail
- Endereco
- Tipo de contrato: avulso ou mensal
- Observacoes
- Data de cadastro
- Status: ativo ou inativo

### 2. Cadastro de computadores e equipamentos

Campos previstos:

- Cliente vinculado
- Nome do computador
- Sistema operacional
- Processador
- Memoria RAM
- Armazenamento
- Status do equipamento
- Observacoes tecnicas
- Data de cadastro

### 3. Sistema de chamados

Campos previstos:

- Cliente vinculado
- Equipamento vinculado, quando aplicavel
- Status: aberto, em andamento, concluido ou cancelado
- Prioridade: baixa, media ou alta
- Descricao do problema
- Solucao aplicada
- Data de abertura
- Data de finalizacao
- Tecnico responsavel

### 4. Monitoramento basico

O agente instalado no computador do cliente deve enviar:

- Uso de CPU
- Uso de memoria RAM
- Espaco em disco
- Temperatura, se possivel
- Status online/offline
- Nome da maquina
- Horario da ultima comunicacao

Observacao: temperatura pode depender do sistema operacional, permissao e suporte do hardware. Deve ser tratada como recurso opcional.

### 5. Painel administrativo

Indicadores previstos:

- Total de clientes
- Total de chamados abertos
- Maquinas online
- Maquinas offline
- Alertas de maquinas lentas
- Alertas de pouco espaco em disco
- Historico de atendimentos

### 6. Relatorios

Relatorios previstos:

- Chamados por cliente
- Manutencoes feitas
- Maquinas com problemas
- Relatorio mensal para clientes com contrato

### 7. Produtos e servicos

Campos previstos:

- Nome do produto ou servico
- Tipo: produto, servico ou peca
- Codigo interno
- Preco de venda
- Custo, quando aplicavel
- Estoque, quando aplicavel
- Observacoes
- Status: ativo ou inativo

### 8. Ordens de servico e manutencoes

Campos previstos:

- Cliente vinculado
- Equipamento vinculado, quando aplicavel
- Tecnico responsavel
- Tipo de servico
- Produtos, pecas ou servicos utilizados
- Descricao da solicitacao
- Diagnostico tecnico
- Servico executado
- Valor de mao de obra
- Valor de pecas/produtos
- Valor total
- Status da OS
- Data de abertura
- Data de conclusao
- Assinatura/aceite futuro do cliente

## Tecnologias desejadas

### Aplicativo administrativo

- Flutter/Dart
- Desktop inicialmente
- Android em seguida
- iOS futuramente
- Deve concentrar as telas do ERP/CRM: login, dashboard, clientes, equipamentos, chamados, OS, manutencoes, produtos, relatorios e financeiro futuro.

### Aplicativos Flutter planejados

O projeto deve evoluir com duas interfaces principais:

#### 1. App administrativo PapezzoSync

Usado pela equipe interna da empresa.

Perfis previstos:

- Administrador
- Tecnico
- Vendedor
- Outros colaboradores futuros

Recursos previstos:

- Dashboard geral
- Clientes PF/PJ
- Equipamentos
- Chamados
- Ordens de servico
- Produtos, pecas e servicos
- Estoque
- Relatorios
- Contratos
- Financeiro futuro
- Controle de usuarios e permissoes

#### 2. Portal/app do cliente

Usado pelos clientes da PapezzoSync.

Recursos previstos:

- Login do cliente
- Visualizar suas maquinas
- Ver status online/offline das maquinas autorizadas
- Abrir chamado
- Solicitar manutencao
- Acompanhar ordens de servico
- Consultar historico de atendimentos
- Consultar relatorios mensais, quando tiver contrato

O portal do cliente deve mostrar apenas dados do proprio cliente, nunca dados de outros clientes.

### Perfis e permissoes

O sistema deve ter controle de acesso por perfil e tambem permissoes especificas por modulo.

Perfis iniciais:

- Admin: ve e gerencia tudo.
- Tecnico: acessa chamados, equipamentos, ordens de servico, manutencoes e monitoramento.
- Vendedor: acessa clientes, produtos, estoque, orcamentos e vendas futuras.
- Cliente: acessa apenas seus proprios dados, chamados, maquinas e OS.

Permissoes especificas previstas:

- Ver clientes
- Criar clientes
- Editar clientes
- Excluir clientes
- Ver equipamentos
- Criar equipamentos
- Editar equipamentos
- Ver chamados
- Criar chamados
- Editar chamados
- Finalizar chamados
- Ver OS
- Criar OS
- Editar OS
- Finalizar OS
- Ver produtos
- Criar produtos
- Editar produtos
- Ver estoque
- Movimentar estoque
- Ver relatorios
- Ver financeiro
- Administrar usuarios
- Administrar permissoes

Mesmo que um usuario tenha um perfil como vendedor ou tecnico, o administrador deve poder liberar ou bloquear partes especificas do sistema para aquele usuario.

### Backend/API

Sugestao inicial:

- Python com FastAPI
- API REST
- Autenticacao com JWT
- Documentacao automatica via Swagger/OpenAPI

### Banco de dados

Sugestao inicial:

- PostgreSQL como primeira opcao
- MySQL como alternativa

Motivo da sugestao: PostgreSQL e forte, gratuito, confiavel e muito usado em sistemas com relatorios, filtros e crescimento futuro.

### Agente de monitoramento

- Python
- Coleta de informacoes com bibliotecas como psutil
- Envio periodico para a API
- Configuracao por arquivo local contendo URL da API e chave/token da maquina

## Estrutura do projeto

Estrutura sugerida:

```text
papezzosync/
  backend/
    app/
      api/
      core/
      models/
      schemas/
      services/
      main.py
    migrations/
    tests/
    requirements.txt
    README.md

  database/
    schema.sql
    seed.sql

  admin_app/
    flutter_app/

  agent/
    papezzosync_agent/
      collector.py
      config.py
      sender.py
      main.py
    requirements.txt
    README.md

  docs/
    papezzosync-visao-inicial.md
    instalacao.md
    roadmap.md
```

## Modelo inicial do banco de dados

Tabelas principais do MVP:

- users
- clients
- equipments
- tickets
- monitoring_snapshots
- alerts

Tabelas previstas para evolucao ERP/CRM:

- products
- service_orders
- service_order_items
- maintenances
- contracts
- invoices ou financial_records
- roles
- permissions
- user_permissions
- role_permissions
- client_users

### users

Armazena usuarios internos do sistema, como administradores e tecnicos.

Campos principais:

- id
- name
- email
- password_hash
- role
- active
- created_at

### clients

Armazena clientes e empresas atendidas.

Campos principais:

- id
- name
- phone
- email
- address
- contract_type
- notes
- active
- created_at

### equipments

Armazena computadores e equipamentos vinculados aos clientes.

Campos principais:

- id
- client_id
- hostname
- operating_system
- processor
- ram_total_gb
- storage_total_gb
- status
- technical_notes
- agent_token_hash
- last_seen_at
- created_at

### tickets

Armazena chamados de suporte.

Campos principais:

- id
- client_id
- equipment_id
- title
- description
- solution
- status
- priority
- assigned_user_id
- opened_at
- closed_at
- created_at

### monitoring_snapshots

Armazena leituras enviadas pelo agente.

Campos principais:

- id
- equipment_id
- cpu_usage_percent
- memory_usage_percent
- disk_usage_percent
- temperature_celsius
- collected_at
- received_at

### alerts

Armazena alertas gerados com base no monitoramento.

Campos principais:

- id
- equipment_id
- type
- severity
- message
- resolved
- created_at
- resolved_at

## Ordem recomendada de desenvolvimento

### Fase 1 - Fundacao

1. Criar estrutura de pastas do projeto.
2. Criar backend com FastAPI.
3. Configurar banco PostgreSQL.
4. Criar tabelas iniciais.
5. Criar endpoints de clientes.
6. Criar endpoints de equipamentos.

### Fase 2 - Chamados

1. Criar endpoints de chamados.
2. Criar filtros por cliente, status e prioridade.
3. Criar historico basico de atendimento.
4. Criar regras para abertura e finalizacao de chamados.

### Fase 3 - Agente de monitoramento

1. Criar agente Python local.
2. Coletar CPU, memoria, disco e nome da maquina.
3. Enviar dados para a API.
4. Registrar ultima comunicacao da maquina.
5. Marcar maquina como offline quando ficar muito tempo sem comunicar.

### Fase 4 - Dashboard

1. Criar endpoint de resumo geral.
2. Mostrar total de clientes.
3. Mostrar chamados abertos.
4. Mostrar maquinas online/offline.
5. Mostrar alertas principais.

### Fase 5 - Interface Flutter

1. Criar app administrativo.
2. Tela de login.
3. Tela de dashboard.
4. Tela de clientes.
5. Tela de equipamentos.
6. Tela de chamados.
7. Tela de relatorios.

### Fase 6 - Relatorios

1. Relatorio por cliente.
2. Relatorio mensal de contrato.
3. Relatorio de maquinas com alerta.
4. Exportacao futura em PDF.

## Funcionalidades futuras

- Acesso remoto
- Area do cliente
- Emissao de orcamentos
- Controle financeiro
- Contratos mensais
- Cadastro de produtos
- Controle de estoque simples
- Ordens de servico completas
- Historico de manutencoes
- Notificacoes automaticas
- Integracao com WhatsApp
- Sistema de backup
- Inventario completo de hardware e software

## MVP recomendado

Para comecar sem travar o projeto, o primeiro MVP deve conter:

- Backend FastAPI
- Banco PostgreSQL
- Login basico
- Cadastro de clientes
- Cadastro de equipamentos
- Cadastro de chamados
- Agente simples coletando CPU, memoria e disco
- Dashboard basico via API

Depois disso, a interface Flutter fica mais facil, porque ja teremos a API pronta para conectar. Em seguida entram os modulos de produtos, ordens de servico e manutencoes para transformar a plataforma em um ERP/CRM mais completo.

## Decisao de arquitetura dos aplicativos

A decisao atual e seguir com duas interfaces Flutter:

- App administrativo para equipe interna.
- Portal/app do cliente para clientes acompanharem maquinas, chamados e OS.

Ambos devem usar a mesma API central, com controle forte de permissoes e separacao de dados por usuario/cliente.
