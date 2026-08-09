# Teste na rede local

Use este modo apenas dentro da sua rede de casa/escritorio.

## Links desta maquina

- Admin: `http://192.168.1.28:5000`
- API: `http://192.168.1.28:8000/docs`
- URL para agentes: `http://192.168.1.28:8000`

## Subir o sistema em modo rede

```powershell
cd C:\Users\vpape\Documents\ERP-PAPEZZOSYNC
.\scripts\start-lan.ps1
```

## Celular

1. Conecte o celular no mesmo Wi-Fi/rede.
2. Abra `http://192.168.1.28:5000`.
3. Faça login normalmente.

Se nao abrir, o Windows Firewall provavelmente bloqueou. Libere entrada TCP nas portas `5000` e `8000` para rede privada.

## Outro computador com agente

No `config.json` do agente daquele computador:

```json
{
  "api_base_url": "http://192.168.1.28:8000",
  "equipment_id": 1,
  "agent_token": "COLE_AQUI_O_TOKEN_GERADO_NO_ADMIN",
  "interval_seconds": 10,
  "collect_logged_user": false
}
```

Cada maquina precisa ter seu proprio cadastro de equipamento e seu proprio token.
