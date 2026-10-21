import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/app.dart';

void main() {
  testWidgets('Offline 2FA smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: Offline2faApp()));

    expect(find.text('Offline 2FA'), findsOneWidget);
  });
}
