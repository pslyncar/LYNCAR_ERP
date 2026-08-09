# Modelo de Dados

## Fonte analisada

- `database/schema.sql`
- `backend/app/models/*.py`
- `backend/app/schemas/*.py`
- `backend/app/migrate_local.py`

## Observacao importante

`database/schema.sql` contem o schema inicial do MVP. Os modelos SQLAlchemy em `backend/app/models` e o script `backend/app/migrate_local.py` mostram uma estrutura mais completa e atualizada no codigo.

## Tabelas no schema inicial

Arquivo: `database/schema.sql`

- `users`
- `clients`
- `equipments`
- `tickets`
- `monitoring_snapshots`
- `alerts`

## Tabelas encontradas nos modelos SQLAlchemy

- `users`
- `clients`
- `equipments`
- `tickets`
- `monitoring_snapshots`
- `alerts`
- `equipment_current_status`
- `products`
- `service_orders`
- `service_order_items`
- `sales`
- `sale_items`
- `sale_payments`
- `pdv_operators`
- `roles`
- `permissions`
- `role_permissions`
- `user_permissions`
- `product_batches`

## Entidades principais

### Estrategia multiempresa planejada

O projeto passa a preparar separacao por empresa/tenant.

Estado atual:

- Login recebe `company_code`.
- Token/sessao carregam `company_code` e `company_name`.
- Existe cadastro master de empresas na tabela `companies`.
- O codigo inicial `papezzosync` aponta para o banco atual de desenvolvimento.
- Cada empresa cadastrada guarda `database_url`, permitindo apontar para banco PostgreSQL separado.
- Ao criar uma empresa pelo master, o sistema pode gerar automaticamente um banco `papezzosync_{codigo}`, criar tabelas, semear permissoes e criar o primeiro usuario admin da empresa.

Evolucao planejada:

- Criar provisionamento automatico de novos bancos a partir do cadastro master.
- Aplicar migracoes do schema do ERP automaticamente no banco de cada empresa criada.
- Subdominio futuro podera substituir o campo Empresa sem mudar a regra central.

### companies

Tabela master para empresas clientes do sistema.

Campos:

- `code`
- `name`
- Dados comerciais/fiscais, como documento, e-mail, contato e endereco.
- `database_url`
- `plan`
- `status`
- `active`
- `notes`
- `created_at`

Regra de unicidade:

- O master bloqueia duplicidade por codigo/subdominio, documento, e-mail comercial ou nome da empresa.

### master_user_index

Tabela master sem senha usada para localizar usuarios entre tenants e evitar conflito de login.

Campos principais:

- `company_code`
- `company_name`
- `user_id`
- `name`
- `email`
- `role`
- `active`

Regras:

- `email` deve ser unico globalmente.
- A migracao sincroniza os usuarios existentes nos bancos dos tenants para esta tabela.
- A tabela nao guarda senha, apenas indice operacional para bloqueio de duplicidade e redirecionamento de dominio.

### users

Campos principais encontrados:

- `id`
- `name`
- `email`
- `password_hash`
- `role`
- `active`
- `created_at`

Relacionamentos:

- Chamados atribuidos.
- Ordens de servico atribuidas.
- Vendas como vendedor.
- Overrides de permissoes.

### clients

Campos principais encontrados:

- `name`
- `person_type`
- `trade_name`
- `document_number`
- `state_registration`
- `municipal_registration`
- `contact_person`
- `phone`
- `mobile_phone`
- `email`
- `secondary_email`
- Endereco detalhado.
- `contract_type`
- `notes`
- `active`

Relacionamentos:

- Equipamentos.
- Chamados.
- Ordens de servico.
- Vendas.

Regra de unicidade:

- A API bloqueia cliente duplicado dentro do mesmo tenant por documento, e-mail, nome/telefone ou nome quando nao houver outro identificador.

### equipments

Campos principais encontrados:

- `client_id`
- `hostname`
- `asset_tag`
- `location`
- `responsible_user`
- `operating_system`
- `processor`
- `ram_total_gb`
- `storage_total_gb`
- `status`
- `technical_notes`
- `agent_token_hash`
- `agent_version`
- `last_ip_address`
- `last_logged_user`
- `last_seen_at`

Relacionamentos:

- Cliente.
- Chamados.
- Ordens de servico.
- Snapshots de monitoramento.
- Status atual.
- Alertas.

### monitoring_snapshots

Campos:

- `equipment_id`
- `cpu_usage_percent`
- `memory_usage_percent`
- `disk_usage_percent`
- `temperature_celsius`
- `collected_at`
- `received_at`

### equipment_current_status

Campos:

- `equipment_id`
- `cpu_usage_percent`
- `memory_usage_percent`
- `disk_usage_percent`
- `storage_volumes` como JSON.
- `temperature_celsius`
- `health_status`
- `collected_at`
- `updated_at`

### alerts

Campos:

- `equipment_id`
- `type`
- `severity`
- `message`
- `metric_value`
- `resolved`
- `created_at`
- `resolved_at`

### tickets

Campos:

- `client_id`
- `equipment_id`
- `title`
- `description`
- `solution`
- `status`
- `priority`
- `assigned_user_id`
- `opened_at`
- `closed_at`
- `created_at`

### products

Campos principais encontrados:

