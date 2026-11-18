double? _stubBaselineMb;

/// Stub padrão para leitura de memória em plataformas não mapeadas.
double? getPlatformMemoryMb() => null;

/// Retorna o nome padrão da aplicação para plataformas não mapeadas.
String getPlatformAppName() => 'FlutterApp';

/// Retorna o nome padrão do dispositivo para plataformas não mapeadas.
String getPlatformDeviceName() => 'Unknown';

/// Obtém ou define o baseline inicial de memória do processo atual (sobrevive a Hot Restart).
double getOrSetProcessBaselineMemoryMb(double currentMb) {
  return _stubBaselineMb ??= currentMb;
}

/// Redefine o baseline de memória do processo para [currentMb] (ou limpa para a próxima leitura).
void resetProcessBaselineMemoryMb([double? currentMb]) {
  _stubBaselineMb = currentMb;
}
