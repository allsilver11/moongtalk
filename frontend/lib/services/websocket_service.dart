import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api_config.dart';
import '../services/api_service.dart';

class WebSocketService {
  static WebSocketService? _instance;
  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _messageController;
  Timer? _pingTimer;
  bool _isConnected = false;

  static WebSocketService get instance {
    _instance ??= WebSocketService._();
    return _instance!;
  }

  WebSocketService._();

  Stream<Map<String, dynamic>> get messageStream {
    _messageController ??= StreamController<Map<String, dynamic>>.broadcast();
    return _messageController!.stream;
  }

  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_isConnected) return;

    final token = ApiService.token;
    if (token == null) return;

    try {
      // 토큰을 쿼리 파라미터로 전달 (WebSocket은 헤더 지원이 제한적)
      _channel = WebSocketChannel.connect(
        Uri.parse('${ApiConfig.wsUrl}?token=$token'),
      );

      _messageController ??= StreamController<Map<String, dynamic>>.broadcast();

      _channel!.stream.listen(
        (data) {
          try {
            final message = jsonDecode(data);
            _messageController?.add(message);
          } catch (e) {
            // Invalid JSON
          }
        },
        onError: (error) {
          _isConnected = false;
          _reconnect();
        },
        onDone: () {
          _isConnected = false;
          _reconnect();
        },
      );

      _isConnected = true;
      _startPing();
    } catch (e) {
      _isConnected = false;
      _reconnect();
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      send({'type': 'ping'});
    });
  }

  void _reconnect() {
    Future.delayed(const Duration(seconds: 5), () {
      if (!_isConnected && ApiService.isLoggedIn) {
        connect();
      }
    });
  }

  void send(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode(message));
    }
  }

  void disconnect() {
    _pingTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    _messageController?.close();
    _messageController = null;
    _instance = null;
  }
}
