import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../encodings.dart';
import '../file_utils.dart';
import '../proofread_engine.dart';
import '../settings.dart';
import '../translate_engine.dart';
import '../widgets.dart';

class ProofreadScreen extends StatefulWidget {
  final AppSettings settings;
  const ProofreadScreen({super.key, required this.settings});

  @override
  State<ProofreadScreen> createState() => _ProofreadScreenState();
}

class _ProofreadScreenState extends State<ProofreadScreen> {
  final ProofreadEngine _engine = ProofreadEngine();
  late final TextEditingController _origCtrl;
  late final TextEditingController _transCtrl;
  late final TextEditingController _concCtrl;
  late final TextEditingController _rpsCtrl;

  Uint8List? _origBytes;
  Uint8List? _transBytes;
  String? _origName;
  String? _transName;

  String _origEnc = 'utf8';
  String _transEnc = 'utf8';

  int _concurrency = 3;
  int _maxRps = 5;

  List<ProofIssue> _issues = [];
  String _status = '选择原文与译文文件后开始校对';

  @override
  void initState() {
    super.initState();
    _origCtrl = TextEditingController();
    _transCtrl = TextEditingController();
    _concCtrl = TextEditingController(text: '${widget.settings.concurrency}');
    _rpsCtrl = TextEditingController(text: '${widget.settings.maxRequestsPerSecond}');
    _concurrency = widget.settings.concurrency;
    _maxRps = widget.settings.maxRequestsPerSecond;
  }

  @override
  void dispose() {
    _origCtrl.dispose();
    _transCtrl.dispose();
    _concCtrl.dispose();
    _rpsCtrl.dispose();
    _engine.dispose();
    super.dispose();
  }

  Future<void> _pickOrig() async {
    try {
      final picked = await pickFileBytes();
      if (picked == null) return;
      final (name, bytes) = picked;
      setState(() {
        _origBytes = bytes;
        _origName = name;
        _origCtrl.text = _origCtrl.text.isEmpty ? name : _origCtrl.text;
      });
    } catch (e) {
      _showSnack('选择失败：$e，可手动输入路径');
    }
  }

  Future<void> _pickTrans() async {
    try {
      final picked = await pickFileBytes();
      if (picked == null) return;
      final (name, bytes) = picked;
      setState(() {
        _transBytes = bytes;
        _transName = name;
        _transCtrl.text = _transCtrl.text.isEmpty ? name : _transCtrl.text;
      });
    } catch (e) {
      _showSnack('选择失败：$e，可手动输入路径');
    }
  }

