import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../services/firebase_messaging_service.dart';
import '../services/fcm_service.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/app_text_field.dart';
import '../widgets/password_field.dart';
import '../widgets/primary_button.dart';
import 'register_page.dart';
import 'forgot_password_page.dart';
import 'home_page.dart';

/// Sign in screen
class SignInPage extends StatefulWidget {
  static const route = '/sign-in';
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool remember = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
  }

  Future<void> _loadRememberedCredentials() async {
    final creds = await StorageService.getRememberedCredentials();
    if (creds != null && mounted) {
      setState(() {
        _username.text = creds['username'] ?? '';
        _password.text = creds['password'] ?? '';
        remember = true;
      });
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    final username = _username.text.trim();
    final password = _password.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showError('Please enter username and password');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await AuthService.login(username: username, password: password);
      
      // Save or clear remembered credentials based on checkbox
      if (remember) {
        await StorageService.saveRememberedCredentials(username, password);
      } else {
        await StorageService.clearRememberedCredentials();
      }
      
      // Send FCM token to backend after successful login
      final fcmToken = FirebaseMessagingService.instance.fcmToken;
      if (fcmToken != null) {
        await FCMService.updateFCMToken(fcmToken);
      }
      
      if (mounted) {
        // Navigate to home screen
        Navigator.pushReplacementNamed(context, HomePage.route);
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
      title: 'Sign in',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(label: 'Username', controller: _username),
          const SizedBox(height: 18),
          PasswordField(label: 'Password', controller: _password),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pushNamed(context, ForgotPasswordPage.route),
              child: const Text('Forgot password?', style: TextStyle(color: Color(0xFF00E5FF))),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: remember,
                onChanged: (v) => setState(() => remember = v ?? false),
                checkColor: Colors.white,
                activeColor: const Color(0xFF00E5FF),
                side: const BorderSide(color: Colors.white70),
              ),
              const Text('Remember Me', style: TextStyle(color: Colors.white)),
            ],
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            text: 'Sign In',
            onPressed: _isLoading ? null : _handleSignIn,
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Don't have an account? ", style: TextStyle(color: Colors.white70)),
              TextButton(
                onPressed: () => Navigator.pushReplacementNamed(context, RegisterPage.route),
                child: const Text('Create one', style: TextStyle(color: Color(0xFF00E5FF))),
              ),
            ],
          )
        ],
      ),
    );
  }
}
