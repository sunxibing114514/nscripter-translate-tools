import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
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
  late final TextEditingController _scriptCtrl; // 原始脚本
  late final TextEditingController _transCtrl; // 翻译文件
  Uint8List? _scriptBytes;
  Uint8List? _transBytes;
  String? _scriptName;
  String? _transName;
  Uint8List _result = Uint8List(0);
  String _status = '请选择原始脚本与翻译文件';

  @override
  void initState() {
    super.initState();
    _scriptCtrl = TextEditingController();
    _transCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _scriptCtrl.dispose();
    _transCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(String which) async {
    try {
      final picked = await pickFileBytes();
      if (picked == null) return;
      final (name, bytes) = picked;
      setState(() {
        if (which == 'script') {
          _scriptBytes = bytes;
          _scriptName = name;
          _scriptCtrl.text = _scriptCtrl.text.isEmpty ? name : _scriptCtrl.text;
        } else {
          _transBytes = bytes;
          _transName = name;
          _transCtrl.text = _transCtrl.text.isEmpty ? name : _transCtrl.text;
        }
        _result = Uint8List(0);
        _status = '已选择：$name';
      });
    } catch (e) {
      _showSnack('选择失败：$e，可手动输入路径');
    }
  }

  Future<void> _run() async {
    Uint8List scriptBytes;
    Uint8List transBytes;
    if (_scriptBytes != null) {
      scriptBytes = _scriptBytes!;
    } else {
      var script = _scriptCtrl.text.trim();
      if (script.isEmpty) {
        _showSnack('请选择原始脚本');
        return;
      }
      scriptBytes = await readBytes(script);
    }
    if (_transBytes != null) {
      transBytes = _transBytes!;
    } else {
      var trans = _transCtrl.text.trim();
      if (trans.isEmpty) {
        _showSnack('请选择翻译文件');
        return;
      }
      transBytes = await readBytes(trans);
    }
    try {
      setState(() => _status = '注入中…（后台处理，可稍候）');
      final commands = widget.settings.activeCommands().toList();
      final encoded = await compute(
        injectOnIsolate,
        [scriptBytes, transBytes, _inEnc, _transEnc, _outEnc, commands],
      );
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
    // 保存为带功能前缀的独立文件名，避免覆盖源脚本
    final base = _scriptName ?? 'script.txt';
    final name = '注入_$base';
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
      appBar: AppBar(title: const Text('翻译注入')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PathField(
            label: '原始脚本路径 (.txt)',
            controller: _scriptCtrl,
            hint: '最初用于提取的脚本',
            browse: () => _pick('script'),
          ),
          const SizedBox(height: 12),
          PathField(
            label: '翻译文件路径 (.txt)',
            controller: _transCtrl,
            hint: '由 提取 / AI翻译 生成',
            browse: () => _pick('trans'),
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
      final text = String.fromCharCodes(bytes);
      return text.length > 4000 ? '${text.substring(0, 4000)}\n…（已截断，完整内容保存在文件中）' : text;
    } catch (_) {
      return '[无法预览二进制内容]';
    }
  }
}