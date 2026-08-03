#!/bin/bash
# 박수 감지 로컬 검증 — 마이크도 오디오 장치도 필요 없다.
#
# ClapDetector가 (rms, dt) 순수 상태 기계라서 합성 시퀀스로 전 경로를
# 결정론적으로 돌릴 수 있다. 픽스처 본문은 Sources/aquarium/ClapSelfTest.swift.
#
# 이 스크립트는 두 가지를 한다:
#   1) 픽스처 전체 실행 (AQUARIUM_CLAP_SELFTEST=1)
#   2) **변이 테스트** — 상수를 일부러 망가뜨려 해당 픽스처가 정말 빨개지는지
#      확인한다. 통과만 확인하면 "실패할 수 없는 테스트"를 눈치채지 못한다.
#      실제로 이 단계에서 죽은 픽스처 두 개(히스테리시스·바닥 동결)를 잡았다.
#
# 사용법:
#   bash scripts/dev/test-clap.sh          # 픽스처만 (빠름)
#   bash scripts/dev/test-clap.sh --mutate # 변이 테스트까지 (재빌드 반복, 느림)
set -uo pipefail
cd "$(dirname "$0")/../.."

BIN=${AQUARIUM_BIN:-.build/release/aquarium}
DETECTOR=Sources/aquarium/ClapDetector.swift
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대=$3 실제=$2)"; fi; }

if [ ! -x "$BIN" ]; then
    echo "빌드된 바이너리가 없다: $BIN"
    echo "  swift build -c release  를 먼저 실행할 것 (AQUARIUM_BIN 으로 경로 지정 가능)"
    exit 1
fi

echo "== 1. 픽스처 전체 =="
OUT=$(AQUARIUM_CLAP_SELFTEST=1 "$BIN" 2>&1); RC=$?
echo "$OUT" | sed 's/^/  /'
check "셀프테스트 종료 코드" "$RC" "0"

echo
echo "== 2. 절대 임계 env 노브 =="
# AQUARIUM_CLAP_THRESHOLD 는 재빌드 없는 현장 노브다. 낮추면 실측 사무실
# 소음 수준의 미세한 소리가 통과해 픽스처 1이 빨개져야 한다.
OUT=$(AQUARIUM_CLAP_THRESHOLD=0.005 AQUARIUM_CLAP_SELFTEST=1 "$BIN" 2>&1); RC=$?
check "임계 0.005 → 실패해야 한다" "$RC" "1"
if echo "$OUT" | grep -q "미세한 소리"; then
    ok "임계를 낮추면 '미세한 소리' 픽스처가 잡힌다"
else
    bad "임계를 낮췄는데 기대한 픽스처가 안 잡혔다"
fi
# 쓰레기 값은 무시하고 기본값으로 돌아가야 한다
OUT=$(AQUARIUM_CLAP_THRESHOLD=nonsense AQUARIUM_CLAP_SELFTEST=1 "$BIN" 2>&1); RC=$?
check "임계=nonsense → 기본값으로 무시" "$RC" "0"
OUT=$(AQUARIUM_CLAP_THRESHOLD=-1 AQUARIUM_CLAP_SELFTEST=1 "$BIN" 2>&1); RC=$?
check "임계=-1 → 기본값으로 무시" "$RC" "0"

if [ "${1:-}" = "--mutate" ]; then
    echo
    echo "== 3. 변이 테스트 (상수를 망가뜨려 픽스처가 잡는지 확인) =="
    command -v swift >/dev/null || { echo "  swift 없음 — 건너뛴다"; }
    cp "$DETECTOR" "$DETECTOR.bak"
    trap 'mv -f "$DETECTOR.bak" "$DETECTOR" 2>/dev/null; swift build -c release >/dev/null 2>&1' EXIT

    mutate() { # 이름  원본문자열  대체문자열  기대_적중_픽스처_패턴
        cp "$DETECTOR.bak" "$DETECTOR"
        if ! python3 - "$DETECTOR" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if old not in s:
    sys.exit(1)
open(p, 'w').write(s.replace(old, new, 1))
PY
        then bad "$1 (패치 문자열을 못 찾았다 — 소스가 바뀌었나?)"; return; fi
        if ! swift build -c release >/dev/null 2>&1; then bad "$1 (빌드 실패)"; return; fi
        OUT=$(AQUARIUM_CLAP_SELFTEST=1 "$BIN" 2>&1)
        if echo "$OUT" | grep -q "FAILED" && echo "$OUT" | grep -q "$4"; then
            ok "$1"
        else
            bad "$1 — 변이를 넣었는데 '$4' 픽스처가 안 잡혔다 (죽은 픽스처)"
        fi
    }

    mutate "히스테리시스 제거 → 벽 반사 오탐" \
        "releaseFactor: Float = 0.4" "releaseFactor: Float = 1.0" "벽 반사"
    mutate "바닥 동결 제거 → 갈채 중 바닥 상승" \
        "if !hot || hotFor > Self.floorUnstickSeconds {" "if true {" "바닥 동결"
    mutate "쿨다운 제거 → 군중 연타 발작" \
        "cooldownSeconds: Double = 3.0" "cooldownSeconds: Double = 0.01" "군중"
    mutate "리프랙토리 제거 → 초기 반사가 온셋 2개" \
        "refractorySeconds: Double = 0.12" "refractorySeconds: Double = 0" "초기 반사"
    mutate "워밍업 제거 → 기동 직후 오탐" \
        "warmupSeconds: Double = 1.0" "warmupSeconds: Double = 0" "워밍업"
    mutate "짝 창 하한 완화 → 299ms 통과" \
        "pairMinSeconds: Double = 0.30" "pairMinSeconds: Double = 0.10" "299ms"
    mutate "짝 창 상한 완화 → 601ms 통과" \
        "pairMaxSeconds: Double = 0.60" "pairMaxSeconds: Double = 1.20" "601ms"
    mutate "온셋 비율 완화 → 칩튠 위 박수 미검출" \
        "onsetRatio: Float = 6" "onsetRatio: Float = 2" "칩튠 재생 중"

    mv -f "$DETECTOR.bak" "$DETECTOR"
    swift build -c release >/dev/null 2>&1
    trap - EXIT
    echo "  (소스 복원 완료)"
else
    echo
    echo "  (변이 테스트는 --mutate 로 실행. 재빌드를 8번 반복하므로 느리다)"
fi

echo
echo "===== $PASS 통과 / $FAIL 실패 ====="
[ "$FAIL" -eq 0 ] || exit 1
