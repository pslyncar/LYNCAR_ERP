# Instalar agente em outro Windows

Use dentro da mesma rede local onde o servidor PapezzoSync esta rodando.

## 1. No sistema admin

1. Cadastre o cliente.
2. Cadastre a maquina/equipamento desse cliente.
3. Abra a maquina e clique em **Gerar token para instalar agente**.
4. Guarde:
   - `equipment_id`
   - `agent_token`

Cada computador precisa ter um cadastro e um token proprio.

## 2. Gerar pacote nesta maquina

```powershell
cd C:\Users\vpape\Documents\ERP-PAPEZZOSYNC
.\scripts\package-agent.ps1
```

O pacote sera criado em:

```text
C:\Users\vpape\Documents\ERP-PAPEZZOSYNC\dist\papezzosync-agent.zip
```

Copie esse `.zip` para o outro computador.

## 3. Instalar no outro computador

Extraia o `.zip`, abra PowerShell dentro da pasta extraida e rode:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 -ApiBaseUrl "http://192.168.1.28:8000" -EquipmentId 1 -AgentToken "COLE_O_TOKEN_AQUI" -IntervalSeconds 10
```

Troque:

- `EquipmentId`: pelo ID da maquina cadastrada.
- `AgentToken`: pelo token gerado no admin.

## 4. Testar uma leitura

```powershell
cd "$env:ProgramData\PapezzoSync\Agent"
.\.venv\Scripts\python.exe -m papezzosync_agent.main --config config.json --once
```

Se aparecer `Snapshot enviado com sucesso.`, volte no admin e abra a tela da maquina.

## 5. Iniciar automatico

O instalador cria uma tarefa do Windows chamada:

```text
PapezzoSync Agent
```

Para iniciar sem reiniciar:

```powershell
Start-ScheduledTask -TaskName "PapezzoSync Agent"
```

## 6. Remover

Na pasta extraida do pacote:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall-windows.ps1
```

## Segurança e LGPD

O agente coleta apenas saude/desempenho da maquina:

- CPU
- memoria
- armazenamento
- nome da maquina
- sistema operacional
- IP local
- temperatura quando disponivel

Ele nao coleta tela, arquivos pessoais, senhas, historico de navegacao ou conteudo de documentos.

Os avisos locais apenas orientam o usuario. O agente nao fecha programas e nao apaga arquivos automaticamente.
