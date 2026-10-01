// 移植正确性测试：以 main（nscript_tool.py）的行为为基准。
// 期望值均按 main 的 Python 语义推导：
// - 命令一律小写匹配；命令后紧跟的字符按 Unicode 字母/数字判断。
// - 提取结果 '\n'.join(result) + '\n'；注入每行以 '\n' 结尾。
// - 注入容忍全角冒号与续行（提取 --expand 的回程），并把换行还原为 @/¥。
import 'package:flutter_test/flutter_test.dart';
import 'package:nscript_translate_tools/src/commands.dart';
import 'package:nscript_translate_tools/src/nscript.dart';

void main() {
  group('normalizeTypePrefix', () {
    test('半角冒号原样返回', () {
      expect(normalizeTypePrefix('T:你好'), 'T:你好');
      expect(normalizeTypePrefix('B:x'), 'B:x');
    });
    test('全角冒号转半角', () {
      expect(normalizeTypePrefix('T：你好'), 'T:你好');
      expect(normalizeTypePrefix('B：x'), 'B:x');
      expect(normalizeTypePrefix('Q：x'), 'Q:x');
    });
    test('字母与冒号之间的空格（含全角空格）被移除', () {
      expect(normalizeTypePrefix('T : 你好'), 'T: 你好');
      expect(normalizeTypePrefix('B　：x'), 'B:x');
    });
    test('非类型行原样返回', () {
      expect(normalizeTypePrefix('hello: world'), 'hello: world');
      expect(normalizeTypePrefix('t:小写不处理'), 't:小写不处理');
      expect(normalizeTypePrefix('T'), 'T');
    });
  });

  group('isCommandLine（main: is_command_line）', () {
    test('内置命令表已统一小写', () {
      // main 的 load_commands 对每条命令做 cmd.lower()；
      // 内置表含大写的命令必须同样能命中。
      expect(defaultCommands.contains('#8b0000'), isTrue,
          reason: '#8B0000 应以小写形式进入命令集');
      expect(defaultCommands.contains('namespnum'), isTrue,
          reason: 'nameSpNum 应以小写形式进入命令集');
      expect(defaultCommands.contains('settextwindow'), isTrue);
      expect(defaultCommands.contains('flushout'), isTrue);
      for (final c in defaultCommands) {
        expect(c == c.toLowerCase(), isTrue, reason: '命令必须小写: $c');
      }
    });

    test('大小写不敏感匹配命令行', () {
      expect(isCommandLine('#8B0000', defaultCommands), isTrue);
      expect(isCommandLine('nameSpNum 1', defaultCommands), isTrue);
      expect(isCommandLine('setTextWindow 3', defaultCommands), isTrue);
      expect(isCommandLine('BG "ev01",10', defaultCommands), isTrue);
      expect(isCommandLine('flushout 200', defaultCommands), isTrue);
      expect(isCommandLine('if %1', defaultCommands), isTrue);
    });

    test('命令后紧跟非 ASCII 字母数字的正文不算命令（Python isalnum 为 Unicode 语义）',
        () {
      // 'end' 是命令，但 'だ' 是字母 → main 视为可翻译文本
      expect(isCommandLine('endだ', defaultCommands), isFalse);
      expect(isCommandLine('brあいう', defaultCommands), isFalse);
      // 命令后是标点（非字母数字）→ 仍视为命令
      expect(isCommandLine('br、', defaultCommands), isTrue);
    });

    test('非命令行', () {
      expect(isCommandLine('テストです', defaultCommands), isFalse);
      expect(isCommandLine('通常のテキスト', defaultCommands), isFalse);
      expect(isCommandLine('', defaultCommands), isFalse);
    });
  });

  group('extractText（main: do_extract）', () {
    const script = ';comment\n'
        '*label\n'
        '`バックティック@テキスト\n'
        '"クォート¥された「文字」です"\n'
        '通常のテキスト行です。\n'
        'br\n'
        'bg "ev01",10\n'
        'ld c,"test",2\n'
        '#8B0000\n'
        'nameSpNum 1\n'
        'setTextWindow 3\n'
        'endだ\n'
        'flushout 200\n'
        'if %1\n'
        'endif\n'
        'テスト@テキスト\n'
        '"エスケープ \\"テスト\\""\n';

    test('expand=false：分类正确，命令/注释/标签行跳过', () {
      expect(
        extractText(script, expand: false),
        'B:バックティック@テキスト\n'
        'Q:クォート¥された「文字」です\n'
        'T:通常のテキスト行です。\n'
        'T:endだ\n'
        'T:テスト@テキスト\n'
        'Q:エスケープ "テスト"\n',
      );
    });

    test('expand=true：@ 和 ¥ 展开为换行（main: apply_expand）', () {
      expect(
        extractText(script, expand: true),
        'B:バックティック\nテキスト\n'
        'Q:クォート\nされた「文字」です\n'
        'T:通常のテキスト行です。\n'
        'T:endだ\n'
        'T:テスト\nテキスト\n'
        'Q:エスケープ "テスト"\n',
      );
    });

    test('无可翻译行时输出单个换行（main 写入 "\\n".join([]) + \'\\n\'）',
        () {
      expect(extractText('bg "ev01"\nbr\n;comment\n'), '\n');
    });

    test('CRLF 输入按 universal newlines 处理', () {
      // 第二行没有反引号 → 普通文本行（T:），与 main 的分类一致
      expect(
        extractText('`テスト\r\nテスト2\r\n', expand: false),
        'B:テスト\nT:テスト2\n',
      );
    });
  });

  group('injectText（main: do_inject）', () {
    test('逐条替换，未翻译行原样保留，输出以换行结尾', () {
      const script = ';comment\n'
          'bg "ev01",10\n'
          'テストです\n'
          '最終行';
      const trans = 'T:测试\nT:最后一行';
      expect(
        injectText(script, trans),
        ';comment\nbg "ev01",10\n测试\n最后一行\n',
      );
    });

    test('类型保持：B/Q/T 分别回填为反引号/双引号/普通文本', () {
      const script = '`あ\n"い\nう\nbr\n';
      const trans = 'B:甲\nQ:乙\nT:丙';
      expect(injectText(script, trans), '`甲\n"乙"\n丙\nbr\n');
    });

    test('脚本中可翻译行多于翻译条目时报错（main: RuntimeError）', () {
      expect(
        () => injectText('あ\nい\n', 'T:甲'),
        throwsStateError,
      );
    });

    test('翻译条目多于可翻译行时报错（main: RuntimeError）', () {
      expect(
        () => injectText('あ\n', 'T:甲\nT:乙'),
        throwsStateError,
      );
    });

    test('首行缺少类型前缀时报错（main: Malformed translation line）', () {
      expect(
        () => injectText('あ\n', '甲\n'),
        throwsFormatException,
      );
    });

    test('全角冒号前缀被接受（readme FAQ：T：→T:）', () {
      expect(injectText('あ\n', 'T：甲'), '甲\n');
      expect(injectText('`あ\n', 'B　：甲'), '`甲\n');
    });

    test('提取 --expand 产生的续行并回上一个条目，并把换行还原为原行符号', () {
      // 原文：反引号行内含 @、引号行内含 ¥
      const script = '`あa@いb\n"c¥d\nう@';
      const trans = 'B:甲a\n乙b\nQ:丙\n丁\nT:戊';
      // B 内容 "甲a\n乙b"：换行按顺序映射回原行的 @ → "甲a@乙b"
      // Q 内容 "丙\n丁"：原行符号为 ¥ → "丙¥丁"
      // T "戊"：原行 "う@" 以 @ 结尾，展开产生的末尾换行成了空行被过滤，
      //        译文未带 @ 时补回 → "戊@"
      expect(injectText(script, trans), '`甲a@乙b\n"丙¥丁"\n戊@\n');
    });

    test('译文缺少原行的尾部 @ 时补回（保持游戏点击等待行为）', () {
      expect(injectText('う@', 'T:戊'), '戊@\n');
      expect(injectText('う@', 'T:戊@'), '戊@\n');
      // 原行结尾不是 @/¥ 时不添加
      expect(injectText('う', 'T:戊'), '戊\n');
    });

    test('expand=false 时译文中的 @/¥ 原样写入（main 行为）', () {
      expect(injectText('う@', 'T:戊@です'), '戊@です\n');
    });

    test('空脚本输出为空（main: writelines([])）', () {
      expect(injectText('', ''), '');
    });

    test('提取→注入往返：translate 保留行结构时链路闭合', () {
      const script = 'Aです@\nbg "ev"\nBだ@\n';
      final extracted = extractText(script, expand: true);
      // 模拟翻译阶段：逐物理行处理，前缀保留、内容替换为中文
      final translated = extracted
          .split('\n')
          .where((l) => l.isNotEmpty)
          .map((l) => l.startsWith('B:')
              ? 'B:甲'
              : l.startsWith('Q:')
                  ? 'Q:乙'
                  : 'T:丙')
          .join('\n');
      final injected = injectText(script, translated);
      // 每个可翻译行的结尾 @ 都应保留
      expect(injected, '丙@\nbg "ev"\n丙@\n');
    });
  });

  group('parseCommandsFile（main: load_commands）', () {
    test('忽略空行与 # 注释，命令小写', () {
      final cmds = parseCommandsFile('# 注释\n\nBG\nld\n');
      expect(cmds.contains('bg'), isTrue);
      expect(cmds.contains('ld'), isTrue);
      expect(cmds.contains('BG'), isFalse);
    });

    test('空内容回退默认命令集', () {
      expect(identical(parseCommandsFile(''), defaultCommands), isTrue);
      expect(identical(parseCommandsFile('\n\n'), defaultCommands), isTrue);
    });
  });
}
