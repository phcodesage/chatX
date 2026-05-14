import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/app_text_field.dart';
import '../widgets/password_field.dart';
import '../widgets/primary_button.dart';
import 'forgot_password_page.dart';
import 'sign_in_page.dart';

/// Reset password screen
class ResetPasswordPage extends StatefulWidget {
  static const route = '/reset-password';
  final String? initialToken;

  const ResetPasswordPage({super.key, this.initialToken});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _token = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  final _tokenFocus = FocusNode();
  final _newPasswordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialToken != null) {
      _token.text = widget.initialToken!;
    }
  }

  @override
  void dispose() {
    _token.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    _tokenFocus.dispose();
    _newPasswordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    // Strip accidental whitespace from pasted token while preserving all symbols.
    final token = _token.text.replaceAll(RegExp(r'\s+'), '');
    final newPassword = _newPassword.text.trim();
    final confirmPassword = _confirmPassword.text.trim();

    if (token.isEmpty) {
      _showError('Please paste the reset token from your email');
      return;
    }

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      _showError('Please enter and confirm your new password');
      return;
    }

    if (newPassword != confirmPassword) {
      _showError('Passwords do not match');
      return;
    }

    if (newPassword.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final message = await AuthService.resetPassword(
        token: token,
        newPassword: newPassword,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.green),
        );

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.pushReplacementNamed(context, SignInPage.route);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        _showError(e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Reset Password',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paste the full token from your email exactly as shown (including dots).',
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Reset Token',
            controller: _token,
            focusNode: _tokenFocus,
            nextFocusNode: _newPasswordFocus,
          ),
          const SizedBox(height: 14),
          PasswordField(
            label: 'New Password',
            controller: _newPassword,
            focusNode: _newPasswordFocus,
            nextFocusNode: _confirmPasswordFocus,
          ),
          const SizedBox(height: 14),
          PasswordField(
            label: 'Confirm New Password',
            controller: _confirmPassword,
            focusNode: _confirmPasswordFocus,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!_isLoading) {
                FocusScope.of(context).unfocus(); // Hide keyboard
                _handleResetPassword();
              }
            },
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            text: _isLoading ? 'Resetting…' : 'Reset Password',
            onPressed: _isLoading ? null : _handleResetPassword,
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => Navigator.pushReplacementNamed(
                  context,
                  ForgotPasswordPage.route,
                ),
                child: const Text(
                  'Get a new token',
                  style: TextStyle(color: Color(0xFF00E5FF)),
                ),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, SignInPage.route),
                child: const Text(
                  'Back to sign in',
                  style: TextStyle(color: Color(0xFF00E5FF)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
