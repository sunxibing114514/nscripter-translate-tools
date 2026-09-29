import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../encodings.dart';
import '../file_utils.dart';
import '../nscript.dart';
import '../settings.dart';
import '../widgets.dart';

class ExtractScreen extends StatefulWidget {
  final AppSettings settings;
  const ExtractScreen({super.key, required this.settings});

  @override
  State<ExtractScreen> createState() => _ExtractScreenState();
}

class _ExtractScreenState extends State<ExtractScreen> {
  String _inEnc = 'shift_jis';
  String _outEnc = 'utf8';
  bool _expand = true;
  String? _sourcePath;
  Uint8List _result = Uint8List(0);
  String _status = '请选择需要提取的原始脚本';

  Future<void> _pick() async {
    final path = await pickFile(extensions: ['txt']);
    if (path == null) return;
    setState(() {
      _sourcePath = path;
      _result = Uint8List(0);
      _status = '已选择：$path';
    });
  }

  Future<void> _run() async {
    if (_sourcePath == null) {
      _showSnack('请先选择原始脚本');
      return;
    }
    try {
      final bytes = await readBytes(_sourcePath!);
      final decoded = decodeBytes(bytes, _inEnc);
      final out = extractText(decoded, expand: _expand);
      final encoded = encodeString(out, _outEnc);
      setState(() {
        _result = encoded;
        _status = '提取完成，${out.split('\n').where((l) => l.trim().isNotEmpty).length} 行可翻译文本';
      });
    } catch (e) {
      _showSnack('提取失败：$e');
    }
  }

  Future<void> _save() async {
    if (_result.isEmpty) {
      _showSnack('没有可保存的结果');
      return;
    }
    final name = _sourcePath == null
        ? 'out.txt'
        : '提取_${_sourcePath!.split('/').last}';
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
        .showSnackBar(SnackBar(content: Text(msg), duration: Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文本提取')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_open),
              title: Text(_sourcePath ?? '选择原始脚本 (.txt)'),
              trailing: const Icon(Icons.attach_file),
              onTap: _pick,
            ),
          ),
          const SizedBox(height: 16),
          EncodingField(
            label: '输入编码（原脚本）',
            value: _inEnc,
            onChanged: (v) => setState(() => _inEnc = v),
          ),
          const SizedBox(height: 12),
          EncodingField(
            label: '输出编码（翻译文件）',
            value: _outEnc,
            onChanged: (v) => setState(() => _outEnc = v),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('将 @ 和 ¥ 转换为换行（便于阅读翻译）'),
            value: _expand,
            onChanged: (v) => setState(() => _expand = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _run,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('提取'),
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
          const SizedBox(height: 8),
          if (_result.isNotEmpty)
            ResultBox(
              title: '提取结果预览',
              text: utf8_fallback(_result),
            ),
        ],
      ),
    );
  }

  String utf8_fallback(Uint8List bytes) {
    try {
      return String.fromCharCodes(bytes);
    } catch (_) {
      return '[无法预览二进制内容]';
    }
  }
}