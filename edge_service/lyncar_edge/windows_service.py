"""Windows Service host for Lyncar Edge."""

import servicemanager
import socket
import sys
from pathlib import Path
import win32event
import win32service
import win32serviceutil

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lyncar_edge.main import main


class LyncarEdgeService(win32serviceutil.ServiceFramework):
    _svc_name_ = "LyncarEdge"
    _svc_display_name_ = "Lyncar Edge"
    _svc_description_ = "Servico local do PDV PedeOn para cache, pedidos e impressao."

    def __init__(self, args):
        super().__init__(args)
        self.stop_event = win32event.CreateEvent(None, 0, 0, None)
        socket.setdefaulttimeout(60)

    def SvcStop(self):
        self.ReportServiceStatus(win32service.SERVICE_STOP_PENDING)
        win32event.SetEvent(self.stop_event)

    def SvcDoRun(self):
        servicemanager.LogInfoMsg("Lyncar Edge iniciado")
        main()


if __name__ == "__main__":
    win32serviceutil.HandleCommandLine(LyncarEdgeService)
