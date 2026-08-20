enum PdvConnectivityChange { unchanged, enteredContingency, recovered }

class PdvConnectivity {
  bool? _online;

  bool? get online => _online;

  bool get inContingency => _online == false;

  PdvConnectivityChange report({required bool online}) {
    if (_online == online) return PdvConnectivityChange.unchanged;
    final wasOffline = _online == false;
    _online = online;
    if (!online) return PdvConnectivityChange.enteredContingency;
    return wasOffline
        ? PdvConnectivityChange.recovered
        : PdvConnectivityChange.unchanged;
  }
}
