import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../encodings.dart';
import '../file_utils.dart';
import '../nscript.dart';
import '../settings.dart';
import '../widgets.dart';

class InjectScreen extends StatefulWidget {
  final AppSettings settings;
  const InjectScreen({super.key, required this.settings});

  @override
  State<InjectScreen> createState() => _InjectScreenState();
}

class _InjectScreenState extends State<InjectScreen> {
  String _inEnc = 'shift_jis';
  String _transEnc = 'utf8';
  String _outEnc = 'shift_jis';
  String? _scriptPath; // 原始脚本
  String? _transPath; // 翻译文件
  Uint8List _result = Uint8List(0);
  String _status = '请选择原始脚本与翻译文件';

  Future<void> _pickScript() async {
    final path = await pickFile(extensions: ['txt']);
    if (path == null) return;
    setState(() {
      _scriptPath = path;
      _result = Uint8List(0);
    });
  }

  Future<void> _pickTrans() async {
    final path = await pickFile(extensions: ['txt']);
    if (path == null) return;
    setState(() {
      _transPath = path;
      _result = Uint8List(0);
    });
  }

  Future<void> _run() async {
    if (_scriptPath == null || _transPath == null) {
      _showSnack('请选择原始脚本与翻译文件');
      return;
    }
    try {
      final scriptBytes = await readBytes(_scriptPath!);
      final transBytes = await readBytes(_transPath!);
      final script = decodeBytes(scriptBytes, _inEnc);
      final trans = decodeBytes(transBytes, _transEnc);
      final out = injectText(script, trans);
      final encoded = encodeString(out, _outEnc);
      setState(() {
        _result = encoded;
        _status = '注入完成';
      });
    } catch (e) {
      _showSnack('注入失败：$e');
    }
  }

  Future<void> _save() async {
    if (_result.isEmpty) {
      _showSnack('没有可保存的结果');
      return;
    }
    final name = _scriptPath == null ? 'script.txt' : _scriptPath!.split('/').last;
    final saved = await saveBytes(name, _result);
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
      appBar: AppBar(title: const Text('翻译注入')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(_scriptPath ?? '原始脚本 (.txt)'),
              subtitle: const Text('最初用于提取的脚本'),
              onTap: _pickScript,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(_transPath ?? '翻译文件 (.txt)'),
              subtitle: const Text('由 提取 / AI翻译 生成'),
              onTap: _pickTrans,
            ),
          ),
          const SizedBox(height: 16),
          EncodingField(label: '原脚本编码', value: _inEnc, onChanged: (v) => setState(() => _inEnc = v)),
          const SizedBox(height: 12),
          EncodingField(label: '翻译文件编码', value: _transEnc, onChanged: (v) => setState(() => _transEnc = v)),
          const SizedBox(height: 12),
          EncodingField(label: '输出脚本编码（通常与原脚本一致）', value: _outEnc, onChanged: (v) => setState(() => _outEnc = v)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _run,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('注入'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _result.isEmpty ? null : _save,
                  icon: const Icon(Icons.save),
                  label: const Text('保存'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('状态：$_status'),
          if (_result.isNotEmpty) ...[
            const SizedBox(height: 8),
            ResultBox(
              title: '注入结果预览',
              text: _preview(_result),
            ),
          ],
        ],
      ),
    );
  }

  String _preview(Uint8List bytes) {
    try {
      return String.fromCharCodes(bytes);
    } catch (_) {
      return '[无法预览二进制内容]';
    }
  }
}