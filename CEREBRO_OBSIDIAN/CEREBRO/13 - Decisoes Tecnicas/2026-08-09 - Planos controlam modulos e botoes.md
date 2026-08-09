# 2026-08-09 - Planos controlam modulos e botoes

## Decisao

Todo novo botao, tela, acao sensivel ou funcionalidade comercial do ERP deve nascer associado a um modulo e/ou permissao.

## Regra

- O Master controla livremente quais modulos fazem parte de cada plano.
- Nao deve existir regra fixa no codigo dizendo que um modulo so pode existir a partir de determinado plano. Quem decide e a Lyncar no Master.
- Ao cadastrar uma empresa, o plano escolhido aplica os modulos padrao automaticamente.
- Excecoes por cliente devem ser feitas no cadastro da empresa, como liberacao extra ou bloqueio especifico.
- Botoes de criar, editar, excluir, transmitir, cancelar, exportar, importar, pagar, estornar, configurar ou acessar areas pagas devem consultar permissao/modulo antes de aparecer ou executar.
- Nenhum botao novo deve ficar solto no frontend sem `session.can(...)`, `session.hasModule(...)` ou validação equivalente no backend.

## Modelo de acesso

Permissoes finais do cliente = plano base + excecoes liberadas - bloqueios especificos.

## Motivo

Isso permite que a Lyncar altere o que o Start, Pro, Business e Enterprise possuem sem editar cliente por cliente, mantendo a possibilidade de liberar algo pontual para um cliente especifico.
