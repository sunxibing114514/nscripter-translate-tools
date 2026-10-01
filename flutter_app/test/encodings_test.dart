// 编码处理测试：表驱动编码（shift_jis/gbk）的宽容解码与有损编码防护。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nscript_translate_tools/src/encodings.dart';

void main() {
  group('decodeBytes / encodeString 基础', () {
    test('utf8 往返', () {
      const s = 'こんにちは世界';
      final bytes = encodeString(s, 'utf8');
      expect(decodeBytes(bytes, 'utf8'), s);
    });

    test('shift_jis 解码常见日文（あ = 0x82A0）', () {
      final decoded = decodeBytes(
          Uint8List.fromList([0x82, 0xA0, 0x82, 0xA2]), 'shift_jis');
      expect(decoded, 'あい');
    });

    test('shift_jis 编解码往返（日文可表示）', () {
      const s = 'これはテストです。';
      final bytes = encodeString(s, 'shift_jis');
      expect(decodeBytes(bytes, 'shift_jis'), s);
    });

    test('gbk 编解码往返（中文可表示）', () {
      const s = '中文测试你好世界';
      final bytes = encodeString(s, 'gbk');
      expect(decodeBytes(bytes, 'gbk'), s);
    });
  });

  group('宽容解码（表驱动编码坏字节只损失该字符）', () {
    test('shift_jis 未定义字节 0x80 替换为 �，其余正常', () {
      final decoded = decodeBytes(
          Uint8List.fromList([0x82, 0xA0, 0x80, 0x82, 0xA2]), 'shift_jis');
      expect(decoded, 'あ\uFFFDい');
    });

    test('gbk 坏字节同样宽容处理', () {
      // 0x80 是 GBK 的无效首字节（会与下一字节组成无效对被替换），
      // 随后的 0xD6D0(中) 0xCEC4(文) 正常解码。
      final decoded = decodeBytes(
          Uint8List.fromList([0x80, 0x80, 0xD6, 0xD0, 0xCE, 0xC4]), 'gbk');
      expect(decoded, contains('\uFFFD'));
      expect(decoded, contains('中文'));
    });

    test('utf8 坏字节回退 latin1（原行为兜底）', () {
      final decoded = decodeBytes(
          Uint8List.fromList([0xE3, 0x81, 0xFF]), 'utf8');
      // 不会抛错
      expect(decoded, isNotNull);
    });
  });

  group('有损编码防护（main 的 Python 编码失败会抛错中止）', () {
    test('shift_jis 无法表示的文字（如韩文）报错而非静默写乱码', () {
      // Python：'한국어'.encode('shift_jis') → UnicodeEncodeError。
      // （注：中文「中文」二字在 JIS 汉字集中，shift_jis 可以表示，故不作为用例）
      expect(() => encodeString('한국어', 'shift_jis'), throwsFormatException);
    });

    test('gbk 能表示中文，不报错', () {
      expect(() => encodeString('中文', 'gbk'), returnsNormally);
    });

    test('utf8 永不报错', () {
      expect(() => encodeString('中文あい', 'utf8'), returnsNormally);
    });
  });
}
