import 'package:flutter_test/flutter_test.dart';

import 'package:bmb_app/main.dart';

void main() {
  testWidgets('app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const BmbApp());
    expect(find.byType(BmbApp), findsOneWidget);
  });
}
