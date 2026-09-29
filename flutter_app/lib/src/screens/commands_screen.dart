import 'package:flutter/material.dart';

import '../commands.dart';
import '../file_utils.dart';
import '../settings.dart';

class CommandsScreen extends StatefulWidget {
  final AppSettings settings;
  const CommandsScreen({super.key, required this.settings});

  @override
  State<CommandsScreen> createState() => _CommandsScreenState();
}

class _CommandsScreenState extends State<CommandsScreen> {
  late Set<String> _commands;
  bool _usingCustom = false;

  @override
  void initState() {
    super.initState();
    _commands = widget.settings.activeCommands();
    _usingCustom = widget.settings.customCommands != null;
  }

  Future<void> _import() async {
    try {
      final picked = await pickFileBytes(extensions: ['txt']);
      if (picked == null) return;
      final (_, bytes) = picked;
      final content = String.fromCharCodes(bytes);
      final parsed = parseCommandsFile(content);
      setState(() {
        _commands = parsed;
        _usingCustom = true;
        widget.settings.customCommands = content;
      });
      _showSnack('已导入命令集，共 ${parsed.length} 条');
    } catch (e) {
      _showSnack('导入失败：$e');
    }
  }

  Future<void> _reset() async {
    setState(() {
      _commands = defaultCommands;
      _usingCustom = false;
      widget.settings.customCommands = null;
    });
    _showSnack('已恢复为默认命令集');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    final list = _commands.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('命令集')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '当前命令 ${list.length} 条${_usingCustom ? '（自定义）' : '（内置默认）'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _import,
                  icon: const Icon(Icons.import_export),
                  label: const Text('导入'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _usingCustom ? _reset : null,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('重置'),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '在“提取/注入”时用于识别命令行。可导入外部 commands.txt。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.6,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: list.length,
              itemBuilder: (_, i) {
                return Card(
                  margin: EdgeInsets.zero,
                  child: Center(
                    child: Text(list[i],
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}