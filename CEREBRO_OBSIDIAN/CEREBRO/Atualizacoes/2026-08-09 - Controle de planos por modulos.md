# 2026-08-09 - Controle de planos por modulos

## Implementado

- Planos do Master agora possuem `default_modules`.
- A tela Master > Planos permite marcar quais modulos pertencem a cada plano.
- Ao selecionar um plano no cadastro da empresa, os modulos do plano passam a ser a base do acesso.
- O backend tambem filtra os modulos pelo plano, para impedir liberacao indevida apenas pelo frontend.
- Na criacao da empresa, o sistema usa os modulos do plano como padrao.
- Na edicao da empresa, o Master pode liberar ou remover modulos especificos como excecao manual daquele cliente.

## Regra operacional

Todo novo botao/acao/tela comercial precisa estar associado a um modulo e/ou permissao antes de entrar em producao.

## Varredura inicial

- Foram encontradas 1.148 ocorrencias visuais/interativas de botoes, chips, listas clicaveis e handlers no Flutter.
- Foram encontradas 205 referencias diretas a permissoes/modulos no frontend.
- A primeira camada entregue controla acesso por modulo/plano.
- A proxima camada deve revisar botoes de acao sensivel para garantir permissao fina por acao, principalmente criar, editar, excluir, cancelar, pagar, transmitir, importar, exportar e configurar.

## Proxima etapa recomendada

Criar um catalogo de funcionalidades/permissoes por botao, com codigo estavel, modulo, rotulo e planos padrao. Esse catalogo deve alimentar a tela de Planos e servir como checklist obrigatorio para novas funcionalidades.