  List<String> _loadLines(Uint8List? bytes, TextEditingController ctrl, String enc) {
    String text;
    if (bytes != null) {
      text = decodeBytes(bytes, enc);
    } else {
      final path = ctrl.text.trim();
      if (path.isEmpty) throw StateError('路径为空');
      text = File(path).existsSync()
          ? decodeBytes(File(path).readAsBytesSync(), enc)
          : '';
    }
    var lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    // 结尾换行符经 split 产生的尾部空串不是真实行；
    // 不去掉会对所有文件都触发「原文 N+1 ≠ 译文 N」的误报。
    if (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return lines;
  }

  Future<void> _start() async {
    if (_engine.state.running) {
      _engine.cancel();
      return;
    }
    if (widget.settings.apiKey.trim().isEmpty) {
      _showSnack('请先在设置中填写 API Key');
      return;
    }
    try {
      final orig = _loadLines(_origBytes, _origCtrl, _origEnc);
      final trans = _loadLines(_transBytes, _transCtrl, _transEnc);
      if (orig.isEmpty && trans.isEmpty) {
        _showSnack('请选择原文与译文文件');
        return;
      }
      setState(() {
        _issues = [];
        _status = '校对中…（后台并发，可稍候）';
      });

      final config = TranslateConfig(
        provider: widget.settings.provider,
        apiKey: widget.settings.apiKey.trim(),
        apiBase: widget.settings.apiBase.trim(),
        model: widget.settings.model.trim(),
        sourceLanguage: '日文',
        targetLanguage: '译文',
        concurrency: _concurrency,
        maxRequestsPerSecond: _maxRps.toDouble(),
        glossary: widget.settings.glossary,
      );

      final collected = <ProofIssue>[];
      await _engine.check(
        config: config,
        origLines: orig,
        transLines: trans,
        onBatch: (issues) {
          collected.addAll(issues);
        },
        onComplete: () {
          collected.sort((a, b) => a.lineNo.compareTo(b.lineNo));
          if (!mounted) return;
          setState(() {
            _issues = collected;
            final issues = collected.where((i) => !i.ok).length;
            _status = '校对完成：共 ${collected.length} 行，其中 $issues 行可能有问题';
          });
        },
        onError: (e) => _showSnack('校对失败：$e'),
      );
    } catch (e) {
      // 文件读取与引擎异常（如未知提供商且未填 api_base）都提示为校对失败
      _showSnack('校对失败：$e');
      if (mounted) {
        setState(() => _status = '校对失败：$e');
      }
    }
  }

  Future<void> _saveReport() async {
    if (_issues.isEmpty) {
      _showSnack('暂无可保存的校对报告');
      return;
    }
    final buf = StringBuffer()
      ..writeln('# AI 校对报告 ${DateTime.now().toString().substring(0, 19)}')
      ..writeln('原文：${_origName ?? '（手动输入）'}')
      ..writeln('译文：${_transName ?? '（手动输入）'}')
      ..writeln('总行数：${_issues.length}')
      ..writeln();
    for (final i in _issues) {
      buf.writeln('${i.lineNo}\t${i.type}\t${i.detail}'
          '${i.suggested != null ? '\t建议: ${i.suggested}' : ''}');
    }
    final bytes = Uint8List.fromList(utf8.encode(buf.toString()));

    // 优先保存到项目 nstran 目录
    final nstran = await widget.settings.ensureNstranFolder();
    if (nstran != null) {
      final target = '$nstran/校对报告_${DateTime.now().millisecondsSinceEpoch}.txt';
      await File(target).writeAsBytes(bytes, flush: true);
      _showSnack('报告已保存：$target');
      return;
    }
    final saved = await saveBytes('校对报告.txt', bytes);
    if (saved != null) _showSnack('报告已保存：$saved');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 校对')),
      body: AnimatedBuilder(
        animation: _engine,
        builder: (context, _) {
          final st = _engine.state;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (st.running) _buildProgressCard(st),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  '对照原文检查译文的错译、漏译、串行、多译。请选择“提取文件（T:/B:/Q: 行）”作为原文，选择对应译文件作为译文。',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
              PathField(
                label: '原文文件（可翻译行）',
                controller: _origCtrl,
                hint: '由“文本提取”生成的文件',
                browse: _pickOrig,
              ),
              const SizedBox(height: 8),
              PathField(
                label: '译文文件',
                controller: _transCtrl,
                hint: '由“AI 翻译”生成的译文',
                browse: _pickTrans,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: EncodingField(label: '原文编码', value: _origEnc, onChanged: (v) => setState(() => _origEnc = v))),
                  const SizedBox(width: 12),
                  Expanded(child: EncodingField(label: '译文编码', value: _transEnc, onChanged: (v) => setState(() => _transEnc = v))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: '并发数', border: OutlineInputBorder(), isDense: true),
                      onChanged: (v) => _concurrency = int.tryParse(v) ?? 3,
                      controller: _concCtrl,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: '最大每秒请求数', border: OutlineInputBorder(), isDense: true),
                      onChanged: (v) => _maxRps = int.tryParse(v) ?? 5,
                      controller: _rpsCtrl,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _start,
                      icon: Icon(st.running ? Icons.stop : Icons.play_arrow),
                      label: Text(st.running ? '停止' : '开始校对'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_issues.isEmpty || st.running) ? null : _saveReport,
                      icon: const Icon(Icons.save),
                      label: const Text('保存报告'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('状态：$_status'),
              if (_issues.isNotEmpty) ..._buildIssueList(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProgressCard(ProofState st) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('校对进度',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16,
                    color: Theme.of(context).colorScheme.onPrimaryContainer)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: st.progress.clamp(0.0, 1.0),
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 8),
            Text('${st.doneWindows}/${st.totalWindows} 窗口完成',
                style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer)),
            const SizedBox(height: 6),
            SizedBox(
              height: 100,
              child: ListView(
                children: [
                  for (final l in st.log.reversed)
                    Text(l,
                        style: const TextStyle(
                            color: Colors.black, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildIssueList() {
    final problems = _issues.where((i) => !i.ok).toList();
    final okCount = _issues.length - problems.length;
    return [
      const SizedBox(height: 8),
      Text('通过 $okCount 行，问题 ${problems.length} 行：'),
      const SizedBox(height: 8),
      if (_issues.length <= 2000) ...[
        for (final i in _issues)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('第 ${i.lineNo} 行 · ${i.type}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: i.ok ? Colors.green : Colors.red)),
                  const SizedBox(height: 4),
                  if (i.detail.isNotEmpty)
                    Text(i.detail, style: const TextStyle(fontSize: 13)),
                  if (i.suggested != null) ...[
                    const SizedBox(height: 4),
                    Text('建议：${i.suggested}',
                        style: const TextStyle(fontSize: 13, color: Colors.blue)),
                  ],
                ],
              ),
            ),
          ),
      ] else
        Text('行数过多（共 ${_issues.length} 行），请保存报告查看完整结果。',
            style: const TextStyle(color: Colors.grey)),
    ];
  }
}