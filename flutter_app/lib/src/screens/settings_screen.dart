import 'package:flutter/material.dart';

import '../file_utils.dart';
import '../settings.dart';

/// 设置界面：主题、项目文件夹(nstran 目录)、翻译 API、术语表、命令集。
class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<ThemeMode>? onThemeChanged;
  const SettingsScreen({super.key, required this.settings, this.onThemeChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _apiKey;
  late final TextEditingController _apiBase;
  late final TextEditingController _model;
  late final TextEditingController _sourceLang;
  late final TextEditingController _targetLang;
  late final TextEditingController _concurrencyCtrl;
  late final TextEditingController _maxRpsCtrl;
  late final TextEditingController _glossary;
  late final TextEditingController _commandsCtrl;
  late final TextEditingController _folderCtrl;
  late String _provider;
  late ThemeMode _themeMode;

  String? _projectFolder;
  bool _showApiKey = false;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _projectFolder = s.projectFolder;
    _folderCtrl = TextEditingController();
    if (_projectFolder != null) _folderCtrl.text = _projectFolder!;
    _themeMode = s.themeMode;
    _commandsCtrl = TextEditingController(text: _commandsToString(s));
    _provider = s.provider;
    _apiKey = TextEditingController(text: s.apiKey);
    _apiBase = TextEditingController(text: s.apiBase);
    _model = TextEditingController(text: s.model);
    _sourceLang = TextEditingController(text: s.sourceLanguage);
    _targetLang = TextEditingController(text: s.targetLanguage);
    _concurrencyCtrl = TextEditingController(text: '${s.concurrency}');
    _maxRpsCtrl = TextEditingController(text: '${s.maxRequestsPerSecond}');
    _glossary = TextEditingController(text: _glossaryToString(s.glossary));
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _apiBase.dispose();
    _model.dispose();
    _sourceLang.dispose();
    _targetLang.dispose();
    _concurrencyCtrl.dispose();
    _maxRpsCtrl.dispose();
    _glossary.dispose();
    _commandsCtrl.dispose();
    _folderCtrl.dispose();
    super.dispose();
  }

  String _glossaryToString(Map<String, String> g) =>
      g.entries.map((e) => '${e.key}=${e.value}').join('\n');

  /// 把当前命令集展示为每行一条的文本。
  String _commandsToString(AppSettings s) {
    final set = s.activeCommands().toList()..sort();
    return set.join('\n');
  }

  /// 把每行一条的命令文本保存为自定义命令集。
  void _saveCommandsFromText() {
    final lines = _commandsCtrl.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toSet();
    if (lines.isEmpty) {
      widget.settings.customCommands = null;
      _showSnack('命令集已清空（恢复默认）');
    } else {
      widget.settings.customCommands = lines.join('\n');
      _showSnack('已保存 ${lines.length} 条自定义命令');
    }
  }

  Map<String, String> _parseGlossary() {
    final map = <String, String>{};
    for (final line in _glossary.text.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (t.contains('=')) {
        final i = t.indexOf('=');
        final k = t.substring(0, i).trim();
        final v = t.substring(i + 1).trim();
        if (k.isNotEmpty) map[k] = v;
      }
    }
    return map;
  }

  Future<void> _pickProjectFolder() async {
    try {
      final path = await pickFolder();
      if (path == null) return;
      _folderCtrl.text = path;
      setState(() => _projectFolder = path);
      widget.settings.projectFolder = path;
      await widget.settings.ensureNstranFolder();
      _showSnack('已设置项目文件夹，并在其中创建 $nstranDirName 目录');
    } catch (e) {
      _showSnack('选择失败：$e，可手动输入路径');
    }
  }

  Future<void> _saveProjectFolderFromText() async {
    final manual = _folderCtrl.text.trim();
    if (manual.isEmpty) {
      _showSnack('请输入项目文件夹路径');
      return;
    }
    setState(() => _projectFolder = manual);
    widget.settings.projectFolder = manual;
    await widget.settings.ensureNstranFolder();
    _showSnack('已设置项目文件夹，并在其中创建 $nstranDirName 目录');
  }

  void _setTheme(ThemeMode m) {
    setState(() => _themeMode = m);
    widget.settings.themeMode = m;
    widget.onThemeChanged?.call(m);
  }

  void _saveGlossaryAndTranslateConfig() {
    final s = widget.settings;
    s.provider = _provider;
    s.apiKey = _apiKey.text.trim();
    s.apiBase = _apiBase.text.trim();
    s.model = _model.text.trim();
    s.sourceLanguage = _sourceLang.text.trim();
    s.targetLanguage = _targetLang.text.trim();
    s.concurrency = int.tryParse(_concurrencyCtrl.text) ?? 3;
    s.maxRequestsPerSecond = int.tryParse(_maxRpsCtrl.text) ?? 5;
    s.glossary = _parseGlossary();
    _showSnack('翻译配置与术语表已保存');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('主题'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.system,
                    groupValue: _themeMode,
                    title: const Text('跟随系统'),
                    onChanged: (v) => _setTheme(ThemeMode.system),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.light,
                    groupValue: _themeMode,
                    title: const Text('浅色'),
                    onChanged: (v) => _setTheme(ThemeMode.light),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.dark,
                    groupValue: _themeMode,
                    title: const Text('深色'),
                    onChanged: (v) => _setTheme(ThemeMode.dark),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          _sectionTitle('项目文件夹'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PathField(
                    label: '项目文件夹路径',
                    controller: _folderCtrl,
                    hint: '点击“浏览”或在此粘贴绝对路径',
                    pick: pickFolder,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '保存后将在其中自动创建 $nstranDirName 目录，存放提取/翻译等生成文件。',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          _sectionTitle('翻译 API'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _provider,
                    decoration: const InputDecoration(
                        labelText: '提供商', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'deepseek', child: Text('deepseek')),
                      DropdownMenuItem(value: 'openai', child: Text('openai')),
                      DropdownMenuItem(value: 'qwen', child: Text('qwen')),
                      DropdownMenuItem(value: 'zhipu', child: Text('zhipu')),
                      DropdownMenuItem(value: 'custom', child: Text('自定义')),
                    ],
                    onChanged: (v) => setState(() => _provider = v ?? _provider),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKey,
                    obscureText: !_showApiKey,
                    decoration: InputDecoration(
                        labelText: 'API Key',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_showApiKey ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _showApiKey = !_showApiKey),
                        )),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiBase,
                    decoration: const InputDecoration(
                        labelText: 'API Base（留空则按提供商自动填充）',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _model,
                    decoration: const InputDecoration(
                        labelText: '模型（如 deepseek-chat）', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _sourceLang,
                          decoration: const InputDecoration(
                              labelText: '原文语言', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _targetLang,
                          decoration: const InputDecoration(
                              labelText: '目标语言', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _concurrencyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: '并发数', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _maxRpsCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: '最大每秒请求数', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          _sectionTitle('术语表'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _glossary,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                        hintText: '每行一项，格式：源=目标\n例如：\n龍=龙\n精霊=精灵',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '保存后用于 AI 批量翻译时的术语替换。',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          _sectionTitle('命令集'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _commandsCtrl,
                    minLines: 6,
                    maxLines: 12,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                        hintText: '每行一条命令，例如：\nmono\ngoto\nlua\nbmp\nbgm\n语音',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '用于提取/注入时识别命令行。可直接在框内增删命令（每行一条），保存后立即生效。留空保存则恢复内置默认。',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _saveCommandsFromText,
                        icon: const Icon(Icons.check),
                        label: const Text('保存命令集'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              _saveCommandsFromText();
              _saveProjectFolderFromText();
              widget.settings.themeMode = _themeMode;
              _saveGlossaryAndTranslateConfig();
            },
            icon: const Icon(Icons.save),
            label: const Text('保存全部设置'),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );
}