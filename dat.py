import sys
import os

BUFFER_SIZE = 32  # 对应原代码 bsize
XOR_KEY = 0x84    # 异或密钥，会翻转每个字节的第8位和第3位（从右向左数）


def xor_process(src_path: str, dst_path: str) -> None:
    """
    从源文件逐字节异或 0x84 后写入目标文件。
    加密和解密使用同一个函数。
    """
    try:
        with open(src_path, 'rb') as src, open(dst_path, 'wb') as dst:
            while True:
                chunk = src.read(BUFFER_SIZE)
                if not chunk:
                    break
                # 异或处理
                transformed = bytes(b ^ XOR_KEY for b in chunk)
                dst.write(transformed)
        print(f"'{src_path}' -> '{dst_path}' 操作完成。")
    except IOError as e:
        print(f"文件操作失败: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    # 逻辑与原C程序完全一致：
    # 1. 优先尝试打开 nscript.dat
    if os.path.exists('nscript.dat'):
        print("找到 nscript.dat，正在解密为 nscript.txt ...")
        xor_process('nscript.dat', 'nscript.txt')
        print("nscript.dat decrypted in nscript.txt")
    else:
        print("未找到 nscript.dat，尝试寻找 nscript.txt ...")
        if not os.path.exists('nscript.txt'):
            print("未找到任何可用文件 (nscript.dat / nscript.txt)，程序终止。", file=sys.stderr)
            sys.exit(1)
        print("找到 nscript.txt，正在加密为 nscript.dat ...")
        xor_process('nscript.txt', 'nscript.dat')
        print("nscript.txt encrypted in nscript.dat")

    print("Press any key to continue...")
    input()  # 模拟原程序的 getchar()，等待用户按键


if __name__ == '__main__':
    main()