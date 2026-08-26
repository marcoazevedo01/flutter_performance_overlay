import 'dart:async';
import 'package:flutter/widgets.dart';

/// Observer de navegação para rastrear e notificar a rota/tela ativa.
class PerformanceRouteObserver extends NavigatorObserver {
  static final PerformanceRouteObserver _instance = PerformanceRouteObserver._internal();
  factory PerformanceRouteObserver() => _instance;
  PerformanceRouteObserver._internal();

  String _currentRoute = '/';
  String get currentRoute => _currentRoute;

  final _controller = StreamController<String>.broadcast();
  Stream<String> get routeStream => _controller.stream;

  void _updateRoute(Route<dynamic>? route) {
    if (route == null) return;
    final name = route.settings.name ?? route.runtimeType.toString();
    if (name.isNotEmpty && name != _currentRoute) {
      _currentRoute = name;
      _controller.add(_currentRoute);
    }
  }

  /// Define manualmente o nome da rota atual (útil para roteadores customizados).
  void setCurrentRoute(String routeName) {
    if (routeName.isNotEmpty && routeName != _currentRoute) {
      _currentRoute = routeName;
      _controller.add(_currentRoute);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _updateRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _updateRoute(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _updateRoute(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _updateRoute(previousRoute);
  }
}
