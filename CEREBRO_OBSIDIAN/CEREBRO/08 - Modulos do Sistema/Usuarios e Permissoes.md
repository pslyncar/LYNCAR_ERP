# Usuarios e Permissoes

## Perfis iniciais

- Admin: acesso total.
- Tecnico: chamados, equipamentos, ordens de servico, manutencoes e monitoramento.
- Vendedor: clientes, produtos, estoque, orcamentos e vendas futuras.
- Cliente: apenas seus proprios dados, maquinas, chamados e ordens de servico.

## Diretriz

Mesmo que um usuario tenha um perfil como vendedor ou tecnico, o administrador deve poder liberar ou bloquear partes especificas do sistema para aquele usuario.

O administrador de uma empresa cliente nao pode liberar acesso a modulos que nao foram contratados/liberados no cadastro master da empresa.

O backend deve filtrar a lista de permissoes disponiveis por modulos habilitados e tambem bloquear tentativa de gravar permissao fora do escopo contratado.

O frontend deve exibir apenas os acessos permitidos para aquela empresa, inclusive ao aplicar o padrao do perfil.
