class User {
  final int id;
  final String username;
  final String phone;
  final String name;
  final String? profileImage;
  final String? profileImageMime;
  final DateTime createdAt;
  final DateTime updatedAt;

  User({
    required this.id,
    required this.username,
    required this.phone,
    required this.name,
    this.profileImage,
    this.profileImageMime,
    required this.createdAt,
    required this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      phone: json['phone'],
      name: json['name'],
      profileImage: json['profile_image'],
      profileImageMime: json['profile_image_mime'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}

class Friend {
  final int id;
  final int friendId;
  final String username;
  final String name;
  final DateTime createdAt;

  Friend({
    required this.id,
    required this.friendId,
    required this.username,
    required this.name,
    required this.createdAt,
  });

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      id: json['id'],
      friendId: json['friend_id'],
      username: json['username'],
      name: json['name'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
