import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
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
  late final TextEditingController _sourceCtrl;
  String? _sourceName;
  Uint8List? _pickedBytes; // 浏览选择时直接携带的数据（Android 兼容）
  String? _sourcePath;
  Uint8List _result = Uint8List(0);
  String _status = '请选择需要提取的原始脚本';

  @override
  void initState() {
    super.initState();
    _sourceCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _sourceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final picked = await pickFileBytes();
      if (picked == null) return;
      final (name, bytes) = picked;
      setState(() {
        _pickedBytes = bytes;
        _sourceName = name;
        _sourceCtrl.text = _sourceCtrl.text.isEmpty ? name : _sourceCtrl.text;
        _result = Uint8List(0);
        _status = '已选择：$name（${bytes.length} 字节）';
      });
    } catch (e) {
      _showSnack('选择失败：$e，可手动输入路径');
    }
  }

  Future<void> _run() async {
    Uint8List bytes;
    if (_pickedBytes != null) {
      bytes = _pickedBytes!;
    } else {
      var src = _sourcePath;
      final manual = _sourceCtrl.text.trim();
      if (manual.isNotEmpty) src = manual;
      if (src == null) {
        _showSnack('请先选择原始脚本');
        return;
      }
      bytes = await readBytes(src);
    }
    try {
      setState(() => _status = '提取中…（后台处理，可稍候）');
      final commands = widget.settings.activeCommands().toList();
      final encoded = await compute(
        extractOnIsolate,
        [bytes, _inEnc, _outEnc, _expand, commands],
      );
      final lines = decodeBytes(encoded, _outEnc)
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .length;
      setState(() {
        _result = encoded;
        _status = '提取完成，$lines 行可翻译文本';
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
    // 保存为带功能前缀的独立文件名，避免覆盖源文件
    final base = _sourceName ??
        (_sourcePath?.split('/').last ?? 'out.txt');
    final name = '提取_$base';
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
          PathField(
            label: '原始脚本路径 (.txt)',
            controller: _sourceCtrl,
            hint: '可点击“浏览”或在此粘贴绝对路径',
            browse: _pick,
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
              text: _preview(_result),
            ),
        ],
      ),
    );
  }

  /// 预览文本：按输出编码解码。
  /// 原实现用 String.fromCharCodes 把字节当作 Latin-1 码位，
  /// UTF-8/GBK 等多字节内容会显示成乱码；这里先按字节截断再宽容解码。
  String _preview(Uint8List bytes) {
    final cut = bytes.length > 4000 ? bytes.sublist(0, 4000) : bytes;
    final text = decodeBytes(cut, _outEnc);
    return text.length > 4000
        ? '${text.substring(0, 4000)}\n…（已截断，完整内容保存在文件中）'
        : text;
  }
}