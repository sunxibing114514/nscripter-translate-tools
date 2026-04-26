import sys

def fix_missing_slashes(original_file, translated_file, output_file):
    """
    根据原文中的尾部斜杠，修复翻译文件中缺失的 \ 或 / 符号。
    原文与译文按行一一对应。
    """
    with open(original_file, 'r', encoding='utf-8') as f:
        orig_lines = f.readlines()

    with open(translated_file, 'r', encoding='utf-8') as f:
        trans_lines = f.readlines()

    if len(orig_lines) != len(trans_lines):
        print(f"警告：行数不一致（原文 {len(orig_lines)} 行，译文 {len(trans_lines)} 行）。将按较短的行数处理。")
        min_len = min(len(orig_lines), len(trans_lines))
        orig_lines = orig_lines[:min_len]
        trans_lines = trans_lines[:min_len]

    fixed_lines = []
    for i, (orig, trans) in enumerate(zip(orig_lines, trans_lines)):
        orig_stripped = orig.rstrip('\n\r')
        trans_stripped = trans.rstrip('\n\r')

        # 只处理以 T: 开头的文本行，其余行照原样保留
        if orig_stripped.startswith('T:'):
            # 检查原文尾部是否有 \ 或 /，且译文缺少
            if orig_stripped.endswith('\\') or orig_stripped.endswith('/'):
                tail_char = orig_stripped[-1]
                if not trans_stripped.endswith(tail_char):
                    # 译文添加缺失的斜杠
                    trans_stripped += tail_char
        # 其他行（如控制命令）不处理
        fixed_lines.append(trans_stripped + '\n')

    with open(output_file, 'w', encoding='utf-8') as f:
        f.writelines(fixed_lines)

    print(f"处理完成，输出已保存至：{output_file}")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("用法：python fix_slashes.py 原文文件 翻译文件 输出文件")
        sys.exit(1)
    fix_missing_slashes(sys.argv[1], sys.argv[2], sys.argv[3])