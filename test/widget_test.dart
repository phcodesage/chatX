import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_messenger/main.dart';
import 'package:flutter_messenger/screens/sign_in_page.dart';

void main() {
  testWidgets('Loads Sign in screen', (tester) async {
    await tester.pumpWidget(const MessengerApp(initialHome: SignInPage()));
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
