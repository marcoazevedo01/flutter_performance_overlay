# Flutter Performance Overlay

Um monitor de desempenho leve, desacoplado, arrastável e expansível para aplicações Flutter com suporte nativo a **Agentes de IA via Model Context Protocol (MCP)**.

[![License](https://img.shields.io/badge/license-BSD_3--Clause-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.10+-02569B?logo=flutter)](https://flutter.dev)

---

## 🚀 Funcionalidades

- **FPS Instantâneo e Médio**: Monitoramento da taxa de quadros em tempo real com alertas visuais coloridos.
- **UI Build Time vs Raster / GPU Time**: Identificação rápida de gargalos na thread do Dart vs desenho na GPU.
- **Jank Rate & Worst Frame**: Contagem e percentual de frames perdidos (> 16.6ms) e duração do pior frame recente.
- **Memória RAM (Atual, Delta e Pico)**: Uso de memória RSS, variação diferencial ($\Delta\text{RAM}$) e pico máximo da sessão.
- **Event Loop Lag Detector**: Detecção de congelamentos síncronos da thread principal do Dart (UI Freeze).
- **Rastreamento de Rota Ativa**: Integração com `PerformanceRouteObserver` para monitorar a tela ativa.
- **Contador de Rebuilds**: Auditoria de reconstruções de widgets com `<TrackRebuild id="..." />`.
- **Clamping de Tela**: O overlay é arrastável e nunca ultrapassa as margens visíveis da tela (`SafeArea`).
- **Integração com Agentes de IA (MCP)**: Expõe um mini-servidor local e ferramentas MCP para que assistentes (Antigravity, Cursor, Claude) inspecionem e diagnostiquem o app em tempo real.

---

## 📦 Instalação

Adicione ao `pubspec.yaml` do seu app:

```yaml
dependencies:
  flutter_performance_overlay:
    git:
      url: https://github.com/marcoazevedo01/flutter_performance_overlay.git
      ref: main
```

Execute no terminal:
```bash
flutter pub get
```

---

## 💡 Como Usar no Flutter

### 1. Injetando o Overlay no `MaterialApp`

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
        // Ativa apenas em modo Debug ou Profile
        if (kDebugMode || kProfileMode) {
          return PerformanceOverlayWidget(
            config: const PerformanceOverlayConfig(
              startExpanded: false,
            ),
            child: child!,
          );
        }
        return child!;
      },
      home: const MyHomePage(),
    );
  }
}
```

### 2. Rastreando Rebuilds de Componentes Críticos

Envolva qualquer widget que você queira auditar com `TrackRebuild`:

```dart
TrackRebuild(
  id: 'MeuCardDePedido',
  child: MeuWidgetPesado(),
)
```

---

## 🤖 Conectando com Agentes de IA via MCP (Model Context Protocol)

O pacote inclui um servidor MCP embutido com **auto-atualização transparente**.

### 1. Baixe o Servidor MCP na sua máquina:

* **Windows (PowerShell):**
  ```powershell
  New-Item -ItemType Directory -Force -Path "$env:LOCALAPPDATA\mcp"
  Invoke-WebRequest -Uri "https://raw.githubusercontent.com/marcoazevedo01/flutter_performance_overlay/main/bin/perf_mcp_server.dart" -OutFile "$env:LOCALAPPDATA\mcp\perf_mcp_server.dart"
  ```

* **Linux / macOS:**
  ```bash
  mkdir -p ~/.local/share/mcp
  curl -sSL https://raw.githubusercontent.com/marcoazevedo01/flutter_performance_overlay/main/bin/perf_mcp_server.dart -o ~/.local/share/mcp/perf_mcp_server.dart
  ```

### 2. Adicione ao seu arquivo `mcp_config.json`:

```json
{
  "flutter-performance": {
    "command": "dart",
    "args": [
      "%LOCALAPPDATA%/mcp/perf_mcp_server.dart"
    ]
  }
}
```

### 🧰 Ferramentas MCP Disponíveis para o Agente:

| Ferramenta MCP | O que ela faz |
| :--- | :--- |
| `get_live_metrics` | Retorna snapshot ao vivo (FPS, UI, GPU, RAM, Delta RAM, Rota e Rebuilds). |
| `audit_performance_issues` | Executa auditoria automática (FPS baixo, Jank, gargalos de UI/GPU, vazamentos de memória). |
| `get_rebuild_hotspots` | Retorna ranking dos widgets que mais sofreram rebuilds no app. |
| `analyze_performance_log_file` | Lê e analisa arquivos JSON de log exportados pelo app. |
| `reset_performance_metrics` | Zera os contadores para iniciar uma nova medição pontual. |

---

## 📄 Licença

Distribuído sob a licença [BSD 3-Clause](LICENSE).
