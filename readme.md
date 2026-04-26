# NScripter 项目工具集

> **AI 参与声明**  
> 本项目中的 `nscript_tool.py`、`translate.py` 以及本说明文档均由 AI 辅助生成。  
> **编写原因**  
> 目前 NScripter 脚本处理工具通常只能在电脑上运行，为了在安卓手机上也能完成文本提取、翻译和注入的全流程，特编写此工具集供个人汉化使用,同时提供ai翻译功能。

本项目包含两个核心工具，用于处理 **NScripter** 游戏引擎的脚本翻译工作流：

- **`nscript_tool.py`** — 从 `.txt` 脚本中提取可翻译文本，或把翻译好的文本注入回脚本，同时保持编码和脚本结构。
- **`translate.py`** — 基于大语言模型（LLM）的批量翻译工具，支持术语表、并发请求和速率控制，适合翻译用 `nscript_tool.py` 提取出来的文本文件。

通过两个工具组合，可以高效完成 NScripter 游戏的汉化（或其他语言本地化）。

---

## 项目结构

```

nscript/
├── config.json          # 翻译工具配置文件
├── nscript_tool.py      # 文本提取/注入工具
├── readme.md            # 本文件
└── translate.py         # LLM 批量翻译脚本

```

---

## 环境要求

- Python 3.7 或更高版本
- 依赖库：
  - `requests`（仅 `translate.py` 需要）
  
  其他模块均为标准库，无需额外安装。

安装依赖：
```bash
pip install requests
```

---

1. nscript_tool.py —— 文本提取与注入

功能简介

nscript_tool.py 专为 NScripter 脚本设计，能够：

- 提取：识别脚本中的三类可翻译文本：
- 反引号行（ `  开头）
- 双引号行（" 开头）
- 普通文本行（非命令行、非注释）
提取结果按 类型:内容 格式保存，如：

```
  B:这里是反引号文本
  Q:这里是双引号文本
  T:这里是普通文本
```

- 注入：将翻译后的文件（保持同类格式）替换回原脚本的对应位置，输出完整的新脚本。
- 编码支持：可指定输入/输出编码（如 shift_jis、utf8），适用于日文原版游戏。
- 符号展开：提取时可将 NScripter 的换行控制符 @ 和 ¥ 转换为真实换行，方便翻译人员阅读。

## 使用方法

### 提取文本

```bash
python nscript_tool.py extract <输入脚本> \
    --in-encoding shift_jis \
    --out-encoding utf8 \
    --out-dir out \
    --expand
```

- <输入脚本>：原始 .txt 脚本（如 01.txt）
- --in-encoding：原脚本编码，日文游戏常用 shift_jis
- --out-encoding：提取后翻译文件的编码，推荐 utf8
- --out-dir：输出目录，默认为 out
- --expand：可选，将 @ 和 ¥ 转换为换行符，便于翻译时阅读

提取后，会在 out/ 下生成与原文件同名的翻译文件（如 out/01.txt）。

### 注入翻译

```bash
python nscript_tool.py inject <原始脚本> <翻译文件> \
    --in-encoding shift_jis \
    --out-encoding shift_jis \
    --trans-encoding utf8 \
    --out-dir injected
```

- <原始脚本>：最初用于提取的脚本
- <翻译文件>：翻译完成的文件（格式与提取结果一致）
- --in-encoding：原始脚本编码
- --out-encoding：生成的新脚本编码，通常与原始脚本一致
- --trans-encoding：翻译文件的编码
- --out-dir：输出目录，默认为 injected

注入完成后，在 injected/ 下会得到可直接用于游戏引擎的新脚本。

###命令速查

操作 命令示例

提取文本 python nscript_tool.py extract 01.txt --in-encoding shift_jis --expand

注入翻译 python nscript_tool.py inject 01.txt translations/01.txt --in-encoding shift_jis --trans-encoding utf8

详细帮助可通过 python nscript_tool.py -h 查看。

---

1. translate.py —— LLM 批量翻译

功能简介

translate.py 用于批量翻译 纯文本行 文件（例如 nscript_tool.py 提取出来的文件），通过调用大语言模型 API 实现逐行翻译，保留原文行顺序和空行。

核心特性：

· 支持多个 LLM 平台（OpenAI、DeepSeek、Qwen、智谱等）
· 并发翻译 + 滑动窗口速率限制，避免 API 超额
· 术语表 功能：可预定义或运行时手动输入，确保专业名词翻译统一
· 详细日志，方便排查问题

配置文件 config.json

在项目根目录创建 config.json，内容参考如下（请替换为实际值，并勿泄露真实 API KEY）：

```json
{
  "provider": "deepseek",
  "api_key": "sk-your-api-key-here",
  "api_base": "",
  "model": "deepseek-chat",
  "source_language": "Japanese",
  "target_language": "Chinese",
  "input_file": "./out/01.txt",
  "output_dir": "./aitrans",
  "concurrency": 5,
  "max_requests_per_second": 10,
  "glossary": {}
}
```

参数说明

|参数| 必填 |说明|

|provider |是 |提供商：openai、deepseek、qwen、zhipu。若自定义 api_base 则自动使用自定义端点 |

|api_key |是 |对应平台的 API 密钥 |

|api_base|否 |自定义 API 端点；留空则根据 provider 自动填充默认地址 |

|model |是 |模型名称，例如 gpt-4o、deepseek-chat、qwen-plus、glm-4 |

|source_language |是 |原文语言（写入提示词） |

|target_language |是 |目标语言，同时用于输出文件名 |

|input_file |是 |待翻译文件的路径（支持相对/绝对） |

|output_dir |否 |译文输出目录，默认 ./aitrans |

|concurrency |否 |并发线程数，默认 3 |

|max_requests_per_second |否 |最大每秒请求数，默认 5（请根据各平台限制调整） |

|glossary |否 |术语表对象，或设为 "interactive" 表示运行时手动输入（详见下文） |




默认 API 地址

提供商 默认地址

openai https://api.openai.com/v1

deepseek https://api.deepseek.com/v1

qwen https://dashscope.aliyuncs.com/compatible-mode/v1

zhipu https://open.bigmodel.cn/api/paas/v4

术语表（可选但强烈推荐）

在 config.json 中直接添加 glossary 对象可以强制某些词汇按指定翻译：

```json
"glossary": {
    "龍": "龙",
    "精霊": "精灵",
    "魔法陣": "魔法阵"
}
```

如和让ai给你输出术语表/你需要上传文本文件
```text
请阅读上传文本，提取其中的专业术语或需要保持翻译一致的名词,例如人名/活动名/地名等，生成一个术语表。

