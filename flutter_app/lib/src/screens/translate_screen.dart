import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../file_utils.dart';
import '../settings.dart';
import '../translate_engine.dart';
import '../widgets.dart';

class TranslateScreen extends StatefulWidget {
  final AppSettings settings;
  const TranslateScreen({super.key, required this.settings});

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> {
  final TranslateEngine _engine = TranslateEngine();

  final _apiKey = TextEditingController();
  final _apiBase = TextEditingController();
  final _model = TextEditingController();
  final _glossary = TextEditingController();
  final _sourceLang = TextEditingController(text: 'Japanese');
  final _targetLang = TextEditingController(text: 'Chinese');
  late final TextEditingController _concurrencyCtrl;
  late final TextEditingController _maxRpsCtrl;

  String _provider = 'deepseek';
  int _concurrency = 5;
  int _maxRps = 10;
  bool _showDefaults = false;

  String? _inputPath;
  Uint8List _results = Uint8List(0);
  String _outputName = '';

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _provider = s.provider;
    _apiKey.text = s.apiKey;
    _apiBase.text = s.apiBase;
    _model.text = s.model;
    _sourceLang.text = s.sourceLanguage;
    _targetLang.text = s.targetLanguage;
    _concurrency = s.concurrency;
    _maxRps = s.maxRequestsPerSecond;
    _glossary.text = _glossaryToString(s.glossary);
    _concurrencyCtrl = TextEditingController(text: '$_concurrency');
    _maxRpsCtrl = TextEditingController(text: '$_maxRps');
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _apiBase.dispose();
    _model.dispose();
    _glossary.dispose();
    _sourceLang.dispose();
    _targetLang.dispose();
    _concurrencyCtrl.dispose();
    _maxRpsCtrl.dispose();
    _engine.dispose();
    super.dispose();
  }

  String _glossaryToString(Map<String, String> g) =>
      g.entries.map((e) => '${e.key}=${e.value}').join('\n');

  Map<String, String> _parseGlossary() {
    final map = <String, String>{};
    for (final line in _glossary.text.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (t.contains('=')) {
        final i = t.indexOf('=');
        final k = t.substring(0, i).trim();
        final v = t.substring(i + 1).trim();
        if (k.isNotEmpty) map[k] = v;
      }
    }
    return map;
  }

  Future<void> _pickInput() async {
    final path = await pickFile(extensions: ['txt']);
    if (path == null) return;
    setState(() {
      _inputPath = path;
      _results = Uint8List(0);
    });
  }

  Future<void> _saveConfig() async {
    final s = widget.settings;
    s.provider = _provider;
    s.apiKey = _apiKey.text.trim();
    s.apiBase = _apiBase.text.trim();
    s.model = _model.text.trim();
    s.sourceLanguage = _sourceLang.text.trim();
    s.targetLanguage = _targetLang.text.trim();
    s.concurrency = _concurrency;
    s.maxRequestsPerSecond = _maxRps;
    s.glossary = _parseGlossary();
    _showSnack('配置已保存');
  }

  Future<void> _start() async {
    if (_engine.state.running) {
      _engine.cancel();
      return;
    }
    if (_inputPath == null) {
      _showSnack('请先选择待翻译的输入文件');
      return;
    }
    if (_apiKey.text.trim().isEmpty) {
      _showSnack('请填写 API Key');
      return;
    }
    try {
      final bytes = await readBytes(_inputPath!);
      final source = utf8.decode(bytes, allowMalformed: true);
      final lines =
          source.trimRight().split('\n').map((l) => l.replaceAll('\r', '')).toList();

      final config = TranslateConfig(
        provider: _provider,
        apiKey: _apiKey.text.trim(),
        apiBase: _apiBase.text.trim(),
        model: _model.text.trim(),
        sourceLanguage: _sourceLang.text.trim(),
        targetLanguage: _targetLang.text.trim(),
        concurrency: _concurrency,
        maxRequestsPerSecond: _maxRps.toDouble(),
        glossary: _parseGlossary(),
      );

      // 输出文件名：原文件名_目标语言.txt
      final base = _inputPath!.split('/').last;
      final dot = base.lastIndexOf('.');
      final name = dot == -1 ? base : base.substring(0, dot);
      final ext = dot == -1 ? '' : base.substring(dot);

      await _engine.translate(
        config: config,
        sourceLines: lines,
        onComplete: (results) async {
          final out = results.join('\n');
          _outputName = '${name}_${config.targetLanguage}$ext';
          _results = Uint8List.fromList(utf8.encode(out));
        },
        onError: (e) => _showSnack('翻译异常：$e'),
      );
    } catch (e) {
      _showSnack('读取输入文件失败：$e');
    }
  }

