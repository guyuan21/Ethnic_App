import 'package:app_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home page only renders camera recognition and chat actions', (
    tester,
  ) async {
    await tester.pumpWidget(const EthnicCultureApp());

    expect(find.text('民族文化识别助手'), findsOneWidget);
    expect(find.text('拍照识别'), findsOneWidget);
    expect(find.text('上传图片识别'), findsNothing);
    expect(find.text('问一问'), findsOneWidget);
    expect(find.byIcon(Icons.photo_library_outlined), findsNothing);
  });
}
