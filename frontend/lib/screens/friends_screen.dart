import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../config/theme.dart';
import 'chat_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  List<Friend> _friends = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() => _isLoading = true);
    try {
      _friends = await ApiService.getFriends();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('친구 목록을 불러오지 못했습니다')),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _showAddFriendDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('친구 추가'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '아이디 또는 휴대폰 번호',
            hintText: '친구의 아이디나 휴대폰 번호 입력',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;

              try {
                await ApiService.addFriend(controller.text.trim());
                Navigator.pop(context, true);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('친구를 찾을 수 없습니다')),
                );
              }
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _loadFriends();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('친구가 추가되었습니다')),
        );
      }
    }
  }

  Future<void> _startChat(Friend friend) async {
    try {
      final result = await ApiService.createRoom(
        type: 'direct',
        memberIds: [friend.friendId],
      );
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              roomId: result['room_id'],
              roomName: friend.name,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('채팅방을 열 수 없습니다')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTheme.gradientAppBar(
        title: '친구',
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded),
            onPressed: _showAddFriendDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _friends.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.people_outline_rounded,
                          size: 40,
                          color: AppTheme.primaryColor.withOpacity(0.4),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '아직 친구가 없습니다',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _showAddFriendDialog,
                        icon: const Icon(Icons.person_add_rounded, size: 18),
                        label: const Text('친구 추가'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppTheme.primaryColor,
                  onRefresh: _loadFriends,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _friends.length,
                    separatorBuilder: (_, __) => Divider(
                      indent: 76,
                      height: 1,
                      color: AppTheme.dividerColor.withOpacity(0.5),
                    ),
                    itemBuilder: (context, index) {
                      final friend = _friends[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Center(
                            child: Text(
                              friend.name[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          friend.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          '@${friend.username}',
                          style: TextStyle(
                            color: AppTheme.textHint,
                            fontSize: 13,
                          ),
                        ),
                        trailing: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        onTap: () => _startChat(friend),
                      );
                    },
                  ),
                ),
    );
  }
}
