// fix_slashes（main: fix_slashes.py）与 dat（main: dat.py）行为测试。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nscript_translate_tools/src/dat.dart';
import 'package:nscript_translate_tools/src/fix_slashes.dart';

void main() {
  group('fixMissingSlashesDetailed（main: fix_missing_slashes）', () {
    test('T: 行缺尾部 \\ 时补上', () {
      final r = fixMissingSlashesDetailed('T:abc\\\nT:def\n', 'T:xyz\nT:uvw\n');
      expect(r.output, 'T:xyz\\\nT:uvw\n');
      expect(r.warning, isNull);
    });

    test('T: 行缺尾部 / 时补上', () {
      final r = fixMissingSlashesDetailed('T:abc/\n', 'T:xyz\n');
      expect(r.output, 'T:xyz/\n');
    });

    test('译文已带尾部符号时不重复添加', () {
      final r = fixMissingSlashesDetailed('T:abc\\\n', 'T:xyz\\\n');
      expect(r.output, 'T:xyz\\\n');
    });

    test('非 T: 行不处理', () {
      final r = fixMissingSlashesDetailed('B:abc\\\nQ:abc/\n', 'B:xyz\nQ:uvw\n');
      expect(r.output, 'B:xyz\nQ:uvw\n');
    });

    test('行数不一致时按较短行数处理并给出警告', () {
      final r = fixMissingSlashesDetailed('T:a\nT:b\n', 'T:x\nT:y\nT:z\n');
      expect(r.warning, isNotNull);
      expect(r.output, 'T:x\nT:y\n');
    });

    test('输出以换行结尾（main 每行 + \\n）', () {
      final r = fixMissingSlashesDetailed('T:a\\', 'T:x');
      expect(r.output, 'T:x\\\n');
    });

    test('空输入输出为空', () {
      expect(fixMissingSlashesDetailed('', '').output, '');
    });
  });

  group('xorProcess（main: dat.py，异或 0x84）', () {
    test('逐字节异或 0x84', () {
      final out = xorProcess(Uint8List.fromList([0x00, 0x84, 0xFF, 0x41]));
      expect(out.toList(), [0x84, 0x00, 0x7B, 0xC5]);
    });

    test('加密解密互逆', () {
      final data = Uint8List.fromList(
          List<int>.generate(256, (i) => i * 7 % 256));
      expect(xorProcess(xorProcess(data)).toList(), data.toList());
    });
  });
}
