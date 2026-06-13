import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mlkit_pose/main.dart';

void main() {
  testWidgets('앱이 정상적으로 빌드되고 하단 탭이 보인다', (tester) async {
    await tester.pumpWidget(const PostureCareApp());
    expect(find.text('실시간'), findsOneWidget);
    expect(find.text('리포트'), findsOneWidget);
  });
}
