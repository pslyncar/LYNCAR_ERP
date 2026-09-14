# Publicação do PedeOn

Este roteiro publica somente os componentes do PedeOn. O aplicativo operacional
`pedeon_operations_flutter` é distribuído separadamente como aplicativo e não
faz parte do pacote do servidor.

## Ordem da atualização

1. Fazer backup do banco master e dos bancos das empresas.
2. Copiar o backend e instalar as dependências em um ambiente virtual novo ou
   já existente.
3. Configurar o `.env` do servidor sem colocar credenciais no Git.
4. Executar as migrações do backend antes de iniciar a nova API.
5. Reiniciar a API FastAPI.
6. Gerar o build Web do Admin e publicar os arquivos estáticos.
7. Gerar o build Web do cardápio público e publicar os arquivos estáticos.
8. Confirmar que a rota `/{slug}/salao` também retorna o `index.html` do
   cardápio público.
9. Instalar o Edge separadamente nos computadores autorizados, quando
   aplicável.

## Variáveis principais

Use valores reais somente no `.env` do servidor:

- `DATABASE_URL`
- `MASTER_DATABASE_URL`
- `SECRET_KEY`
- `CORS_ORIGINS`
- `PEDEON_PUBLIC_BASE_URL`
- `PEDEON_API_PUBLIC_URL`
- credenciais sociais configuradas pelo Master

O segredo OAuth do Google, Facebook ou Apple nunca deve ser enviado ao
repositório, ao build Web ou exibido na interface.

## Liberação do PedeOn

O módulo fica desativado por padrão nos planos existentes. A liberação deve
ser feita pelo Master por segmento/plano ou por exceção específica da empresa.
Depois de liberar o módulo, o administrador da empresa poderá configurar loja,
catálogo, pagamentos, entrega, estações e terminais.

## Verificações após a publicação

- API responde em `/health` e expõe a documentação protegida;
- empresa liberada consegue abrir o Admin PedeOn;
- empresa não liberada recebe bloqueio;
- cardápio público abre por slug;
- salão abre em `/{slug}/salao` na rede local;
- pedido público chega à Central de Pedidos;
- pedido de salão chega à cozinha;
- caixa vincula o recebimento ao usuário logado;
- Pix manual permanece aguardando conferência;
- Edge registra heartbeat e sincroniza após uma interrupção de rede.

Não publicar banco local, `uploads`, logs, arquivos `.env`, `.venv`, builds
temporários ou o aplicativo operacional do PDV PedeOn neste pacote.
