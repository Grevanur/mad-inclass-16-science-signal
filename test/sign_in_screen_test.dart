import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inclass_16/screens/auth_gate.dart';

void main() {
  testWidgets('sign-in screen explains cloud identity and hides password', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));

    expect(find.text('Trust the evidence.'), findsOneWidget);
    expect(find.byKey(const Key('emailField')), findsOneWidget);
    final password = tester.widget<TextField>(
      find.byKey(const Key('passwordField')),
    );
    expect(password.obscureText, isTrue);
    expect(find.byKey(const Key('signInButton')), findsOneWidget);
  });
}
