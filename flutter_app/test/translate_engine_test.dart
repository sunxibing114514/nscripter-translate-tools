// 翻译引擎测试：以 main（translate.py）为基准的核心行为。
// 使用 MockClient 离线验证：重试语义、失败保留原文、前缀处理、
// 源语言跳过、限速/并发参数钳制。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
// 同一前缀导入两个库：MockClient 在 testing.dart，Response/Client 在 http.dart
import 'package:http/testing.dart' as http;
import 'package:nscript_translate_tools/src/translate_engine.dart';

TranslateConfig _config({
  int maxRetries = 3,
  int concurrency = 2,
  double maxRps = 1000,
  String provider = 'deepseek',
  String apiBase = '',
  Map<String, String> glossary = const {},
}) =>
    TranslateConfig(
      provider: provider,
      apiKey: 'test-key',
      apiBase: apiBase,
      model: 'test-model',
      sourceLanguage: 'Japanese',
      targetLanguage: 'Chinese',
      concurrency: concurrency,
      maxRequestsPerSecond: maxRps,
      maxRetries: maxRetries,
      retryDelay: 1,
      glossary: glossary,
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
    // Response 默认按 Content-Type 的 charset 编码字符串体（缺省 latin1），
    // 显式声明 utf-8，中文内容才不会在 bodyBytes 里变成乱码。
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  group('TranslateConfig.resolvedBase（main: 默认 API 地址）', () {
    test('按提供商补全默认地址', () {
      expect(_config().resolvedBase(), 'https://api.deepseek.com/v1');
      expect(
        TranslateConfig(
          provider: 'qwen',
          apiKey: 'k',
          apiBase: '',
          model: 'm',
          sourceLanguage: 'Japanese',
          targetLanguage: 'Chinese',
        ).resolvedBase(),
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
      );
    });

    test('自定义地址未带协议时自动补 https://', () {
      expect(
        _config(apiBase: 'api.example.com/v1').resolvedBase(),
        'https://api.example.com/v1',
      );
      expect(
        _config(apiBase: 'http://api.example.com/v1').resolvedBase(),
        'http://api.example.com/v1',
      );
    });

    test('未知提供商且未填地址时报错', () {
      expect(
        () => _config(provider: 'unknown').resolvedBase(),
        throwsArgumentError,
      );
    });
  });

  group('extractTranslation（main: extract_translation_from_line）', () {
    test('提取 textarea 内容并去空白', () {
      expect(extractTranslation('<textarea>  译文  </textarea>', 1), '译文');
    });

    test('去掉行首序号 / T: 标记', () {
      expect(extractTranslation('1. T:译文', 1), '译文');
      expect(extractTranslation('1. 译文', 1), '译文');
      expect(extractTranslation('1. T:甲\n2. T:乙', 1), '甲\n乙');
    });

    test('无 textarea 标签时使用原始响应', () {
      expect(extractTranslation('没有标签的响应', 1), '没有标签的响应');
    });
  });

  group('buildPrompt（main: build_prompt）', () {
    test('包含 main 提示词中的 @ 与 \\ 符号说明及术语表', () {
      final p = buildPrompt(_config(glossary: {'龍': '龙'}));
      expect(p, contains('@ \\ 等'));
      expect(p, contains('- 龍 → 龙'));
      expect(p, contains('<textarea>'));
      expect(p, contains('Chinese'));
    });
  });

  group('lineContainsSourceLanguage（跳过无源语言行）', () {
    test('日语行判定', () {
      expect(lineContainsSourceLanguage('T:こんにちは', 'Japanese'), isTrue);
      expect(lineContainsSourceLanguage('T:OK', 'Japanese'), isFalse);
      expect(lineContainsSourceLanguage('Q:「……」', 'Japanese'), isFalse);
    });

    test('语言可识别性', () {
      expect(lineContainsSourceLanguageDetectable('Japanese'), isTrue);
      expect(lineContainsSourceLanguageDetectable('日本語'), isTrue);
      expect(lineContainsSourceLanguageDetectable('Klingon'), isFalse);
    });
  });

  group('TranslateEngine.translate（MockClient 离线验证）', () {
    test('成功：保留类型前缀，空行保留', () async {
      final engine = TranslateEngine();
      final client =
          http.MockClient((req) async => _ok('<textarea>你好</textarea>'));
      final results = <String>[];
      await engine.translate(
        config: _config(),
        sourceLines: ['T:こんにちは', 'B:テスト', ''],
        onComplete: results.addAll,
        onError: (_) {},
        httpClient: client,
      );
      expect(results, ['T:你好', 'B:你好', '']);
      expect(engine.state.failed, 0);
      expect(engine.state.running, isFalse);
    });

    test('AI 回显前缀（T：你好，全角冒号）被去掉后补半角前缀', () async {
      final engine = TranslateEngine();
      final client =
          http.MockClient((req) async => _ok('<textarea>T：你好</textarea>'));
      final results = <String>[];
      await engine.translate(
        config: _config(),
        sourceLines: ['T:こんにちは'],
        onComplete: results.addAll,
        onError: (_) {},
        httpClient: client,
      );
      expect(results, ['T:你好']);
    });

    test('AI 回显半角前缀（T:你好）同样不产生双前缀', () async {
      final engine = TranslateEngine();
      final client =
          http.MockClient((req) async => _ok('<textarea>T:你好</textarea>'));
      final results = <String>[];
      await engine.translate(
        config: _config(),
        sourceLines: ['T:こんにちは'],
        onComplete: results.addAll,
        onError: (_) {},
        httpClient: client,
      );
      expect(results, ['T:你好']);
    });

    test('失败行保留原文（含前缀）并计入 failed，不写失败标记', () async {
      final engine = TranslateEngine();
      final client = http.MockClient(
          (req) async => http.Response('server error', 500));
      final results = <String>[];
      await engine.translate(
        config: _config(maxRetries: 0),
        sourceLines: ['T:こんにちは', 'B:テスト'],
        onComplete: results.addAll,
        onError: (_) {},
        httpClient: client,
      );
      // 输出与输入行结构一致，可直接用于注入（main 会写入无前缀的失败标记，
      // 导致注入阶段 Malformed translation line 报错）
      expect(results, ['T:こんにちは', 'B:テスト']);
      expect(engine.state.failed, 2);
      expect(engine.state.running, isFalse);
    });

    test('不含源语言文字的行跳过翻译并保持原样', () async {
      final engine = TranslateEngine();
      final client =
          http.MockClient((req) async => _ok('<textarea>你好</textarea>'));
      final results = <String>[];
      await engine.translate(
        config: _config(),
        sourceLines: ['T:こんにちは', 'T:OK', 'Q:「……」'],
        onComplete: results.addAll,
        onError: (_) {},
        httpClient: client,
      );
      expect(results, ['T:你好', 'T:OK', 'Q:「……」']);
      expect(engine.state.failed, 0);
    });

    test('并发数/速率填 0 时按 1 处理，不卡死', () async {
      final engine = TranslateEngine();
      final client =
          http.MockClient((req) async => _ok('<textarea>好</textarea>'));
      final results = <String>[];
      await engine.translate(
        config: _config(concurrency: 0, maxRps: 0),
        sourceLines: ['T:あ'],
        onComplete: results.addAll,
        onError: (_) {},
        httpClient: client,
      );
      expect(results, ['T:好']);
    });

    test('未知提供商且未填地址：抛错且引擎不卡在 running', () async {
      final engine = TranslateEngine();
      final client = http.MockClient((req) async => _ok('x'));
      await expectLater(
        engine.translate(
          config: _config(provider: 'nope'),
          sourceLines: ['T:あ'],
          onComplete: (_) {},
          onError: (_) {},
          httpClient: client,
        ),
        throwsArgumentError,
      );
      expect(engine.state.running, isFalse);
    });
  });

  group('backoffSeconds（main 的退避公式，指数封顶）', () {
    test('2^n 与 3^n', () {
      expect(backoffSeconds(2, 2, 0), 2);
      expect(backoffSeconds(2, 2, 1), 4);
      expect(backoffSeconds(2, 2, 2), 8);
      expect(backoffSeconds(2, 3, 0), 2);
      expect(backoffSeconds(2, 3, 1), 6);
      expect(backoffSeconds(2, 3, 2), 18);
    });

    test('超大 attempt 被封顶，不会出现 retryDelay<<attempt 的超长等待', () {
      expect(backoffSeconds(2, 2, 20), 2 * 32);
      expect(backoffSeconds(2, 3, 20), 2 * 243);
    });
  });
}
