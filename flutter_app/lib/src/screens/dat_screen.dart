import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../dat.dart';
import '../file_utils.dart';

class DatScreen extends StatefulWidget {
  const DatScreen({super.key});

  @override
  State<DatScreen> createState() => _DatScreenState();
}

class _DatScreenState extends State<DatScreen> {
  String? _path;
  Uint8List _result = Uint8List(0);
  String _status = '选择 nscript.dat 或 nscript.txt';
  String _mode = '';

  Future<void> _pick() async {
    final p = await pickFile(extensions: ['dat', 'txt']);
    if (p == null) return;
    setState(() {
      _path = p;
      _result = Uint8List(0);
      final lower = p.toLowerCase();
      if (lower.endsWith('.dat')) {
        _mode = 'dat → txt（解密）';
      } else {
        _mode = 'txt → dat（加密）';
      }
      _status = '已选择：$p';
    });
  }

  Future<void> _run() async {
    if (_path == null) return;
    try {
      final bytes = await readBytes(_path!);
      final out = xorProcess(bytes);
      setState(() {
        _result = out;
        _status = '$_mode 完成（${bytes.length} 字节）';
      });
    } catch (e) {
      _showSnack('处理失败：$e');
    }
  }

  Future<void> _save() async {
    if (_result.isEmpty) return;
    final lower = _path?.toLowerCase() ?? '';
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
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: Text(_path ?? '选择文件'),
              trailing: _mode.isEmpty ? null : Chip(label: Text(_mode)),
              onTap: _pick,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _path == null ? null : _run,
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