import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foxel/main.dart';

void main() {
  testWidgets('无账户时展示账户管理页空态', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const FoxelDriveApp());
    await tester.pump();
    await tester.pump();

    // 空态标题与副标题
    expect(find.text('账户'), findsOneWidget);
    expect(find.text('还没有账户'), findsNWidgets(2));
    expect(find.textContaining('添加第一个 Foxel 服务器'), findsOneWidget);

    // 空态两个入口
    expect(find.text('添加账户'), findsOneWidget);
    expect(find.text('扫码添加'), findsOneWidget);

    // 无账户时不显示底部导航（文件 / 传输 / 设置）
    expect(find.text('文件'), findsNothing);
    expect(find.text('传输'), findsNothing);
    expect(find.text('设置'), findsNothing);
  });
}
