# Agente PapezzoSync

Programa instalado no computador do cliente para enviar informacoes basicas de saude da maquina para a API.

## Dados coletados no MVP

- Nome da maquina
- Uso de CPU
- Uso de memoria RAM
- Uso de disco
- Temperatura, quando a maquina disponibilizar sensores compativeis
- Horario da coleta

## Dados que nao devem ser coletados

- Tela do usuario
- Arquivos pessoais
- Senhas
- Historico de navegacao
- Conteudo de documentos
- Dados privados

## Tecnologia sugerida

- Python
- psutil
- requests ou httpx

## Temperatura

O agente tenta ler temperatura pelo `psutil` e, no Windows, pelo sensor ACPI
quando ele estiver disponivel. Se a maquina, driver ou permissao nao
disponibilizar esse dado, o agente envia `temperature_celsius` como `null` e
continua funcionando normalmente.

## Orientacoes locais

O agente tambem pode avisar o usuario quando a maquina estiver com CPU,
memoria RAM ou armazenamento muito alto. Esses avisos sao limitados por
intervalo para nao incomodar o cliente.

Por seguranca e LGPD:

- O agente nao fecha programas sozinho.
- O agente nao apaga arquivos.
- O agente nao le tela, documentos, senhas, abas do navegador ou conteudo privado.
- Quando necessario, ele usa apenas nomes de processos, como `chrome.exe` ou `excel.exe`, para orientar o usuario.
- Qualquer fechamento de programa deve ser feito manualmente pelo usuario, depois de salvar o trabalho.

## Como testar localmente

Crie ambiente virtual:

```powershell
cd C:\Users\vpape\Documents\ERP-PAPEZZOSYNC\agent
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

Copie `config.example.json` para `config.json` e preencha:

- `api_base_url`
- `equipment_id`
- `agent_token`
- `collect_logged_user`: deixe `false` por padrao. Ligue apenas se houver autorizacao do cliente.
- `local_notifications_enabled`: deixe `true` para avisos locais.
- `notification_cooldown_minutes`: tempo minimo entre avisos do mesmo tipo.

Enviar uma leitura:

```powershell
.\.venv\Scripts\python.exe -m papezzosync_agent.main --once
```

Rodar continuamente:

```powershell
.\.venv\Scripts\python.exe -m papezzosync_agent.main
```
