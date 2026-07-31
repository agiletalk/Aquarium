#!/bin/bash
# lounge-slack-poller.sh — Slack "모두의 수조" poller
#
#   Slack 채널에서 AQUA1.… 분양 코드를 주워 `aquarium --adopt` 로 넘긴다.
#   코어(Swift)는 Slack의 존재를 모른다. 이 스크립트가 유일한 접점이고,
#   사람이 손으로 치는 것과 똑같은 CLI로만 코어와 대화한다.
#
#   설정  ~/.aquarium-lounge/config          (chmod 600 — 토큰이 여기 산다)
#   상태  ~/.aquarium-lounge/{last_ts,seen,cooldown_until}
#   로그  ~/.aquarium-lounge/poller.log      (이 스크립트가 직접 회전시킨다)
#
#   사용법
#     lounge-slack-poller.sh           # 1회 폴링 (launchd가 60초마다 호출)
#     DRY_RUN=1 lounge-slack-poller.sh # 입양/리액션 없이 훑기만
#
#   폴링 주기는 launchd plist의 StartInterval이 정한다(config가 아니다).
#   바꾸려면 scripts/lounge-set-interval.sh <초>
#
#   세팅 문서: docs/lounge-setup.md

set -euo pipefail

# launchd는 PATH를 /usr/bin:/bin:/usr/sbin:/sbin 으로만 준다.
# aquarium·jq는 Homebrew에 있으므로 직접 얹는다.
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH

TAB=$'\t'
PARTIAL=0   # 1이면 이번 런은 부분 처리 — last_ts를 전진시키지 않는다

# ─────────────────────────────────────────────────────────── 설정

LOUNGE_DIR="${AQUARIUM_LOUNGE_DIR:-$HOME/.aquarium-lounge}"
CONFIG="${AQUARIUM_LOUNGE_CONFIG:-$LOUNGE_DIR/config}"

LAST_TS="$LOUNGE_DIR/last_ts"
SEEN="$LOUNGE_DIR/seen"
COOLDOWN="$LOUNGE_DIR/cooldown_until"
LOG="$LOUNGE_DIR/poller.log"
LOCK="$LOUNGE_DIR/lock"

# 기본값 먼저 → config가 덮어쓴다
SLACK_API_BASE="https://slack.com/api"
POLL_LIMIT=200          # Tier 3 상한은 999. 200이면 사실상 항상 1페이지
MAX_PAGES=20            # 폭주 방어. 넘으면 이번 런은 부분 처리
MAX_ADOPTS_PER_RUN=25   # reactions.add 버스트 방어 (전시 첫날)
MAX_CODE_LEN=4096       # 이보다 긴 건 코드가 아니라 폭탄이다 (아래 참고)
SEEN_MAX=50000          # 약 850KB. 넘으면 절반으로 자른다
LOG_MAX_LINES=2000
FATAL_COOLDOWN=300      # 설정 오류로 60초마다 에러가 도배되는 걸 막는다
CURL_TIMEOUT=25
REACT_OK="fish"         # 🐠
REACT_BAD="warning"     # ⚠️
AQUARIUM_BIN=""
JQ_BIN=""
DRY_RUN="${DRY_RUN:-0}"

if [ ! -f "$CONFIG" ]; then
  printf '설정 파일이 없습니다: %s\n docs/lounge-setup.md 3단계를 보세요.\n' "$CONFIG" >&2
  exit 1
fi

# 토큰이 든 파일이다. 권한이 새면 실행을 거부한다 — "plist에 토큰을 넣었다"와
# "chmod 644 했다"를 조용히 넘기지 않고 시끄럽게 만드는 게 목적이다.
cfg_perm=$(stat -f '%Lp' "$CONFIG")
cfg_owner=$(stat -f '%u' "$CONFIG")
case "$cfg_perm" in
  600|400) ;;
  *) printf '설정 파일 권한이 %s 입니다. 토큰 파일은 600이어야 합니다:\n  chmod 600 %s\n' \
       "$cfg_perm" "$CONFIG" >&2; exit 1 ;;
esac
if [ "$cfg_owner" != "$(id -u)" ]; then
  printf '설정 파일 소유자가 현재 사용자가 아닙니다: %s\n' "$CONFIG" >&2
  exit 1
fi

# shellcheck source=/dev/null
. "$CONFIG"

: "${SLACK_BOT_TOKEN:?config에 SLACK_BOT_TOKEN 이 없습니다}"
: "${SLACK_CHANNEL_ID:?config에 SLACK_CHANNEL_ID 가 없습니다}"

