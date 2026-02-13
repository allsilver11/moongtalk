import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  static String get baseUrl {
    if (kIsWeb) {
      return Uri.base.origin; // 현재 접속 중인 호스트 자동 사용
    }
    return 'http://16.8.32.84'; // 모바일/데스크톱 앱용
  }

  static String get wsUrl {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      final wsScheme = origin.startsWith('https') ? 'wss' : 'ws';
      return '$wsScheme${origin.substring(origin.indexOf('://'))}/ws';
    }
    return 'ws://16.8.32.84/ws';
  }
}
