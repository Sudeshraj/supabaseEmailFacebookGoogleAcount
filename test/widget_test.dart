import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/config/environment_manager.dart'; // Add this import

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Initialize EnvironmentManager
    final env = EnvironmentManager();
    await env.init(flavor: 'test'); // or 'development'
    
    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp(env: env)); // Pass env here

    // Verify that our counter starts at 0.
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    // Tap the '+' icon and trigger a frame.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // Verify that our counter has incremented.
    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}