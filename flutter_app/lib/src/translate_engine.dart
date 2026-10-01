/// 移植自 translate.py 的 LLM 批量翻译引擎。
///
/// main（translate.py）为行为基准：
/// - 重试次数/退避公式与 main 一致（max_retries、retry_delay*2^n、429 用 3^n）。
/// - 翻译失败的行保留原文（含类型前缀），而不是写入无前缀的
///   「[翻译失败]」标记——那会让后续注入直接失败（main 的已知问题）。
/// 支持：多平台（openai/deepseek/qwen/zhipu / 自定义 api_base）、并发翻译、
/// 滑动窗口限速、指数退避重试、术语表，以及实时速率/进度反馈。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'nscript.dart' show normalizeTypePrefix;

/// 翻译任务配置（对应 config.json）。
class TranslateConfig {
  final String provider;
  final String apiKey;
  final String apiBase;
  final String model;
  final String sourceLanguage;
  final String targetLanguage;
  final int concurrency;
  final double maxRequestsPerSecond;
  final int maxRetries;
  final int retryDelay; // 秒
  final Map<String, String> glossary;

  const TranslateConfig({
    required this.provider,
    required this.apiKey,
    required this.apiBase,
    required this.model,
    required this.sourceLanguage,
    required this.targetLanguage,
    this.concurrency = 3,
    this.maxRequestsPerSecond = 5,
    this.maxRetries = 3,
    this.retryDelay = 2,
    this.glossary = const {},
  });

  static const Map<String, String> defaultBases = {
    'openai': 'https://api.openai.com/v1',
    'deepseek': 'https://api.deepseek.com/v1',
    'qwen': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    'zhipu': 'https://open.bigmodel.cn/api/paas/v4',
  };

  /// 解析最终 api_base。
  /// 自定义地址未携带协议时自动补全 https://，
  /// 否则 Dart 会把域名误当作 scheme、host 为空，导致无法解析 IP。
  String resolvedBase() {
    if (apiBase.trim().isNotEmpty) {
      var base = apiBase.trim();
      if (!base.contains('://')) base = 'https://$base';
      return base;
    }
    final base = defaultBases[provider.toLowerCase()];
    if (base == null) {
      throw ArgumentError('未知的 AI 提供商 $provider，请在配置中指定 api_base');
    }
    return base;
  }
}

/// 翻译过程状态，供 UI 实时刷新。
@immutable
class TranslateState {
  final bool running;
  final int total;
  final int done;
  final int failed;
  final double currentRate; // 每秒请求数（滑动窗口）
  final double averageRate; // 平均每秒请求数
  final String currentLine;
  final List<String> log;

  const TranslateState({
    this.running = false,
    this.total = 0,
    this.done = 0,
    this.failed = 0,
    this.currentRate = 0,
    this.averageRate = 0,
    this.currentLine = '',
    this.log = const [],
  });

  double get progress => total == 0 ? 0 : (done + failed) / total;

  TranslateState copyWith({
    bool? running,
    int? total,
    int? done,
    int? failed,
    double? currentRate,
    double? averageRate,
    String? currentLine,
    List<String>? log,
  }) {
    return TranslateState(
      running: running ?? this.running,
      total: total ?? this.total,
      done: done ?? this.done,
      failed: failed ?? this.failed,
      currentRate: currentRate ?? this.currentRate,
      averageRate: averageRate ?? this.averageRate,
      currentLine: currentLine ?? this.currentLine,
      log: log ?? this.log,
    );
  }
}

class Semaphore {
  int _permits;
  final _waiters = Queue<Completer<void>>();

  /// 并发数至少为 1：0 或负数会让所有任务永远等待（界面卡死）。
  Semaphore(int permits) : _permits = permits < 1 ? 1 : permits;

  Future<void> acquire() async {
    if (_permits > 0) {
      _permits--;
    } else {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _permits++;
    }
  }
}

/// 滑动窗口速率限制器（Dart 事件循环单线程，天然线程安全）。
class RateLimiter {
  final double maxRps;
  final Queue<double> _window = Queue<double>();
  static const double _windowSec = 1.0;

  /// 速率至少为 1 次/秒：<=0 会导致死循环或空队列访问崩溃。
  RateLimiter(double rps) : maxRps = rps <= 0 ? 1 : rps;

