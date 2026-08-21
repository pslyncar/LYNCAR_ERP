# 2026-08-21 - Fila fiscal transacional e evolucao para broker

## Decisao

A emissao fiscal do PDV usa duas camadas duraveis:

1. fila local persistente no PDV Windows, para sobreviver a queda do aplicativo, da internet ou da API;
2. fila fiscal transacional no PostgreSQL do backend, processada por worker independente da tela e do PDV.

O PostgreSQL e a fonte da verdade dos documentos, da numeracao, da fila e dos resultados. WebSocket serve apenas para avisar que existem dados novos; nunca e a garantia de entrega.

## Ordenacao e concorrencia

- A autoridade da numeracao fica exclusivamente no backend.
- O PDV nunca escolhe, reserva ou incrementa numero fiscal.
- A unidade de serializacao e `empresa + ambiente + modelo + serie`.
- Cada trabalho possui chave idempotente por documento e tipo de operacao.
- Locks transacionais e restricoes unicas impedem que dois workers autorizem o mesmo documento.
- Varios PDVs podem vender simultaneamente; a etapa fiscal e ordenada por serie, sem duplicar ou pular numero apenas por repeticao da mesma tentativa.
- Rejeicao definitiva conserva o numero para correcao e reenvio do mesmo documento. O numero so avanca com autorizacao, contingencia valida ou comprovacao externa de que ja foi usado.

## Timeout e contingencia

Timeout de autorizacao e resultado desconhecido, nao rejeicao:

- a NFC-e normal original permanece como `pending_return`, com sua chave e seu numero;
- cria-se uma nova NFC-e em contingencia offline com o numero sequencial seguinte e referencia ao documento original;
- o backend consulta primeiro a chave original;
- se a original tiver sido autorizada, a contingencia relacionada nao deve ser transmitida automaticamente e exige tratamento de duplicidade;
- se a original realmente nao existir na SEFAZ apos as verificacoes previstas, a contingencia pode ser transmitida;
- documentos em contingencia sao retransmitidos automaticamente quando o servico volta;
- rejeicao 656 aplica espera/backoff e nao gera repeticao agressiva contra a SEFAZ.

## Por que PostgreSQL agora

A fila no banco nao e improviso: usa o padrao de fila duravel/transacional, mantendo na mesma transacao o documento e a intencao de transmissao. Para a escala atual, isso reduz componentes, elimina a janela entre gravar a nota e publicar uma mensagem e facilita auditoria e recuperacao.

Como a numeracao fiscal de uma mesma serie precisa ser serial, adicionar RabbitMQ agora nao aumentaria a vazao dessa serie. O ganho atual vem de paralelizar empresas e series diferentes, mantendo cada faixa ordenada.

## Evolucao futura para broker

Reavaliar RabbitMQ ou um servico gerenciado de filas quando houver necessidade real de uma ou mais destas capacidades:

- varios clusters de processamento fiscal independentes ou operacao multi-regiao;
- volume sustentado em que a fila no banco afete a latencia ou a carga transacional do ERP;
- necessidade de escalar consumidores e roteamento por empresa/regiao separadamente;
- grande volume de eventos nao fiscais que nao precise da serializacao por serie;
- requisitos operacionais de dead-letter queue, replay e telemetria centralizada entre muitos servicos.

Mesmo depois da adocao de broker:

- PostgreSQL continua sendo a fonte da verdade;
- a publicacao deve usar transactional outbox, nunca gravacao no banco seguida de publicacao sem garantia atomica;
- o consumidor continua idempotente;
- a chave de particionamento/ordenacao continua sendo `empresa + ambiente + modelo + serie`;
- o broker nao se torna autoridade de numeracao;
- WebSocket continua apenas como notificacao para as interfaces.

RabbitMQ e uma opcao natural para filas com roteamento e acknowledgements. Um servico gerenciado equivalente pode ser preferido para reduzir operacao. A escolha deve ser feita por metricas e requisitos da epoca, nao apenas pela quantidade de clientes contratados.

## Operacao e observabilidade obrigatorias

- monitorar profundidade da fila, idade do trabalho mais antigo, tentativas, bloqueios e tempo de autorizacao;
- alertar para trabalhos permanentemente bloqueados, rejeicao 656 e divergencia entre documento original e contingencia;
- manter acao manual de carga/sincronizacao no PDV e no master como recuperacao operacional, sem substituir o fluxo automatico;
- registrar auditoria suficiente para reconstruir cada tentativa sem reenviar cegamente.

## Implementacao de referencia

- backend: `C:\erp_build\backend`;
- PDV Windows correto: `C:\LYNCAR_PDV_APP_WINDOWS`;
- fila backend: `backend/app/services/fiscal_queue.py`;
- rotas fiscais: `backend/app/api/routes/fiscal.py`;
- modelo de fila: `backend/app/models/fiscal.py`;
- cliente e fila local do PDV: `C:\LYNCAR_PDV_APP_WINDOWS\lib`.

Esta decisao substitui a automacao dependente da tela descrita em `2026-06-27 - PDV offline e NFC-e contingencia.md`.
