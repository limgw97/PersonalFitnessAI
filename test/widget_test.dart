import 'package:fitmind/main.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('앱이 실행되고 첫 화면이 표시된다', (tester) async {
    // 테스트 환경에는 Android Keystore가 없으므로 가짜 저장소 사용
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(const FitMindApp());
    await tester.pumpAndSettle();

    expect(find.text('로그인 안 됨'), findsOneWidget);
  });
}
