import requests
import json
import re
import os
import sys
import time
import logging
import threading
from collections import deque
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

# ---------------------------- 全局速率限制器 ----------------------------
class RateLimiter:
    """基于滑动窗口的线程安全速率限制器"""
    def __init__(self, max_calls_per_second):
        self.max_calls = max_calls_per_second
        self.window = deque()
        self.lock = threading.Lock()

    def wait(self):
        with self.lock:
            now = time.monotonic()
            while self.window and self.window[0] <= now - 1.0:
                self.window.popleft()
            if len(self.window) >= self.max_calls:
                sleep_time = self.window[0] + 1.0 - now
                if sleep_time > 0:
                    time.sleep(sleep_time)
                now = time.monotonic()
                while self.window and self.window[0] <= now - 1.0:
                    self.window.popleft()
            self.window.append(now)

# ---------------------------- 日志配置 ----------------------------
def setup_logging():
    logger = logging.getLogger()
    logger.setLevel(logging.DEBUG)
    ch = logging.StreamHandler()
    ch.setLevel(logging.INFO)
    fh = logging.FileHandler("translate.log", encoding="utf-8")
    fh.setLevel(logging.DEBUG)
    formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
    ch.setFormatter(formatter)
    fh.setFormatter(formatter)
    logger.addHandler(ch)
    logger.addHandler(fh)
    return logger

logger = setup_logging()

# ---------------------------- 配置加载 ----------------------------
def load_config(config_path="config.json"):
    logger.info(f"加载配置文件: {config_path}")
    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)
    required = ["provider", "api_key", "model", "source_language", "target_language", "input_file"]
    for key in required:
        if key not in config:
            raise ValueError(f"配置文件缺少必要字段: {key}")
    config.setdefault("concurrency", 3)
    config.setdefault("max_requests_per_second", 5)
    config.setdefault("output_dir", "./aitrans")
    # 术语表：支持直接提供字典，或设为 "interactive" 后手动输入
    config.setdefault("glossary", {})
    if config["glossary"] == "interactive":
        config["glossary"] = input_glossary()
    logger.info("配置文件加载成功")
    return config

# ---------------------------- 手动输入术语表 ----------------------------
def input_glossary():
    """
    交互式输入术语表，格式：源术语=目标术语
    输入空行结束
    """
    print("=== 手动输入术语表 ===")
    print("请输入术语对（格式：源术语=目标术语），输入空行结束：")
    glossary = {}
    while True:
        entry = input("> ").strip()
        if not entry:
            break
        if "=" in entry:
            src, tgt = entry.split("=", 1)
            src = src.strip()
            tgt = tgt.strip()
            if src and tgt:
                glossary[src] = tgt
                print(f"  已添加：{src} -> {tgt}")
            else:
                print("  [跳过] 源术语或目标术语为空")
        else:
            print("  [跳过] 格式错误，请使用 '源术语=目标术语'")
    logger.info(f"手动输入术语表：{glossary}")
    return glossary

# ---------------------------- 提示词构建（含术语表） ----------------------------
def build_prompt(source_lang, target_lang, glossary=None):
    base_prompt = f"""你是一名专业的翻译家，你的任务是把{source_lang}文本翻译成{target_lang}。
请严格按照原文翻译，不要添加额外解释，不要合并或拆分行，保留原文中的序号、标记符、占位符、换行符、转义符、代码调用过程等特殊内容，保持原来的格式。原文中的序号、标记符、占位符、换行符、转义符、代码调用过程等特殊内容包括@ \ 等 请保留这些符号不做修改

### 翻译原则
忠实准确地进行翻译。原作是伟大艺术作品，允许使用直白或粗俗的描述，不应随意删减或篡改，不应回避或淡化，以保持作品的原貌。"""

    # 注入术语表
    if glossary:
        term_lines = "\n".join(
            f"- {src} → {tgt}" for src, tgt in glossary.items()
        )
        glossary_section = f"""

### 术语表（必须严格遵守）
在翻译过程中，以下术语必须按照指定的翻译进行转换，不得自由发挥：
{term_lines}
"""
        base_prompt += glossary_section

    base_prompt += """

### 以textarea标签输出译文
<textarea>
{target_lang}文本
</textarea>"""
    return base_prompt

