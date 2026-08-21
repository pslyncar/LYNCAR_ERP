import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papezzosync_admin/screens/login_screen.dart';

void main() {
  testWidgets('shows login screen', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: LoginScreen(onLogin: (_) {})));

    expect(find.text('Bem-vindo'), findsOneWidget);
    expect(find.text('Acesse sua operação LYNCAR'), findsOneWidget);
    expect(find.text('Usuário'), findsOneWidget);
    expect(find.text('Senha'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });
}
