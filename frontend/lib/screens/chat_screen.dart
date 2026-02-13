import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../models/chat.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
import '../config/theme.dart';
import '../utils/file_saver.dart';

class ChatScreen extends StatefulWidget {
  final int roomId;
  final String roomName;

  const ChatScreen({
    super.key,
    required this.roomId,
    required this.roomName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  List<Message> _messages = [];
  List<RoomMember> _members = [];
  bool _isLoading = true;
  bool _isSending = false;
  StreamSubscription? _wsSubscription;
  late final NotificationProvider _notificationProvider;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadMembers();
    _listenToMessages();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _notificationProvider = context.read<NotificationProvider>();
    _notificationProvider.setActiveRoom(widget.roomId);
  }

  @override
  void dispose() {
    _notificationProvider.setActiveRoom(null);
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _wsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    try {
      _members = await ApiService.getRoomMembers(widget.roomId);
    } catch (_) {}
  }

  void _markRead() {
    if (_messages.isEmpty) return;
    final lastId = _messages.last.id;
    ApiService.markRead(widget.roomId, lastId);
  }

  int _getUnreadCount(Message message, int currentUserId) {
    if (message.senderId != currentUserId) return 0;
    int count = 0;
    for (final m in _members) {
      if (m.userId != currentUserId && m.lastReadMessageId < message.id) {
        count++;
      }
    }
    return count;
  }

  void _listenToMessages() {
    _wsSubscription =
        WebSocketService.instance.messageStream.listen((message) {
      if (message['type'] == 'new_message') {
        final payload = message['payload'];
        if (payload['room_id'] == widget.roomId) {
          final newMessage = Message.fromJson(payload);
          setState(() {
            _messages.add(newMessage);
          });
          _scrollToBottom();
          _markRead();
        }
      } else if (message['type'] == 'messages_read') {
        final payload = message['payload'];
        if (payload['room_id'] == widget.roomId) {
          final userId = payload['user_id'] as int;
          final lastReadId = payload['last_read_message_id'] as int;
          setState(() {
            for (final m in _members) {
              if (m.userId == userId && lastReadId > m.lastReadMessageId) {
                m.lastReadMessageId = lastReadId;
              }
            }
          });
        }
      }
    });
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      _messages = await ApiService.getMessages(widget.roomId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메시지를 불러오지 못했습니다')),
        );
      }
    }
    setState(() => _isLoading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
      _markRead();
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    _messageController.clear();
    setState(() => _isSending = true);

    try {
      await ApiService.sendMessage(widget.roomId, content);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메시지 전송에 실패했습니다')),
        );
        _messageController.text = content;
      }
    }

    setState(() => _isSending = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _pickAndSendFile() async {
    final picker = ImagePicker();

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_rounded,
                      color: AppTheme.primaryColor),
                ),
                title: const Text('사진 선택'),
                onTap: () => Navigator.pop(context, 'image'),
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.videocam_rounded,
                      color: Colors.orange.shade700),
                ),
                title: const Text('동영상 선택'),
                onTap: () => Navigator.pop(context, 'video'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );

    if (choice == null) return;

    XFile? file;
    if (choice == 'image') {
      file = await picker.pickImage(source: ImageSource.gallery);
    } else {
      file = await picker.pickVideo(source: ImageSource.gallery);
    }

    if (file == null) return;

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(choice == 'image' ? '사진 전송' : '동영상 전송'),
        content: Text('${file!.name}\n\n전송하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('전송'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSending = true);

    try {
      final bytes = await file.readAsBytes();
      final mimeType =
          file.mimeType ?? (choice == 'image' ? 'image/jpeg' : 'video/mp4');
      await ApiService.sendFileBytes(widget.roomId, bytes, file.name, mimeType);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('파일 전송에 실패했습니다')),
        );
      }
    }

    setState(() => _isSending = false);
  }

  Future<void> _toggleMute() async {
    final newState = await _notificationProvider.toggleMute(widget.roomId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newState ? '알림이 꺼졌습니다' : '알림이 켜졌습니다'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _leaveRoom() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('채팅방 나가기'),
        content: const Text('채팅방을 나가시겠습니까?\n모든 멤버가 나가면 대화 내용이 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('나가기'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ApiService.leaveRoom(widget.roomId);
        if (mounted) {
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('채팅방 나가기에 실패했습니다')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthProvider>().user?.id;

    return Scaffold(
      appBar: AppTheme.gradientAppBar(
        title: widget.roomName,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'leave') _leaveRoom();
              if (value == 'mute') _toggleMute();
            },
            itemBuilder: (context) {
              final isMuted = context
                  .read<NotificationProvider>()
                  .isRoomMuted(widget.roomId);
              return [
                PopupMenuItem(
                  value: 'mute',
                  child: Row(
                    children: [
                      Icon(
                        isMuted
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_off_rounded,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(isMuted ? '알림 켜기' : '알림 끄기'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'leave',
                  child: Row(
                    children: [
                      Icon(Icons.exit_to_app_rounded,
                          color: AppTheme.errorColor),
                      const SizedBox(width: 8),
                      Text('나가기',
                          style: TextStyle(color: AppTheme.errorColor)),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: Container(
        color: AppTheme.chatBackground,
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? Center(
                          child: Text('메시지가 없습니다',
                              style: TextStyle(color: AppTheme.textHint)))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final isMe = message.senderId == currentUserId;
                            final showDate = index == 0 ||
                                !_isSameDay(_messages[index - 1].createdAt,
                                    message.createdAt);

                            // 같은 시간(HH:mm) 그룹의 마지막 메시지에만 시간 표시
                            final isLastInTimeGroup = index == _messages.length - 1 ||
                                _messages[index + 1].senderId != message.senderId ||
                                !_isSameMinute(message.createdAt, _messages[index + 1].createdAt);

                            final unreadCount = _getUnreadCount(message, currentUserId ?? 0);

                            return Column(
                              children: [
                                if (showDate)
                                  Container(
                                    margin: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor
                                          .withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      DateFormat('yyyy년 M월 d일')
                                          .format(message.createdAt),
                                      style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                _buildMessageBubble(message, isMe,
                                    showTime: isLastInTimeGroup,
                                    unreadCount: unreadCount),
                              ],
                            );
                          },
                        ),
            ),
            // ─── Input Bar ───
            Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.add_rounded, size: 22),
                        onPressed: _isSending ? null : _pickAndSendFile,
                        color: AppTheme.primaryColor,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundColor,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: TextField(
                          controller: _messageController,
                          focusNode: _focusNode,
                          decoration: InputDecoration(
                            hintText: '메시지 입력...',
                            hintStyle: TextStyle(color: AppTheme.textHint),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 10),
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: _isSending ? null : AppTheme.primaryGradient,
                        color: _isSending ? AppTheme.textHint : null,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _isSending
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.send_rounded, size: 20),
                              onPressed: _sendMessage,
                              color: Colors.white,
                              padding: EdgeInsets.zero,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isSameMinute(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day &&
        a.hour == b.hour && a.minute == b.minute;
  }

  String _getAuthFileUrl(int fileId) {
    return '${ApiService.getFileUrl(fileId)}?token=${ApiService.token}';
  }

  void _showImageViewer(Message message) {
    if (message.fileId == null) return;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Stack(
        children: [
          Center(
            child: InteractiveViewer(
              child: Image.network(
                _getAuthFileUrl(message.fileId!),
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.broken_image_rounded,
                      color: Colors.white, size: 64);
                },
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 16,
            child: Row(
              children: [
                _viewerButton(
                  icon: Icons.download_rounded,
                  onTap: () => _downloadFile(message),
                ),
                const SizedBox(width: 8),
                _viewerButton(
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewerButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Future<void> _downloadFile(Message message) async {
    if (message.fileId == null) return;
    try {
      final response = await http.get(
        Uri.parse(ApiService.getFileUrl(message.fileId!)),
        headers: {'Authorization': 'Bearer ${ApiService.token}'},
      );
      if (response.statusCode == 200) {
        final contentDisposition = response.headers['content-disposition'];
        String filename = '${message.type}_${message.fileId}';
        if (contentDisposition != null &&
            contentDisposition.contains('filename=')) {
          filename = contentDisposition
              .split('filename=')
              .last
              .replaceAll('"', '');
        }
        saveFileFromBytes(response.bodyBytes, filename);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('다운로드 완료')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('다운로드에 실패했습니다')),
        );
      }
    }
  }

  Widget _buildMessageBubble(Message message, bool isMe,
      {bool showTime = true, int unreadCount = 0}) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe && message.senderName != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  message.senderName!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            // ─── Bubble Content ───
            if (message.type == 'text')
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: isMe ? AppTheme.chatBubbleGradient : null,
                  color: isMe ? null : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isMe ? AppTheme.primaryColor : Colors.black)
                          .withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  message.content ?? '',
                  style: TextStyle(
                    color: isMe ? Colors.white : AppTheme.textPrimary,
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                ),
              )
            else if (message.fileId != null && message.type == 'image')
              GestureDetector(
                onTap: () => _showImageViewer(message),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                    child: Image.network(
                      _getAuthFileUrl(message.fileId!),
                      width: 200,
                      height: 200,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          width: 200,
                          height: 200,
                          color: AppTheme.dividerColor,
                          child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 200,
                          height: 200,
                          color: AppTheme.dividerColor,
                          child: const Icon(Icons.broken_image_rounded,
                              size: 48, color: AppTheme.textHint),
                        );
                      },
                    ),
                  ),
                ),
              )
            else if (message.fileId != null)
              GestureDetector(
                onTap: () => _downloadFile(message),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: isMe ? AppTheme.chatBubbleGradient : null,
                    color: isMe ? null : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.videocam_rounded,
                    size: 40,
                    color: isMe ? Colors.white70 : AppTheme.textHint,
                  ),
                ),
              ),
            // ─── Timestamp + Read Status ───
            if (showTime || (isMe && unreadCount == 0 && _members.length > 1))
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isMe && _members.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          unreadCount > 0 ? '$unreadCount' : '읽음',
                          style: TextStyle(
                            fontSize: 10,
                            color: unreadCount > 0
                                ? AppTheme.primaryColor
                                : AppTheme.textHint,
                            fontWeight: unreadCount > 0
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    if (showTime)
                      Text(
                        DateFormat('HH:mm').format(message.createdAt),
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textHint,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