# ---------------------------- 单行翻译调用 ----------------------------
def translate_single_line(api_base, api_key, model, line, system_prompt, line_number, rate_limiter):
    rate_limiter.wait()
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    user_message = f"请翻译以下单行文本：\n{line}"
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_message}
        ],
        "temperature": 0.1,
        "max_tokens": 200
    }
    logger.info(f"--- 翻译第 {line_number} 行 ---")
    logger.info(f"发送原文：{line}")
    url = api_base.rstrip("/") + "/chat/completions"
    response = requests.post(url, headers=headers, json=payload, timeout=120)
    response.raise_for_status()
    result = response.json()
    content = result["choices"][0]["message"]["content"]
    logger.info(f"AI 原始响应 (第 {line_number} 行)：{content}")
    return line_number, line, content

# ---------------------------- 译文提取 ----------------------------
def extract_translation_from_line(response_text, line_number):
    pattern = r"<textarea>\s*(.*?)\s*</textarea>"
    match = re.search(pattern, response_text, re.DOTALL | re.IGNORECASE)
    if match:
        translated = match.group(1).strip()
    else:
        logger.warning(f"第 {line_number} 行未找到 <textarea> 标签，使用原始响应")
        translated = response_text.strip()
    translated = re.sub(r'^\d+\.\s*T?:?\s*', '', translated, flags=re.MULTILINE)
    translated = re.sub(r'^\d+\.\s*$', '', translated, flags=re.MULTILINE)
    return translated.strip()

# ---------------------------- 文件处理 ----------------------------
def read_lines(input_path):
    logger.info(f"读取源文件: {input_path}")
    with open(input_path, "r", encoding="utf-8") as f:
        return [line.rstrip('\n') for line in f.readlines()]

def save_translation(lines, input_path, target_lang, output_dir="./aitrans"):
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    base = os.path.basename(input_path)
    name, ext = os.path.splitext(base)
    out_name = f"{name}_{target_lang}{ext}"
    out_path = os.path.join(output_dir, out_name)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write('\n'.join(lines))
    logger.info(f"翻译完成，译文已保存至: {out_path}")

# ---------------------------- 主流程 ----------------------------
def main():
    config_path = sys.argv[1] if len(sys.argv) > 1 else "config.json"
    try:
        config = load_config(config_path)
        provider = config["provider"]
        api_key = config["api_key"]
        api_base = config.get("api_base", "")
        if not api_base:
            default_bases = {
                "openai": "https://api.openai.com/v1",
                "deepseek": "https://api.deepseek.com/v1",
                "qwen": "https://dashscope.aliyuncs.com/compatible-mode/v1",
                "zhipu": "https://open.bigmodel.cn/api/paas/v4"
            }
            api_base = default_bases.get(provider.lower(), "")
            if not api_base:
                raise ValueError(f"未知的 AI 提供商 {provider}，请在配置中明确指定 api_base")
        model = config["model"]
        source_lang = config["source_language"]
        target_lang = config["target_language"]
        input_file = config["input_file"]
        output_dir = config["output_dir"]
        concurrency = config["concurrency"]
        max_rps = config["max_requests_per_second"]
        glossary = config["glossary"]  # 可能是字典，也可能是 {}

        original_lines = read_lines(input_file)
        total = len(original_lines)
        logger.info(f"共 {total} 行，开始并发翻译 (并发数={concurrency}, 最大请求速率={max_rps}/s)")

        # 构建包含术语表的系统提示词
        system_prompt = build_prompt(source_lang, target_lang, glossary)
        rate_limiter = RateLimiter(max_rps)

        tasks = []
        for idx, line in enumerate(original_lines, start=1):
            if not line.strip():
                continue
            tasks.append((idx, line))

        translated_lines = [""] * total
        with ThreadPoolExecutor(max_workers=concurrency) as executor:
            futures = {
                executor.submit(
                    translate_single_line,
                    api_base, api_key, model, line, system_prompt, line_number, rate_limiter
                ): line_number
                for line_number, line in tasks
            }
            for future in as_completed(futures):
                line_number, original_line, raw_response = future.result()
                translated = extract_translation_from_line(raw_response, line_number)
                translated_lines[line_number - 1] = translated

        for idx, line in enumerate(original_lines, start=1):
            if not line.strip():
                translated_lines[idx - 1] = ""

        save_translation(translated_lines, input_file, target_lang, output_dir)

    except Exception as e:
        logger.exception("翻译过程中出现异常")
        sys.exit(1)

if __name__ == "__main__":
    main()