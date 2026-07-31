#!/bin/bash
# demo-local.sh — 모두의 수조를 로컬에서 눈으로 확인한다
#
#   bash scripts/dev/demo-local.sh
#
# Slack 워크스페이스 없이 전체 흐름을 재현한다:
#   내 어항에서 물고기 분양 → 코드를 "채널"에 게시 → poller가 주움
#   → 라운지 어항으로 헤엄쳐 입장 → 🐠 리액션
#
# 진짜 어항 상태(~/.aquarium.json)는 건드리지 않는다 — HOME을 임시 디렉토리로
# 격리한다. 끝나고 정리 명령까지 안내한다.

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
ROOT=$PWD
BIN=$ROOT/.build/release/aquarium
PORT=${PORT:-8099}
DEMO=${DEMO_DIR:-${TMPDIR:-/tmp}/aquarium-demo}

command -v tmux >/dev/null || { echo "tmux 가 필요합니다: brew install tmux"; exit 1; }
command -v jq   >/dev/null || { echo "jq 가 필요합니다: brew install jq"; exit 1; }
[ -x "$BIN" ] || { echo "먼저 빌드하세요: swift build -c release"; exit 1; }

rm -rf "$DEMO"; mkdir -p "$DEMO/mine" "$DEMO/lounge" "$DEMO/state"
CHANNEL="$DEMO/channel.txt"; : > "$CHANNEL"

pkill -f "fake-slack.py --port $PORT" 2>/dev/null
tmux kill-session -t aq-demo 2>/dev/null

echo "▸ 가짜 Slack 채널 기동 (127.0.0.1:$PORT)"
python3 "$ROOT/scripts/dev/fake-slack.py" --port "$PORT" \
  --messages-file "$CHANNEL" --record "$DEMO/state/req.log" > "$DEMO/state/fake.out" 2>&1 &
for _ in $(seq 1 40); do
  curl -s -o /dev/null "http://127.0.0.1:$PORT/conversations.history" && break
  sleep 0.1
done

( umask 077; cat > "$DEMO/state/config" <<EOF
SLACK_BOT_TOKEN="xoxb-demo"
SLACK_CHANNEL_ID="C0DEMO"
SLACK_API_BASE="http://127.0.0.1:$PORT"
AQUARIUM_BIN="$BIN"
EOF
)
chmod 600 "$DEMO/state/config"

poll() {
  AQUARIUM_LOUNGE_DIR="$DEMO/state" AQUARIUM_LOUNGE_CONFIG="$DEMO/state/config" \
  HOME="$DEMO/lounge" bash "$ROOT/scripts/lounge-slack-poller.sh" >/dev/null 2>&1
}

echo "▸ 내 어항을 만들고 물고기를 기른다"
tmux new-session -d -s aq-demo-seed -x 100 -y 30 "HOME='$DEMO/mine' AQUARIUM_TANKNAME='동료' '$BIN'"
sleep 9; tmux send-keys -t aq-demo-seed q; sleep 3; tmux kill-session -t aq-demo-seed 2>/dev/null
NAME=$(python3 -c "import json;print(json.load(open('$DEMO/mine/.aquarium.json'))['fish'][0]['name'])")
echo "   → '$NAME'"

echo "▸ 분양 코드 생성"
CODE=$(HOME="$DEMO/mine" AQUARIUM_TANKNAME='동료' "$BIN" --release "$NAME" | tail -1)
echo "   → ${CODE:0:44}… (${#CODE}자)"

echo "▸ 라운지 어항 기동 (비어 있는 상태로 시작)"
python3 -c "
import json,time
json.dump({'version':1,'savedAt':time.time(),'tankBornAt':time.time()-2592000,
'breedRemaining':99999,'lighting':'day','fish':[]}, open('$DEMO/lounge/.aquarium.json','w'))"
tmux new-session -d -s aq-demo -x 120 -y 34 \
  "HOME='$DEMO/lounge' AQUARIUM_LANG=ko '$BIN' --lounge"
sleep 3

poll                      # 첫 실행 — 기준점만 심는다(과거 백필 없음)
echo "▸ 채널에 코드를 붙여넣는다"
printf '%s\n' "우리 애 좀 부탁해요 $CODE" >> "$CHANNEL"

echo "▸ poller 실행"
poll
sleep 8                   # 어항 인박스 점검(5초) + 입장 연출

echo
echo "──────────────────────────────────────────────"
tmux capture-pane -t aq-demo -p | sed -n '2,30p'
echo "──────────────────────────────────────────────"
echo
echo "무슨 일이 있었나:"
grep -E '입양 OK|코드 무효|런 종료' "$DEMO/state/poller.log" 2>/dev/null | tail -3 | sed 's/^/  /'
REACT=$(jq -r 'select(.path|endswith("reactions.add")) | .params.name' "$DEMO/state/req.log" 2>/dev/null | tr '\n' ' ')
echo "  슬랙 리액션: ${REACT:-(없음)}  (fish = 🐠)"

# 큐가 비었다 = 어항이 실제로 집어갔다는 확정 증거.
# 세이브 파일은 60초 오토세이브 뒤에나 갱신되므로 그걸 기다리지 않는다.
QLEFT=$(grep -c . "$DEMO/lounge/.aquarium-adopt-inbox" 2>/dev/null | tr -d ' ')
if [ "${QLEFT:-0}" = "0" ]; then
  echo "  ✅ 입양 큐가 비었다 — 어항이 '$NAME'을 받아 입장시켰다"
else
  echo "  ⏳ 큐에 ${QLEFT}개 남음 (5초당 한 마리씩 들어오는 중)"
fi
echo
echo "  라운지 어항에 원래 살던 물고기도 있어서 '$NAME'만 눈으로 집어내긴 어렵습니다."
echo "  아래 2)로 한 마리 더 보내면 화면 가장자리에서 헤엄쳐 들어오는 게 보입니다."

cat <<EOF

────────────────────────────────────────────────────────
직접 해보기 — 먼저 이 줄부터 복사해서 붙여넣으세요

    export D=$DEMO
    export AQ=$BIN
    alias poll='AQUARIUM_LOUNGE_DIR=\$D/state AQUARIUM_LOUNGE_CONFIG=\$D/state/config HOME=\$D/lounge bash $ROOT/scripts/lounge-slack-poller.sh'

  1) 어항 화면 열어두기 (빠져나오려면 Ctrl-B 누른 뒤 D)
       tmux attach -t aq-demo

  2) 물고기 한 마리 더 보내기 — 가장자리에서 헤엄쳐 들어오는 게 보입니다
       python3 -c "import json;print([f['name'] for f in json.load(open('\$D/mine/.aquarium.json'))['fish']])"
       CODE=\$(HOME=\$D/mine \$AQ --release <위 이름 중 하나> | tail -1)
       echo "\$CODE" >> \$D/channel.txt
       poll

  3) 깨진 코드 → ⚠️ 확인
       echo "AQUA1.zzzz" >> \$D/channel.txt && poll

  4) 같은 코드 다시 올리기 → 복제되지 않고 중복스킵
       echo "\$CODE" >> \$D/channel.txt && poll

  5) 페이싱 보기 — 5마리를 한꺼번에 올려도 5초에 한 마리씩 입장
       tail -f \$D/state/poller.log      (다른 창에서)

정리
       tmux kill-session -t aq-demo; pkill -f 'fake-slack.py --port $PORT'; rm -rf $DEMO

진짜 어항(~/.aquarium.json)은 건드리지 않았습니다 — HOME을 임시 디렉토리로
격리했습니다.
────────────────────────────────────────────────────────
EOF
