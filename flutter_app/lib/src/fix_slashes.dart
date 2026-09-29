/// 移植自 fix_slashes.py 的逻辑。
///
/// 根据原文中的尾部斜杠，修复翻译文件中缺失的 `\` 或 `/` 符号。
/// 原文与译文按行一一对应，仅处理以 `T:` 开头的文本行。
library;

String fixMissingSlashes(String origContent, String transContent) {
  List<String> origLines =
      origContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  List<String> transLines = transContent
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');

  if (origLines.length != transLines.length) {
    final minLen = origLines.length < transLines.length
        ? origLines.length
        : transLines.length;
    origLines = origLines.sublist(0, minLen);
    transLines = transLines.sublist(0, minLen);
  }

  final fixed = <String>[];
  for (var i = 0; i < transLines.length && i < origLines.length; i++) {
    final orig = origLines[i].replaceAll(RegExp(r'[\r\n]+$'), '');
    var trans = transLines[i].replaceAll(RegExp(r'[\r\n]+$'), '');

    if (orig.startsWith('T:')) {
      if (orig.endsWith('\\') || orig.endsWith('/')) {
        final tailChar = orig[orig.length - 1];
        if (!trans.endsWith(tailChar)) {
          trans = trans + tailChar;
        }
      }
    }
    fixed.add(trans);
  }
  return fixed.join('\n');
}