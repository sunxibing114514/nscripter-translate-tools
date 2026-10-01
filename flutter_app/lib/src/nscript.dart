/// 移植自 nscript_tool.py 的文本提取 / 注入核心逻辑。
///
/// main（nscript_tool.py）为行为基准：
/// - 命令一律小写匹配（load_commands 的 cmd.lower()）。
/// - 命令后紧跟的字符是否为字母数字，按 Unicode 语义判断
///   （Python str.isalnum 对日文假名/汉字同样返回 True），
///   否则「endだ…」这类正文会被误判为命令行而漏翻。
/// - 注入时容忍全角冒号（readme FAQ：T：→T:）并回接续行，
///   把提取时展开的换行按顺序还原为原行中的 @ / ¥。
library;

import 'dart:typed_data';

import 'commands.dart';
import 'encodings.dart';

enum TextType { backtick, quoted, text }

class ScriptText {
  final TextType type;
  final String content;
  ScriptText(this.type, this.content);
}

/// 与 Python str.isalnum 一致：任意文字系统的字母（\p{L}）或数字（\p{N}）。
final RegExp _alnumRe = RegExp(r'^(?:\p{L}|\p{N})$', unicode: true);

bool _isAlnum(String ch) => _alnumRe.hasMatch(ch);

/// 行首类型前缀标准化为半角（T：→ T:、T :→ T:、B　:→ B:）。
/// 仅处理 T/B/Q 三种类型字母，用于：
/// - 翻译结果（保证注入器要求的半角格式）；
/// - 注入时容忍 AI/手工编辑产生的全角冒号（main 的 readme FAQ）。
String normalizeTypePrefix(String line) {
  if (line.length >= 2) {
    final c0 = line[0];
    if (c0 != 'T' && c0 != 'B' && c0 != 'Q') return line;
    var i = 1;
    // 跳过类型字母与冒号之间的空白（含全角空格）
    while (i < line.length && (line[i] == ' ' || line[i] == '\u3000')) {
      i++;
    }
    if (i < line.length && (line[i] == ':' || line[i] == '：')) {
      return '$c0:${line.substring(i + 1)}';
    }
  }
  return line;
}

/// 统一换行符（等价于 Python 文本模式读取的 universal newlines）。
String _normalizeNewlines(String s) =>
    s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

/// 从双引号开头的字符串中提取内容，支持简单的转义。
String extractQuotedString(String s) {
  if (s.isEmpty || s[0] != '"') return '';
  final buf = StringBuffer();
  var i = 1;
  while (i < s.length) {
    final c = s[i];
    if (c == '"') break;
    if (c == '\\' && i + 1 < s.length) {
      final nxt = s[i + 1];
      if (nxt == '"') {
        buf.write('"');
      } else if (nxt == '\\') {
        buf.write('\\');
      } else {
        buf.write('\\');
        buf.write(nxt);
      }
      i += 2;
    } else {
      buf.write(c);
      i++;
    }
  }
  return buf.toString();
}

/// 将 @ 和 ¥ 替换为换行符（main 的 apply_expand）。
String applyExpand(String content) =>
    content.replaceAll('@', '\n').replaceAll('¥', '\n');

/// 判断一行是否为命令行（main 的 is_command_line）。
bool isCommandLine(String line, Set<String> commands) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return false;
  final firstWord = trimmed.split(RegExp(r'\s+')).first.toLowerCase();
  if (commands.contains(firstWord)) return true;

  final lower = trimmed.toLowerCase();
  // 仅比较与首字符一致的命令，避免对每个命令做 startsWith（O(N×M) 慢）。
  // 命令集已统一小写（见 commands.dart），按首字符过滤是安全的。
  final head = lower[0];
  for (final cmd in commands) {
    if (cmd.isEmpty) continue;
    if (cmd[0] != head) continue;
    if (lower.startsWith(cmd) &&
        (trimmed.length == cmd.length || !_isAlnum(trimmed[cmd.length]))) {
      return true;
    }
  }
  return false;
}

