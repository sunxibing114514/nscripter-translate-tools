/// 移植自 translate.py 的 LLM 批量翻译引擎。
///
/// 支持：多平台（openai/deepseek/qwen/zhipu / 自定义 api_base）、并发翻译、
/// 滑动窗口限速、指数退避重试、术语表，以及实时速率/进度反馈。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
  String resolvedBase() {
    if (apiBase.trim().isNotEmpty) return apiBase.trim();
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
  Semaphore(this._permits);

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

  RateLimiter(this.maxRps);

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
        await Future.delayed(Duration(microseconds: (waitFor * 1e6).round()));
        continue;
      }
    }
    _window.add(_now());
  }

  double _now() => DateTime.now().microsecondsSinceEpoch / 1e6;
}

/// 翻译引擎。
class TranslateEngine extends ChangeNotifier {
  TranslateState _state = const TranslateState();
  TranslateState get state => _state;

  bool _running = false;
  bool _cancel = false;

  int _rpsCount = 0;
  int _totalRequests = 0;
  double _elapsed = 0;
  Timer? _rpsTimer;
  final Stopwatch _stopwatch = Stopwatch();

  void _emit(TranslateState s) {
    _state = s;
    notifyListeners();
  }

  void _appendLog(String msg) {
    final prev = _state.log;
    final newLog = [...prev, msg];
    _emit(_state.copyWith(log: newLog.length > 500 ? newLog.sublist(newLog.length - 500) : newLog));
  }

  void _bumpRate() {
    _rpsCount++;
    _totalRequests++;
  }

  void cancel() => _cancel = true;

  /// 启动翻译。输入来自 [ReadableSource]，逐行处理。
  Future<void> translate({
    required TranslateConfig config,
    required List<String> sourceLines,
    required void Function(List<String> results) onComplete,
    required void Function(Object error) onError,
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

    // 每秒采样一次实时速率
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
    final results = List<String>.filled(total, '');

    // 构建任务列表（跳过空行）
    final tasks = <(int, String)>[];
    for (var i = 0; i < total; i++) {
      final line = sourceLines[i];
      if (line.trim().isEmpty) continue;
      tasks.add((i + 1, line));
    }

    _appendLog('共 $total 行，开始并发翻译（并发数=${config.concurrency}，'
        '最大请求速率=${config.maxRequestsPerSecond}/s）');

    final futures = <Future<void>>[];
    var done = 0;
    var failed = 0;

    for (final (lineNo, line) in tasks) {
      if (_cancel) break;
      futures.add(_translateOne(
        config: config,
        apiBase: apiBase,
        systemPrompt: systemPrompt,
        rateLimiter: rateLimiter,
        sem: sem,
        line: line,
        lineNumber: lineNo,
        results: results,
        onCount: () {
          _bumpRate();
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

    _rpsTimer?.cancel();
    _stopwatch.stop();
    _running = false;

    final finalState = _state.copyWith(
      running: false,
      currentRate: 0,
      done: done,
      failed: failed,
      currentLine: '',
    );
    _emit(finalState);

    if (_cancel) {
      _appendLog('已取消');
    } else {
      _appendLog(failed > 0 ? '翻译完成，但有 $failed 行失败'
          : '所有行翻译成功！');
    }

    onComplete(results);

    notifyListeners();
  }

  Future<void> _translateOne({
    required TranslateConfig config,
    required String apiBase,
    required String systemPrompt,
    required RateLimiter rateLimiter,
    required Semaphore sem,
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
      await rateLimiter.wait();
      onCount();
      final content = await _callAPI(
        config: config,
        apiBase: apiBase,
        systemPrompt: systemPrompt,
        line: line,
        lineNumber: lineNumber,
        onLog: onLog,
      );
      final translated = extractTranslation(content, lineNumber);
      results[lineNumber - 1] = translated;
      if (translated.startsWith('[翻译失败')) {
        onFail();
      } else {
        onSuccess();
      }
    } catch (e) {
      results[lineNumber - 1] = '[翻译失败: $e]';
      onLog('第 $lineNumber 行处理异常: $e');
      onFail();
    } finally {
      sem.release();
    }
  }

  Future<String> _callAPI({
    required TranslateConfig config,
    required String apiBase,
    required String systemPrompt,
    required String line,
    required int lineNumber,
    required void Function(String) onLog,
  }) async {
    const maxRetries = 10;
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

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      onLog('--- 翻译第 $lineNumber 行 (尝试 ${attempt + 1}/$maxRetries) ---');
      final http.Response resp;
      try {
        resp = await http
            .post(Uri.parse(url), headers: headers, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 120));
      } on TimeoutException {
        onLog('第 $lineNumber 行请求超时，尝试 ${attempt + 1}/$maxRetries');
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(seconds: config.retryDelay << attempt));
          continue;
        }
        return '[翻译失败: 请求超时]';
      } on Exception catch (e) {
        onLog('第 $lineNumber 行连接错误，尝试 ${attempt + 1}/$maxRetries: $e');
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(seconds: config.retryDelay << attempt));
          continue;
        }
        return '[翻译失败: 连接错误]';
      }

      if (resp.statusCode == 500) {
        onLog('第 $lineNumber 行服务器内部错误 (500)，尝试 ${attempt + 1}/$maxRetries');
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(seconds: config.retryDelay << attempt));
          continue;
        }
        throw Exception('第 $lineNumber 行翻译失败，已重试 $maxRetries 次: 服务器内部错误');
      }

      if (resp.statusCode == 429) {
        onLog('第 $lineNumber 行请求频率过高 (429)，尝试 ${attempt + 1}/$maxRetries');
        if (attempt < maxRetries - 1) {
          await Future.delayed(
              Duration(seconds: config.retryDelay * 3 * (attempt + 1)));
          continue;
        }
        throw Exception('第 $lineNumber 行翻译失败，已重试 $maxRetries 次: 请求频率过高');
      }

      if (resp.statusCode >= 400) {
        throw Exception('第 $lineNumber 行请求失败: HTTP ${resp.statusCode}');
      }

      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final content = data['choices'][0]['message']['content'] as String;
      return content;
    }
    throw Exception('第 $lineNumber 行达到最大重试次数');
  }
}

