/// 文件选择 / 读取 / 保存辅助。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart' as pp;

/// 弹出文件选择框，返回选中文件的绝对路径（取消时返回 null）。
Future<String?> pickFile({List<String>? extensions, FileType type = FileType.any}) async {
  final result = await FilePicker.platform.pickFiles(type: type, allowedExtensions: extensions);
  if (result == null || result.files.isEmpty) return null;
  return result.files.single.path;
}

/// 弹出文件夹选择框，返回选中文件夹的绝对路径（取消时返回 null）。
Future<String?> pickFolder() async {
  final selected = await FilePicker.platform.getDirectoryPath();
  return selected;
}

/// 弹出保存对话框并写入字节，返回保存路径（取消时返回 null）。
Future<String?> saveBytes(String suggestedName, Uint8List bytes) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: '选择保存位置',
    fileName: suggestedName,
    type: FileType.any,
  );
  if (path == null) return null;
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}

Future<String?> saveBytesAsBytes(String suggestedName, List<int> bytes) =>
    saveBytes(suggestedName, Uint8List.fromList(bytes));

/// 读取文件字节。
Future<Uint8List> readBytes(String path) async => File(path).readAsBytes();

/// 应用文档目录（用于命令行 / 工作目录）。
Future<Directory> appDir() async {
  final base = await pp.getApplicationDocumentsDirectory();
  return Directory('${base.path}/nscript_tools');
}