import 'package:flutter/material.dart';

import '../settings.dart';
import 'commands_screen.dart';
import 'dat_screen.dart';
import 'extract_screen.dart';
import 'fix_slashes_screen.dart';
import 'inject_screen.dart';
import 'settings_screen.dart';
import 'translate_screen.dart';

class HomeScreen extends StatelessWidget {
  final AppSettings settings;
  const HomeScreen({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final tools = <_Tool>[
      _Tool('文本提取', '从 NScripter 脚本提取可翻译文本', Icons.upload_file_outlined,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExtractScreen(settings: settings)))),
      _Tool('翻译注入', '将翻译文件注入回脚本', Icons.south_west,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => InjectScreen(settings: settings)))),
      _Tool('AI 批量翻译', 'LLM 批量翻译（实时速率）', Icons.translate,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => TranslateScreen(settings: settings)))),
      _Tool('符号修复', '修复翻译后缺失的 \\ 与 /', Icons.build_outlined,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => FixSlashesScreen()))),
      _Tool('DAT 解封包', 'nscript.dat ↔ nscript.txt (XOR)', Icons.lock_outline,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => DatScreen()))),
      _Tool('命令集', '查看 / 导入 NScripter 命令表', Icons.list_alt_outlined,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => CommandsScreen(settings: settings)))),
      _Tool('设置', '项目文件夹 / API / 术语表 / 命令集', Icons.settings_outlined,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(settings: settings)))),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('NScripter 翻译工具集')),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: tools.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final t = tools[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(t.icon)),
              title: Text(t.title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(t.subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: t.onTap,
            ),
          );
        },
      ),
    );
  }
}

class _Tool {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  _Tool(this.title, this.subtitle, this.icon, this.onTap);
}