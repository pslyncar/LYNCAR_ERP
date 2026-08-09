# 2026-07-03 - PDV com avisos discretos e sem observação da venda

## Decisão

No PDV de caixa, a tela deve ser rápida e limpa:

- não exibir campo "Observações da venda";
- não usar painel grande de erro dentro do corpo do PDV;
- avisos operacionais do PDV devem aparecer como notificação flutuante pequena, bonita, sem bloquear o uso e sumir sozinhos;
- mensagens críticas podem ser vermelhas, mas não devem empurrar a tela nem impedir o operador de continuar bipando produtos;
- observação de fechamento de caixa continua existindo, pois é outro fluxo.

## Implementado

- Removido campo visual de observações da venda no PDV Windows e nas variações de PDV.
- Payload de venda criada pelo PDV envia observação vazia, evitando reaproveitar texto antigo salvo.
- `_error` no PDV agora é consumido por snackbar flutuante estilizado, com duração curta e sem ocupar área da tela.
- Telas administrativas continuam podendo usar `ErrorPanel`; a regra de aviso discreto é principalmente para operação de caixa.

## Arquivos principais

- `admin_app/admin_flutter/lib/screens/pdv_screen.dart`
- `admin_app/admin_flutter/lib/services/receipt_print_io.dart`
- `admin_app/admin_flutter/lib/services/receipt_print_stub.dart`
- `admin_app/admin_flutter/lib/services/receipt_print_web.dart`

## Validação

Build Windows do PDV executado com sucesso:

```powershell
flutter build windows --release -t lib/main_pdv.dart
```

## Ajuste complementar - foco e atalhos

- Avisos do PDV Windows passaram a usar overlay flutuante pr�prio, no topo, sem bloquear opera��o e com remo��o autom�tica.
- Ao bipar/digitar c�digo inexistente, o aviso aparece e o foco volta imediatamente ao campo de c�digo.
- Ao tentar finalizar sem item no PDV Windows, aparece aviso flutuante sem abrir painel grande.
- Di�logo "Fechar temporariamente o caixa" agora tem atalhos: Enter/F8 confirma e Esc cancela.
- Prote��o contra m�ltiplos di�logos de fechamento tempor�rio abertos ao mesmo tempo.

## 2026-07-03 - Cliente no PDV por teclado e correção de português
- PDV Windows: campo Cliente passou a ser acessível por teclado via Ctrl+L.
- Janela de seleção de cliente permite pesquisar por nome, CPF/CNPJ, telefone ou e-mail.
- Dentro da janela: setas ↑/↓ navegam, Enter seleciona e Esc cancela.
- Ao fechar a janela, o foco retorna para o leitor/código do produto.
- Corrigidos textos com mojibake no PDV: código, conexão, débito, crédito, observação, diagnóstico, autorização e status de TEF/impressora.
- Padrão do PDV mantido: toda ação operacional deve ter atalho e não deve travar o uso do caixa.

## 2026-07-03 - Correção complementar PDV teclado e textos vindos do cache
- Corrigido diálogo "Fechar temporariamente o caixa" para capturar teclado com foco próprio: Enter, Enter numérico e F8 confirmam; Esc cancela.
- Adicionada limpeza visual de mojibake em nomes exibidos no PDV, evitando nomes como AÃ§úcar quando dados/cache vierem com encoding antigo.
- Mantido o dado original no banco/cache; a limpeza é apenas visual no PDV e nos textos de impressão/itens da venda.