  Future<void> wait() async {
    while (_window.length >= maxRps) {
      final now = _now();
      // 清理过期的记录
      while (_window.isNotEmpty && _window.first <= now - _windowSec) {
        _window.removeFirst();
      }
      if (_window.length < maxRps) break;
      final head = _window.first;
      final waitFor = head + _windowSec - now;
      if (waitFor > 0) {
        await Future.delayed(
            Duration(microseconds: (waitFor * 1e6).round()));
      }
    }
    _window.add(_now());
  }

  double _now() => DateTime.now().microsecondsSinceEpoch / 1e6;
}

/// 退避秒数（main：retry_delay * base^attempt；指数封顶防止溢出/超长等待）。
int backoffSeconds(int retryDelay, int base, int attempt) {
  final exp = attempt > 5 ? 5 : attempt;
  var factor = 1;
  for (var i = 0; i < exp; i++) {
    factor *= base;
  }
  return retryDelay * factor;
}

/// 翻译引擎。
class TranslateEngine extends ChangeNotifier {
  TranslateState _state = const TranslateState();
  TranslateState get state => _state;

  bool _running = false;
  bool _cancel = false;

  int _rpsCount = 0;
  int _totalRequests = 0;
  Timer? _rpsTimer;
  final Stopwatch _stopwatch = Stopwatch();

  void _emit(TranslateState s) {
    _state = s;
    notifyListeners();
  }

  void _appendLog(String msg) {
    final newLog = [..._state.log, msg];
    _emit(_state.copyWith(
        log: newLog.length > 500 ? newLog.sublist(newLog.length - 500) : newLog));
  }

  void cancel() => _cancel = true;