- Nome, tipo, codigo interno, codigo de barras, descricao.
- Marca, modelo, categoria e local de estoque.
- Controle de lote/validade (`tracks_batch`), lote inicial e validade inicial para cadastros diretos.
- Preco de venda, valor de compra/base de custo, quantidade base do custo, custo medio, valor em estoque, margem, quantidade, estoque minimo e unidade.
- Campos fiscais: NCM, CEST, CFOP, origem, CST, CSOSN, aliquotas ICMS/PIS/COFINS/IPI/ISS.
- Campos novo sistema tributario: IBS/CBS, CBS, IBS estadual/municipal, imposto seletivo.
- `active`, `notes`, `created_at`.

Observacao de custo:

- `average_cost` representa o custo medio atual por unidade de estoque.
- `stock_value` representa o valor contabil/gerencial atual do estoque.
- `purchase_total_cost` representa o valor total da compra/base inicial.
- `purchase_quantity` representa a quantidade comprada/base que o valor total da compra cobre.
- Campos antigos de teste devem ser renomeados por migracao, nao mantidos como modelo final.

### product_batches

Tabela de saldo por lote do estoque.

Campos principais:

- Produto.
- Lote.
- Validade.
- Saldo atual do lote.
- Unidade.
- Origem: cadastro inicial, entrada de estoque, producao, venda/estorno.
- Numero de origem, fornecedor, NF, serie e observacoes.
- Status ativo e datas de criacao/atualizacao.

Regras:

- Entrada de mercadoria aceita cria ou soma saldo no lote.
- Saidas de venda/PDV e consumo de producao baixam lote por FIFO de validade, usando primeiro o lote que vence antes.
- Cancelamento/estorno devolve saldo para lote de retorno quando nao houver rastreabilidade detalhada do lote original.
- A listagem de estoque usa `product_batches` para mostrar a proxima validade/lote com saldo.

Tipos aceitos no schema Pydantic:

- `produto`
- `peca`
- `servico`
- `insumo`

### service_orders

Campos principais encontrados:

- Cliente, equipamento, chamado e tecnico responsavel.
- `number`, `title`, `status`, `priority`, `service_type`.
- Equipamento recebido, motivo de espera, descricao da solicitacao.
- Diagnostico, servico executado e notas internas.
- Mao de obra, itens, desconto e total.
- Abertura, agendamento, fechamento e criacao.

Status aceitos:

- `aberta`
- `em_diagnostico`
- `aguardando_aprovacao`
- `em_execucao`
- `concluida`
- `cancelada`

### service_order_items

Campos:

- `service_order_id`
- `product_id`
- `description`
- `quantity`
- `unit_price`
- `total_price`
- `created_at`

### sales, sale_items, sale_payments

Vendas:

- Numero, cliente, vendedor, origem, status, subtotal, desconto, total, pago, troco, notas, venda e cancelamento.

Itens:

- Produto opcional, codigo de barras, descricao, quantidade, unidade, preco unitario, desconto e total.

Pagamentos:

- Metodo, valor, codigo de autorizacao e notas.

Status aceitos:

- `rascunho`
- `finalizada`
- `cancelada`

Origens aceitas:

- `pdv`
- `venda`
- `os`

### pdv_operators

Campos:

- `name`
- `code`
- `pin_hash`
- `role`
- `can_open_cash`
- `can_authorize_withdrawal`
- `can_authorize_cancel`
- `can_authorize_discount`
- `active`
- `notes`
- `created_at`

### suppliers

Fornecedores cadastrados dentro do banco de cada empresa/tenant.

Campos principais:

- Nome, nome fantasia, documento, inscricao estadual, telefone, e-mail, endereco basico, observacoes e status.

### stock_entries e stock_entry_items

Registram entradas de mercadoria.

Entrada:

- Fornecedor, usuario, origem, status, chave da NF-e, numero, serie, fornecedor textual, valor total, observacoes e datas.

Itens:

- Produto opcional durante conferencia, descricao, codigo, quantidade da nota, quantidade recebida, unidade, custo unitario, custo total, NCM, CFOP, lote, validade, status de conferencia e observacao.

Ao confirmar uma entrada, o sistema cria movimentos `purchase_in`, recalcula `average_cost` e atualiza `stock_value` apenas para itens aceitos com produto vinculado. Itens pendentes, sem cadastro ou marcados para devolucao ficam registrados para rastreabilidade, mas nao movimentam estoque.

Itens aceitos com lote, validade ou produto marcado para controle de lote tambem criam/atualizam saldo em `product_batches`.

### roles, permissions, role_permissions, user_permissions

Implementam controle de acesso por perfil, permissoes e overrides por usuario.

## Migracao local

Arquivo: `backend/app/migrate_local.py`

O script:

- Executa `Base.metadata.create_all`.
- Adiciona colunas em clientes, equipamentos, alertas, status atual, OS e produtos.
- Cria indices para documento de cliente, patrimonio de equipamento e codigo de barras de produto.
- Atualiza OS sem numero para `M{id}`.
- Semeia roles e permissoes padrao.

## Nao determinado

- Nao foi encontrada configuracao Alembic.
- Nao foi inspecionado o banco real em execucao.
- Nao ha documentacao encontrada de estrategia de versionamento formal de schema.
