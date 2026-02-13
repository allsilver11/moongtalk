import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/user.dart';
import '../models/chat.dart';

class ApiService {
  static String? _token;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
  }

  static Future<void> setToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  static Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
  }

  static String? get token => _token;
  static bool get isLoggedIn => _token != null;

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  // Auth APIs
  static Future<Map<String, dynamic>> sendCode(String phone) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/send-code'),
      headers: _headers,
      body: jsonEncode({'phone': phone}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> verifyCode(String phone, String code) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/verify-code'),
      headers: _headers,
      body: jsonEncode({'phone': phone, 'code': code}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> register({
    required String username,
    required String phone,
    required String password,
    required String name,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/register'),
      headers: _headers,
      body: jsonEncode({
        'username': username,
        'phone': phone,
        'password': password,
        'name': name,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/login'),
      headers: _headers,
      body: jsonEncode({'username': username, 'password': password}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['token'] != null) {
      await setToken(data['token']);
    }
    return data;
  }

  // User APIs
  static Future<User> getProfile() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/users/me'),
      headers: _headers,
    );
    return User.fromJson(jsonDecode(response.body));
  }

  static Future<Map<String, dynamic>> updateProfile(String name) async {
    final response = await http.put(
      Uri.parse('${ApiConfig.baseUrl}/api/users/me'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> updateProfileImage(List<int> bytes, String filename) async {
    final request = http.MultipartRequest(
      'PUT',
      Uri.parse('${ApiConfig.baseUrl}/api/users/me/profile-image'),
    );
    request.headers['Authorization'] = 'Bearer $_token';
    request.files.add(http.MultipartFile.fromBytes('image', bytes, filename: filename));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return jsonDecode(response.body);
  }

  static Future<List<Map<String, dynamic>>> searchUser(String query) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/users/search?q=$query'),
      headers: _headers,
    );
    return List<Map<String, dynamic>>.from(jsonDecode(response.body));
  }

  static String getProfileImageUrl(int userId) {
    return '${ApiConfig.baseUrl}/api/users/$userId/profile-image';
  }

  // Friend APIs
  static Future<List<Friend>> getFriends() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/friends'),
      headers: _headers,
    );
    final list = jsonDecode(response.body) as List;
    return list.map((e) => Friend.fromJson(e)).toList();
  }

  static Future<Map<String, dynamic>> addFriend(String query) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/friends'),
      headers: _headers,
      body: jsonEncode({'query': query}),
    );
    return jsonDecode(response.body);
  }

  static Future<void> deleteFriend(int friendId) async {
    await http.delete(
      Uri.parse('${ApiConfig.baseUrl}/api/friends/$friendId'),
      headers: _headers,
    );
  }

  // Chat Room APIs
  static Future<List<ChatRoom>> getRooms() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/rooms'),
      headers: _headers,
    );
    final list = jsonDecode(response.body) as List;
    return list.map((e) => ChatRoom.fromJson(e)).toList();
  }

  static Future<Map<String, dynamic>> createRoom({
    required String type,
    String? name,
    required List<int> memberIds,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/rooms'),
      headers: _headers,
      body: jsonEncode({
        'type': type,
        'name': name,
        'member_ids': memberIds,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<void> markRead(int roomId, int messageId) async {
    await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/rooms/$roomId/read'),
      headers: _headers,
      body: jsonEncode({'message_id': messageId}),
    );
  }

  static Future<void> leaveRoom(int roomId) async {
    await http.delete(
      Uri.parse('${ApiConfig.baseUrl}/api/rooms/$roomId/leave'),
      headers: _headers,
    );
  }

  static Future<Map<String, dynamic>> toggleMute(int roomId) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/rooms/$roomId/mute'),
      headers: _headers,
    );
    return jsonDecode(response.body);
  }

  static Future<List<RoomMember>> getRoomMembers(int roomId) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/rooms/$roomId/members'),
      headers: _headers,
    );
    final list = jsonDecode(response.body) as List;
    return list.map((e) => RoomMember.fromJson(e)).toList();
  }

  // Message APIs
  static Future<List<Message>> getMessages(int roomId, {int limit = 50, int offset = 0}) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/rooms/$roomId/messages?limit=$limit&offset=$offset'),
      headers: _headers,
    );
    final list = jsonDecode(response.body) as List;
    return list.map((e) => Message.fromJson(e)).toList();
  }

  static Future<Map<String, dynamic>> sendMessage(int roomId, String content) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/rooms/$roomId/messages'),
      headers: _headers,
      body: jsonEncode({'content': content}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> sendFileBytes(int roomId, List<int> bytes, String filename, String mimeType) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiConfig.baseUrl}/api/rooms/$roomId/files'),
    );
    request.headers['Authorization'] = 'Bearer $_token';
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
    ));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return jsonDecode(response.body);
  }

  static String getFileUrl(int fileId) {
    return '${ApiConfig.baseUrl}/api/files/$fileId';
  }
}
