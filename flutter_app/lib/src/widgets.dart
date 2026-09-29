/// 通用 UI 小部件。
library;

import 'package:flutter/material.dart';

import 'encodings.dart';
import 'file_utils.dart';

/// 路径选择：一个文本输入框 + 「浏览」按钮。
/// 文本输入框可手动填入/粘贴绝对路径，作为系统文件选择器的兜底。
class PathField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final Future<String?> Function()? pick;
  const PathField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.pick,
  });

  Future<void> _browse(BuildContext context) async {
    try {
      final path = pick == null ? await pickFile() : await pick!();
      if (path != null) controller.text = path;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('选择失败：$e，可手动输入路径')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () => _browse(context),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
          child: const Text('浏览'),
        ),
      ],
    );
  }
}

/// 编码下拉选择。
class EncodingField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String label;
  const EncodingField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = '编码',
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: supportedEncodings.contains(value) ? value : 'utf8',
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [
        for (final e in supportedEncodings)
          DropdownMenuItem<String>(value: e, child: Text(e)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// 展示结果的只读文本区。
class ResultBox extends StatelessWidget {
  final String text;
  final String? title;
  const ResultBox({super.key, required this.text, this.title});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(title!, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
            ],
            SelectableText(
              text,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}