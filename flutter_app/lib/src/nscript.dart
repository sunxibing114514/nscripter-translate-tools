/// 移植自 nscript_tool.py 的文本提取 / 注入核心逻辑。
library;

import 'commands.dart';

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
  final lower = trimmed.toLowerCase();
  for (final cmd in commands) {
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