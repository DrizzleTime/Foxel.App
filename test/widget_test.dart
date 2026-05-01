import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foxel/main.dart';

void main() {
  testWidgets('shows settings page before login', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const FoxelDriveApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Foxel 设置'), findsOneWidget);
    expect(find.text('连接后端'), findsOneWidget);
    expect(find.text('后端地址'), findsOneWidget);
    expect(find.text('账号'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
  });
}
