import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glint/glint.dart';
import 'package:glint_showcase/duck_dash.dart';

void main() {
  testWidgets('Duck Dash boots with the ready overlay and a game view', (
    tester,
  ) async {
    await tester.pumpWidget(const DuckDashApp());
    await tester.pump();
    expect(find.byType(GlintGameView), findsOneWidget);
    expect(find.text('DUCK\nDASH'), findsOneWidget);
    expect(find.text('TAP TO RUN'), findsOneWidget);
    // Unmount so the game ticker is disposed before the test ends.
    await tester.pumpWidget(const SizedBox());
  });
}