[ -n "$AQUARIUM_BIN" ] || AQUARIUM_BIN=$(command -v aquarium || true)
[ -n "$JQ_BIN" ]       || JQ_BIN=$(command -v jq || true)

if [ -z "$AQUARIUM_BIN" ] || [ ! -x "$AQUARIUM_BIN" ]; then
  printf 'aquarium 실행 파일을 찾지 못했습니다. config에 AQUARIUM_BIN=... 을 적어주세요.\n' >&2
  exit 1
fi
if [ -z "$JQ_BIN" ] || [ ! -x "$JQ_BIN" ]; then
  printf 'jq 를 찾지 못했습니다:  brew install jq\n' >&2
  exit 1
fi

mkdir -p "$LOUNGE_DIR"
chmod 700 "$LOUNGE_DIR" 2>/dev/null || true
: >> "$SEEN"

# ─────────────────────────────────────────────────────────── 로깅
#
# ⚠️ 이 로그는 스크립트가 직접 회전시킨다. launchd의 StandardOutPath를
#    회전시키면 안 된다 — launchd가 그 fd를 O_APPEND로 붙잡고 있어서 파일을
#    갈아치우면 이후 출력이 사라진 inode로 조용히 흘러간다. 로그가 멈춘 것처럼
#    보이는데 어디에도 에러가 없다. 회전은 fd를 열기 "전에" 한 번만 한다.

rotate_file() {  # rotate_file <path> <max_lines>
  local f=$1 max=$2 n
  [ -f "$f" ] || return 0
  n=$(wc -l < "$f" | tr -d ' ')
  [ "$n" -gt "$max" ] 2>/dev/null || return 0
  tail -n "$(( max / 2 ))" "$f" > "$f.rot" && mv -f "$f.rot" "$f"
}

rotate_file "$LOG" "$LOG_MAX_LINES"
rotate_file "$SEEN" "$SEEN_MAX"
exec 3>>"$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >&3; }

die() {
  log "FATAL $*"
  printf '[aquarium-lounge] FATAL %s\n' "$*" >&2
  printf '%s\n' "$(( $(date +%s) + FATAL_COOLDOWN ))" > "$COOLDOWN.tmp" \
    && mv -f "$COOLDOWN.tmp" "$COOLDOWN"
  exit 1
}

atomic_write() { printf '%s\n' "$2" > "$1.tmp.$$" && mv -f "$1.tmp.$$" "$1"; }

# 수조와 poller가 다른 계정에서 돌면 ~/.aquarium-adopt-inbox 가 갈려서
# "로그는 입양 OK인데 화면엔 아무것도 없는" 상태가 된다. 서사가 아니라
# grep 한 번으로 잡히도록 매 런 찍는다.
log "런 시작 user=$(whoami) HOME=$HOME bin=$AQUARIUM_BIN"

# ─────────────────────────────────────────────────────────── 락
# launchd는 동일 라벨을 중복 실행하지 않지만, 세팅 중 사람이 손으로 돌린다.

if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
    log "10분 넘은 락 발견 — 회수한다"
    rmdir "$LOCK" 2>/dev/null || true
    mkdir "$LOCK" 2>/dev/null || { log "락 회수 실패 — 건너뜀"; exit 0; }
  else
    log "다른 런이 진행 중 — 건너뜀"
    exit 0
  fi
fi

RUNDIR=$(mktemp -d "${TMPDIR:-/tmp}/aqpoll.XXXXXX")
# shellcheck disable=SC2329  # trap으로 호출된다
cleanup() { rmdir "$LOCK" 2>/dev/null || true; rm -rf "$RUNDIR" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# ─────────────────────────────────────────────────── 쿨다운 (429 / 설정 오류)

now_epoch=$(date +%s)
if [ -f "$COOLDOWN" ]; then
  cool=$(tr -dc '0-9' < "$COOLDOWN" 2>/dev/null || true)
  [ -n "$cool" ] || cool=0
  if [ "$now_epoch" -lt "$cool" ]; then
    log "쿨다운 중 ($(( cool - now_epoch ))초 남음) — 건너뜀"
    exit 0
  fi
  rm -f "$COOLDOWN"
fi

# ─────────────────────────────────────────────── 첫 실행: 백필하지 않는다

if [ ! -f "$LAST_TS" ]; then
  atomic_write "$LAST_TS" "${now_epoch}.000000"
  log "첫 실행 — 기준점 ${now_epoch}.000000 부터 감시. 과거 히스토리는 백필하지 않는다."
  exit 0
fi

last_ts=$(tr -d ' \n' < "$LAST_TS" 2>/dev/null || true)
case "$last_ts" in
  ''|*[!0-9.]*)
    log "last_ts 손상('$last_ts') — 현재 시각으로 리셋"
    last_ts="${now_epoch}.000000"
    atomic_write "$LAST_TS" "$last_ts"
    ;;
