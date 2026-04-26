#!/usr/bin/env python3
"""
NScripter 文本提取/注入工具
用于从 NScripter 脚本中提取可翻译文本，或将翻译后的文本注入回脚本。

支持编码转换、特殊符号展开、反引号/双引号/普通文本分类。
"""

import os
import sys
import argparse
from typing import Optional, List, TextIO

# ========== NScripter 命令表 ==========
COMMANDS = {
    # 原始核心指令
    "bg", "ld", "lsp", "lsph", "csp", "vsp", "msp", "print", "tal", "cl",
    "br", "wait", "delay", "goto", "gosub", "return", "if", "else", "endif",
    "for", "next", "break", "continue", "stop", "play", "playonce", "wave",
    "waveloop", "wavestop", "mp3", "mp3loop", "avi", "bgm", "setwindow",
    "textoff", "texton", "erasetextwindow", "rmode", "systemcall", "trap",
    "select", "selgosub", "selnum", "btnwait", "btn", "btndef", "click",
    "reset", "definereset", "mov", "add", "sub", "inc", "dec", "mul", "div",
    "mod", "rnd", "rnd2", "cmp", "notif", "end", "quit", "save", "load",
    "lookback", "caption", "effect", "transmode", "stralias",
    "numalias", "defaultfont", "selectcolor", "menuselectcolor", "globalon",
    "humanz", "underline", "rlookback", "roff", "rmenu", "menusetwindow",
    "killmenu", "defaultspeed", "windoweffect", "mousecursor", "locate",
    "puttext", "mesbox", "autoclick", "quakex", "quakey", "monocro", "nega",
    "nsa",                 
    "clickstr",            
    "versionstr",      
    "mp3fadeout",     
    "game",             
    "!sd",               
    "cell",             
    "spbtn",             
    "~",             
    "resettimer",       
    "blt",              
    "waittimer",         
    "jumpb",            
    "ofscpy",             
    "clickstr",              
    "textspeed", "prnum", "spfont", "spstr", "deletescreenshot",
}

# ========== 字符串工具 ==========
def is_command_line(line: str) -> bool:
    trimmed = line.strip()
    if not trimmed:
        return False
    # 先尝试按空格分割取第一个词（一般情况）
    first_word = trimmed.split()[0].lower()
    if first_word in COMMANDS:
        return True
    # 处理命令后紧跟引号、括号等无空格的情况
    # 遍历已知命令，检查 trimmed 是否以该命令开头，并且命令后的第一个字符不是字母或数字（或者就是字符串结尾）
    lower_line = trimmed.lower()
    for cmd in COMMANDS:
        if lower_line.startswith(cmd) and (len(trimmed) == len(cmd) or not trimmed[len(cmd)].isalnum()):
            return True
    return False

# ========== 提取类型 ==========
from enum import Enum

class TextType(Enum):
    BACKTICK = 1
    QUOTED  = 2
    TEXT    = 3

class ScriptText:
    def __init__(self, type_: TextType, content: str):
        self.type = type_
        self.content = content

# ========== 文本提取逻辑 ==========
def extract_quoted_string(s: str) -> str:
    """从双引号开头的字符串中提取内容，支持简单的转义"""
    if not s or s[0] != '"':
        return ""
    result = []
    i = 1
    while i < len(s):
        c = s[i]
        if c == '"':
            break
        if c == '\\' and i + 1 < len(s):
            nxt = s[i + 1]
            if nxt == '"':
                result.append('"')
            elif nxt == '\\':
                result.append('\\')
            else:
                result.append('\\')
                result.append(nxt)
            i += 2
        else:
            result.append(c)
            i += 1
    return ''.join(result)

def apply_expand(content: str) -> str:
    """将 @ 和 ¥ 替换为换行符"""
    return content.replace('@', '\n').replace('¥', '\n')

def process_script_line(line: str, expand_symbols: bool = False) -> Optional[ScriptText]:
    """处理一行 NScripter 脚本，若为可翻译文本则返回 ScriptText，否则返回 None"""
    trimmed = line.rstrip('\n\r')
    # 跳过空行、注释、标签
    if not trimmed or trimmed[0] in (';', '*'):
        return None

    # 反引号行
    if trimmed.startswith('`'):
        content = trimmed[1:]
        if expand_symbols:
            content = apply_expand(content)
        return ScriptText(TextType.BACKTICK, content)

    # 双引号行
    if trimmed.startswith('"'):
        content = extract_quoted_string(trimmed)
        if expand_symbols:
            content = apply_expand(content)
        return ScriptText(TextType.QUOTED, content)

    # br 命令本身不是文本
    if trimmed.lower() == 'br':
        return None

    # 非命令行作为普通文本
    if not is_command_line(trimmed):
        content = trimmed
        if expand_symbols:
            content = apply_expand(content)
        return ScriptText(TextType.TEXT, content)

    return None

