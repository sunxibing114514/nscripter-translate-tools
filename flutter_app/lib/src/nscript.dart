/// 移植自 nscript_tool.py 的文本提取 / 注入核心逻辑。
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

/// 将 @ 和 ¥ 替换为换行符。
String applyExpand(String content) =>
    content.replaceAll('@', '\n').replaceAll('¥', '\n');

/// 判断一行是否为命令行。
bool isCommandLine(String line, Set<String> commands) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return false;
  final firstWord =
      trimmed.split(RegExp(r'\s+')).first.toLowerCase();
  if (commands.contains(firstWord)) return true;

  if (commands.contains(trimmed.toLowerCase())) return true;

  // 仅比较与首字符一致的命令，避免对每个命令做 startsWith（O(N×M) 慢）。
  final lower = trimmed.toLowerCase();
  final head = trimmed.isNotEmpty ? lower[0] : '';
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

bool _isAlnum(String ch) {
  final code = ch.codeUnitAt(0);
  final isDigit = code >= 0x30 && code <= 0x39;
  final isUpper = code >= 0x41 && code <= 0x5A;
  final isLower = code >= 0x61 && code <= 0x7A;
  return isDigit || isUpper || isLower;
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

/// 提取可翻译文本，返回提取结果字符串（格式：`B:`/`Q:`/`T:` 前缀）。
String extractText(String scriptContent,
    {Set<String>? commands, bool expand = false}) {
  final cmds = commands ?? defaultCommands;
  final result = <String>[];
  for (final line in scriptContent.split('\n')) {
    final st = processScriptLine(line, commands: cmds, expandSymbols: expand);
    if (st != null) {
      final prefix = {
        TextType.backtick: 'B',
        TextType.quoted: 'Q',
        TextType.text: 'T',
      }[st.type];
      result.add('$prefix:${st.content}');
    }
  }
  return (result.isEmpty ? '' : result.join('\n')) +
      (result.isEmpty ? '' : '\n');
}

/// 将翻译文件注入回脚本，返回新的脚本内容。
String injectText(String scriptContent, String transContent,
    {Set<String>? commands}) {
  final cmds = commands ?? defaultCommands;
  final scriptLines =
      scriptContent.split('\n').map((l) => l.replaceAll(RegExp(r'\r$'), '')).toList();

  final transItems = <ScriptText>[];
  for (final rawLine in transContent.split('\n')) {
    final tl = rawLine.replaceAll(RegExp(r'[\r\n]+$'), '');
    if (tl.trim().isEmpty) continue;
    if (tl.length < 2 || tl[1] != ':') {
      throw FormatException('翻译行格式错误: $tl');
    }
    const typeMap = {
      'B': TextType.backtick,
      'Q': TextType.quoted,
      'T': TextType.text,
    };
    final t = typeMap[tl[0]];
    if (t == null) {
      throw FormatException(
          '翻译行存在未知类型前缀: $tl');
    }
    transItems.add(ScriptText(t, tl.substring(2)));
  }

  final output = <String>[];
  var idx = 0;
  for (final line in scriptLines) {
    final orig =
        processScriptLine(line, commands: cmds, expandSymbols: false);
    if (orig != null) {
      if (idx >= transItems.length) {
        throw StateError('脚本中可翻译行数多于翻译条目数');
      }
      final repl = transItems[idx];
      idx++;
      String newLine;
      switch (repl.type) {
        case TextType.backtick:
          newLine = '`${repl.content}';
        case TextType.quoted:
          newLine = '"${repl.content}"';
        case TextType.text:
          newLine = repl.content;
      }
      output.add(newLine);
    } else {
      output.add(line);
    }
  }

  if (idx != transItems.length) {
    throw StateError('翻译条目数多于脚本中的可翻译行数');
  }
  return output.join('\n');
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