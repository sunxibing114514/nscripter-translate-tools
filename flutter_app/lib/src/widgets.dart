/// 通用 UI 小部件。
library;

import 'package:flutter/material.dart';

import 'encodings.dart';

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