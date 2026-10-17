import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_ai/src/app.dart';

void main() {
  testWidgets('App opens with four main sections', (tester) async {
    await tester.pumpWidget(const MyAiApp());
    expect(find.text('МОЙ ИИ'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Агенты'), findsOneWidget);
  });
}
