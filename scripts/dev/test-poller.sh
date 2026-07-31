#!/bin/bash
# test-poller.sh — lounge-slack-poller.sh 검증 (실제 Slack 워크스페이스 불필요)
#
#   bash scripts/dev/test-poller.sh
#
# fake-slack.py를 띄우고 poller를 여러 시나리오로 돌린 뒤, 로그와 요청 기록으로
# 판정한다. aquarium 바이너리는 실물을 쓰되 HOME을 임시 디렉토리로 격리한다.

# shellcheck disable=SC2015
#   A && ok "..." || bad "..." 패턴을 쓴다. ok()는 항상 0을 반환하므로
#   "A가 참인데 C도 실행"되는 SC2015의 함정이 여기서는 성립하지 않는다.
set -uo pipefail
set +m          # 잡 컨트롤 알림("Terminated: 15") 억제 — pkill로 정리한다
cd "$(dirname "$0")/../.." || exit 1
ROOT=$PWD
POLLER=$ROOT/scripts/lounge-slack-poller.sh
FAKE=$ROOT/scripts/dev/fake-slack.py
BIN=${AQUARIUM_BIN:-$ROOT/.build/release/aquarium}
PORT=${PORT:-8099}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/aqtest.XXXXXX")
PASS=0; FAIL=0

[ -x "$BIN" ] || { echo "aquarium 바이너리가 없습니다: $BIN (swift build -c release)"; exit 1; }
command -v jq >/dev/null || { echo "jq 가 필요합니다: brew install jq"; exit 1; }

