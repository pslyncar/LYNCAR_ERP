# Mapa de Endpoints

## Endpoints iniciais documentados

- `GET /health`
- `POST /auth/login`
- `GET /auth/me`
- `GET /master/companies`
- `POST /master/companies`
- `PUT /master/companies/{company_id}`
- `GET /admin/users`
- `POST /admin/users`
- `PUT /admin/users/{user_id}`
- `GET /admin/roles`
- `GET /admin/permissions`
- `PUT /admin/users/{user_id}/permissions`
- `GET /pdv/operators`
- `POST /pdv/operators`
- `PUT /pdv/operators/{operator_id}`
- `POST /pdv/authorize`
- `POST /clients`
- `GET /clients`
- `GET /clients/{client_id}`
- `PUT /clients/{client_id}`
- `DELETE /clients/{client_id}`
- `POST /equipments`
- `GET /equipments`
- `GET /equipments?client_id={client_id}`
- `GET /equipments/{equipment_id}`
- `PUT /equipments/{equipment_id}`
- `DELETE /equipments/{equipment_id}`
- `POST /tickets`
- `GET /tickets`
- `GET /tickets?client_id={client_id}`
- `GET /tickets?status=aberto`
- `GET /tickets/{ticket_id}`
- `PUT /tickets/{ticket_id}`
- `DELETE /tickets/{ticket_id}`
- `POST /monitoring/snapshots`
- `GET /monitoring/snapshots?equipment_id={equipment_id}`
- `GET /dashboard/summary`
- `POST /products`
- `GET /products`
- `GET /products/{product_id}`
- `PUT /products/{product_id}`
- `DELETE /products/{product_id}`
- `POST /service-orders`
- `GET /service-orders`
- `GET /service-orders/{service_order_id}`
- `PUT /service-orders/{service_order_id}`
- `POST /service-orders/{service_order_id}/items`
- `DELETE /service-orders/{service_order_id}`
# Caixa de XML

- `GET /xml-inbox/settings`: devolve o endereco exclusivo do tenant autenticado.
- `GET /xml-inbox/messages`: lista eventos sanitizados da Caixa de XML do tenant.
- `POST /xml-inbox/inbound/{routing_token}`: webhook tecnico do provedor de e-mail, protegido por `X-Inbound-Secret`.