esac

# ─────────────────────────────────────────────────────────── Slack 호출

HTTP_CODE=0
slack_call() {  # slack_call <method> <curl args...>
  local method=$1; shift
  local rc=0
  set +e
  HTTP_CODE=$(curl -sS -m "$CURL_TIMEOUT" \
      -D "$RUNDIR/hdr" -o "$RUNDIR/body" -w '%{http_code}' \
      -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
      -H "Accept: application/json" \
      "$@" "${SLACK_API_BASE}/${method}" 2>"$RUNDIR/curlerr")
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    HTTP_CODE=0
    log "curl 실패 method=$method rc=$rc $(tr -d '\n' < "$RUNDIR/curlerr" 2>/dev/null)"
    return 1
  fi
  return 0
}

# 헤더 이름은 대소문자 무의미. macOS awk엔 IGNORECASE가 없으므로 tr로 눕힌다.
retry_after() {
  local v
  # shellcheck disable=SC2018,SC2019  # HTTP 헤더명은 스펙상 ASCII다.
  # [:upper:]/[:lower:]는 로케일에 따라 멀티바이트 처리가 달라져 오히려 불안정하다.
  v=$(tr -d '\r' < "$RUNDIR/hdr" 2>/dev/null | tr 'A-Z' 'a-z' \
      | awk '/^retry-after:/ { print $2; exit }')
  case "$v" in
    ''|*[!0-9]*) printf '60\n' ;;
    *)           printf '%s\n' "$v" ;;
  esac
}

# 본문이 JSON이 아닐 수 있다(프록시 에러 페이지, 5xx HTML, 429의 빈 본문).
# 파서가 그걸 가정하면 안 된다 — 절대 죽지 않게.
slack_error() {
  "$JQ_BIN" -r 'if type == "object" then (if (.ok // false) then "" else (.error // "unknown") end)
                else "non_json_response" end' < "$RUNDIR/body" 2>/dev/null || printf 'unparsable\n'
}

enter_cooldown() {  # enter_cooldown <seconds> <why>
  atomic_write "$COOLDOWN" "$(( $(date +%s) + $1 + 1 ))"
  log "쿨다운 $1초 설정 — $2"
}

# ───────────────────────────────────── 리액션 (절대 런을 죽이지 않는다)

react() {  # react <ts> <emoji-name>
  local ts=$1 name=$2 err
  if [ "$DRY_RUN" = "1" ]; then log "[dry-run] react :$name: ts=$ts"; return 0; fi

  if ! slack_call reactions.add \
        --data-urlencode "channel=${SLACK_CHANNEL_ID}" \
        --data-urlencode "timestamp=${ts}" \
        --data-urlencode "name=${name}"; then
    log "리액션 네트워크 실패 ts=$ts (입양 자체는 이미 완료)"
    return 0
  fi

  if [ "$HTTP_CODE" = "429" ]; then
    enter_cooldown "$(retry_after)" "reactions.add 429"; PARTIAL=1; return 0
  fi

  err=$(slack_error)
  case "$err" in
    "") : ;;
    already_reacted|message_not_found)
        log "리액션 무시 가능 ts=$ts err=$err" ;;
    ratelimited)
        enter_cooldown "$(retry_after)" "reactions.add ratelimited"; PARTIAL=1 ;;
    missing_scope)
        log "리액션 실패: reactions:write 스코프가 없습니다 (입양은 정상 동작 중)" ;;
    *)  log "리액션 실패 ts=$ts err=$err (입양은 완료)" ;;
  esac
  return 0
}

# ─────────────────────────────────────────────────────── 페이지네이션
#
#   conversations.history는 최신 → 과거 순으로 준다. oldest를 주면 그 구간의
#   최신 것부터 나오고 next_cursor가 과거로 넘어간다. 전 페이지를 모은 뒤
#   오름차순으로 처리한다.
#
#   ⚠️ 종료 판정은 반드시 has_more/next_cursor로 한다. 메시지 개수로 판정하면,
#      앱이 실수로 공개 배포되어 limit이 15로 조용히 잘렸을 때 오탐한다.
#      그래서 페이지마다 msgs=/has_more= 를 무조건 남긴다 — 이 로그가
#      "조용한 절단"을 잡는 유일한 트립와이어다.

