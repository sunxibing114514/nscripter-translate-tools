/// 移植自 dat.py 的逻辑：nscript.dat / nscript.txt 的 XOR 加密与解密。
///
/// 加密与解密使用同一个函数（异或 0x84）。
library;

import 'dart:typed_data';

const int xorKey = 0x84; // 异或密钥

/// 逐字节异或 [xorKey] 后返回。既是解封包也是封包。
Uint8List xorProcess(Uint8List bytes) {
  final out = Uint8List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    out[i] = bytes[i] ^ xorKey;
  }
  return out;
}