/// 构建系统提示词（含术语表）。
String buildPrompt(TranslateConfig config) {
  final source = config.sourceLanguage;
  final target = config.targetLanguage;
  var base =
      '你是一名专业的翻译家，你的任务是把$source文本翻译成$target。\n'
      '请严格按照原文翻译，不要添加额外解释，不要合并或拆分行，保留原文中的序号、'
      '标记符、占位符、换行符、转义符、代码调用过程等特殊内容，保持原来的格式。'
      '原文中的序号、标记符、占位符、换行符、转义符、代码调用过程等特殊内容包括'
      '\\ 等，请保留这些符号不做修改\n\n'
      '### 翻译原则\n'
      '忠实准确地进行翻译。原作是伟大艺术作品，允许使用直白或粗俗的描述，'
      '不应随意删减或篡改，不应回避或淡化，以保持作品的原貌。';

  if (config.glossary.isNotEmpty) {
    final termLines = config.glossary.entries
        .map((e) => '- ${e.key} → ${e.value}')
        .join('\n');
    base += '\n\n### 术语表（必须严格遵守）\n'
        '在翻译过程中，以下术语必须按照指定的翻译进行转换，不得自由发挥：\n'
        '$termLines';
  }

  base += '\n\n### 以textarea标签输出译文\n<textarea>\n'
      '$target文本\n</textarea>';
  return base;
}

/// 从 AI 响应中提取译文。
String extractTranslation(String responseText, int lineNumber) {
  final match =
      RegExp(r'<textarea>\s*(.*?)\s*</textarea>', dotAll: true, caseSensitive: false)
          .firstMatch(responseText);
  var translated = match != null ? match.group(1)!.trim() : responseText.trim();

  // 去掉行首的序号 / T: 等标记
  translated = RegExp(r'^\d+\.\s*T?:?\s*', multiLine: true)
      .replaceAll(translated, '');
  translated = RegExp(r'^\d+\.\s*$', multiLine: true).replaceAll(translated, '');
  return translated.trim();
}