/// 处理一行，若为可翻译文本则返回 [ScriptText]，否则返回 null。
ScriptText? processScriptLine(String line,
    {Set<String>? commands, bool expandSymbols = false}) {
  final cmds = commands ?? defaultCommands;
  final trimmed = line.replaceAll(RegExp(r'[\r\n]+$'), '');
  if (trimmed.isEmpty ||
      trimmed.startsWith(';') ||
      trimmed.startsWith('*')) {
    return null;
  }

  if (trimmed.startsWith('`')) {
    var content = trimmed.substring(1);
    if (expandSymbols) content = applyExpand(content);
    return ScriptText(TextType.backtick, content);
  }

  if (trimmed.startsWith('"')) {
    var content = extractQuotedString(trimmed);
    if (expandSymbols) content = applyExpand(content);
    return ScriptText(TextType.quoted, content);
  }

  if (trimmed.toLowerCase() == 'br') return null;

  if (!isCommandLine(trimmed, cmds)) {
    var content = trimmed;
    if (expandSymbols) content = applyExpand(content);
    return ScriptText(TextType.text, content);
  }

  return null;
}

/// 提取可翻译文本（main 的 do_extract）。
/// 结果与 main 一致以换行符结尾：'\n'.join(result) + '\n'。
String extractText(String scriptContent,
    {Set<String>? commands, bool expand = false}) {
  final cmds = commands ?? defaultCommands;
  final result = <String>[];
  for (final line in _normalizeNewlines(scriptContent).split('\n')) {
    final st = processScriptLine(line, commands: cmds, expandSymbols: expand);
    if (st != null) {
      final prefix = {
        TextType.backtick: 'B',
        TextType.quoted: 'Q',
        TextType.text: 'T',
      }[st.type]!;
      result.add('$prefix:${st.content}');
    }
  }
  return '${result.join('\n')}\n';
}

/// 注入时把译文内容中的换行还原为原行对应位置的 @ / ¥。
///
/// 提取（--expand）会把原行中的 @、¥ 展开为换行，翻译文件里表现为
/// 物理续行；注入器把续行并回后，译文内容里仍是换行。直接写入会
/// 破坏脚本行结构，这里按出现顺序映射回原行中的符号；原行没有更多
/// 符号时退回 '@'（NScripter 的换行+点击等待符），保证不产生乱行。
///
/// 另外，原行以 @/¥ 结尾时，展开产生的末尾换行在翻译文件里是空行、
/// 会被当作空行过滤掉，导致结尾符号丢失（main 同样丢失，游戏里表现为
/// 该行不等待点击直接继续）。当译文完全没有出现任何 @/¥（符号无迹可循）
/// 且换行数少于原行符号数时，把结尾符号补回。
String _restoreBreakSymbols(String translated, String original) {
  final raw = translated;
  final symbols = <String>[];
  for (var i = 0; i < original.length; i++) {
    final c = original[i];
    if (c == '@' || c == '¥') symbols.add(c);
  }

  var content = translated;
  var k = 0;
  if (content.contains('\n')) {
    final buf = StringBuffer();
    for (var i = 0; i < content.length; i++) {
      final c = content[i];
      if (c == '\n') {
        buf.write(k < symbols.length ? symbols[k] : '@');
        k++;
      } else {
        buf.write(c);
      }
    }
    content = buf.toString();
  }

  if (original.isNotEmpty) {
    final last = original[original.length - 1];
    if ((last == '@' || last == '¥') &&
        k < symbols.length &&
        !raw.contains('@') &&
        !raw.contains('¥') &&
        !content.endsWith(last)) {
      content += last;
    }
  }
  return content;
}

