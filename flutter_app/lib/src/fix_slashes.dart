/// 移植自 fix_slashes.py 的逻辑。
///
/// 根据原文中的尾部斜杠，修复翻译文件中缺失的 `\` 或 `/` 符号。
/// 原文与译文按行一一对应，仅处理以 `T:` 开头的文本行。
library;

/// 符号修复结果：[output] 为修复后的文本，
/// [warning] 在原文/译文行数不一致时给出提示（main 会打印警告）。
class FixSlashesResult {
  final String output;
  final String? warning;
  const FixSlashesResult(this.output, this.warning);
}

String _normalizeNewlines(String s) =>
    s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

/// 按行切分（等价 Python 文本模式 readlines）：
/// 统一换行符，并去掉结尾换行符产生的尾部空行产物。
List<String> _splitLines(String content) {
  if (content.isEmpty) return const [];
  final lines = _normalizeNewlines(content).split('\n');
  if (lines.isNotEmpty && lines.last == '') {
    lines.removeLast();
  }
  return lines;
}

/// 修复译文行尾缺失的 `\` / `/`（main 的 fix_missing_slashes）。
FixSlashesResult fixMissingSlashesDetailed(
    String origContent, String transContent) {
  var origLines = _splitLines(origContent);
  var transLines = _splitLines(transContent);

  String? warning;
  if (origLines.length != transLines.length) {
    warning = '警告：行数不一致（原文 ${origLines.length} 行，'
        '译文 ${transLines.length} 行）。已按较短的行数处理，请复核。';
    final minLen =
        origLines.length < transLines.length ? origLines.length : transLines.length;
    origLines = origLines.sublist(0, minLen);
    transLines = transLines.sublist(0, minLen);
  }

  final fixed = <String>[];
  for (var i = 0; i < origLines.length && i < transLines.length; i++) {
    final orig = origLines[i];
    var trans = transLines[i];

    // 只处理以 T: 开头的文本行，其余行照原样保留
    if (orig.startsWith('T:')) {
      // 检查原文尾部是否有 \ 或 /，且译文缺少
      if (orig.endsWith('\\') || orig.endsWith('/')) {
        final tailChar = orig[orig.length - 1];
        if (!trans.endsWith(tailChar)) {
          // 译文添加缺失的斜杠
          trans = trans + tailChar;
        }
      }
    }
    fixed.add(trans);
  }

  // main 的 fixed_lines 每行以 '\n' 结尾
  final output = fixed.isEmpty ? '' : '${fixed.join('\n')}\n';
  return FixSlashesResult(output, warning);
}

/// 兼容旧签名（main 行为，无警告信息）。
String fixMissingSlashes(String origContent, String transContent) =>
    fixMissingSlashesDetailed(origContent, transContent).output;
