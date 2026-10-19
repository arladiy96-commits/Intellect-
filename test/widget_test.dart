import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_ai/src/app.dart';

void main() {
  testWidgets('Baboon shows new shell and the approved navigation', (tester) async {
    await tester.pumpWidget(const MyAiApp());
    expect(find.text('БАБУИН'), findsWidgets);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('Главная'), findsWidgets);
    expect(find.text('Чат'), findsWidgets);
    expect(find.text('Инструменты'), findsWidgets);
    expect(find.text('Знания'), findsWidgets);
    expect(find.text('Настройки'), findsWidgets);
  });
}
