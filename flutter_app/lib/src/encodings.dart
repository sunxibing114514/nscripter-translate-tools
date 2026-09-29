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

/// 将字符串编码为目标编码的字节。
Uint8List encodeString(String s, String enc) {
  final bytes = resolveEncoding(enc).encode(s);
  return Uint8List.fromList(bytes);
}

/// 使用指定编码解码字节；失败时回退到 latin1（宽容解码）。
String decodeBytes(Uint8List bytes, String enc) {
  try {
    return resolveEncoding(enc).decode(bytes);
  } catch (_) {
    return latin1.decode(bytes, allowInvalid: true);
  }
}