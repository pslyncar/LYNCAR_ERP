# Lyncar Edge

Servico local-first que coordena os terminais de um estabelecimento. Ele nao e
uma tela de PDV e nao consome uma licenca adicional. O instalador futuro podera
leva-lo junto no perfil `principal`.

## Desenvolvimento

Variaveis obrigatorias:

- `LYNCAR_EDGE_CLOUD_URL`: URL da API Lyncar.
- `LYNCAR_EDGE_ACCESS_TOKEN`: token da ativacao do terminal principal.
- `LYNCAR_EDGE_TERMINAL_KEY`: chave do terminal ativado.
- `LYNCAR_EDGE_NODE_KEY`: identidade estavel gerada na instalacao.
- `LYNCAR_EDGE_LAN_KEY`: segredo compartilhado somente na rede local.

Depois de configurado, o Edge exibe um código temporário em `/health` e
`/.well-known/lyncar-edge`. O dispositivo PedeOn informa esse código para se
parear; não é necessário câmera ou QR Code. O código é invalidado após o
pareamento.

O banco SQLite fica em `%PROGRAMDATA%\Lyncar\Edge\edge.db` por padrao. Em
desenvolvimento, use `LYNCAR_EDGE_DATA_DIR` para apontar para uma pasta isolada.

O WebSocket da nuvem e apenas um aviso. A consistencia vem de snapshot, cursores,
reconciliacao e outbox idempotente.
