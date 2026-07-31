#!/bin/bash
# lounge-set-interval.sh — Slack poller 폴링 주기 변경
#
#   scripts/lounge-set-interval.sh 30     # 30초로
#   scripts/lounge-set-interval.sh        # 현재 주기 확인
#
# plist의 StartInterval이 주기의 유일한 진실 원천이다. config 파일에는 주기를
# 두지 않는다 — poller는 원샷이라 자기 실행 주기를 스스로 정할 수 없고,
# config에 적어두면 효력 없는 장식이 되어 실제 주기와 어긋날 때 사람을 태운다.
#
# 이 스크립트는 값을 따로 보관하지 않는다. plist를 고치고 재적용할 뿐이다.
# (손으로 plist를 고치고 launchctl 재적용을 잊는 사고를 막는 게 목적이다.)

set -euo pipefail

LABEL="com.agiletalk.aquarium.lounge-slack-poller"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
MIN=10
MAX=3600

if [ ! -f "$PLIST" ]; then
  printf 'launchd 잡이 설치되어 있지 않습니다: %s\n' "$PLIST" >&2
  printf 'docs/lounge-setup.md 6단계를 먼저 수행하세요.\n' >&2
  exit 1
fi

current() { /usr/libexec/PlistBuddy -c "Print :StartInterval" "$PLIST" 2>/dev/null || echo "?"; }

# 실효 주기 — plist 파일이 아니라 launchd가 실제로 물고 있는 값.
# launchctl은 "run interval = 60 seconds" 로 찍으므로 숫자만 뽑는다
# ($NF를 쓰면 "seconds"가 나온다).
effective() {
  launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null \
    | sed -n 's/.*run interval = \([0-9][0-9]*\).*/\1/p' | head -1 || true
}

if [ $# -eq 0 ]; then
  printf 'plist의 StartInterval : %s초\n' "$(current)"
  eff=$(effective)
  printf 'launchd 실효 주기     : %s\n' "${eff:-(잡이 로드되어 있지 않음)}"
  if [ -n "$eff" ] && [ "$eff" != "$(current)" ]; then
    printf '\n⚠️  plist와 실효 주기가 다릅니다. 재적용이 필요합니다:\n    %s <초>\n' "$0"
  fi
  exit 0
fi

n=$1
case "$n" in
  ''|*[!0-9]*) printf '초 단위 정수를 주세요. 예: %s 30\n' "$0" >&2; exit 1 ;;
esac

# 실수로 1을 넣으면 Tier 3 예산을 태우기 시작한다. 하한을 둔다.
if [ "$n" -lt "$MIN" ]; then
  printf '%s초는 너무 짧습니다(최소 %s초). Slack rate limit을 태웁니다.\n' "$n" "$MIN" >&2
  exit 1
fi
if [ "$n" -gt "$MAX" ]; then
  printf '%s초는 너무 깁니다(최대 %s초). 라운지 화면이 심심해집니다.\n' "$n" "$MAX" >&2
  exit 1
fi

before=$(current)
plutil -replace StartInterval -integer "$n" "$PLIST"
plutil -lint "$PLIST" >/dev/null

# 재적용해야 실제로 바뀐다. bootout은 잡이 없으면 실패하므로 무시한다.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

printf '폴링 주기: %s초 → %s초 (재적용 완료)\n' "$before" "$n"
eff=$(effective)
printf 'launchd 실효 주기: %s\n' "${eff:-확인 불가}"
printf '\n다음 폴링 로그: tail -f ~/.aquarium-lounge/poller.log\n'
