// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:worker_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Mock path_provider method channel to avoid iOS/macOS-only APIs
    const MethodChannel('plugins.flutter.io/path_provider')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return '/tmp/test_documents';
      }
      if (methodCall.method == 'getApplicationSupportDirectory') {
        return '/tmp/test_support';
      }
      if (methodCall.method == 'getLibraryDirectory') {
        return '/tmp/test_library';
      }
      if (methodCall.method == 'getTemporaryDirectory') {
        return '/tmp/test_temp';
      }
      return null;
    });
  });

  tearDown(() {
    // Clean up mock
    const MethodChannel('plugins.flutter.io/path_provider')
        .setMockMethodCallHandler(null);
  });

  testWidgets('Whisper Orchard Node app loads', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Pump a few frames to allow initial build
    await tester.pump();

    // Verify that the app title is displayed.
    expect(find.text('Whisper Orchard Node'), findsOneWidget);

    // Verify that both tabs are present.
    expect(find.text('ダッシュボード'), findsOneWidget);
    expect(find.text('モデル管理'), findsOneWidget);
  });
}
