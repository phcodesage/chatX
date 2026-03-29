import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_messenger/widgets/chat_composer_shell.dart';

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    required double composerInset,
    required EdgeInsets mediaPadding,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 800),
            padding: mediaPadding,
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatComposerShell(
                composerInset: composerInset,
                backgroundColor: Colors.black,
                padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
                child: const SizedBox(
                  key: Key('composer-content'),
                  height: 40,
                  width: 200,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('respects bottom safe area when composer inset is zero', (
    tester,
  ) async {
    await pumpShell(
      tester,
      composerInset: 0,
      mediaPadding: const EdgeInsets.only(bottom: 24),
    );

    final rect = tester.getRect(find.byType(ChatComposerShell));
    expect(rect.height, 79);
  });

  testWidgets('uses composer inset when it is larger than bottom safe area', (
    tester,
  ) async {
    await pumpShell(
      tester,
      composerInset: 60,
      mediaPadding: const EdgeInsets.only(bottom: 24),
    );

    final rect = tester.getRect(find.byType(ChatComposerShell));
    expect(rect.height, 115);
  });

  testWidgets('animates to the new composer inset value', (tester) async {
    await pumpShell(
      tester,
      composerInset: 0,
      mediaPadding: const EdgeInsets.only(bottom: 24),
    );

    await pumpShell(
      tester,
      composerInset: 60,
      mediaPadding: const EdgeInsets.only(bottom: 24),
    );

    await tester.pump(const Duration(milliseconds: 240));

    final rect = tester.getRect(find.byType(ChatComposerShell));
    expect(rect.height, 115);
  });
}