PAIRS="$RUNDIR/pairs"
: > "$PAIRS"
cursor=""
page=0
newest_ts=""
msg_total=0

while :; do
  page=$(( page + 1 ))
  if [ "$page" -gt "$MAX_PAGES" ]; then
    log "페이지 상한 ${MAX_PAGES} 도달 — 이번 런은 부분 처리"; PARTIAL=1; break
  fi

  args=( --get
         --data-urlencode "channel=${SLACK_CHANNEL_ID}"
         --data-urlencode "oldest=${last_ts}"
         --data-urlencode "limit=${POLL_LIMIT}" )
  [ -n "$cursor" ] && args+=( --data-urlencode "cursor=${cursor}" )

  if ! slack_call conversations.history "${args[@]}"; then PARTIAL=1; break; fi

  if [ "$HTTP_CODE" = "429" ]; then
    enter_cooldown "$(retry_after)" "conversations.history 429"; PARTIAL=1; break
  fi

  err=$(slack_error)
  case "$err" in
    "") ;;
    invalid_auth|token_revoked|account_inactive|not_authed)
        die "Slack 토큰 문제 ($err). config의 SLACK_BOT_TOKEN을 다시 확인하세요." ;;
    missing_scope)
        needed=$("$JQ_BIN" -r '.needed // "?"' < "$RUNDIR/body" 2>/dev/null || echo '?')
        die "스코프 부족 (필요: $needed). 스코프 추가 후 반드시 Reinstall to Workspace 하세요." ;;
    channel_not_found)
        die "채널을 찾을 수 없습니다 (SLACK_CHANNEL_ID=${SLACK_CHANNEL_ID}). ID 오타이거나, 프라이빗 채널인데 봇이 초대되지 않았습니다." ;;
    not_in_channel)
        die "봇이 채널에 없습니다. 채널에서 /invite @<봇이름> 을 실행하세요." ;;
    ratelimited)
        enter_cooldown "$(retry_after)" "conversations.history ratelimited"; PARTIAL=1; break ;;
    *)
        log "conversations.history 오류 err=$err http=$HTTP_CODE — 이번 런 중단"
        PARTIAL=1; break ;;
  esac

  count=$("$JQ_BIN" -r '(.messages // []) | length' < "$RUNDIR/body")
  more=$("$JQ_BIN"  -r '.has_more // false'        < "$RUNDIR/body")
  msg_total=$(( msg_total + count ))

  pmax=$("$JQ_BIN" -r '[(.messages // [])[].ts // empty] | max // empty' < "$RUNDIR/body")
  if [ -n "$pmax" ] && [ -z "$newest_ts" ]; then newest_ts="$pmax"; fi

  # ── 핵심: 코드 추출을 전부 jq 안에서 한다 ────────────────────────────
  #   · grep -oE 가 무매치로 exit 1 해서 런이 죽는 사고가 없다
  #   · for code in $(...) 워드 스플리팅이 없다
  #   · text의 개행/탭이 새어나오지 않는다 (base64url엔 공백이 없으므로
  #     쌍 하나 = 한 줄이 보장된다)
  #   · 정규식은 --arg로 넘긴다. jq 문자열 리터럴에 넣으면 \. 를 \\. 로
  #     이스케이프해야 해서 사고가 난다.
  # shellcheck disable=SC2016  # jq 프로그램이다. 셸이 확장하면 안 된다.
  "$JQ_BIN" -r --arg re 'AQUA1\.[A-Za-z0-9_-]+' '
      (.messages // [])[]
      | select(.bot_id == null)                                     # 봇 메시지 제외 (에코 루프 방지)
      | select((.subtype // "") | . == "" or . == "thread_broadcast")
      | . as $m
      | ($m.text // "")
      | scan($re)
      | "\($m.ts)\t\(.)"
    ' < "$RUNDIR/body" >> "$PAIRS" 2>>"$RUNDIR/jqerr" || {
      log "jq 파싱 실패 page=$page: $(tr -d '\n' < "$RUNDIR/jqerr" 2>/dev/null)"
      PARTIAL=1; break
    }

  cursor=$("$JQ_BIN" -r '.response_metadata.next_cursor // ""' < "$RUNDIR/body")
  log "page=$page msgs=$count has_more=$more cursor=$([ -n "$cursor" ] && echo yes || echo no)"

  [ "$more" = "true" ] && [ -n "$cursor" ] || break
done

# ────────────────────────────────────────── 처리 (오름차순, 실패 격리)

SORTED="$RUNDIR/pairs.sorted"
# sort -u 로 완전 중복 줄 제거 → ts 오름차순.
# LC_ALL=C 없으면 소수점 구분자가 ','인 로케일에서 ts 비교가 깨진다.
LC_ALL=C sort -u "$PAIRS" | LC_ALL=C sort -n > "$SORTED" || : > "$SORTED"

adopted=0; invalid=0; skipped=0; deferred=0

while IFS="$TAB" read -r ts code; do
  [ -n "${ts:-}" ] || continue
  [ -n "${code:-}" ] || continue

  hash=$(printf '%s' "$code" | shasum -a 256 | cut -c1-16)

  # -x 줄 전체 일치, -F 정규식 아님, -- 옵션 종료
  if grep -qxF -- "$hash" "$SEEN" 2>/dev/null; then
    skipped=$(( skipped + 1 )); continue
  fi

  # 길이 가드. 정상 코드는 250자 안팎이다. 코어의 클램프는 decode 안에서
  # 도는데, 거기 닿기 전에 이미 argv로 올라간 뒤다 — 100KB짜리 코드가
  # 프로세스 테이블과 로그를 더럽히기 전에 여기서 자른다.
  if [ "${#code}" -gt "$MAX_CODE_LEN" ]; then
    log "코드가 너무 김 ts=$ts len=${#code} — 건너뜀"
    printf '%s\n' "$hash" >> "$SEEN"
    invalid=$(( invalid + 1 ))
    react "$ts" "$REACT_BAD"
    continue
  fi

  if [ "$adopted" -ge "$MAX_ADOPTS_PER_RUN" ]; then
    log "이번 런 입양 상한 ${MAX_ADOPTS_PER_RUN} 도달 — 나머지는 다음 런에서"
    PARTIAL=1; break
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] adopt ts=$ts hash=$hash len=${#code}"
    adopted=$(( adopted + 1 )); continue
  fi

  # 코드 하나가 터져도 런 전체를 죽이지 않는다
  set +e
  adopt_out=$("$AQUARIUM_BIN" --adopt "$code" 2>&1)
  adopt_rc=$?
  set -e
  adopt_out=$(printf '%s' "$adopt_out" | tr '\n' ' ')

  case "$adopt_rc" in
    0)
      # 순서: 입양 → seen 기록 → 리액션. seen 기록 전에 죽으면 다음 런이
      # 재입양하지만, 코어의 ingestAdoptions id 중복 검사가 흡수한다.
      printf '%s\n' "$hash" >> "$SEEN"
      adopted=$(( adopted + 1 ))
      log "입양 OK   ts=$ts hash=$hash | $adopt_out"
      react "$ts" "$REACT_OK"
      ;;
    1)
      printf '%s\n' "$hash" >> "$SEEN"   # 깨진 코드는 다시 시도해도 소용없다
      invalid=$(( invalid + 1 ))
      log "코드 무효 ts=$ts hash=$hash | $adopt_out"
      react "$ts" "$REACT_BAD"
      ;;
    *)
      # 75(EX_TEMPFAIL) 및 기타 = 일시적 실패. seen에 넣지 않고 리액션도 달지
      # 않는다 — 다음 런이 그대로 다시 집는다. last_ts도 전진시키지 않는다.
      deferred=$(( deferred + 1 )); PARTIAL=1
      log "일시 실패 ts=$ts hash=$hash rc=$adopt_rc — 다음 런에서 재시도 | $adopt_out"
      ;;
  esac
done < "$SORTED"

# ──────────────────────────────────────────────────────── last_ts 전진
#
#   완전히 깨끗하게 끝난 런에서만 전진시킨다. 부분 처리였다면 그대로 두고
#   다음 런이 다시 훑게 한다 — 해시 dedup 덕분에 재훑기는 멱등이다.

if [ "$PARTIAL" -eq 0 ] && [ -n "$newest_ts" ]; then
  atomic_write "$LAST_TS" "$newest_ts"
fi

log "런 종료 msgs=$msg_total pages=$page 입양=$adopted 무효=$invalid 중복스킵=$skipped 보류=$deferred partial=$PARTIAL"
exit 0
