class ProcessingSessionNavigation {
  static final Map<String, int> _debugRoutesBySession = <String, int>{};
  static final Map<String, int> _resultRoutesBySession = <String, int>{};

  static void enterDebug(String sessionId) {
    _debugRoutesBySession[sessionId] =
        (_debugRoutesBySession[sessionId] ?? 0) + 1;
    _log(sessionId, debugReused: _debugRoutesBySession[sessionId]! == 1);
  }

  static void exitDebug(String sessionId) {
    _decrement(_debugRoutesBySession, sessionId);
    _log(sessionId);
  }

  static void enterResult(String sessionId) {
    _resultRoutesBySession[sessionId] =
        (_resultRoutesBySession[sessionId] ?? 0) + 1;
    _log(sessionId, resultReused: _resultRoutesBySession[sessionId]! == 1);
  }

  static void exitResult(String sessionId) {
    _decrement(_resultRoutesBySession, sessionId);
    _log(sessionId);
  }

  static void logTransition(
    String sessionId, {
    bool? debugReused,
    bool? resultReused,
  }) {
    _log(sessionId, debugReused: debugReused, resultReused: resultReused);
  }

  static void _decrement(Map<String, int> source, String sessionId) {
    final next = (source[sessionId] ?? 0) - 1;
    if (next <= 0) {
      source.remove(sessionId);
    } else {
      source[sessionId] = next;
    }
  }

  static void _log(String sessionId, {bool? debugReused, bool? resultReused}) {
    final activeDebug = _debugRoutesBySession[sessionId] ?? 0;
    final activeResult = _resultRoutesBySession[sessionId] ?? 0;
    final activeRoutes = activeDebug + activeResult;
    final hasStaleReference = activeDebug > 1 || activeResult > 1;

    print(
      'NAVIGATION_FLOW: '
      'debugReused=${debugReused ?? activeDebug <= 1} '
      'resultReused=${resultReused ?? activeResult <= 1} '
      'sessionId=$sessionId',
    );
    print(
      'SESSION_STATE: '
      'activeRoutes=$activeRoutes '
      'hasStaleReference=$hasStaleReference',
    );
  }
}
