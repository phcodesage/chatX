import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/app_text_field.dart';
import '../widgets/primary_button.dart';
import 'reset_password_page.dart';
import 'sign_in_page.dart';

/// Forgot password screen
class ForgotPasswordPage extends StatefulWidget {
  static const route = '/forgot-password';
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _userOrEmail = TextEditingController();
  final _fieldFocus = FocusNode();
  bool _isLoading = false;

  @override
  void dispose() {
    _userOrEmail.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  Future<void> _handleForgotPassword() async {
    final emailOrUsername = _userOrEmail.text.trim();

    if (emailOrUsername.isEmpty) {
      _showError('Please enter your email or username');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final message = await AuthService.forgotPassword(
        emailOrUsername: emailOrUsername,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.green),
        );

        // Continue directly to the token entry step after sending reset email.
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.pushReplacementNamed(context, ResetPasswordPage.route);
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
      title: 'Forgot Password',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            label: 'Email or Username',
            controller: _userOrEmail,
            focusNode: _fieldFocus,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!_isLoading) {
                FocusScope.of(context).unfocus(); // Hide keyboard
                _handleForgotPassword();
              }
            },
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            text: _isLoading ? 'Sending…' : 'Send Reset Email',
            onPressed: _isLoading ? null : _handleForgotPassword,
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pushReplacementNamed(
                context,
                ResetPasswordPage.route,
              ),
              child: const Text(
                'I already have a reset token',
                style: TextStyle(color: Color(0xFF00E5FF)),
              ),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () =>
                  Navigator.pushReplacementNamed(context, SignInPage.route),
              child: const Text(
                'Back to sign in',
                style: TextStyle(color: Color(0xFF00E5FF)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