/// 将翻译文件注入回脚本，返回新的脚本内容（main 的 do_inject）。
///
/// 与 main 的差异（均为打通「提取→翻译→注入」链路所必需）：
/// - 类型前缀容忍全角冒号 / 前缀空格（main 会直接报
///   Malformed translation line，readme FAQ 要求用户手工改 T：→T:）。
/// - 提取时 --expand 展开的换行产生的无前缀续行并回上一个条目，
///   否则展开流程在注入时必然中断（main 即如此）。
/// - 译文内容中的换行按顺序还原为原行中的 @ / ¥。
String injectText(String scriptContent, String transContent,
    {Set<String>? commands}) {
  final cmds = commands ?? defaultCommands;
  final normalized = _normalizeNewlines(scriptContent);
  final scriptLines =
      normalized.isEmpty ? const <String>[] : normalized.split('\n');

  const typeMap = {
    'B': TextType.backtick,
    'Q': TextType.quoted,
    'T': TextType.text,
  };

  final items = <(TextType, String)>[];
  for (final rawLine in _normalizeNewlines(transContent).split('\n')) {
    final tl = normalizeTypePrefix(rawLine.trim());
    if (tl.isEmpty) continue;
    final isItem = tl.length >= 2 &&
        tl[1] == ':' &&
        (tl[0] == 'B' || tl[0] == 'Q' || tl[0] == 'T');
    if (isItem) {
      items.add((typeMap[tl[0]]!, tl.substring(2)));
    } else if (items.isEmpty) {
      throw FormatException('翻译行缺少 B:/T:/Q: 类型前缀: $tl');
    } else {
      // 提取 --expand 展开的换行产生的续行：并回上一个条目
      final last = items[items.length - 1];
      items[items.length - 1] = (last.$1, '${last.$2}\n$tl');
    }
  }

  final output = <String>[];
  var idx = 0;
  for (final line in scriptLines) {
    final orig =
        processScriptLine(line, commands: cmds, expandSymbols: false);
    if (orig != null) {
      if (idx >= items.length) {
        throw StateError('脚本中可翻译行数多于翻译条目数');
      }
      final (type, content) = items[idx];
      idx++;
      final restored = _restoreBreakSymbols(content, orig.content);
      String newLine;
      switch (type) {
        case TextType.backtick:
          newLine = '`$restored';
        case TextType.quoted:
          newLine = '"$restored"';
        case TextType.text:
          newLine = restored;
      }
      output.add(newLine);
    } else {
      output.add(line);
    }
  }

  if (idx != items.length) {
    throw StateError('翻译条目数多于脚本中的可翻译行数');
  }
  if (output.isEmpty) return '';
  // main 对每行补 '\n'：join 后若尚未以换行结尾则补齐
  final joined = output.join('\n');
  return joined.endsWith('\n') ? joined : '$joined\n';
}

/// 供后台 isolate（compute）调用的提取入口。
/// args 顺序：[script(utf8/latin1编码字节), inEnc, outEnc, expand, commandsList]
Uint8List extractOnIsolate(List<Object> args) {
  final bytes = args[0] as List<int>;
  final inEnc = args[1] as String;
  final outEnc = args[2] as String;
  final expand = args[3] as bool;
  final commands = (args[4] as List).map((e) => e.toString()).toSet();
  final decoded = decodeBytes(Uint8List.fromList(bytes), inEnc);
  final out = extractText(decoded, commands: commands, expand: expand);
  return encodeString(out, outEnc);
}

/// 供后台 isolate（compute）调用的注入入口。
/// args 顺序：[scriptBytes, transBytes, inEnc, transEnc, outEnc, commandsList]
Uint8List injectOnIsolate(List<Object> args) {
  final scriptBytes = args[0] as List<int>;
  final transBytes = args[1] as List<int>;
  final inEnc = args[2] as String;
  final transEnc = args[3] as String;
  final outEnc = args[4] as String;
  final commands = (args[5] as List).map((e) => e.toString()).toSet();
  final scriptText = decodeBytes(Uint8List.fromList(scriptBytes), inEnc);
  final transText = decodeBytes(Uint8List.fromList(transBytes), transEnc);
  final out = injectText(scriptText, transText, commands: commands);
  return encodeString(out, outEnc);
}
