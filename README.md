# Flutter Performance Overlay

Um monitor de desempenho leve, desacoplado, arrastável e expansível para aplicações Flutter com suporte nativo a **agentes de IA via Model Context Protocol (MCP)**.

[![License](https://img.shields.io/badge/license-BSD_3--Clause-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.10+-02569B?logo=flutter)](https://flutter.dev)

---

## 🚀 Funcionalidades

- **FPS Instantâneo e Médio**: Monitoramento da taxa de quadros em tempo real com alertas visuais por cores.
- **UI Build Time vs Raster / GPU Time**: Identificação rápida de gargalos na thread do Dart vs desenho na GPU.
- **Jank Rate & Worst Frame**: Contagem e percentual de frames perdidos (> 16.6ms) e duração do pior frame recente.
- **Memória RAM (Atual, Delta e Pico)**: Uso de memória RSS, variação diferencial ($\Delta\text{RAM}$) e pico máximo da sessão.
- **Event Loop Lag Detector**: Detecção de congelamentos síncronos da thread principal do Dart (UI Freeze).
- **Rastreamento de Rota Ativa**: Integração com `PerformanceRouteObserver` para monitorar qual tela está sendo exibida.
- **Contador de Rebuilds**: Auditoria de reconstruções de widgets com `<TrackRebuild id="..." />`.
- **Clamping de Tela**: O overlay é arrastável e nunca ultrapassa as margens visíveis da tela (`SafeArea`).
- **Integração com Agentes de IA (MCP)**: Expõe um mini-servidor local e ferramentas MCP para que assistentes (Antigravity, Cursor, Claude) inspecionem e diagnostiquem o app em tempo de execução.

---

## 📦 Instalação

Adicione ao seu `pubspec.yaml`:

```yaml
dependencies:
  flutter_performance_overlay:
    git:
      url: https://github.com/marcoazevedo01/flutter_performance_overlay.git
      ref: main
```

---

## 💡 Como Usar

### 1. Uso Plug-and-Play no `MaterialApp`

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_performance_overlay/flutter_performance_overlay.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meu App',
      navigatorObservers: [
        PerformanceRouteObserver(), // Captura a rota atual automaticamente
      ],
      builder: (context, child) {
        return PerformanceOverlayWidget(
          config: const PerformanceOverlayConfig(
            enabled: kDebugMode || kProfileMode,
            startExpanded: false,
          ),
          child: child!,
        );
      },
      home: const MyHomePage(),
    );
  }
}
```

### 2. Rastreando Rebuilds de Componentes Críticos

Envolva widgets que você deseja auditar com `TrackRebuild`:

```dart
TrackRebuild(
  id: 'MeuItemLista',
  child: ListTile(
    title: Text(item.nome),
  ),
)
```

---

## 🤖 Conectando com Agentes de IA via MCP (Model Context Protocol)

O pacote inclui um servidor MCP embutido que se conecta ao seu app em execução.

Adicione ao arquivo `mcp_config.json` do seu cliente MCP (Antigravity, Claude Desktop, Cursor):

```json
{
  "flutter-performance": {
    "command": "dart",
    "args": [
      "caminho/para/flutter_performance_overlay/bin/perf_mcp_server.dart"
    ]
  }
}
```

### Ferramentas MCP Disponíveis:
* `get_live_metrics`: Retorna as métricas em tempo real do app aberto.
* `audit_performance_issues`: Executa auditoria automática (FPS baixo, Jank, gargalos de UI/GPU, vazamentos de memória).
* `get_rebuild_hotspots`: Retorna ranking dos widgets com mais rebuilds.
* `analyze_performance_log_file`: Analisa arquivos de log em disco.
* `reset_performance_metrics`: Zera contadores de medição.

---

## 📄 Licença

Distribuído sob a licença [BSD 3-Clause](LICENSE).
