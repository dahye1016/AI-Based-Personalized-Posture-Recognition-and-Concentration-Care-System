import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mlkit_pose/main.dart';

void main() {
  testWidgets('앱이 온보딩 화면으로 시작한다', (tester) async {
    await tester.pumpWidget(const PostureCareApp());
    expect(find.text('시작하기'), findsOneWidget);
    expect(find.text('실시간 자세 알림'), findsOneWidget);
  });

  testWidgets('메인 탭 4개가 보인다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RootNav()));
    await tester.pump();
    expect(find.text('실시간'), findsOneWidget);
    expect(find.text('리포트'), findsOneWidget);
    expect(find.text('챌린지'), findsOneWidget);
    expect(find.text('스트레칭'), findsWidgets);
  });
}