要求：
1. 以 JSON 对象格式输出，键为原文，值为你认为最合适的目标语言翻译（若未指定目标语言，则使用目标语言 = 英文）。
2. 如果术语有多种可能译文，选择最通用或上下文最贴切的一个。
3. 忽略标点、格式标记等非术语内容。
4. 只输出 JSON，不要额外解释。

实例格式
"glossary": {
    "龍": "龙",
    "精霊": "精灵",
    "魔法陣": "魔法阵"
}
```

如果想每次执行时动态输入，可将值设为字符串 "interactive"：

```json
"glossary": "interactive"
```

程序运行后会提示你逐行输入 源术语=目标术语，按回车结束。

运行翻译

确保配置文件准备完毕，然后在终端执行：

```bash
python translate.py
```

如果配置文件非默认名称或路径，可指定：

```bash
python translate.py my_config.json
```

翻译过程中控制台会输出进度信息，详细日志写入 translate.log。

输出结果

翻译后的文件默认保存在 aitrans/ 目录下，命名规则：
原文件名_目标语言.扩展名

例如 01.txt，目标语言为 Chinese，输出 aitrans/01_Chinese.txt。
该文件可直接作为 nscript_tool.py 的注入翻译文件使用。

日志说明

· 控制台：INFO 级别，显示行号、请求发送等基本信息。
· 日志文件（translate.log）：DEBUG 级别，记录完整的 API 请求原文和原始响应，便于调试。

---

完整工作流程示例

假设你有一份日文 NScripter 脚本 game_script.txt（编码为 Shift-JIS），想将其汉化为中文，步骤如下：

1. 提取文本
   ```bash
   python nscript_tool.py extract game_script.txt --in-encoding shift_jis --expand
   ```
   得到 out/game_script.txt，内容形如：
   ```
   B:彼はゆっくりと歩き出した。
   Q:「おはよう」
   T:システムメッセージ
   ```
2. 配置翻译
   编辑 config.json：
   ```json
   {
     "provider": "deepseek",
     "api_key": "sk-your-key",
     "model": "deepseek-chat",
     "source_language": "Japanese",
     "target_language": "Chinese",
     "input_file": "./out/game_script.txt",
     "glossary": { "彼": "他", "歩き出した": "迈步" }
   }
   ```
3. 运行翻译
   ```bash
   python translate.py
   ```
   翻译完成后在 aitrans/ 下得到 game_script_Chinese.txt。
4. 注入回脚本
   ```bash
   python nscript_tool.py inject game_script.txt aitrans/game_script_Chinese.txt \
       --in-encoding shift_jis --out-encoding shift_jis --trans-encoding utf8
   ```
   在 injected/ 目录下得到完全本地化的 game_script.txt，可直接放入游戏工程使用。

---

常见问题

Q：为什么翻译结果中出现了多余的数字或字母？
A：translate.py 会自动去除行首的序号标记（如 1. T:xxx）。如果仍有残留，请检查翻译文件格式是否与提取结果一致。

Q：翻译后注入时提示行数不匹配？
A：确保翻译过程中没有增减行数，空行必须保留。如果翻译文件被手动修改，请确保只修改了 : 后面的内容，且类型前缀（B/Q/T）未改变。

Q：想用其他 AI 服务（非内置）？
A：在 config.json 中填写完整的 api_base（必须兼容 OpenAI Chat Completions 接口），provider 可任意填写，模型名按实际设置即可。

---

许可与贡献

本项目仅供学习与个人本地化使用。使用前请确保遵守相关游戏的版权规定及 API 提供商的使用条款。欢迎提交 Issue 或 PR 改进工具。
