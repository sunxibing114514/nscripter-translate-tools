/// 文件选择 / 读取 / 保存辅助。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart' as pp;

/// 从 [result] 中提取字节。优先直接使用 withData 返回的数据，
/// 否则退回按 path 读取（Android 上 path 可能为 null，此时会抛出可读错误）。
Uint8List _bytesOf(PlatformFile f) {
  if (f.bytes != null) return f.bytes!;
  if (f.path != null) {
    return File(f.path!).readAsBytesSync();
  }
  throw StateError('无法读取所选文件内容（无路径且未携带数据）');
}

/// 根据是否提供 [extensions] 推断合适的 [FileType]。
/// file_picker 8.x 要求：仅当 type=FileType.custom 时才能携带 allowedExtensions，
/// 否则选择框/保存框直接抛 ArgumentError。空扩展名则退回 FileType.any。
FileType _resolveType(FileType type, List<String>? extensions) {
  if (extensions != null && extensions.isNotEmpty) return FileType.custom;
  return type;
}

/// 弹出文件选择框并直接读取字节，返回 (文件名, 字节)。
/// 取消时返回 null。失败时抛出异常。
Future<(String, Uint8List)?> pickFileBytes({
  List<String>? extensions,
  FileType type = FileType.any,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: _resolveType(type, extensions),
    allowedExtensions: extensions,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final f = result.files.single;
  return (f.name, _bytesOf(f));
}

/// 弹出文件选择框，返回选中文件的绝对路径（取消返回 null）。
/// Android 上若系统返回 content:// URI 而无真实路径，将抛出异常提示。
Future<String?> pickFile({List<String>? extensions, FileType type = FileType.any}) async {
  final result = await FilePicker.platform.pickFiles(
    type: _resolveType(type, extensions),
    allowedExtensions: extensions,
  );
  if (result == null || result.files.isEmpty) return null;
  final p = result.files.single.path;
  if (p == null) throw StateError('所选文件没有可访问路径');
  return p;
}

/// 弹出文件夹选择框，返回选中文件夹的绝对路径（取消返回 null）。
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
