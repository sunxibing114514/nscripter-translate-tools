// 校对引擎测试：以 MockClient 离线验证。
// 重点：503（如模型名填错时代理返回“No available channel”）等一切失败
// 都要重试；持续失败时窗口内的行以「校验失败」标记进报告（不静默缺失）；
// LLM 输出解析与行号对齐。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
// 同一前缀导入两个库：MockClient 在 testing.dart，Response/Client 在 http.dart
import 'package:http/testing.dart' as http;
import 'package:nscript_translate_tools/src/proofread_engine.dart';
import 'package:nscript_translate_tools/src/translate_engine.dart';

TranslateConfig _config({int maxRetries = 3, String provider = 'deepseek'}) =>
    TranslateConfig(
      provider: provider,
      apiKey: 'k',
      apiBase: '',
      model: 'm',
      sourceLanguage: 'Japanese',
      targetLanguage: 'Chinese',
      concurrency: 2,
      maxRequestsPerSecond: 1000,
      maxRetries: maxRetries,
      retryDelay: 0, // 测试中退避等待为 0
    );

http.Response _ok(String content) => http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content}
        }
      ]
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'});

// new-api 类代理在模型不存在时返回 503 + JSON 错误体
http.Response _modelNotFound() => http.Response(
    jsonEncode({
      'error': {
        'code': 'model_not_found',
        'message': 'No available channel for model snvidia/x under group default',
        'type': 'new_api_error',
      }
    }),
    503,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  test('成功：解析 LLM 逐行输出，未评定的行默认通过', () async {
    final engine = ProofreadEngine();
    final client = http.MockClient((req) async => _ok(
        '第 1 行|OK|无问题\n'
        '第 2 行|错译|语义不符|正确译文\n'
        '第 3 行|漏译|译文缺失\n'));
    final issues = <ProofIssue>[];
    await engine.check(
      config: _config(),
      origLines: ['こんにちは', 'テスト', 'さようなら', 'おはよう'],
      transLines: ['你好', '测试', '', '早上好'],
      onBatch: issues.addAll,
      onComplete: () {},
      onError: (_) {},
      httpClient: client,
    );
    expect(issues.length, 4);
    expect(issues[0].type, 'OK');
    expect(issues[1].type, '错译');
    expect(issues[1].detail, '语义不符');
    expect(issues[1].suggested, '正确译文');
    expect(issues[2].type, '漏译');
    expect(issues[2].suggested, isNull);
    // LLM 只评定了前 3 行，第 4 行默认 OK
    expect(issues[3].type, 'OK');
    expect(engine.state.doneWindows, 1);
    expect(engine.state.failedWindows, 0);
    expect(engine.state.running, isFalse);
  });

  test('503（模型不存在）按退避重试后成功', () async {
    final engine = ProofreadEngine();
    var calls = 0;
    final client = http.MockClient((req) async {
      calls++;
      return calls == 1 ? _modelNotFound() : _ok('第 1 行|OK|无问题');
    });
    final issues = <ProofIssue>[];
    await engine.check(
      config: _config(maxRetries: 3),
      origLines: ['こんにちは', 'テスト'],
      transLines: ['你好', '测试'],
      onBatch: issues.addAll,
      onComplete: () {},
      onError: (_) {},
      httpClient: client,
    );
    expect(calls, 2); // 第一次 503，第二次成功
    expect(issues.length, 2);
    expect(issues.every((i) => i.ok), isTrue);
    expect(engine.state.failedWindows, 0);
    // 日志里能看到 503 及代理给出的原因
    expect(engine.state.log.any((l) => l.contains('503')), isTrue);
    expect(
        engine.state.log.any((l) => l.contains('No available channel')), isTrue);
  });

  test('持续 503：窗口内的行以「校验失败」进报告，不静默缺失', () async {
    final engine = ProofreadEngine();
    final client = http.MockClient((req) async => _modelNotFound());
    final issues = <ProofIssue>[];
    await engine.check(
      config: _config(maxRetries: 0),
      origLines: ['こんにちは', 'テスト', 'さようなら', 'おはよう'],
      transLines: ['你好', '测试', '再见', '早上好'],
      onBatch: issues.addAll,
      onComplete: () {},
      onError: (_) {},
      httpClient: client,
    );
    expect(engine.state.failedWindows, 1);
    expect(issues.length, 4); // 4 行全部出现在报告里
    for (final i in issues) {
      expect(i.type, '校验失败');
      expect(i.ok, isFalse);
      expect(i.detail, contains('503'));
      expect(i.detail, contains('No available channel'));
    }
    expect(engine.state.running, isFalse);
  });

  test('窗口切分：每窗口独立请求，行号跨窗口对齐', () async {
    final engine = ProofreadEngine();
    final client = http.MockClient((req) async => _ok(List.generate(
            8, (i) => '第 ${i + 1} 行|OK|无问题').join('\n')));
    final issues = <ProofIssue>[];
    final orig = List.generate(8, (i) => '原文$i');
    final trans = List.generate(8, (i) => '译文$i');
    await engine.check(
      config: _config(),
      origLines: orig,
      transLines: trans,
      windowSize: 3, // 3+3+2 = 3 个窗口
      onBatch: issues.addAll,
      onComplete: () {},
      onError: (_) {},
      httpClient: client,
    );
    expect(engine.state.totalWindows, 3);
    expect(engine.state.doneWindows, 3);
    expect(issues.length, 8);
    // 并发完成顺序不确定，按行号排序后再比对
    final lineNos = issues.map((i) => i.lineNo).toList()..sort();
    expect(lineNos, List.generate(8, (i) => i + 1));
  });

  test('原文译文行数不一致时按较短边校对', () async {
    final engine = ProofreadEngine();
    final client =
        http.MockClient((req) async => _ok('第 1 行|OK|无问题\n第 2 行|OK|无问题'));
    final issues = <ProofIssue>[];
    await engine.check(
      config: _config(),
      origLines: ['あ', 'い'],
      transLines: ['甲', '乙', '丙'],
      onBatch: issues.addAll,
      onComplete: () {},
      onError: (_) {},
      httpClient: client,
    );
    expect(issues.length, 2);
    expect(engine.state.doneWindows, 1);
  });

  test('未知提供商且未填地址：抛错且引擎不卡在 running', () async {
    final engine = ProofreadEngine();
    final client = http.MockClient((req) async => _ok('x'));
    await expectLater(
      engine.check(
        config: _config(provider: 'nope'),
        origLines: ['あ'],
        transLines: ['甲'],
        onBatch: (_) {},
        onComplete: () {},
        onError: (_) {},
        httpClient: client,
      ),
      throwsArgumentError,
    );
    expect(engine.state.running, isFalse);
  });
}
