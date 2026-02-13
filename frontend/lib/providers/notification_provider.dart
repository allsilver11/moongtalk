import 'dart:async';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

class InAppNotification {
  final int roomId;
  final String senderName;
  final String body;

  InAppNotification({
    required this.roomId,
    required this.senderName,
    required this.body,
  });
}

class NotificationProvider extends ChangeNotifier {
  int? _activeRoomId;
  final Set<int> _mutedRoomIds = {};
  StreamSubscription? _wsSubscription;
  int _currentUserId = 0;

  final _inAppNotificationController =
      StreamController<InAppNotification>.broadcast();
  Stream<InAppNotification> get inAppNotifications =>
      _inAppNotificationController.stream;

  int? get activeRoomId => _activeRoomId;
  Set<int> get mutedRoomIds => Set.unmodifiable(_mutedRoomIds);

  bool isRoomMuted(int roomId) => _mutedRoomIds.contains(roomId);

  Future<void> init(int userId) async {
    _currentUserId = userId;
    await NotificationService.instance.init();
    await NotificationService.instance.requestPermission();
    _startListening();
  }

  void updateMutedRooms(Map<int, bool> roomMuteMap) {
    _mutedRoomIds.clear();
    for (final entry in roomMuteMap.entries) {
      if (entry.value) _mutedRoomIds.add(entry.key);
    }
    notifyListeners();
  }

  void setActiveRoom(int? roomId) {
    _activeRoomId = roomId;
  }

  Future<bool> toggleMute(int roomId) async {
    try {
      final result = await ApiService.toggleMute(roomId);
      final isMuted = result['is_muted'] as bool;
      if (isMuted) {
        _mutedRoomIds.add(roomId);
      } else {
        _mutedRoomIds.remove(roomId);
      }
      notifyListeners();
      return isMuted;
    } catch (e) {
      return isRoomMuted(roomId);
    }
  }

  void _startListening() {
    _wsSubscription?.cancel();
    _wsSubscription =
        WebSocketService.instance.messageStream.listen((message) {
      if (message['type'] == 'new_message') {
        _handleNewMessage(message['payload']);
      }
    });
  }

  void _handleNewMessage(Map<String, dynamic> payload) {
    final roomId = payload['room_id'] as int;
    final senderId = payload['sender_id'] as int;

    // 본인 메시지 무시
    if (senderId == _currentUserId) return;

    // 현재 보고있는 채팅방 무시
    if (_activeRoomId == roomId) return;

    // 음소거된 채팅방 무시
    if (_mutedRoomIds.contains(roomId)) return;

    final senderName = payload['sender_name'] as String? ?? '알 수 없음';
    final content = payload['content'] as String?;
    final msgType = payload['type'] as String? ?? 'text';

    String body;
    if (msgType == 'text' && content != null) {
      body = content;
    } else if (msgType == 'image') {
      body = '사진을 보냈습니다';
    } else if (msgType == 'video') {
      body = '동영상을 보냈습니다';
    } else {
      body = '새 메시지';
    }

    // OS 알림 시도
    NotificationService.instance.showNotification(
      id: roomId,
      title: senderName,
      body: body,
      payload: roomId.toString(),
    );

    // 인앱 알림도 표시
    _inAppNotificationController.add(InAppNotification(
      roomId: roomId,
      senderName: senderName,
      body: body,
    ));
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _inAppNotificationController.close();
    super.dispose();
  }
}
