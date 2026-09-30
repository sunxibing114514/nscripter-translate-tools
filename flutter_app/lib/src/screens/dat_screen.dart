import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../dat.dart';
import '../file_utils.dart';
import '../widgets.dart';

class DatScreen extends StatefulWidget {
  const DatScreen({super.key});

  @override
  State<DatScreen> createState() => _DatScreenState();
}

class _DatScreenState extends State<DatScreen> {
  late final TextEditingController _pathCtrl;
  Uint8List? _pickedBytes;
  String? _name;
  Uint8List _result = Uint8List(0);
  String _status = '选择 nscript.dat 或 nscript.txt';
  String _mode = '';

  @override
  void initState() {
    super.initState();
    _pathCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  void _applyName(String n) {
    setState(() {
      _name = n;
      _result = Uint8List(0);
      final lower = n.toLowerCase();
      if (lower.endsWith('.dat')) {
        _mode = 'dat → txt（解密）';
      } else {
        _mode = 'txt → dat（加密）';
      }
      _status = '已选择：$n';
    });
  }

  Future<void> _pick() async {
    try {
      final picked = await pickFileBytes();
      if (picked == null) return;
      final (name, bytes) = picked;
      _pickedBytes = bytes;
      _pathCtrl.text = _pathCtrl.text.isEmpty ? name : _pathCtrl.text;
      _applyName(name);
    } catch (e) {
      _showSnack('选择失败：$e，可手动输入路径');
    }
  }

  Future<void> _run() async {
    Uint8List bytes;
    String mode;
    if (_pickedBytes != null) {
      bytes = _pickedBytes!;
      mode = _mode;
    } else {
      var path = _pathCtrl.text.trim();
      if (path.isEmpty) return;
      bytes = await readBytes(path);
      final lower = path.toLowerCase();
      mode = lower.endsWith('.dat') ? 'dat → txt（解密）' : 'txt → dat（加密）';
    }
    try {
      final out = xorProcess(bytes);
      setState(() {
        _result = out;
        _status = '$mode 完成（${bytes.length} 字节）';
      });
    } catch (e) {
      _showSnack('处理失败：$e');
    }
  }

  Future<void> _save() async {
    if (_result.isEmpty) return;
    final lower = _name?.toLowerCase() ?? '';
    final name = lower.endsWith('.dat') ? 'nscript.txt' : 'nscript.dat';
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
      appBar: AppBar(title: const Text('DAT 解封包 / 封包')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              '对 nscript.dat（解密→nscript.txt）或 nscript.txt（加密→nscript.dat）进行异或(0x84)处理。加密与解密使用同一逻辑。',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          PathField(
            label: '文件路径（nscript.dat / nscript.txt）',
            controller: _pathCtrl,
            hint: '点击“浏览”或在此粘贴绝对路径',
            browse: _pick,
          ),
          if (_name != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(label: Text(_mode.isEmpty ? '已选择' : _mode)),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _run,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('运行'),
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
        ],
      ),
    );
  }
}