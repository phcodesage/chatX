import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/firebase_messaging_service.dart';
import '../services/fcm_service.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/app_text_field.dart';
import '../widgets/password_field.dart';
import '../widgets/primary_button.dart';
import 'sign_in_page.dart';
import 'lobby_screen.dart';

/// Registration screen
class RegisterPage extends StatefulWidget {
  static const route = '/register';
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  // Focus nodes for keyboard tab-through on desktop.
  final _firstFocus = FocusNode();
  final _lastFocus = FocusNode();
  final _usernameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _isLoading = false;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _firstFocus.dispose();
    _lastFocus.dispose();
    _usernameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    final firstName = _first.text.trim();
    final lastName = _last.text.trim();
    final username = _username.text.trim();
    final email = _email.text.trim();
    final password = _password.text.trim();
    final confirm = _confirm.text.trim();

    if (firstName.isEmpty ||
        username.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      _showError('Please fill in all required fields');
      return;
    }

    if (password != confirm) {
      _showError('Passwords do not match');
      return;
    }

    if (password.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await AuthService.register(
        username: username,
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName.isNotEmpty ? lastName : null,
      );

      // Send FCM token to backend after successful registration.
      final fcmToken = FirebaseMessagingService.instance.fcmToken;
      if (fcmToken != null) {
        await FCMService.updateFCMToken(fcmToken);
      }

      if (mounted) {
        Navigator.pushReplacementNamed(context, LobbyScreen.route);
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
    final isWide = MediaQuery.sizeOf(context).width >= 600;

    return AuthScaffold(
      title: 'Create your account',
      child: Column(
        children: [
          // On wide screens, show First / Last name side by side.
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'First Name',
                    controller: _first,
                    focusNode: _firstFocus,
                    nextFocusNode: _lastFocus,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AppTextField(
                    label: 'Last Name',
                    controller: _last,
                    focusNode: _lastFocus,
                    nextFocusNode: _usernameFocus,
                  ),
                ),
              ],
            )
          else ...[
            AppTextField(
              label: 'First Name',
              controller: _first,
              focusNode: _firstFocus,
              nextFocusNode: _lastFocus,
            ),
            const SizedBox(height: 10),
            AppTextField(
              label: 'Last Name',
              controller: _last,
              focusNode: _lastFocus,
              nextFocusNode: _usernameFocus,
            ),
          ],
          const SizedBox(height: 14),
          AppTextField(
            label: 'Username',
            controller: _username,
            focusNode: _usernameFocus,
            nextFocusNode: _emailFocus,
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'Email',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            focusNode: _emailFocus,
            nextFocusNode: _passwordFocus,
          ),
          const SizedBox(height: 14),
          // On wide screens, show Password / Confirm side by side.
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: PasswordField(
                    label: 'Password',
                    controller: _password,
                    focusNode: _passwordFocus,
                    nextFocusNode: _confirmFocus,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: PasswordField(
                    label: 'Confirm Password',
                    controller: _confirm,
                    focusNode: _confirmFocus,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_isLoading) {
                        FocusScope.of(context).unfocus(); // Hide keyboard
                        _handleRegister();
                      }
                    },
                  ),
                ),
              ],
            )
          else ...[
            PasswordField(
              label: 'Password',
              controller: _password,
              focusNode: _passwordFocus,
              nextFocusNode: _confirmFocus,
            ),
            const SizedBox(height: 14),
            PasswordField(
              label: 'Confirm Password',
              controller: _confirm,
              focusNode: _confirmFocus,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_isLoading) {
                  FocusScope.of(context).unfocus(); // Hide keyboard
                  _handleRegister();
                }
              },
            ),
          ],
          const SizedBox(height: 20),
          PrimaryButton(
            text: _isLoading ? 'Creating account…' : 'Register',
            onPressed: _isLoading ? null : _handleRegister,
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Already have an account?',
                style: TextStyle(color: Colors.white70),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, SignInPage.route),
                child: const Text(
                  'Sign in',
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