# ========== 核心功能 ==========
def do_extract(input_path: str, out_dir: str, in_enc: str, out_enc: str, expand: bool):
    """提取脚本中的文本并写入输出目录"""
    with open(input_path, 'r', encoding=in_enc) as f:
        lines = f.readlines()

    result = []
    for line in lines:
        st = process_script_line(line, expand_symbols=expand)
        if st:
            prefix = {
                TextType.BACKTICK: 'B',
                TextType.QUOTED:   'Q',
                TextType.TEXT:     'T',
            }[st.type]
            result.append(f"{prefix}:{st.content}")

    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, os.path.basename(input_path))
    with open(out_path, 'w', encoding=out_enc) as f:
        f.write('\n'.join(result) + '\n')
    print(f"Extracted -> {out_path}")

def do_inject(input_path: str, trans_path: str, out_dir: str,
              in_enc: str, out_enc: str, trans_enc: str):
    """将翻译文件注入原始脚本并写入输出目录"""
    with open(input_path, 'r', encoding=in_enc) as f:
        script_lines = f.readlines()

    with open(trans_path, 'r', encoding=trans_enc) as f:
        trans_lines = [line.rstrip('\n\r') for line in f if line.strip()]

    # 解析翻译文件行
    trans_items: List[ScriptText] = []
    for tline in trans_lines:
        if len(tline) < 2 or tline[1] != ':':
            raise ValueError(f"Malformed translation line: {tline}")
        type_map = {'B': TextType.BACKTICK, 'Q': TextType.QUOTED, 'T': TextType.TEXT}
        if tline[0] not in type_map:
            raise ValueError(f"Unknown type prefix in translation line: {tline}")
        trans_items.append(ScriptText(type_map[tline[0]], tline[2:]))

    output = []
    trans_idx = 0
    for line in script_lines:
        orig_text = process_script_line(line, expand_symbols=False)  # 注入时不展开
        if orig_text:
            if trans_idx >= len(trans_items):
                raise RuntimeError("More translatable lines in script than translation entries")
            repl = trans_items[trans_idx]
            trans_idx += 1

            if repl.type == TextType.BACKTICK:
                new_line = f"`{repl.content}\n"
            elif repl.type == TextType.QUOTED:
                new_line = f'"{repl.content}"\n'
            else:  # TEXT
                new_line = repl.content + '\n'
            output.append(new_line)
        else:
            # 保留原始行（包括换行符）
            output.append(line if line.endswith('\n') else line + '\n')

    if trans_idx != len(trans_items):
        raise RuntimeError("More translation entries than translatable lines in script")

    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, os.path.basename(input_path))
    with open(out_path, 'w', encoding=out_enc) as f:
        f.writelines(output)
    print(f"Injected -> {out_path}")

# ========== 命令行解析与使用方式 ==========
def main():
    parser = argparse.ArgumentParser(
        description="NScripter 文本提取/注入工具\n"
                    "从 NScripter 脚本中提取可翻译文本，或将其翻译后注入回脚本。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="示例:\n"
               "  python nscript_tool.py extract script.txt --in-encoding shift_jis --out-encoding utf8 --expand\n"
               "  python nscript_tool.py inject script.txt trans.txt --in-encoding shift_jis --out-encoding utf8 --trans-encoding utf8"
    )
    sub = parser.add_subparsers(dest='mode', required=True, help="操作模式")

    # extract 子命令
    ext = sub.add_parser('extract', help='提取文本')
    ext.add_argument('input', help='输入 NScripter 脚本')
    ext.add_argument('--in-encoding', default='utf8', help='输入脚本编码 (默认: utf8)')
    ext.add_argument('--out-encoding', default='utf8', help='输出翻译文件编码 (默认: utf8)')
    ext.add_argument('--out-dir', default='out', help='输出目录 (默认: out)')
    ext.add_argument('--expand', action='store_true', help='将 @ 和 ¥ 转换为换行符')

    # inject 子命令
    inj = sub.add_parser('inject', help='注入翻译')
    inj.add_argument('input', help='原始 NScripter 脚本')
    inj.add_argument('trans', help='翻译文件 (由 extract 生成)')
    inj.add_argument('--in-encoding', default='utf8', help='输入脚本编码 (默认: utf8)')
    inj.add_argument('--out-encoding', default='utf8', help='输出脚本编码 (默认: utf8)')
    inj.add_argument('--trans-encoding', default='utf8', help='翻译文件编码 (默认: utf8)')
    inj.add_argument('--out-dir', default='injected', help='输出目录 (默认: injected)')

    args = parser.parse_args()

    try:
        if args.mode == 'extract':
            do_extract(args.input, args.out_dir,
                       in_enc=args.in_encoding, out_enc=args.out_encoding,
                       expand=args.expand)
        else:
            do_inject(args.input, args.trans, args.out_dir,
                      in_enc=args.in_encoding, out_enc=args.out_encoding,
                      trans_enc=args.trans_encoding)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()