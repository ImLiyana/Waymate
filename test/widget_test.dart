import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:waymate/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const WayMateApp());
    expect(find.text('Theme is working!'), findsOneWidget);
  });
}