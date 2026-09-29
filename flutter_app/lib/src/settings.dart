/// 应用设置持久化：翻译配置 + 自定义命令集。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'commands.dart';

class AppSettings {
  static const _kProvider = 'provider';
  static const _kApiKey = 'api_key';
  static const _kApiBase = 'api_base';
  static const _kModel = 'model';
  static const _kSourceLang = 'source_language';
  static const _kTargetLang = 'target_language';
  static const _kConcurrency = 'concurrency';
  static const _kMaxRps = 'max_requests_per_second';
  static const _kGlossary = 'glossary';
  static const _kCustomCommands = 'custom_commands';

  final SharedPreferences _prefs;
  AppSettings._(this._prefs);

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings._(prefs);
  }

  // ---- 翻译配置 ----
  String get provider => _prefs.getString(_kProvider) ?? 'deepseek';
  set provider(String v) => _prefs.setString(_kProvider, v);

  String get apiKey => _prefs.getString(_kApiKey) ?? '';
  set apiKey(String v) => _prefs.setString(_kApiKey, v);

  String get apiBase => _prefs.getString(_kApiBase) ?? '';
  set apiBase(String v) => _prefs.setString(_kApiBase, v);

  String get model => _prefs.getString(_kModel) ?? '';
  set model(String v) => _prefs.setString(_kModel, v);

  String get sourceLanguage => _prefs.getString(_kSourceLang) ?? 'Japanese';
  set sourceLanguage(String v) => _prefs.setString(_kSourceLang, v);

  String get targetLanguage => _prefs.getString(_kTargetLang) ?? 'Chinese';
  set targetLanguage(String v) => _prefs.setString(_kTargetLang, v);

  int get concurrency => _prefs.getInt(_kConcurrency) ?? 5;
  set concurrency(int v) => _prefs.setInt(_kConcurrency, v);

  int get maxRequestsPerSecond => _prefs.getInt(_kMaxRps) ?? 10;
  set maxRequestsPerSecond(int v) => _prefs.setInt(_kMaxRps, v);

  /// 术语表存储为 JSON。
  Map<String, String> get glossary {
    final raw = _prefs.getString(_kGlossary) ?? '{}';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  set glossary(Map<String, String> v) {
    _prefs.setString(_kGlossary, jsonEncode(v));
  }

  // ---- 自定义命令集 ----
  /// 若用户曾加载过自定义命令文件，返回其内容；否则返回 null。
  String? get customCommands => _prefs.getString(_kCustomCommands);
  set customCommands(String? v) {
    if (v == null) {
      _prefs.remove(_kCustomCommands);
    } else {
      _prefs.setString(_kCustomCommands, v);
    }
  }

  /// 当前生效的命令集（自定义优先，否则用内置默认）。
  Set<String> activeCommands() {
    final custom = customCommands;
    if (custom != null && custom.trim().isNotEmpty) {
      return parseCommandsFile(custom);
    }
    return defaultCommands;
  }
}