  /// 启动翻译。输入来自 [sourceLines]，逐行处理。
  ///
  /// [httpClient] 仅供测试注入 MockClient；生产为 null 时使用默认 Client
  ///（整个任务复用连接）。
  Future<void> translate({
    required TranslateConfig config,
    required List<String> sourceLines,
    required void Function(List<String> results) onComplete,
    required void Function(Object error) onError,
    http.Client? httpClient,
  }) async {
    if (_running) return;
    _running = true;
    _cancel = false;
    _rpsCount = 0;
    _totalRequests = 0;
    _stopwatch.reset();
    _stopwatch.start();

    final total = sourceLines.length;
    _emit(const TranslateState(running: true, total: 0, log: []));
    _emit(_state.copyWith(total: total));

    final client = httpClient ?? http.Client();
    try {
      // 每秒采样两次实时速率
      _rpsTimer?.cancel();
      _rpsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!_running) return;
        final rate = _rpsCount / 0.5;
        _rpsCount = 0;
        final avg = _stopwatch.elapsedMilliseconds > 0
            ? (_totalRequests * 1000 / _stopwatch.elapsedMilliseconds)
            : 0.0;
        _emit(_state.copyWith(currentRate: rate, averageRate: avg));
      });

      final apiBase = config.resolvedBase();
      final systemPrompt = buildPrompt(config);
      final rateLimiter = RateLimiter(config.maxRequestsPerSecond);
      final sem = Semaphore(config.concurrency);
      // 初始化为原文行（前缀标准化）：翻译成功后被覆盖；
      // 失败/取消的行保留原文，保证输出文件行结构完整、可直接注入。
      final results =
          List<String>.generate(total, (i) => normalizeTypePrefix(sourceLines[i]));

      final skipNoSource =
          lineContainsSourceLanguageDetectable(config.sourceLanguage);
      // 构建任务列表（跳过空行、以及不含源语言文字的整行）
      final tasks = <(int, String)>[];
      var skipped = 0;
      for (var i = 0; i < total; i++) {
        final line = sourceLines[i];
        if (line.trim().isEmpty) continue;
        if (skipNoSource && !lineContainsSourceLanguage(line, config.sourceLanguage)) {
          results[i] = normalizeTypePrefix(line); // 无源语言文字，整行保持原样
          skipped++;
          continue;
        }
        tasks.add((i + 1, line));
      }

      _appendLog('共 $total 行，开始并发翻译（并发数=${config.concurrency}，'
          '最大请求速率=${config.maxRequestsPerSecond}/s'
          '${skipped > 0 ? '，跳过不含原文语言的 $skipped 行' : ''}）');

      var done = skipped;
      var failed = 0;

      final futures = <Future<void>>[];
      for (final (lineNo, line) in tasks) {
        if (_cancel) break;
        futures.add(_translateOne(
          config: config,
          apiBase: apiBase,
          systemPrompt: systemPrompt,
          rateLimiter: rateLimiter,
          sem: sem,
          client: client,
          line: line,
          lineNumber: lineNo,
          results: results,
          onCount: () {
            _rpsCount++;
            _totalRequests++;
            _emit(_state.copyWith(currentLine: line));
          },
          onSuccess: () {
            done++;
            _emit(_state.copyWith(done: done, failed: failed));
          },
          onFail: () {
            failed++;
            _emit(_state.copyWith(done: done, failed: failed));
          },
          onLog: _appendLog,
        ));
      }

      await Future.wait(futures);

      // 保留空行
      for (var i = 0; i < total; i++) {
        if (sourceLines[i].trim().isEmpty) results[i] = '';
      }

      _stopwatch.stop();

      final finalState = _state.copyWith(
        running: false,
        currentRate: 0,
        done: done,
        failed: failed,
        currentLine: '',
      );
      _emit(finalState);

      if (_cancel) {
        _appendLog('已取消（未翻译的行保留原文）');
      } else {
        _appendLog(failed > 0
            ? '翻译完成，但有 $failed 行失败（失败行保留原文，可用 AI 校对复核）'
            : '所有行翻译成功！');
      }

      onComplete(results);
    } finally {
      _rpsTimer?.cancel();
      _stopwatch.stop();
      _running = false;
      if (httpClient == null) client.close();
      // 异常路径也要把 running 置回 false（界面的按钮状态依赖它）
      if (_state.running) _emit(_state.copyWith(running: false));
      notifyListeners();
    }
  }

  Future<void> _translateOne({
    required TranslateConfig config,
    required String apiBase,
    required String systemPrompt,
    required RateLimiter rateLimiter,
    required Semaphore sem,
    required http.Client client,
    required String line,
    required int lineNumber,
    required List<String> results,
    required VoidCallback onCount,
    required VoidCallback onSuccess,
    required VoidCallback onFail,
    required void Function(String) onLog,
  }) async {
    await sem.acquire();
    try {
      final content = await _callAPI(
        config: config,
        apiBase: apiBase,
        systemPrompt: systemPrompt,
        line: line,
        lineNumber: lineNumber,
        rateLimiter: rateLimiter,
        client: client,
        onCount: onCount,
        onLog: onLog,
      );
      if (content.startsWith('[翻译失败')) {
        // 失败：results 里保留初始化时的原文行，保证输出文件可注入
        onLog('第 $lineNumber 行翻译失败，保留原文（$content）');
        onFail();
        return;
      }
      final translated = extractTranslation(content, lineNumber);
      final prefix = _scriptPrefixOf(line);
      // 源行带类型前缀时：去掉 AI 回显的前缀并标准化为半角 T:/B:/Q:；
      // 纯文本行（未经提取）保持 AI 译文原样（与 main 一致）。
      final body = prefix.isEmpty ? translated : _stripEchoedPrefix(translated, line);
      results[lineNumber - 1] =
          prefix.isEmpty ? body : normalizeTypePrefix('$prefix$body');
      onSuccess();
    } catch (e) {
      onLog('第 $lineNumber 行处理异常: $e');
      onFail();
    } finally {
      sem.release();
    }
  }

  /// 与 main 的 translate_single_line 对齐：
  /// 任何一次尝试失败都按退避重试，最终失败返回「[翻译失败 …]」标记，
  /// 由调用方决定保留原文；每次尝试（含重试）都经过限速器。
  Future<String> _callAPI({
    required TranslateConfig config,
    required String apiBase,
    required String systemPrompt,
    required String line,
    required int lineNumber,
    required RateLimiter rateLimiter,
    required http.Client client,
    required VoidCallback onCount,
    required void Function(String) onLog,
  }) async {
    final attempts = config.maxRetries + 1;
    final url = '${apiBase.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
    final headers = {
      'Authorization': 'Bearer ${config.apiKey}',
      'Content-Type': 'application/json',
    };
    final payload = {
      'model': config.model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': '请翻译以下单行文本：\n$line'},
      ],
      'temperature': 0.1,
      'max_tokens': 200,
    };

    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      onLog('--- 翻译第 $lineNumber 行 (尝试 ${attempt + 1}/$attempts) ---');
      try {
        await rateLimiter.wait();
        onCount();
        final resp = await client
            .post(Uri.parse(url), headers: headers, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 120));

        if (resp.statusCode == 500) {
          lastError = '服务器内部错误 (500)';
          if (attempt < attempts - 1) {
            final wait = backoffSeconds(config.retryDelay, 2, attempt);
            onLog('第 $lineNumber 行，$lastError，等待 $wait 秒后重试…');
            await Future.delayed(Duration(seconds: wait));
            continue;
          }
          return '[翻译失败: 第 $lineNumber 行翻译失败，已重试 ${config.maxRetries} 次: 服务器内部错误]';
        }

        if (resp.statusCode == 429) {
          lastError = '请求频率过高 (429)';
          if (attempt < attempts - 1) {
            final wait = backoffSeconds(config.retryDelay, 3, attempt);
            onLog('第 $lineNumber 行，$lastError，等待 $wait 秒后重试…');
            await Future.delayed(Duration(seconds: wait));
            continue;
          }
          return '[翻译失败: 第 $lineNumber 行翻译失败，已重试 ${config.maxRetries} 次: 请求频率过高]';
        }

        if (resp.statusCode >= 400) {
          // main 的 raise_for_status 同样走通用异常分支重试
          lastError = 'HTTP ${resp.statusCode}';
          if (attempt < attempts - 1) {
            final wait = backoffSeconds(config.retryDelay, 2, attempt);
            onLog('第 $lineNumber 行，请求失败 $lastError，等待 $wait 秒后重试…');
            await Future.delayed(Duration(seconds: wait));
            continue;
          }
          return '[翻译失败: 第 $lineNumber 行 HTTP ${resp.statusCode}]';
        }

        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final content = data['choices'][0]['message']['content'] as String?;
        if (content == null) {
          throw const FormatException('响应缺少 choices[0].message.content');
        }
        return content;
      } on TimeoutException catch (e) {
        lastError = e;
        if (attempt < attempts - 1) {
          final wait = backoffSeconds(config.retryDelay, 2, attempt);
          onLog('第 $lineNumber 行请求超时，等待 $wait 秒后重试…');
          await Future.delayed(Duration(seconds: wait));
          continue;
        }
        return '[翻译失败: 请求超时]';
      } catch (e) {
        // main 的通用 except 分支：连接错误、响应结构异常等一律重试
        lastError = e;
        if (attempt < attempts - 1) {
          final wait = backoffSeconds(config.retryDelay, 2, attempt);
          onLog('第 $lineNumber 行请求异常: $e，等待 $wait 秒后重试…');
          await Future.delayed(Duration(seconds: wait));
          continue;
        }
        return '[翻译失败: $e]';
      }
    }
    return '[翻译失败: ${lastError ?? '未知错误'}]';
  }
}

