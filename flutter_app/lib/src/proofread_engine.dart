/// AI 校对引擎：对照原文检查译文的错译 / 漏译 / 串行 / 多译。
///
/// 复用 [TranslateConfig] 与限速/并发控制。将原文行与译文行按窗口批量提交给
/// LLM，逐行判定并返回校验结果，方便人工复核。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'translate_engine.dart'
    show
        Semaphore,
        TranslateConfig,
        RateLimiter,
        backoffSeconds,
        errorDetailFromBody;

/// 单行校验结果。
class ProofIssue {
  final int lineNo; // 1-based
  final String type; // OK / 错译 / 漏译 / 串行 / 多译 / 未知
  final String detail;
  final String? suggested; // 建议译文（可选）
  const ProofIssue({
    required this.lineNo,
    required this.type,
    required this.detail,
    this.suggested,
  });

  bool get ok => type == 'OK';
}

/// 校对过程状态。
@immutable
class ProofState {
  final bool running;
  final int totalWindows;
  final int doneWindows;
  final int failedWindows;
  final List<String> log;
  const ProofState({
    this.running = false,
    this.totalWindows = 0,
    this.doneWindows = 0,
    this.failedWindows = 0,
    this.log = const [],
  });
  double get progress =>
      totalWindows == 0 ? 0 : doneWindows / totalWindows;
  ProofState copyWith({
    bool? running,
    int? totalWindows,
    int? doneWindows,
    int? failedWindows,
    List<String>? log,
  }) {
    return ProofState(
      running: running ?? this.running,
      totalWindows: totalWindows ?? this.totalWindows,
      doneWindows: doneWindows ?? this.doneWindows,
      failedWindows: failedWindows ?? this.failedWindows,
      log: log ?? this.log,
    );
  }
}

/// 校对引擎。
class ProofreadEngine extends ChangeNotifier {
  ProofState _state = const ProofState();
  ProofState get state => _state;
  bool _running = false;
  bool _cancel = false;

  void _emit(ProofState s) {
    _state = s;
    notifyListeners();
  }

  void _log(String msg) {
    final newLog = [..._state.log, msg];
    _emit(_state.copyWith(
        log: newLog.length > 300 ? newLog.sublist(newLog.length - 300) : newLog));
  }

  void cancel() => _cancel = true;

  /// 启动校对。原文与译文行一一对齐（长度应相同）。
  ///
  /// [httpClient] 仅供测试注入 MockClient；生产为 null 时使用默认 Client
  ///（整个任务复用连接）。
  Future<void> check({
    required TranslateConfig config,
    required List<String> origLines,
    required List<String> transLines,
    required void Function(List<ProofIssue> issues) onBatch,
    required void Function() onComplete,
    required void Function(Object error) onError,
    int windowSize = 8,
    http.Client? httpClient,
  }) async {
    if (_running) return;
    _running = true;
    _cancel = false;
    _emit(const ProofState(running: true, log: []));

    // 行数不匹配：先记录，作为整体性提示
    if (origLines.length != transLines.length) {
      _log('⚠️ 原文 ${origLines.length} 行 ≠ 译文 ${transLines.length} 行，'
          '可能存在漏译/多译，请结合逐行结果复核。');
    }

    final n = origLines.length < transLines.length
        ? origLines.length
        : transLines.length;
    if (n == 0) {
      _emit(const ProofState());
      _running = false;
      onComplete();
      return;
    }

    // 分窗口
    final windows = <(int, List<(int, String, String)>)>[];
    for (var start = 0; start < n; start += windowSize) {
      final end = start + windowSize < n ? start + windowSize : n;
      final pairs = <(int, String, String)>[];
      for (var i = start; i < end; i++) {
        pairs.add((i + 1, origLines[i], transLines[i]));
      }
      windows.add((start, pairs));
    }

    _emit(_state.copyWith(totalWindows: windows.length));
    final client = httpClient ?? http.Client();
    try {
      final apiBase = config.resolvedBase();
      final rateLimiter = RateLimiter(config.maxRequestsPerSecond);
      final sem = Semaphore(config.concurrency);
      final futures = <Future<void>>[];
      var done = 0;
      var failed = 0;
      var reported = 0;

      for (final (_, pairs) in windows) {
        if (_cancel) break;
        futures.add(_checkWindow(
          config: config,
          apiBase: apiBase,
          client: client,
          rateLimiter: rateLimiter,
          sem: sem,
          pairs: pairs,
          onIssue: (issues) {
            onBatch(issues);
            reported += issues.where((i) => !i.ok).length;
          },
          onSuccess: () {
            done++;
            _emit(_state.copyWith(doneWindows: done, failedWindows: failed));
          },
          onFail: () {
            failed++;
            _emit(_state.copyWith(doneWindows: done, failedWindows: failed));
          },
          onLog: _log,
        ));
      }

      await Future.wait(futures);
      _emit(_state.copyWith(
          running: false, doneWindows: done, failedWindows: failed));
      if (failed > 0) {
        _log('校对结束：共发现 $reported 个疑似问题'
            '（含错译/漏译/串行/多译/校验失败）；'
            '另有 $failed 个窗口请求失败，对应行已标记为「校验失败」，请人工复核。');
      } else {
        _log('校对完成：共发现 $reported 个疑似问题（含错译/漏译/串行/多译），请人工复核。');
      }
      if (_cancel) _log('已取消（未校验的行不会出现在报告中）');
      onComplete();
    } finally {
      // 无论正常结束还是异常（如未知的提供商 api_base），都不能卡在 running
      _running = false;
      if (httpClient == null) client.close();
      if (_state.running) _emit(_state.copyWith(running: false));
      notifyListeners();
    }
  }

