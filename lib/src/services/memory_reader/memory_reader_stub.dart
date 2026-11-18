double? _stubBaselineMb;

/// Stub padrão para leitura de memória em plataformas não mapeadas.
double? getPlatformMemoryMb() => null;

/// Obtém ou define o baseline inicial de memória do processo atual (sobrevive a Hot Restart).
double getOrSetProcessBaselineMemoryMb(double currentMb) {
  return _stubBaselineMb ??= currentMb;
}

/// Redefine o baseline de memória do processo para [currentMb] (ou limpa para a próxima leitura).
void resetProcessBaselineMemoryMb([double? currentMb]) {
  _stubBaselineMb = currentMb;
}
