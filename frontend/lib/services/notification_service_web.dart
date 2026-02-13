import 'dart:html' as html;

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;
  NotificationService._();

  bool _initialized = false;

  Future<void> init() async {
    _initialized = true;
  }

  Future<void> requestPermission() async {
    try {
      await html.Notification.requestPermission();
    } catch (e) {
      // Not supported
    }
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) return;
    if (html.Notification.permission != 'granted') return;

    html.Notification(title,
        body: body, icon: '/icons/Icon-192.png', tag: 'msg_$id');
  }
}