/// 构建系统提示词（含术语表），文本与 main 的 build_prompt 对齐。
String buildPrompt(TranslateConfig config) {
  final source = config.sourceLanguage;
  final target = config.targetLanguage;
  var base =
      '你是一名专业的翻译家，你的任务是把$source文本翻译成$target。\n'
      '请严格按照原文翻译，不要添加额外解释，不要合并或拆分行，保留原文中的序号、'
      '标记符、占位符、换行符、转义符、代码调用过程等特殊内容，保持原来的格式。'
      '原文中的序号、标记符、占位符、换行符、转义符、代码调用过程等特殊内容包括'
      '@ \\ 等 请保留这些符号不做修改\n\n'
      '### 翻译原则\n'
      '忠实准确地进行翻译。原作是伟大艺术作品，允许使用直白或粗俗的描述，'
      '不应随意删减或篡改，不应回避或淡化，以保持作品的原貌。';

  if (config.glossary.isNotEmpty) {
    final termLines = config.glossary.entries
        .map((e) => '- ${e.key} → ${e.value}')
        .join('\n');
    base += '\n\n### 术语表（必须严格遵守）\n'
        '在翻译过程中，以下术语必须按照指定的翻译进行转换，不得自由发挥：\n'
        '$termLines\n';
  }

  base += '\n\n### 以textarea标签输出译文\n<textarea>\n'
      '$target文本\n</textarea>';
  return base;
}