cleanup() { pkill -f "fake-slack.py --port $PORT" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

ok()   { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  ❌ %s\n' "$1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — 기대 '$3' 실제 '$2'"; fi; }

start_fake() { # start_fake <scenario> [fake429]
  pkill -f "fake-slack.py --port $PORT" 2>/dev/null; sleep 0.3
  python3 "$FAKE" --port "$PORT" --scenario "$1" --record "$WORK/req.log" \
      --fake-429 "${2:-}" > "$WORK/fake.out" 2>&1 &
  for _ in $(seq 1 40); do
    curl -s -o /dev/null "http://127.0.0.1:$PORT/conversations.history" && return 0
    sleep 0.1
  done
  echo "fake-slack 기동 실패"; cat "$WORK/fake.out"; exit 1
}

# newenv <name> [aquarium_bin] — 격리된 라운지 상태 디렉토리 + config
newenv() {
  local d=$WORK/$1
  rm -rf "$d"; mkdir -p "$d/home"
  ( umask 077; cat > "$d/config" <<EOF
SLACK_BOT_TOKEN="xoxb-fake"
SLACK_CHANNEL_ID="C0FAKE"
SLACK_API_BASE="http://127.0.0.1:$PORT"
AQUARIUM_BIN="${2:-$BIN}"
EOF
  )
  chmod 600 "$d/config"
  echo "$d"
}

# poll <envdir> — poller 1회 실행 (첫 실행은 백필 안 하므로 보통 2번 부른다)
poll() {
  local d=$1
  AQUARIUM_LOUNGE_DIR="$d" AQUARIUM_LOUNGE_CONFIG="$d/config" HOME="$d/home" \
    bash "$POLLER" >>"$d/stdout.log" 2>>"$d/stderr.log"
  echo $?
}
plog()  { cat "$1/poller.log" 2>/dev/null; }
plines(){ wc -l < "$1/poller.log" 2>/dev/null | tr -d ' ' || echo 0; }
# poller.log는 런을 거듭하며 누적된다. 직전 런이 남긴 줄만 봐야 한다.
psince(){ tail -n "+$(( ${2:-0} + 1 ))" "$1/poller.log" 2>/dev/null; }
reacts(){ grep -c 'reactions.add' "$WORK/req.log" 2>/dev/null | tr -d ' '; }
reactname() { jq -r 'select(.path|endswith("reactions.add")) | .params.name' "$WORK/req.log" 2>/dev/null | tr '\n' ' '; }

echo "=== 1. 첫 실행은 백필하지 않는다 ==="
start_fake basic
D=$(newenv t1)
rc=$(poll "$D")
check "종료 코드" "$rc" "0"
check "첫 실행에 입양 0" "$(plog "$D" | grep -c '입양 OK')" "0"
[ -f "$D/last_ts" ] && ok "last_ts 기준점 생성됨" || bad "last_ts 없음"
check "reactions.add 호출 0" "$(reacts)" "0"

echo
echo "=== 2. 한 메시지의 코드 2개 + 깨진 코드 ==="
: > "$WORK/req.log"
echo "0" > "$D/last_ts"     # 과거 전체를 보게
rc=$(poll "$D")
check "종료 코드" "$rc" "0"
check "입양 성공 2건" "$(plog "$D" | grep -c '입양 OK')" "2"
check "무효 1건" "$(plog "$D" | grep -c '코드 무효')" "1"
printf '  리액션: %s\n' "$(reactname)"
check "리액션 3회" "$(reacts)" "3"

echo
echo "=== 3. 재실행은 멱등 (중복 스킵, 리액션 0회) ==="
: > "$WORK/req.log"
echo "0" > "$D/last_ts"
before=$(plines "$D")
rc=$(poll "$D")
check "종료 코드" "$rc" "0"
check "이번 런 입양 0건" "$(psince "$D" "$before" | grep -c '입양 OK')" "0"
check "reactions.add 0회" "$(reacts)" "0"
plog "$D" | tail -1 | grep -q '중복스킵=3' && ok "중복스킵=3" || bad "중복스킵 카운트: $(plog "$D" | tail -1)"

echo
echo "=== 4. 개행/탭/따옴표가 든 text ==="
start_fake nasty-text
D=$(newenv t4); poll "$D" >/dev/null; echo "0" > "$D/last_ts"; : > "$WORK/req.log"
poll "$D" >/dev/null
check "입양 1건" "$(plog "$D" | grep -c '입양 OK')" "1"
check "리액션 1회" "$(reacts)" "1"

echo
echo "=== 5. 봇/시스템 메시지 필터, thread_broadcast는 통과 ==="
start_fake filtered
D=$(newenv t5); poll "$D" >/dev/null; echo "0" > "$D/last_ts"; : > "$WORK/req.log"
poll "$D" >/dev/null
check "입양 1건 (thread_broadcast만)" "$(plog "$D" | grep -c '입양 OK')" "1"

echo
echo "=== 6. 빈 채널 ==="
start_fake empty
D=$(newenv t6); poll "$D" >/dev/null; echo "0" > "$D/last_ts"
rc=$(poll "$D")
check "종료 코드" "$rc" "0"
plog "$D" | tail -1 | grep -q 'msgs=0' && ok "msgs=0 기록됨" || bad "msgs 로그 없음"

echo
echo "=== 7. 페이지네이션 (2페이지) ==="
start_fake paged
D=$(newenv t7); poll "$D" >/dev/null; echo "0" > "$D/last_ts"; : > "$WORK/req.log"
poll "$D" >/dev/null
check "입양 2건 (양 페이지)" "$(plog "$D" | grep -c '입양 OK')" "2"
check "history 요청 2회" "$(grep -c 'conversations.history' "$WORK/req.log")" "2"
plog "$D" | grep -q 'page=2' && ok "page=2 로그" || bad "page=2 로그 없음"

echo
echo "=== 8. limit이 조용히 잘려도 has_more로 끝낸다 ==="
start_fake clamped
D=$(newenv t8); poll "$D" >/dev/null; echo "0" > "$D/last_ts"
poll "$D" >/dev/null
check "입양 1건 (2페이지 끝까지 감)" "$(plog "$D" | grep -c '입양 OK')" "1"
plog "$D" | grep -q 'msgs=15 has_more=true' && ok "절단 흔적이 로그에 보인다" \
  || bad "msgs/has_more 로그: $(plog "$D" | grep 'page=' | head -2 | tr '\n' ' ')"

echo
echo "=== 9. 429 — Retry-After 존중, last_ts 미전진 ==="
start_fake basic history
D=$(newenv t9); poll "$D" >/dev/null; echo "0" > "$D/last_ts"
rc=$(poll "$D")
check "종료 코드" "$rc" "0"
check "last_ts 그대로" "$(cat "$D/last_ts")" "0"
[ -f "$D/cooldown_until" ] && ok "쿨다운 파일 생성" || bad "쿨다운 파일 없음"
plog "$D" | grep -q '쿨다운 7초' && ok "Retry-After 7 반영" || bad "Retry-After 미반영: $(plog "$D" | tail -2)"
rc=$(poll "$D")
plog "$D" | tail -1 | grep -q '쿨다운 중' && ok "다음 런은 건너뜀" || bad "쿨다운 무시됨"

echo
echo "=== 10. 리액션이 429여도 입양은 유지되고 런은 안 죽는다 ==="
start_fake basic reactions
D=$(newenv t10); poll "$D" >/dev/null; echo "0" > "$D/last_ts"
rc=$(poll "$D")
check "종료 코드" "$rc" "0"
[ "$(plog "$D" | grep -c '입양 OK')" -ge 1 ] && ok "입양은 진행됨" || bad "입양이 막혔다"
check "last_ts 미전진(partial)" "$(cat "$D/last_ts")" "0"

echo
echo "=== 11. 비-JSON 응답 ==="
start_fake garbage
D=$(newenv t11); poll "$D" >/dev/null; echo "0" > "$D/last_ts"
rc=$(poll "$D")
check "종료 코드 (죽지 않음)" "$rc" "0"
# HTML은 jq가 파싱 자체를 못 해 exit 1 → 'unparsable'. 유효 JSON이지만 객체가
# 아닌 경우만 'non_json_response'. 둘 다 안전 경로이므로 양쪽을 받는다.
plog "$D" | grep -qE 'unparsable|non_json_response' \
  && ok "JSON 아닌 본문을 안전하게 처리" || bad "감지 실패: $(plog "$D" | tail -2)"
plog "$D" | tail -1 | grep -q 'partial=1' && ok "partial=1 — last_ts 미전진" \
  || bad "partial 플래그 없음: $(plog "$D" | tail -1)"

echo
echo "=== 12. 치명적 에러는 stderr + 쿨다운 ==="
for sc in err-not-in-channel err-invalid-auth err-missing-scope; do
  start_fake $sc
  D=$(newenv "t12-$sc"); poll "$D" >/dev/null; echo "0" > "$D/last_ts"
  rc=$(poll "$D")
  if [ "$rc" = "1" ] && grep -q FATAL "$D/stderr.log" && [ -f "$D/cooldown_until" ]; then
    ok "$sc → exit 1 + stderr FATAL + 쿨다운"
  else
    bad "$sc → rc=$rc stderr=$(tail -1 "$D/stderr.log" 2>/dev/null)"
  fi
done

echo
echo "=== 13. 길이 폭탄은 실행 전에 걸러진다 ==="
start_fake huge-code
D=$(newenv t13); poll "$D" >/dev/null; echo "0" > "$D/last_ts"; : > "$WORK/req.log"
rc=$(poll "$D")
check "종료 코드" "$rc" "0"
plog "$D" | grep -q '코드가 너무 김' && ok "길이 가드 작동" || bad "가드 미작동"
check "⚠️ 리액션 1회" "$(reacts)" "1"
check "입양 시도 0건" "$(plog "$D" | grep -c '입양 OK')" "0"

echo
echo "=== 14. exit 75(EX_TEMPFAIL) — 리액션 없음, seen 미기록, 재시도 ==="
cat > "$WORK/fake-adopt-75" <<'EOF'
#!/bin/bash
echo "일시적 실패(테스트 스텁)"
exit 75
EOF
chmod +x "$WORK/fake-adopt-75"
start_fake basic
D=$(newenv t14 "$WORK/fake-adopt-75"); poll "$D" >/dev/null
echo "0" > "$D/last_ts"; : > "$WORK/req.log"
rc=$(poll "$D")
check "종료 코드 (런은 정상 종료)" "$rc" "0"
check "reactions.add 0회" "$(reacts)" "0"
check "seen 비어 있음" "$(grep -c . "$D/seen" 2>/dev/null | tr -d ' ')" "0"
check "last_ts 미전진" "$(cat "$D/last_ts")" "0"
plog "$D" | grep -q '일시 실패' && ok "보류로 기록됨" || bad "보류 로그 없음"
# 이제 정상 바이너리로 바꾸면 같은 코드를 다시 집어야 한다
sed -i '' "s|AQUARIUM_BIN=.*|AQUARIUM_BIN=\"$BIN\"|" "$D/config"
: > "$WORK/req.log"
poll "$D" >/dev/null
[ "$(plog "$D" | grep -c '입양 OK')" -ge 1 ] && ok "다음 런에서 실제로 재시도됨" || bad "재시도 안 됨"

echo
echo "=== 15. config 권한이 느슨하면 실행 거부 ==="
D=$(newenv t15); chmod 644 "$D/config"
rc=$(poll "$D")
check "종료 코드" "$rc" "1"
grep -q '600이어야' "$D/stderr.log" && ok "권한 오류 안내" || bad "안내 없음"

echo
echo "=== 16. 계정 진단 로그 ==="
D=$(newenv t16); poll "$D" >/dev/null
plog "$D" | grep -q "런 시작 user=$(whoami) HOME=" && ok "user/HOME 기록됨" \
  || bad "진단 로그 없음: $(plog "$D" | head -1)"

echo
echo "════════════════════════════════════"
printf '  통과 %d · 실패 %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
