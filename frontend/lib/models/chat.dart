class ChatRoom {
  final int id;
  final String type;
  final String? name;
  final String? lastMessage;
  final String? lastSender;
  final DateTime? lastTime;
  final int memberCount;
  final bool isMuted;

  ChatRoom({
    required this.id,
    required this.type,
    this.name,
    this.lastMessage,
    this.lastSender,
    this.lastTime,
    required this.memberCount,
    this.isMuted = false,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: json['id'],
      type: json['type'],
      name: json['name'],
      lastMessage: json['last_message'],
      lastSender: json['last_sender'],
      lastTime: json['last_time'] != null ? DateTime.parse(json['last_time']).toLocal() : null,
      memberCount: json['member_count'] ?? 0,
      isMuted: json['is_muted'] ?? false,
    );
  }
}

class Message {
  final int id;
  final int roomId;
  final int senderId;
  final String? senderName;
  final String? content;
  final String type;
  final int? fileId;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.roomId,
    required this.senderId,
    this.senderName,
    this.content,
    required this.type,
    this.fileId,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      roomId: json['room_id'],
      senderId: json['sender_id'],
      senderName: json['sender_name'],
      content: json['content'],
      type: json['type'],
      fileId: json['file_id'],
      createdAt: DateTime.parse(json['created_at']).toLocal(),
    );
  }
}

class RoomMember {
  final int id;
  final int roomId;
  final int userId;
  final String username;
  final String name;
  final DateTime joinedAt;
  int lastReadMessageId;

  RoomMember({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.username,
    required this.name,
    required this.joinedAt,
    this.lastReadMessageId = 0,
  });

  factory RoomMember.fromJson(Map<String, dynamic> json) {
    return RoomMember(
      id: json['id'],
      roomId: json['room_id'],
      userId: json['user_id'],
      username: json['username'],
      name: json['name'],
      joinedAt: DateTime.parse(json['joined_at']).toLocal(),
      lastReadMessageId: json['last_read_message_id'] ?? 0,
    );
  }
}