/// 从 AI 响应中提取译文（main 的 extract_translation_from_line）。
String extractTranslation(String responseText, int lineNumber) {
  final match = RegExp(r'<textarea>\s*(.*?)\s*</textarea>',
          dotAll: true, caseSensitive: false)
      .firstMatch(responseText);
  var translated = match != null ? match.group(1)!.trim() : responseText.trim();

  // 去掉行首的序号 / T: 等标记
  translated = translated.replaceAll(
      RegExp(r'^\d+\.\s*T?:?\s*', multiLine: true), '');
  translated =
      translated.replaceAll(RegExp(r'^\d+\.\s*$', multiLine: true), '');
  return translated.trim();
}

// ---- 按源语言文字判定某一行是否可跳过（不含源语言则无需翻译） ----

bool _isCjk(int c) =>
    (c >= 0x3400 && c <= 0x4DBF) || (c >= 0x4E00 && c <= 0x9FFF);
bool _isHira(int c) => c >= 0x3040 && c <= 0x309F;
bool _isKata(int c) => c >= 0x30A0 && c <= 0x30FF;
bool _isHangul(int c) => c >= 0xAC00 && c <= 0xD7A3;
bool _isCyr(int c) => (c >= 0x0400 && c <= 0x04FF);
bool _isLatin(int c) =>
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0x00C0 && c <= 0x024F);

/// 输入语言字符串是否可被字符集识别（可识别才启用“不含源语言则跳过”）。
bool lineContainsSourceLanguageDetectable(String sourceLanguage) {
  final s = sourceLanguage.trim().toLowerCase();
  return s.contains('japan') ||
      s.contains('日') ||
      s.contains('korean') ||
      s.contains('韩') ||
      s.contains('russian') ||
      s.contains('俄') ||
      s.contains('chinese') ||
      s.contains('中') ||
      s.contains('english') ||
      s.contains('英') ||
      s.contains('french') ||
      s.contains('法') ||
      s.contains('german') ||
      s.contains('德') ||
      s.contains('spanish') ||
      s.contains('西') ||
      s.contains('italian') ||
      s.contains('意') ||
      s == 'ja' ||
      s == 'ko' ||
      s == 'zh' ||
      s == 'en';
}

/// 提取源行的类型前缀（T:/B:/Q:），无则返回空串。
String _scriptPrefixOf(String line) {
  if (line.length >= 2 &&
      line[1] == ':' &&
      (line[0] == 'T' || line[0] == 'B' || line[0] == 'Q')) {
    return line[0];
  }
  return '';
}

/// AI 有时会在译文中回显类型前缀（如 “T:译文”、“T：译文”）。
/// 源行本身带前缀时去掉回显，避免与重新添加的前缀叠加成 “T:T:…”
/// （该前缀随后会泄漏进游戏文本）。
String _stripEchoedPrefix(String translated, String sourceLine) {
  if (_scriptPrefixOf(sourceLine).isEmpty) return translated;
  final norm = normalizeTypePrefix(translated);
  if (norm.length >= 2 &&
      norm[1] == ':' &&
      (norm[0] == 'T' || norm[0] == 'B' || norm[0] == 'Q')) {
    return norm.substring(2);
  }
  return norm;
}

/// [line] 是否包含 [sourceLanguage] 对应的文字（不含则说明无需翻译）。
bool lineContainsSourceLanguage(String line, String sourceLanguage) {
  final s = sourceLanguage.trim().toLowerCase();
  bool any(bool Function(int) pred) {
    for (final r in line.runes) {
      if (pred(r)) return true;
    }
    return false;
  }

  if (s.contains('japan') || s.contains('日') || s == 'ja') {
    return any((c) => _isHira(c) || _isKata(c) || _isCjk(c));
  }
  if (s.contains('korean') || s.contains('韩') || s == 'ko') {
    return any((c) => _isHangul(c) || _isCjk(c));
  }
  if (s.contains('russian') || s.contains('俄')) {
    return any(_isCyr);
  }
  if (s.contains('chinese') || s.contains('中') || s == 'zh') {
    return any(_isCjk);
  }
  if (s.contains('english') ||
      s.contains('英') ||
      s.contains('french') ||
      s.contains('法') ||
      s.contains('german') ||
      s.contains('德') ||
      s.contains('spanish') ||
      s.contains('西') ||
      s.contains('italian') ||
      s.contains('意') ||
      s == 'en') {
    return any(_isLatin);
  }
  // 无法识别的语言：视为包含，不跳过（保持原有行为）
  return true;
}
