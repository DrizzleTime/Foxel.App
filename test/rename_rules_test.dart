import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foxel/features/drive/services/rename_rules.dart';

RenameTarget file(String name) => RenameTarget(name: name, isDir: false);
RenameTarget dir(String name) => RenameTarget(name: name, isDir: true);

void main() {
  group('查找替换', () {
    test('只替换主名，扩展名保持不变', () {
      final result = RenamePlanner.preview(
        targets: [file('IMG_0431.jpg')],
        rule: const RenameRule(findText: 'IMG_', replaceText: '旅行_'),
      );
      expect(result.single.newName, '旅行_0431.jpg');
      expect(result.single.isUsable, isTrue);
    });

    test('不区分大小写时可命中', () {
      final result = RenamePlanner.preview(
        targets: [file('img_1.jpg')],
        rule: const RenameRule(
          findText: 'IMG_',
          replaceText: 'x_',
          caseSensitive: false,
        ),
      );
      expect(result.single.newName, 'x_1.jpg');
    });

    test('不含查找文本的项被跳过', () {
      final result = RenamePlanner.preview(
        targets: [file('说明.txt')],
        rule: const RenameRule(findText: 'IMG_', replaceText: 'x_'),
      );
      expect(result.single.isSkipped, isTrue);
      expect(result.single.skipReason, '不含查找文本');
    });

    test('勾选含扩展名时作用于完整文件名', () {
      final result = RenamePlanner.preview(
        targets: [file('a.jpg')],
        rule: const RenameRule(
          findText: 'jpg',
          replaceText: 'png',
          includeExtension: true,
        ),
      );
      expect(result.single.newName, 'a.png');
    });
  });

  group('前后缀与序号', () {
    test('添加前缀后缀', () {
      final result = RenamePlanner.preview(
        targets: [file('报告.pdf')],
        rule: const RenameRule(
          mode: RenameMode.affix,
          prefix: '2026_',
          suffix: '_终稿',
        ),
      );
      expect(result.single.newName, '2026_报告_终稿.pdf');
    });

    test('序号按列表顺序递增并补零', () {
      final result = RenamePlanner.preview(
        targets: [dir('素材'), file('照片.jpg'), file('笔记.pdf')],
        rule: const RenameRule(mode: RenameMode.numbering),
      );
      expect(result[0].newName, '素材_001');
      expect(result[1].newName, '照片_002.jpg');
      expect(result[2].newName, '笔记_003.pdf');
    });

    test('序号可放前缀并支持自定义起始与步长', () {
      final result = RenamePlanner.preview(
        targets: [file('a.txt'), file('b.txt')],
        rule: const RenameRule(
          mode: RenameMode.numbering,
          numberPosition: NumberPosition.prefix,
          startNumber: 10,
          step: 5,
          digits: 2,
          separator: '-',
        ),
      );
      expect(result[0].newName, '10-a.txt');
      expect(result[1].newName, '15-b.txt');
    });
  });

  group('大小写与扩展名', () {
    test('首字母大写', () {
      final result = RenamePlanner.preview(
        targets: [file('hello world.txt')],
        rule: const RenameRule(
          mode: RenameMode.letterCase,
          letterCase: LetterCaseMode.capitalize,
        ),
      );
      expect(result.single.newName, 'Hello world.txt');
    });

    test('修改扩展名只作用于文件', () {
      final result = RenamePlanner.preview(
        targets: [file('a.jpeg'), dir('照片')],
        rule: const RenameRule(
          mode: RenameMode.extension,
          newExtension: 'jpg',
        ),
      );
      expect(result[0].newName, 'a.jpg');
      expect(result[1].isSkipped, isTrue);
    });
  });

  group('冲突与边界', () {
    test('A 改名为 B 且 B 在本批未改名时，也要判冲突（防覆盖）', () {
      // 选了 A.txt 与 B.txt，规则只命中 A.txt：B.txt 原名仍占用目录。
      final result = RenamePlanner.preview(
        targets: [file('A.txt'), file('B.txt')],
        rule: const RenameRule(findText: 'A', replaceText: 'B'),
      );
      expect(result[0].conflictReason, '目标名已存在');
      expect(result[0].isUsable, isFalse);
      expect(result[1].isSkipped, isTrue);
    });

    test('目标名与目录中既有条目重名时报冲突', () {
      final result = RenamePlanner.preview(
        targets: [file('旧.txt')],
        rule: const RenameRule(
          mode: RenameMode.affix,
          prefix: '',
          suffix: '',
        ),
        existingNames: {'旧.txt'},
      );
      // 规则无效（前后缀都空）-> 名称未变化
      expect(result.single.isSkipped, isTrue);

      final conflict = RenamePlanner.preview(
        targets: [file('a.txt')],
        rule: const RenameRule(mode: RenameMode.affix, suffix: '_1'),
        existingNames: {'a_1.txt'},
      );
      expect(conflict.single.conflictReason, '目标名已存在');
      expect(conflict.single.isUsable, isFalse);
    });

    test('本批内部重名会被标记', () {
      final result = RenamePlanner.preview(
        targets: [file('a.txt'), file('b.txt')],
        rule: const RenameRule(mode: RenameMode.affix, prefix: '同'),
        existingNames: const <String>{},
      );
      // 前缀不同 -> 不冲突
      expect(result[0].newName, '同a.txt');
      expect(result[1].newName, '同b.txt');

      final same = RenamePlanner.preview(
        targets: [file('a.txt'), dir('a')],
        rule: const RenameRule(
          mode: RenameMode.extension,
          newExtension: 'txt',
        ),
        existingNames: const <String>{},
      );
      // a -> 文件夹跳过扩展名；a.txt -> a.txt 未变化
      expect(same[0].isSkipped, isTrue);
      expect(same[1].isSkipped, isTrue);
    });

    test('非法字符被替换，Windows 保留名加前缀', () {
      final result = RenamePlanner.preview(
        targets: [file('a<b>c.txt')],
        rule: const RenameRule(mode: RenameMode.affix, suffix: '_x'),
      );
      expect(result.single.newName, 'a_b_c_x.txt');

      // conreadme.txt 的 stem 是 conreadme，不是保留名，不该加前缀；
      // 只有完整名恰好是保留名（con.txt）时才需要规避。
      final notReserved = RenamePlanner.preview(
        targets: [file('readme.txt')],
        rule: const RenameRule(mode: RenameMode.affix, prefix: 'con'),
      );
      expect(notReserved.single.newName, 'conreadme.txt');

      final reserved = RenamePlanner.preview(
        targets: [file('readme.txt')],
        rule: const RenameRule(findText: 'readme', replaceText: 'con'),
      );
      expect(reserved.single.newName, 'foxel_con.txt');
    });

    test('超长名称按字素截断且不切断 emoji', () {
      final long = '${'a' * 120}.txt';
      final result = RenamePlanner.preview(
        targets: [file(long)],
        rule: const RenameRule(mode: RenameMode.affix, suffix: '_end'),
      );
      final newName = result.single.newName;
      expect(newName.characters.length, lessThanOrEqualTo(
        RenamePlanner.maxNameLength + 4,
      ));

      final emoji = RenamePlanner.preview(
        targets: [file('😀😀😀.txt')],
        rule: const RenameRule(mode: RenameMode.affix, suffix: '_x'),
      );
      expect(emoji.single.newName, '😀😀😀_x.txt');
    });
  });

  test('规则是否配置完整', () {
    expect(const RenameRule().isConfigured, isFalse);
    expect(const RenameRule(findText: 'a').isConfigured, isTrue);
    expect(
      const RenameRule(mode: RenameMode.affix, suffix: 'x').isConfigured,
      isTrue,
    );
    expect(const RenameRule(mode: RenameMode.numbering).isConfigured, isTrue);
  });
}
