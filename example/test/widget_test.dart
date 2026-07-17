import 'package:flutter_test/flutter_test.dart';
import 'package:glint/glint.dart';
import 'package:glint_showcase/main.dart';

void main() {
  testWidgets('showcase embeds Glint First Light', (tester) async {
    await tester.pumpWidget(const GlintShowcase());
    expect(find.byType(GlintGpuFirstLight), findsOneWidget);
    expect(find.text('3D belongs in the widget tree.'), findsOneWidget);
  });
}
