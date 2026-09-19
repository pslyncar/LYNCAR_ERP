# Sincronização diária das referências da Lyna

O repositório já possui `backend/scripts/sync_fiscal_sources.py`. Ele sincroniza as tabelas auxiliares oficiais de NCM, CFOP, CEST e cClassTrib IBS/CBS.

## Por que não duplica

- NCM, CFOP e cClassTrib usam seus códigos como chaves únicas.
- CEST é reaproveitado pela combinação CEST + NCM + descrição.
- A rotina usa uma trava de processo para impedir duas sincronizações simultâneas.
- Cada fonte é confirmada em transação própria; se uma falhar, a última versão válida permanece.
- A rotina não altera produtos, notas, XML, assinatura ou transmissão para a SEFAZ.

## Instalação no servidor Debian

Depois de atualizar o código no servidor, o responsável deve executar os comandos abaixo a partir da raiz do repositório:

1. Configure o timezone do servidor, se necessário:

   ```bash
   sudo timedatectl set-timezone America/Sao_Paulo
   ```

2. Confira `/etc/lyncar/lyncar.env` com o mesmo ambiente do backend e, caso a fonte oficial mude de endereço, defina as variáveis `FISCAL_NCM_JSON_URL`, `FISCAL_CFOP_URL`, `FISCAL_CEST_URL` e `FISCAL_IBS_CBS_CLASS_TRIB_URL`.

3. Instale os arquivos do serviço e do agendamento:

   ```bash
   sudo install -o root -g root -m 0644 deploy/systemd/lyncar-fiscal-sync.service /etc/systemd/system/
   sudo install -o root -g root -m 0644 deploy/systemd/lyncar-fiscal-sync.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now lyncar-fiscal-sync.timer
   ```

Os arquivos assumem o seguinte padrão:

- código em `/opt/lyncar`;
- backend em `/opt/lyncar/backend`;
- ambiente Python em `/opt/lyncar/venv`;
- usuário do serviço `lyncar`;
- variáveis do backend em `/etc/lyncar/lyncar.env`.

Se o servidor usar outro caminho, usuário ou ambiente virtual, altere esses valores em `deploy/systemd/lyncar-fiscal-sync.service` antes de instalar. O serviço é somente de sincronização de referências fiscais; ele não reinicia o ERP nem modifica o motor de emissão.

4. Verifique o próximo horário e o resultado:

   ```bash
   systemctl list-timers lyncar-fiscal-sync.timer
   systemctl status lyncar-fiscal-sync.timer
   journalctl -u lyncar-fiscal-sync.service -n 100 --no-pager
   ```

O timer dispara às 04:00. Se uma fonte estiver indisponível, o serviço tenta novamente de hora em hora por até 23 horas, sem apagar a versão anterior.
