#!/usr/bin/env python3
"""fake-slack.py — lounge-slack-poller.sh 검증용 가짜 Slack API.

실제 워크스페이스 없이 페이지네이션·429·에러·리액션 경로를 전부 돌린다.
표준 라이브러리만 쓴다(레포의 의존성 0 철학).

  python3 scripts/dev/fake-slack.py --port 8099 --scenario basic

poller 쪽에서는 config에 다음 한 줄만 넣으면 붙는다:
  SLACK_API_BASE="http://127.0.0.1:8099"

`python3 -m http.server`로는 부족해서 만들었다 — 그쪽은 POST에 501을 주고
(reactions.add를 못 돌린다), 쿼리스트링을 무시해서 cursor를 바꿀 수 없다.

요청은 전부 --record 파일에 한 줄 JSON으로 남는다. 테스트가
"reactions.add가 몇 번 불렸나"를 세는 근거다.
"""
import argparse, json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

CODE_A = "AQUA1.eyJzcGVjaWVzIjozLCJjb2xvciI6NDUsInNwZWVkIjowLjMsImVhdGVuIjowLCJpZCI6ImZzLWEifQ"
CODE_B = "AQUA1.eyJzcGVjaWVzIjo1LCJjb2xvciI6ODIsInNwZWVkIjowLjMsImVhdGVuIjowLCJpZCI6ImZzLWIifQ"
CODE_C = "AQUA1.eyJzcGVjaWVzIjo3LCJjb2xvciI6MjAxLCJzcGVlZCI6MC4zLCJlYXRlbiI6MCwiaWQiOiJmcy1jIn0"


def msg(ts, text, **extra):
    m = {"type": "message", "user": "U123", "ts": ts, "text": text}
    m.update(extra)
    return m


# 시나리오별 conversations.history 페이지.
# 값이 list면 [page1, page2, ...], dict면 원문 그대로(에러 등).
SCENARIOS = {
    # 한 메시지에 코드 2개 + 깨진 코드 + 코드 없는 메시지
    "basic": [[
        msg("1700000001.000100", f"내 물고기 보냅니다 {CODE_A} 그리고 하나 더 {CODE_B}"),
        msg("1700000002.000200", "안녕하세요 (코드 없는 메시지)"),
        msg("1700000003.000300", "AQUA1.zzzz 이건 깨진 코드"),
    ]],

    # text에 개행·탭·따옴표가 섞여 있다 — jq scan이 쌍당 한 줄을 지키는지
    "nasty-text": [[
        msg("1700000010.000100",
            f'여러 줄\n메시지입니다\t탭도 있고 "따옴표"도 있어요\n{CODE_A}\n끝'),
    ]],

    # 봇/시스템/스레드 메시지 필터링
    "filtered": [[
        msg("1700000020.000100", f"채널 입장 {CODE_A}", subtype="channel_join"),
        msg("1700000021.000100", f"봇이 올림 {CODE_B}", bot_id="B999"),
        msg("1700000022.000100", f"스레드에도 게시 {CODE_C}", subtype="thread_broadcast"),
    ]],

    "empty": [[]],

    # 2페이지 — has_more/next_cursor를 따라가는지
    "paged": [
        [msg("1700000102.000100", f"두 번째 페이지가 있음 {CODE_B}")],
        [msg("1700000101.000100", f"과거 페이지 {CODE_A}")],
    ],

    # limit을 무시하고 조용히 잘린 척 — 개수가 아니라 has_more로 끝내는지
    "clamped": [
        [msg(f"17000002{i:02d}.000100", "x") for i in range(15)],
        [msg("1700000199.000100", f"마지막 {CODE_A}")],
    ],

    # 길이 폭탄 — poller의 MAX_CODE_LEN 가드
    "huge-code": [[
        msg("1700000300.000100", "AQUA1." + "A" * 200000),
    ]],

    # 에러들
    "err-not-in-channel": {"ok": False, "error": "not_in_channel"},
    "err-invalid-auth": {"ok": False, "error": "invalid_auth"},
    "err-missing-scope": {"ok": False, "error": "missing_scope",
                          "needed": "channels:history"},
}


