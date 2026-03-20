import 'package:flutter/material.dart';

import '../services/share_intent_service.dart';
import 'lobby_screen.dart';
import 'share_target_screen.dart';

/// Home page - redirects to lobby screen
class HomePage extends StatefulWidget {
  static const route = '/home';
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeNext();
    });
  }

  Future<void> _routeNext() async {
    if (!mounted || _isNavigating) {
      return;
    }
    _isNavigating = true;

    final sharedItems = await ShareIntentService.instance
        .takePendingSharedItems();
    if (!mounted) {
      return;
    }

    if (sharedItems.isNotEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ShareTargetScreen(sharedItems: sharedItems, users: const []),
        ),
      );

      if (!mounted) {
        return;
      }
    }

    Navigator.pushReplacementNamed(context, LobbyScreen.route);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
