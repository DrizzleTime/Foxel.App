import 'package:flutter_test/flutter_test.dart';

import 'package:foxel/core/storage/download_dir_store.dart';

void main() {
  group('DownloadDirStore.sanitizeFileSegment', () {
    test('正常文件名原样保留（含中文与空格）', () {
      expect(DownloadDirStore.sanitizeFileSegment('report.pdf'), 'report.pdf');
      expect(DownloadDirStore.sanitizeFileSegment('旅行 照片.jpg'), '旅行 照片.jpg');
    });

    test('挡掉路径穿越：. 与 .. 及其变体一律判为不可用', () {
      expect(DownloadDirStore.sanitizeFileSegment('.'), '');
      expect(DownloadDirStore.sanitizeFileSegment('..'), '');
      expect(DownloadDirStore.sanitizeFileSegment('...'), '');
      expect(DownloadDirStore.sanitizeFileSegment('   '), '');
      expect(DownloadDirStore.sanitizeFileSegment(''), '');
    });

    test('斜杠与非法字符替换为下划线，不会残留目录分隔', () {
      // "../etc/passwd" 里的 "/" 全部被替换，前导 ".." 再去掉
      expect(
        DownloadDirStore.sanitizeFileSegment('../etc/passwd'),
        '_etc_passwd',
      );
      expect(DownloadDirStore.sanitizeFileSegment('a:b*c?.txt'), 'a_b_c_.txt');
      expect(DownloadDirStore.sanitizeFileSegment('a\\b.txt'), 'a_b.txt');
    });

    test('Windows 保留设备名加前缀', () {
      expect(DownloadDirStore.sanitizeFileSegment('CON.txt'), 'foxel_CON.txt');
      expect(DownloadDirStore.sanitizeFileSegment('nul'), 'foxel_nul');
      expect(DownloadDirStore.sanitizeFileSegment('com1.log'), 'foxel_com1.log');
    });

    test('长文件名不截断（截断会造成同名覆盖）', () {
      final longName = '${'a' * 80}.txt';
      expect(DownloadDirStore.sanitizeFileSegment(longName), longName);
    });
  });
}
