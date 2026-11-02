import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foxel/core/models/account.dart';
import 'package:foxel/core/models/accounts_snapshot.dart';
import 'package:foxel/features/accounts/pages/account_center_page.dart';

Account _account(String id, String alias) {
  return Account(
    id: id,
    alias: alias,
    baseUrl: 'https://demo.foxel.cc',
    username: 'admin',
    token: 'token',
  );
}

Widget _wrap(
  ValueListenable<AccountsSnapshot> snapshot, {
  required Future<bool> Function(List<Account> accounts) onRemove,
}) {
  return MaterialApp(
    home: AccountCenterPage(
      snapshot: snapshot,
      onSwitchAccount: (_) async => true,
      onAddAccount: () {},
      onAddManually: () {},
      onAddByQr: () {},
      onEditAccount: (_) {},
      onRemoveAccounts: onRemove,
    ),
  );
}

void main() {
  testWidgets('仅一个账户时「编辑」可用并能进入多选', (WidgetTester tester) async {
    final snapshot = ValueNotifier<AccountsSnapshot>(
      AccountsSnapshot(
        accounts: <Account>[_account('acc_1', '唯一账户')],
        activeId: 'acc_1',
      ),
    );

    await tester.pumpWidget(_wrap(snapshot, onRemove: (_) async => true));
    await tester.pumpAndSettle();

    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('唯一账户'), findsOneWidget);

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    // 进入多选：出现取消 / 全选，且当前账户也可勾选
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('使用中'), findsOneWidget);
  });

  testWidgets('多选后点删除，回调收到被勾选的账户', (WidgetTester tester) async {
    final snapshot = ValueNotifier<AccountsSnapshot>(
      AccountsSnapshot(
        accounts: <Account>[_account('acc_1', '甲账户'), _account('acc_2', '乙账户')],
        activeId: 'acc_1',
      ),
    );

    List<Account>? removed;
    await tester.pumpWidget(
      _wrap(
        snapshot,
        onRemove: (accounts) async {
          removed = accounts;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('乙账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(removed?.map((account) => account.id).toList(), <String>['acc_2']);
  });

  testWidgets('全选可勾选包括当前账户在内的所有账户', (WidgetTester tester) async {
    final snapshot = ValueNotifier<AccountsSnapshot>(
      AccountsSnapshot(
        accounts: <Account>[_account('acc_1', '甲账户'), _account('acc_2', '乙账户')],
        activeId: 'acc_1',
      ),
    );

    List<Account>? removed;
    await tester.pumpWidget(
      _wrap(
        snapshot,
        onRemove: (accounts) async {
          removed = accounts;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(removed?.length, 2);
  });

  testWidgets('无账户时展示空态、不出现编辑入口', (WidgetTester tester) async {
    final snapshot = ValueNotifier<AccountsSnapshot>(AccountsSnapshot.empty);

    await tester.pumpWidget(_wrap(snapshot, onRemove: (_) async => true));
    await tester.pumpAndSettle();

    // 非根形态（从设置页进入）空态只显示一个主标题
    expect(find.text('还没有账户'), findsOneWidget);
    expect(find.text('添加账户'), findsOneWidget);
    expect(find.text('扫码添加'), findsOneWidget);
    expect(find.text('编辑'), findsNothing);
  });
}