  Future<void> _save() async {
    if (_results.isEmpty) {
      _showSnack('暂无可保存的翻译结果');
      return;
    }
    final saved = await saveBytes(_outputName.isEmpty ? 'out.txt' : _outputName, _results);
    if (saved != null) _showSnack('已保存到：$saved');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 批量翻译')),
      body: AnimatedBuilder(
        animation: _engine,
        builder: (context, _) {
          final st = _engine.state;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (st.running) _buildProgressCard(st),
              _buildSteps(),
              _buildConfigForm(st),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: st.running ? _engine.cancel : _start,
                      icon: Icon(st.running ? Icons.stop : Icons.play_arrow),
                      label: Text(st.running ? '停止' : '开始翻译'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_results.isEmpty || st.running) ? null : _save,
                      icon: const Icon(Icons.save),
                      label: const Text('保存译文'),
                    ),
                  ),
                ],
              ),
              if (_results.isNotEmpty) ...[
                const SizedBox(height: 12),
                ResultBox(
                  title: '译文预览（$_outputName）',
                  text: String.fromCharCodes(_results.length > 4000
                      ? _results.sublist(0, 4000)
                      : _results),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildProgressCard(TranslateState st) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('翻译进度',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onPrimaryContainer)),
            const SizedBox(height: 12),
            // 实时速率 - 核心需求
            Row(
              children: [
                Expanded(
                  child: _RateBox(
                    label: '实时速率',
                    value: '${st.currentRate.toStringAsFixed(1)} 次/秒',
                    icon: Icons.speed,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _RateBox(
                    label: '平均速率',
                    value: '${st.averageRate.toStringAsFixed(1)} 次/秒',
                    icon: Icons.trending_up,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: st.progress.clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .onPrimaryContainer
                    .withOpacity(0.15),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${st.done} 成功 / ${st.failed} 失败　共 ${st.total} 行　' +
                  '(${(st.progress * 100).toStringAsFixed(1)}%)',
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
            if (st.currentLine.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('当前：${st.currentLine}',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 8),
            Text('实时日志（最近 ${st.log.length} 条）：', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Container(
              height: 140,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(8),
              child: ListView.builder(
                reverse: true,
                itemCount: st.log.length,
                itemBuilder: (_, i) {
                  final line = st.log[st.log.length - 1 - i];
                  return Text(line,
                      style: const TextStyle(color: Colors.white70, fontSize: 11));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSteps() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Text('步骤：1) 选择输入文件（提取产出的翻译文件）  2) 填写平台/密钥/模型  3) 点击“开始翻译”',
          style: TextStyle(fontSize: 12, color: Colors.grey)),
    );
  }

  Widget _buildConfigForm(TranslateState st) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: Text(_inputPath ?? '选择待翻译的输入文件 (.txt)'),
            subtitle: const Text('由“文本提取”生成的文件'),
            onTap: st.running ? null : _pickInput,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _provider,
          decoration: const InputDecoration(
              labelText: '提供商', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'deepseek', child: Text('deepseek')),
            DropdownMenuItem(value: 'openai', child: Text('openai')),
            DropdownMenuItem(value: 'qwen', child: Text('qwen')),
            DropdownMenuItem(value: 'zhipu', child: Text('zhipu')),
            DropdownMenuItem(value: 'custom', child: Text('自定义')),
          ],
          onChanged: st.running ? null : (v) => setState(() => _provider = v ?? _provider),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _apiKey,
          enabled: !st.running,
          obscureText: !_showDefaults,
          decoration: const InputDecoration(
              labelText: 'API Key', border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.key)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _apiBase,
          enabled: !st.running,
          decoration: const InputDecoration(
              labelText: 'API Base（留空则按提供商自动填充）',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _model,
          enabled: !st.running,
          decoration: const InputDecoration(
              labelText: '模型（如 deepseek-chat）', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _sourceLang,
                enabled: !st.running,
                decoration: const InputDecoration(
                    labelText: '原文语言', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _targetLang,
                enabled: !st.running,
                decoration: const InputDecoration(
                    labelText: '目标语言', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _concurrencyCtrl,
                enabled: !st.running,
                keyboardType: TextInputType.number,
                onChanged: (v) =>
                    _concurrency = int.tryParse(v) ?? 3,
                decoration: const InputDecoration(
                    labelText: '并发数', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _maxRpsCtrl,
                enabled: !st.running,
                keyboardType: TextInputType.number,
                onChanged: (v) => _maxRps = int.tryParse(v) ?? 5,
                decoration: const InputDecoration(
                    labelText: '最大每秒请求数', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _glossary,
          enabled: !st.running,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
              labelText: '术语表（每行 源=目标）',
              hintText: '龍=龙\n精霊=精灵',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: st.running ? null : _saveConfig,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存配置'),
          ),
        ),
      ],
    );
  }
}

class _RateBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _RateBox({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Theme.of(context).colorScheme.onPrimary),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, color: Theme.of(context).colorScheme.onPrimary)),
            ],
          ),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: onPrimary)),
        ],
      ),
    );
  }
}