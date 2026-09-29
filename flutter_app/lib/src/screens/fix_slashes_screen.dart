import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../encodings.dart';
import '../file_utils.dart';
import '../fix_slashes.dart';
import '../widgets.dart';

class FixSlashesScreen extends StatefulWidget {
  const FixSlashesScreen({super.key});

  @override
  State<FixSlashesScreen> createState() => _FixSlashesScreenState();
}

class _FixSlashesScreenState extends State<FixSlashesScreen> {
  String? _origPath;
  String? _transPath;
  String _encoding = 'utf8';
  Uint8List _result = Uint8List(0);
  String _status = '选择原文与翻译文件后运行';

  Future<void> _pickOriginal() async {
    final p = await pickFile(extensions: ['txt']);
    if (p != null) setState(() => _origPath = p);
  }

  Future<void> _pickTrans() async {
    final p = await pickFile(extensions: ['txt']);
    if (p != null) setState(() => _transPath = p);
  }

  Future<void> _run() async {
    if (_origPath == null || _transPath == null) {
      _showSnack('请选择原文与翻译文件');
      return;
    }
    try {
      final origBytes = await readBytes(_origPath!);
      final transBytes = await readBytes(_transPath!);
      final orig = decodeBytes(origBytes, _encoding);
      final trans = decodeBytes(transBytes, _encoding);
      final out = fixMissingSlashes(orig, trans);
      setState(() {
        _result = encodeString(out, _encoding);
        _status = '处理完成，缺失的尾部斜杠已修复';
      });
    } catch (e) {
      _showSnack('处理失败：$e');
    }
  }

  Future<void> _save() async {
    if (_result.isEmpty) {
      _showSnack('没有可保存的结果');
      return;
    }
    final name = 'fixed.txt';
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
      appBar: AppBar(title: const Text('符号修复')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(_origPath ?? '原文文件（未提取的脚本）'),
              onTap: _pickOriginal,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(_transPath ?? '翻译后文件'),
              onTap: _pickTrans,
            ),
          ),
          const SizedBox(height: 16),
          EncodingField(
              label: '文件编码', value: _encoding,
              onChanged: (v) => setState(() => _encoding = v)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _run,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('修复'),
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
            ResultBox(title: '修复结果预览', text: String.fromCharCodes(_result)),
          ],
        ],
      ),
    );
  }
}