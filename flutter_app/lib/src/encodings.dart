import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' as charset;

/// 支持的编码列表（用于 UI 下拉选择）。
const List<String> supportedEncodings = [
  'utf8',
  'shift_jis',
  'gbk',
  'euc_jp',
  'latin1',
  'utf16',
];

/// 根据名称解析为 [Encoding]，支持 utf8/latin1/ascii 及 charset 包中的
/// shift_jis、gbk、euc-jp 等。
Encoding resolveEncoding(String name) {
  final n = name.trim().toLowerCase();
  switch (n) {
    case 'utf8':
    case 'utf-8':
      return utf8;
    case 'latin1':
    case 'latin-1':
    case 'iso-8859-1':
      return latin1;
    case 'ascii':
      return ascii;
    case 'utf16':
    case 'utf-16':
      return charset.utf16;
  }

  final cs = charset.Charset.getByName(n) ??
      charset.Charset.getByName(_normalize(n));
  if (cs != null) return cs;
  return utf8;
}

String _normalize(String n) => n.replaceAll('-', '_').toLowerCase();

/// 表驱动编码（shift_jis / gbk / euc_jp）。
/// 这些编码器对无法表示的字符不会抛错，而是静默写入替代字节
/// （如 0xEF 0xBF 0xBD），生成乱码脚本；解码器则支持
/// [allowMalformed]，坏字节只损失该字符而不是整文件失败。
Encoding? _resolveTableCodec(String name, {required bool allowMalformed}) {
  final n = _normalize(name).replaceAll('_', '');
  switch (n) {
    case 'shiftjis':
    case 'sjis':
      return charset.ShiftJISCodec(allowMalformed: allowMalformed);
    case 'gbk':
    case 'gb2312':
    case 'cp936':
      return charset.GbkCodec(allowMalformed: allowMalformed);
    case 'eucjp':
      return charset.EucJPCodec(allowMalformed);
  }
  return null;
}

bool _isTableEncoding(String name) =>
    _resolveTableCodec(name, allowMalformed: false) != null;

/// 将字符串编码为目标编码的字节。
///
/// 表驱动编码在字符无法表示时会静默写入替代字节（乱码）；
/// main（Python）编码失败会直接抛错中止。这里通过「编码→解码」
/// 往返校验等价地暴露问题，避免静默损坏游戏脚本。
Uint8List encodeString(String s, String enc) {
  final bytes = Uint8List.fromList(resolveEncoding(enc).encode(s));
  if (_isTableEncoding(enc)) {
    String back;
    try {
      back = decodeBytes(bytes, enc);
    } catch (_) {
      throw FormatException(
          '输出编码 $enc 无法表示译文中部分字符（编码校验失败），已中止以避免生成乱码文件；'
          '可改用 utf8 等输出编码，或修正对应译文后重试');
    }
    if (back != s) {
      throw FormatException(
          '输出编码 $enc 无法表示译文中部分字符（往返校验不一致），已中止以避免生成乱码文件；'
          '可改用 utf8 等输出编码，或修正对应译文后重试');
    }
  }
  return bytes;
}

/// 使用指定编码解码字节。
///
/// 表驱动编码使用 allowMalformed 解码：单个坏字节只被替换为 �，
/// 其余内容正常解码；避免原实现一旦遇到坏字节就整文件回退
/// latin1 造成全文乱码。最后仍失败才回退 latin1（宽容解码）。
String decodeBytes(Uint8List bytes, String enc) {
  final tolerant = _resolveTableCodec(enc, allowMalformed: true);
  if (tolerant != null) {
    try {
      return tolerant.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }
  try {
    return resolveEncoding(enc).decode(bytes);
  } catch (_) {
    return latin1.decode(bytes, allowInvalid: true);
  }
}