class Handler(BaseHTTPRequestHandler):
    scenario = "basic"
    fake_429 = ""
    record_path = None
    reacted = set()

    def log_message(self, *a):  # 기본 stderr 로그 억제
        pass

    def _record(self, method, path, params):
        if not self.record_path:
            return
        with open(self.record_path, "a") as f:
            f.write(json.dumps({"method": method, "path": path,
                                "params": params}, ensure_ascii=False) + "\n")

    def _send(self, code, body, ctype="application/json", headers=None):
        raw = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(raw)

    def _429(self, what):
        # 일부러 두 형태를 번갈아 낸다: 본문이 JSON이 아닌 429와 JSON인 429.
        # 파서가 본문을 JSON이라 가정하면 여기서 터진다.
        if what == "history":
            self._send(429, "Too Many Requests (not json)", "text/plain",
                       {"Retry-After": "7"})
        else:
            self._send(429, json.dumps({"ok": False, "error": "ratelimited"}),
                       headers={"Retry-After": "7"})

    def do_GET(self):
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        self._record("GET", u.path, q)

        if not u.path.endswith("/conversations.history"):
            self._send(404, json.dumps({"ok": False, "error": "unknown_method"}))
            return

        if self.fake_429 in ("history", "both"):
            self._429("history")
            return

        data = SCENARIOS.get(self.scenario)
        if isinstance(data, dict):          # 에러 시나리오
            self._send(200, json.dumps(data))
            return
        if data is None:
            self._send(200, "<html>이건 JSON이 아닙니다</html>", "text/html")
            return

        pages = data
        idx = int(q.get("cursor", "0") or "0")
        idx = max(0, min(idx, len(pages) - 1))
        has_more = idx + 1 < len(pages)
        body = {"ok": True, "messages": pages[idx], "has_more": has_more}
        if has_more:
            body["response_metadata"] = {"next_cursor": str(idx + 1)}
        self._send(200, json.dumps(body, ensure_ascii=False))

    def do_POST(self):
        u = urlparse(self.path)
        n = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(n).decode() if n else ""
        q = {k: v[0] for k, v in parse_qs(raw).items()}
        self._record("POST", u.path, q)

        if not u.path.endswith("/reactions.add"):
            self._send(404, json.dumps({"ok": False, "error": "unknown_method"}))
            return
        if self.fake_429 in ("reactions", "both"):
            self._429("reactions")
            return

        key = (q.get("channel"), q.get("timestamp"), q.get("name"))
        if key in self.reacted:
            self._send(200, json.dumps({"ok": False, "error": "already_reacted"}))
            return
        self.reacted.add(key)
        self._send(200, json.dumps({"ok": True}))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int, default=8099)
    p.add_argument("--scenario", default="basic")
    p.add_argument("--record", default=None)
    p.add_argument("--fake-429", default=os.environ.get("FAKE_429", ""))
    a = p.parse_args()

    if a.scenario not in SCENARIOS and a.scenario != "garbage":
        print(f"알 수 없는 시나리오: {a.scenario}", file=sys.stderr)
        print("사용 가능: " + ", ".join(sorted(SCENARIOS) + ["garbage"]), file=sys.stderr)
        sys.exit(2)

    Handler.scenario = a.scenario
    Handler.fake_429 = a.fake_429
    Handler.record_path = a.record
    if a.record and os.path.exists(a.record):
        os.remove(a.record)

    srv = HTTPServer(("127.0.0.1", a.port), Handler)
    print(f"fake-slack: 127.0.0.1:{a.port} scenario={a.scenario} 429={a.fake_429 or 'off'}",
          flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
