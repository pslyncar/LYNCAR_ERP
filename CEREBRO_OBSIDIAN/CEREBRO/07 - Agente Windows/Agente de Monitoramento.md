# Agente de Monitoramento

Programa instalado no computador do cliente para enviar informacoes basicas de saude da maquina para a API.

## Caminho

```text
agent/papezzosync_agent
```

## Dependencias

Arquivo: `agent/requirements.txt`

- `psutil==7.1.3`
- `requests==2.32.5`

## Versao

Arquivo: `collector.py`

```text
AGENT_VERSION = 0.1.5
```

## Dados coletados

Arquivo: `collector.py`.

- `equipment_id`
- `cpu_usage_percent`
- `memory_usage_percent`
- `disk_usage_percent`
- `storage_volumes`
- `temperature_celsius`
- `collected_at`
- `hostname`
- `operating_system`
- `ip_address`
- `agent_version`
- `logged_user`, somente quando `collect_logged_user` estiver ativo.

## Volumes de armazenamento

O agente percorre `psutil.disk_partitions(all=False)`, ignora particoes com `cdrom` e particoes sem filesystem, calcula:

- dispositivo.
- ponto de montagem.
- filesystem.
- total GB.
- usado GB.
- livre GB.
- percentual de uso.

## Temperatura

Fluxo encontrado:

1. Tenta `psutil.sensors_temperatures()`.
2. No Windows, tenta PowerShell com `Get-CimInstance` em `root\wmi` para `MSAcpi_ThermalZoneTemperature`.
3. Se nao houver leitura valida, envia `null`.

## Envio para API

Arquivo: `sender.py`.

Endpoint:

```text
POST /monitoring/agent/snapshots
```

Cabecalho:

```text
X-Agent-Token: <token do equipamento>
```

Timeout HTTP: 15 segundos.

## Configuracao

Arquivo: `config.py` e exemplos `config.example.json`, `config.local.example.json`.

Campos:

- `api_base_url`
- `equipment_id`
- `agent_token`
- `interval_seconds`
- `collect_logged_user`
- `local_notifications_enabled`
- `notification_cooldown_minutes`

## Execucao

Arquivo: `main.py`.

Modos:

- `--once`: coleta e envia uma unica leitura.
- Loop continuo: coleta e envia a cada `interval_seconds`.

Parametros CLI:

- `--config`
- `--api-base-url`
- `--equipment-id`
- `--agent-token`
- `--interval-seconds`
- `--collect-logged-user`
- `--disable-local-notifications`
- `--notification-cooldown-minutes`
- `--once`

## Avisos locais

Arquivo: `advisor.py`.

Limites locais:

- CPU alta: 85%.
- Memoria alta: 85%.
- Armazenamento alto: 80%.

O agente mostra orientacoes ao usuario via popup Windows quando possivel, ou imprime no console. O estado de notificacoes fica em:

```text
%LOCALAPPDATA%\PapezzoSync\Agent\notification_state.json
```

O cooldown padrao nos exemplos e 30 minutos.

## Instalacao Windows

Arquivo: `agent/install-windows.ps1`.

O instalador:

- Exige `ApiBaseUrl`, `EquipmentId` e `AgentToken`.
- Instala por padrao em `%ProgramData%\PapezzoSync\Agent`.
- Cria `.venv`.
- Instala dependencias.
- Gera `config.json`.
- Cria tarefa agendada `PapezzoSync Agent`.
- Se a tarefa falhar, cria inicializacao automatica na pasta Startup.

## Remocao

Arquivo: `agent/uninstall-windows.ps1`.

- Remove tarefa agendada.
- Remove pasta de instalacao.

## Empacotamento

Arquivo: `scripts/package-agent.ps1`.

Gera:

```text
dist/papezzosync-agent.zip
```

## Regras de privacidade documentadas

Conforme `agent/README.md` e `docs/instalar-agente-windows.md`, o agente nao deve coletar:

- Tela do usuario.
- Arquivos pessoais.
- Senhas.
- Historico de navegacao.
- Conteudo de documentos.
- Dados privados.

Tambem nao fecha programas sozinho e nao apaga arquivos automaticamente.

## Nao determinado

- O diretorio `agent/vendor/LibreHardwareMonitor` existe, mas o codigo Python analisado usa `psutil` e PowerShell ACPI para temperatura.
- Nao foi executada instalacao em Windows de cliente.
- Nao foi verificado se a tarefa agendada esta ativa em alguma maquina.
