import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../config/theme.dart';

class SmsVerifyScreen extends StatefulWidget {
  final String phone;

  const SmsVerifyScreen({super.key, required this.phone});

  @override
  State<SmsVerifyScreen> createState() => _SmsVerifyScreenState();
}

class _SmsVerifyScreenState extends State<SmsVerifyScreen> {
  final _codeController = TextEditingController();
  int _remainingSeconds = 180;
  Timer? _timer;
  bool _codeSent = false;

  @override
  void initState() {
    super.initState();
    _sendCode();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final auth = context.read<AuthProvider>();
    final success = await auth.sendCode(widget.phone);

    if (success) {
      setState(() {
        _codeSent = true;
        _remainingSeconds = 180;
      });
      _startTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('인증코드가 발송되었습니다')),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? '인증코드 발송에 실패했습니다')),
      );
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _verifyCode() async {
    if (_codeController.text.trim().length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('6자리 인증코드를 입력하세요')),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final success = await auth.verifyCode(
      widget.phone,
      _codeController.text.trim(),
    );

    if (success && mounted) {
      Navigator.pop(context, true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? '인증에 실패했습니다')),
      );
    }
  }

  String get _formattedTime {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTheme.gradientAppBar(title: '휴대폰 인증'),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.primaryColor.withOpacity(0.12),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.sms_outlined,
                    size: 40,
                    color: AppTheme.primaryColor.withOpacity(0.7),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${widget.phone}로\n인증코드를 발송했습니다',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '개발 모드: 백엔드 콘솔에서 인증코드 확인',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 12,
                color: AppTheme.textPrimary,
              ),
              decoration: InputDecoration(
                labelText: '인증코드 6자리',
                counterText: '',
                suffixText: _formattedTime,
                suffixStyle: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w600,
                  color: _remainingSeconds < 60
                      ? AppTheme.errorColor
                      : AppTheme.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Consumer<AuthProvider>(
              builder: (context, auth, _) {
                return ElevatedButton(
                  onPressed:
                      auth.isLoading || _remainingSeconds == 0 ? null : _verifyCode,
                  child: auth.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('인증하기'),
                );
              },
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _remainingSeconds == 0 ? _sendCode : null,
              child: Text(
                _remainingSeconds == 0 ? '인증코드 재발송' : '인증코드를 받지 못하셨나요?',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