  Future<void> _checkWindow({
    required TranslateConfig config,
    required String apiBase,
    required http.Client client,
    required RateLimiter rateLimiter,
    required Semaphore sem,
    required List<(int, String, String)> pairs,
    required void Function(List<ProofIssue>) onIssue,
    required VoidCallback onSuccess,
    required VoidCallback onFail,
    required void Function(String) onLog,
  }) async {
    await sem.acquire();
    try {
      await rateLimiter.wait();
      final (start, issues) = await _callProofread(
        config: config,
        apiBase: apiBase,
        client: client,
        pairs: pairs,
        onLog: onLog,
      );
      onLog('窗口(第 $start-${start + pairs.length - 1} 行)完成');
      onIssue(issues);
      onSuccess();
    } catch (e) {
      onLog('窗口处理异常: $e');
      // 窗口内的行按「校验失败」标记进入报告——不能静默缺失，
      // 否则报告行数对不上、且看起来像“没有问题”。
      onIssue(pairs
          .map((p) => ProofIssue(
                lineNo: p.$1,
                type: '校验失败',
                detail: '该行所在窗口的校验请求失败：$e',
              ))
          .toList());
      onFail();
    } finally {
      sem.release();
    }
  }

  /// 与翻译引擎的 _callAPI 语义对齐：任何失败（含 503 等 5xx、
  /// 4xx、超时、响应结构异常）都按退避重试，最终失败才抛出。
  /// 每次失败都把响应体中的可读原因带进日志（如 503 的
  /// “No available channel for model xxx”，即模型名填错）。
  Future<(int, List<ProofIssue>)> _callProofread({
    required TranslateConfig config,
    required String apiBase,
    required http.Client client,
    required List<(int, String, String)> pairs,
    required void Function(String) onLog,
  }) async {
    final attempts = config.maxRetries + 1;
    final url = '${apiBase.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
    final headers = {
      'Authorization': 'Bearer ${config.apiKey}',
      'Content-Type': 'application/json',
    };
    final start = pairs.first.$1;

    final textRows = pairs
        .map((p) => '第 ${p.$1} 行\n原文：${p.$2}\n译文：${p.$3}')
        .join('\n\n');

    final system =
        '你是一名专业的翻译校对手。你会收到一段已抽取的游戏文本原文与对应的译文。'
        '你的任务是逐行核对译文是否与原文匹配，找出以下四类问题并给出修正建议：\n'
        '- 漏译：译文缺失、为空、或与原文明显无关/语义严重缺失。\n'
        '- 错译：译文与原文语义不符、人名地名术语错误、明显误译。\n'
        '- 串行：相邻行的译文与原文上下文不连贯、译文顺序错位/重复/张冠李戴。\n'
        '- 多译：译文对原文做了额外发挥、擅自增删内容。\n\n'
        '请对每一行严格按下面格式输出一行（不要输出其他任何内容）：\n'
        '行号|状态|说明\n'
        '状态取值：OK / 漏译 / 错译 / 串行 / 多译\n'
        '若状态不是 OK，请在说明后用“ ”加上你建议的修正译文：\n'
        '行号|错译|说明|建议译文\n'
        '规则：原文中的 \\、@、标记符等请保留，不要改动。不要输出空行外的任何解释。';

    final user =
        '以下是第 $start 行起的 ${pairs.length} 行原文与译文，请逐行校对：\n\n$textRows';

    final payload = {
      'model': config.model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'temperature': 0,
    };

    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      onLog('--- 校对窗口(第 $start 行起) 尝试 ${attempt + 1}/$attempts ---');
      try {
        final resp = await client
            .post(Uri.parse(url), headers: headers, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 120));

        if (resp.statusCode == 429 || resp.statusCode >= 500) {
          // 503（渠道不可用/模型不存在）、500、502 等服务端错误：
          // 与 429 一样按退避重试，并把响应体里的原因带出来
          final detail = errorDetailFromBody(resp);
          lastError =
              'HTTP ${resp.statusCode}${detail.isEmpty ? '' : '：$detail'}';
          if (attempt < attempts - 1) {
            final wait = backoffSeconds(
                config.retryDelay, resp.statusCode == 429 ? 3 : 2, attempt);
            onLog('第 $start 行起的窗口，请求失败 $lastError，等待 $wait 秒后重试…');
            await Future.delayed(Duration(seconds: wait));
            continue;
          }
          break;
        }
        if (resp.statusCode >= 400) {
          final detail = errorDetailFromBody(resp);
          lastError =
              'HTTP ${resp.statusCode}${detail.isEmpty ? '' : '：$detail'}';
          if (attempt < attempts - 1) {
            final wait = backoffSeconds(config.retryDelay, 2, attempt);
            onLog('第 $start 行起的窗口，请求失败 $lastError，等待 $wait 秒后重试…');
            await Future.delayed(Duration(seconds: wait));
            continue;
          }
          break;
        }

        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final content = data['choices'][0]['message']['content'];
        if (content is! String || content.trim().isEmpty) {
          // 部分推理模型在异常路径下 content 为空/缺失
          throw const FormatException('响应缺少 choices[0].message.content');
        }
        return (start, _parseIssues(content, pairs));
      } on TimeoutException {
        lastError = '请求超时';
        if (attempt < attempts - 1) {
          final wait = backoffSeconds(config.retryDelay, 2, attempt);
          onLog('第 $start 行起的窗口请求超时，等待 $wait 秒后重试…');
          await Future.delayed(Duration(seconds: wait));
          continue;
        }
        break;
      } catch (e) {
        // 与翻译引擎一致：连接错误、响应结构异常（含 content 缺失）等一律重试
        lastError = '$e';
        if (attempt < attempts - 1) {
          final wait = backoffSeconds(config.retryDelay, 2, attempt);
          onLog('第 $start 行起的窗口请求异常: $e，等待 $wait 秒后重试…');
          await Future.delayed(Duration(seconds: wait));
          continue;
        }
        break;
      }
    }
    throw Exception('校对窗口请求失败（已重试 ${config.maxRetries} 次）：$lastError');
  }

  /// 解析 LLM 输出。
  List<ProofIssue> _parseIssues(
      String content, List<(int, String, String)> pairs) {
    final issues = <ProofIssue>[];
    final expectedLines = pairs.map((p) => p.$1).toSet();
    final byLine = <int, ProofIssue>{};
    // 兼容可能被 LLM 加 markdown 代码块包裹
    var text = content.replaceAll(RegExp(r'```.*?\n?', dotAll: true), '');
    for (final line in text.split('\n')) {
      final l = line.trim();
      if (l.isEmpty) continue;
      final parts = l.split('|');
      if (parts.length < 3) continue;
      final lineNo = int.tryParse(parts[0].replaceAll(RegExp(r'[^\d]'), ''));
      if (lineNo == null || !expectedLines.contains(lineNo)) continue;
      final type = parts[1].trim();
      var typeNorm = '未知';
      final t = type.toLowerCase();
      if (t == 'ok') typeNorm = 'OK';
      else if (t.contains('漏') || t.contains('缺')) typeNorm = '漏译';
      else if (t.contains('错')) typeNorm = '错译';
      else if (t.contains('串')) typeNorm = '串行';
      else if (t.contains('多')) typeNorm = '多译';
      final detail = parts.length > 2 ? parts[2].trim() : '';
      final suggested = parts.length > 3 ? parts[3].trim() : null;
      byLine[lineNo] = ProofIssue(
          lineNo: lineNo, type: typeNorm, detail: detail, suggested: suggested);
    }
    // 补齐 LLM 未评定的行，默认 OK
    for (final l in pairs.map((p) => p.$1)) {
      if (!byLine.containsKey(l)) {
        byLine[l] = const ProofIssue(
            lineNo: 0, type: 'OK', detail: '（未明确标注，默认通过）').copyFor(l);
      }
    }
    final sorted = byLine.keys.toList()..sort();
    sorted.forEach((k) => issues.add(byLine[k]!));
    return issues;
  }
}

extension on ProofIssue {
  ProofIssue copyFor(int lineNo) =>
      ProofIssue(lineNo: lineNo, type: type, detail: detail, suggested: suggested);
}