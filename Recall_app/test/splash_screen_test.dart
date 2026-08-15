import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/widgets/splash_screen.dart';

void main() {
  testWidgets('normal splash is removed after its 2.4 second timeline', (
    tester,
  ) async {
    await tester.pumpWidget(_app(disableAnimations: false));
    expect(find.byType(SplashScreen), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2399));
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2));

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.text('主页内容'), findsOneWidget);
  });

  testWidgets('reduce motion uses the shortened fade-only timeline', (
    tester,
  ) async {
    await tester.pumpWidget(_app(disableAnimations: true));
    expect(find.byType(SplashScreen), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 899));
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2));

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.text('主页内容'), findsOneWidget);
  });
}

Widget _app({required bool disableAnimations}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: const SplashGate(
      child: Scaffold(body: Center(child: Text('主页内容'))),
    ),
  ),
);
