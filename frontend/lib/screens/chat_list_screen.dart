import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../models/chat.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
import 'chat_screen.dart';
import 'friends_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<ChatRoom> _rooms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRooms();
    _listenToMessages();
  }

  void _listenToMessages() {
    WebSocketService.instance.messageStream.listen((message) {
      if (message['type'] == 'new_message') {
        _loadRooms();
      }
    });
  }

  Future<void> _loadRooms() async {
    setState(() => _isLoading = true);
    try {
      _rooms = await ApiService.getRooms();
      if (mounted) {
        final muteMap = {for (var room in _rooms) room.id: room.isMuted};
        context.read<NotificationProvider>().updateMutedRooms(muteMap);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('채팅 목록을 불러오지 못했습니다')),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _createGroupChat() async {
    final nameController = TextEditingController();
    final friends = await ApiService.getFriends();
    final selectedFriends = <int>[];

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('그룹 채팅 만들기'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '채팅방 이름',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('멤버 선택',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: friends.length,
                    itemBuilder: (context, index) {
                      final friend = friends[index];
                      final isSelected =
                          selectedFriends.contains(friend.friendId);
                      return CheckboxListTile(
                        value: isSelected,
                        title: Text(friend.name),
                        subtitle: Text('@${friend.username}'),
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              selectedFriends.add(friend.friendId);
                            } else {
                              selectedFriends.remove(friend.friendId);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: selectedFriends.isEmpty
                  ? null
                  : () async {
                      try {
                        await ApiService.createRoom(
                          type: 'group',
                          name: nameController.text.trim().isEmpty
                              ? null
                              : nameController.text.trim(),
                          memberIds: selectedFriends,
                        );
                        Navigator.pop(context, true);
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('채팅방 생성에 실패했습니다')),
                        );
                      }
                    },
              child: const Text('만들기'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await _loadRooms();
    }
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);

    if (messageDate == today) {
      return DateFormat('HH:mm').format(time);
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return '어제';
    } else {
      return DateFormat('MM/dd').format(time);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTheme.gradientAppBar(
        title: '채팅',
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add_rounded),
            onPressed: _createGroupChat,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rooms.isEmpty
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
                          Icons.chat_bubble_outline_rounded,
                          size: 40,
                          color: AppTheme.primaryColor.withOpacity(0.4),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '아직 채팅이 없습니다',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const FriendsScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.person_rounded, size: 18),
                        label: const Text('친구와 대화하기'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppTheme.primaryColor,
                  onRefresh: _loadRooms,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _rooms.length,
                    separatorBuilder: (_, __) => Divider(
                      indent: 76,
                      height: 1,
                      color: AppTheme.dividerColor.withOpacity(0.5),
                    ),
                    itemBuilder: (context, index) {
                      final room = _rooms[index];
                      final displayName = room.name ?? '채팅방';
                      final isGroup = room.type == 'group';

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 6,
                        ),
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: isGroup
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFFFFD700),
                                      Color(0xFFFFA000)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(
                            isGroup
                                ? Icons.group_rounded
                                : Icons.person_rounded,
                            color: isGroup
                                ? AppTheme.primaryDark
                                : Colors.white,
                            size: 22,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (room.memberCount > 2)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${room.memberCount}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              ),
                            if (room.isMuted)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.notifications_off_rounded,
                                  size: 14,
                                  color: AppTheme.textHint,
                                ),
                              ),
                          ],
                        ),
                        subtitle: room.lastMessage != null
                            ? Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  room.lastSender != null
                                      ? '${room.lastSender == context.read<AuthProvider>().user?.name ? '나' : room.lastSender}: ${room.lastMessage!}'
                                      : room.lastMessage!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppTheme.textHint,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            : null,
                        trailing: room.lastTime != null
                            ? Text(
                                _formatTime(room.lastTime),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textHint,
                                ),
                              )
                            : null,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                roomId: room.id,
                                roomName: displayName,
                              ),
                            ),
                          ).then((_) => _loadRooms());
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
