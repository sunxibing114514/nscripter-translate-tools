import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../encodings.dart';
import '../file_utils.dart';
import '../fix_slashes.dart';
import '../settings.dart';
import '../widgets.dart';

class FixSlashesScreen extends StatefulWidget {
  final AppSettings settings;
  const FixSlashesScreen({super.key, required this.settings});

  @override
  State<FixSlashesScreen> createState() => _FixSlashesScreenState();
}

class _FixSlashesScreenState extends State<FixSlashesScreen> {
  Uint8List? _origBytes;
  Uint8List? _transBytes;
  String _encoding = 'utf8';
  Uint8List _result = Uint8List(0);
  String _status = '选择原文与翻译文件后运行';

  Future<void> _pickOriginal() async {
    try {
      final picked = await pickFileBytes();
      if (picked == null) return;
      final (_, bytes) = picked;
      setState(() => _origBytes = bytes);
    } catch (e) {
      _showSnack('选择失败：$e');
    }
  }

  Future<void> _pickTrans() async {
    try {
      final picked = await pickFileBytes();
      if (picked == null) return;
      final (_, bytes) = picked;
      setState(() => _transBytes = bytes);
    } catch (e) {
      _showSnack('选择失败：$e');
    }
  }

  Future<void> _run() async {
    if (_origBytes == null || _transBytes == null) {
      _showSnack('请选择原文与翻译文件');
      return;
    }
    try {
      final orig = decodeBytes(_origBytes!, _encoding);
      final trans = decodeBytes(_transBytes!, _encoding);
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
    // 优先保存到项目 nstran 目录
    final nstran = await widget.settings.ensureNstranFolder();
    if (nstran != null) {
      final target = '$nstran/$name';
      await File(target).writeAsBytes(_result, flush: true);
      _showSnack('已保存到 nstran：$target');
      return;
    }
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
              title: Text(_origBytes == null ? '原文文件（未提取的脚本）' : '原文文件（已选择）'),
              onTap: _pickOriginal,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(_transBytes == null ? '翻译后文件' : '翻译后文件（已选择）'),
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