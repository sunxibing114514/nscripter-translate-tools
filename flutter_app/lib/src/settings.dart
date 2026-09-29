/// 应用设置持久化：翻译配置 + 自定义命令集。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;

import 'package:shared_preferences/shared_preferences.dart';

import 'commands.dart';

/// 项目目录下存放生成的临时 / 中间 / 成品文件的子目录名称。
const String nstranDirName = 'nstran';

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
  static const _kProjectFolder = 'project_folder';
  static const _kThemeMode = 'theme_mode';

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

  // ---- 项目文件夹 ----
  /// 项目根目录（用户选择的游戏 / 脚本目录）。
  String? get projectFolder => _prefs.getString(_kProjectFolder);
  set projectFolder(String? v) {
    if (v == null) {
      _prefs.remove(_kProjectFolder);
    } else {
      _prefs.setString(_kProjectFolder, v);
    }
  }

  /// nstran 目录绝对路径；未设置项目文件夹时返回 null。
  String? get nstranFolder {
    final pf = projectFolder;
    if (pf == null || pf.isEmpty) return null;
    return '$pf/$nstranDirName';
  }

  /// 确保 nstran 目录存在并返回其路径。
  /// 若未设置项目文件夹则返回 null。
  Future<String?> ensureNstranFolder() async {
    final nf = nstranFolder;
    if (nf == null) return null;
    await Directory(nf).create(recursive: true);
    return nf;
  }

  // ---- 主题（默认跟随系统） ----
  ThemeMode get themeMode {
    final v = _prefs.getString(_kThemeMode);
    switch (v) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  set themeMode(ThemeMode m) {
    _prefs.setString(
        _kThemeMode, switch (m) { ThemeMode.light => 'light', ThemeMode.dark => 'dark', _ => 'system' });
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