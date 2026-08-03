# 라운지 맥 세팅 — 모두의 수조

동료가 사내 Slack 채널에 `AQUA1.…` 분양 코드를 붙여넣으면, 라운지 대형 화면의
수조로 그 물고기가 헤엄쳐 들어온다. 이 문서는 **라운지 맥에서 딱 한 번** 하는
세팅 절차다.

- **소요 시간**: 30~45분 (Slack 앱 승인 대기 제외)
- **준비물**: 라운지 맥 관리자 계정, Slack 워크스페이스에 앱을 만들 권한,
  대형 디스플레이
- **끝나면**: 아무도 안 만져도 몇 주간 혼자 돌아간다

> 전제: 라운지 맥은 최초 세팅 이후 일상적으로 조작할 수 없다. 그래서 서버도
> 인바운드도 없이 아웃바운드 폴링만으로 성립하게 짜여 있다.

---

## 1. 전제 확인

```sh
sw_vers                       # macOS 12 이상
command -v brew               # Homebrew 있어야 함
```

**계정을 하나로 통일한다.** 수조를 띄우는 계정과 poller를 돌리는 계정이 다르면
`~/.aquarium-adopt-inbox` 가 갈려서 **로그에는 "입양 OK"가 찍히는데 화면에는
아무것도 안 나오는** 상태가 된다. 가장 찾기 어려운 고장이다.

```sh
brew install agiletalk/tap/aquarium
brew install jq
```

---

## 2. Slack 앱 만들기

### 2-1. 앱 생성 — 매니페스트로 (권장)

<https://api.slack.com/apps> → **Create New App** → **From a manifest** →
워크스페이스 선택 → [`docs/slack-app-manifest.yml`](slack-app-manifest.yml)
내용을 붙여넣기 → **Create**.

스코프가 미리 박혀 있어서 **2-2를 건너뛸 수 있고**, 아래 "Reinstall 함정"도
애초에 발생하지 않는다. 비공개 채널이면 매니페스트의 `channels:history` 를
`groups:history` 로 바꿔서 붙여넣는다.

> 손으로 만들려면 **Blank app** 을 고른다 (예전 "From scratch" 가 이 이름으로
> 바뀌었다. 위쪽 `AI agent` / `Starter app` 은 우리와 무관한 템플릿이다).
> 그다음 2-2로.

### 2-2. 스코프 — 손으로 만들었을 때만

**OAuth & Permissions** → **Bot Token Scopes** 에 추가한다.

| 스코프 | 언제 | 왜 |
|---|---|---|
| `channels:history` | 채널이 **퍼블릭**일 때 | `conversations.history` 가 요구 |
| `groups:history` | 채널이 **프라이빗**일 때 | 같은 메서드가 프라이빗 채널엔 이 스코프를 요구한다. 폐기된 게 아니라 2026년 현재도 이게 맞다 |
| `reactions:write` | 항상 | 🐠 / ⚠️ 영수증 |

`channels:read` 는 **필요 없다.** 채널 이름 → ID 변환용(`conversations.list`)인데,
ID는 Slack UI에서 한 번 복사하면 끝이다. 스코프는 적을수록 좋다.

> ⚠️ **가장 흔한 사고**: 스코프를 추가하고 **"Reinstall to Workspace" 를 누르지
> 않는 것.** 기존 토큰에는 새 스코프가 붙지 않아서 로그에 `missing_scope` 가
> 계속 뜬다. 스코프를 건드렸으면 **반드시 재설치하고 토큰을 다시 복사**한다.

### 2-3. ⛔ 절대 누르지 말 것: Activate Public Distribution

> 이 앱은 우리 워크스페이스 안에서만 쓰는 **internal customer-built app** 이다.
> 그 상태에서 `conversations.history` 는 **분당 50회 이상 / 한 번에 최대 1,000건**
> 을 쓸 수 있다.
>
> **Manage Distribution** 에서 공개 배포를 켜는 순간 Slack은 이 앱을
> "commercially distributed" 로 재분류하고, 같은 메서드가 **분당 1회 / 한 번에
> 최대 15건** 으로 떨어진다.
> ([2025-05-29 공지](https://docs.slack.dev/changelog/2025/05/29/rate-limit-changes-for-non-marketplace-apps),
> [2025-06-03 보충](https://docs.slack.dev/changelog/2025/06/03/rate-limits-clarity/) —
> "Any internal customer-built apps will maintain their existing rate limits")
>
> **에러가 나는 게 아니라 조용히 잘린다.** `poller.log` 의 `msgs=` 값이 갑자기
> 15에서 멈춘다면 이걸 의심하라. 그래서 poller는 페이지마다 `msgs=`/`has_more=`
> 를 무조건 남긴다.

### 2-4. 봇 토큰 복사

**OAuth & Permissions** → **Install to Workspace** → 승인 →
**Bot User OAuth Token** (`xoxb-` 로 시작) 복사.

### 2-5. 채널 초대 + 채널 ID

1. 채널을 만든다 (예: `#aquarium-lounge`)
2. 채널에서 `/invite @aquarium` — **공개·비공개 모두 초대가 필수**다.
   (핸들은 매니페스트의 `features.bot_user.display_name` 값이다. 앱 이름이
   아니라 이쪽이니 헷갈리지 말 것.)
   봇 토큰은 스코프가 있어도 **자기가 속한 대화만** 읽을 수 있다
   ([conversations.history 문서](https://docs.slack.dev/reference/methods/conversations.history):
   "Only user tokens can access public channels they are not in").
   초대를 빠뜨리면 공개 채널은 `not_in_channel`, 비공개 채널은 아예 보이지
   않아서 `channel_not_found` 가 뜬다 — 같은 원인인데 증상이 다르다.
3. 채널 이름 클릭 → 맨 아래 **채널 ID: `C0123ABCD`** 복사.
   (또는 채널 우클릭 → 링크 복사 → URL 마지막 조각 `.../archives/C0123ABCD`)

---

## 3. 설정 파일

```sh
mkdir -p ~/.aquarium-lounge && chmod 700 ~/.aquarium-lounge
( umask 077; cat > ~/.aquarium-lounge/config <<'EOF'
SLACK_BOT_TOKEN="xoxb-여기에-붙여넣기"
SLACK_CHANNEL_ID="C0123ABCD"

# 선택 — 기본값을 바꿀 때만
# AQUARIUM_BIN=/opt/homebrew/bin/aquarium
# MAX_ADOPTS_PER_RUN=25
EOF
)
chmod 600 ~/.aquarium-lounge/config
ls -l ~/.aquarium-lounge/config     # -rw------- 이어야 한다
```

> 🔐 **토큰을 launchd plist에 넣지 마세요.** `~/Library/LaunchAgents/*.plist` 는
> 644(누구나 읽기 가능)이고 `launchctl print` 로도 환경 변수가 평문으로 보인다.
> poller는 config 파일 권한이 600이 아니면 **실행을 거부**한다.

**폴링 주기는 여기 없다.** 주기는 launchd plist가 소유한다 (→ 6단계).

---

## 4. poller 스크립트 설치

> `brew install agiletalk/tap/aquarium` 은 **바이너리만** 설치한다. 릴리스
> tarball에는 `aquarium` 실행 파일 하나뿐이라 poller 스크립트는 들어 있지 않다.

```sh
mkdir -p ~/Aquarium && cd ~/Aquarium
git clone --depth 1 https://github.com/agiletalk/Aquarium .
chmod +x scripts/lounge-slack-poller.sh scripts/lounge-set-interval.sh
```

---

## 5. 손으로 한 번 돌려서 검증

```sh
cd ~/Aquarium
DRY_RUN=1 bash scripts/lounge-slack-poller.sh   # 첫 실행: 기준점만 심는다
DRY_RUN=1 bash scripts/lounge-slack-poller.sh   # 두 번째부터 실제로 훑는다
cat ~/.aquarium-lounge/poller.log
```

`DRY_RUN=1` 은 입양도 리액션도 하지 않고 로그만 남긴다. 채널에 코드를 하나
올려두고 `[dry-run] adopt …` 가 찍히는지 보면 된다.

정상이면 `DRY_RUN` 없이 한 번 돌려서 실제로 🐠 가 붙는지 확인한다.

> **첫 실행은 과거 히스토리를 백필하지 않는다.** 기준점을 "지금"으로 심고
> 끝낸다. 채널 히스토리를 통째로 입양해버리는 사고를 막기 위한 의도된 동작이다.

---

## 6. launchd 등록

```sh
cd ~/Aquarium
sed "s|__HOME__|$HOME|g" scripts/com.agiletalk.aquarium.lounge-slack-poller.plist \
  > ~/Library/LaunchAgents/com.agiletalk.aquarium.lounge-slack-poller.plist
plutil -lint ~/Library/LaunchAgents/com.agiletalk.aquarium.lounge-slack-poller.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.agiletalk.aquarium.lounge-slack-poller.plist
```

확인 / 조작:

```sh
launchctl print gui/$(id -u)/com.agiletalk.aquarium.lounge-slack-poller
launchctl kickstart -k gui/$(id -u)/com.agiletalk.aquarium.lounge-slack-poller  # 지금 즉시 1회
launchctl bootout  gui/$(id -u)/com.agiletalk.aquarium.lounge-slack-poller      # 해제
```

### 폴링 주기 바꾸기

기본 **60초**다. 코드를 올리고 나서 물고기가 나타나기까지 평균 ~35초, 최악
~65초 (폴링 0~60초 + 어항 인박스 점검 0~5초).

```sh
bash scripts/lounge-set-interval.sh        # 현재 주기 확인
bash scripts/lounge-set-interval.sh 30     # 30초로 (재적용까지 자동)
```

30초도 rate limit 상 안전하다. 그런데도 60을 기본으로 둔 건 **2-3의 공개 배포
사고에 대한 헤지**다 — 그 상태가 되면 분당 1회로 떨어지는데, 60초·단일 페이지면
버티고 30초는 즉시 초과한다.

주기만 config가 아니라 plist에 산다. poller는 원샷 스크립트라 자기 실행 주기를
스스로 정할 수 없어서, config에 적어두면 효력 없는 장식이 되기 때문이다.
poller가 매 런 실효 주기를 로그에 남기므로 어긋나면 바로 보인다.

---

## 7. 수조 띄우기 — 터미널과 화면

### 창 크기가 어항 크기를 정한다

정원은 `max(8, min(120, 가로칸 × 세로줄 ÷ 80))` 이다.
**정원 120을 채우려면 가로 × 세로 ≥ 9,600.**

`200 × 48 = 9,600` 은 딱 경계라 한 칸만 모자라도 정원이 줄어든다.
**210 × 50 (= 10,500)** 정도로 여유를 두자.

전체화면에서는 프로필의 Columns/Rows 설정이 무시되고 **폰트 크기가 유일한
레버**다. 전체화면 창에서 먼저 이걸로 확인한다:

```sh
printf '%s x %s = %s\n' "$(tput cols)" "$(tput lines)" "$(( $(tput cols) * $(tput lines) ))"
```

9,600을 넘을 때까지 폰트를 줄인다.

### iTerm2 프로필

Terminal.app보다 iTerm2를 권한다 — 프로필에 실행 명령과 전체화면을 박을 수 있다.

- **Profiles → General → Command**: `Command` 선택 후
  ```
  /bin/bash -lc 'export AQUARIUM_TANKNAME="라운지"; while :; do /opt/homebrew/bin/aquarium --lounge; sleep 3; done'
  ```
  `while :;` 는 크래시 재기동 가드다.
  **주의**: 이 루프 때문에 `Ctrl-C` 로는 수조가 안 꺼진다(바로 재시작한다).
  정비하려면 iTerm2를 `Cmd-Q` 로 종료한다.
- **Profiles → Window → Style**: `Full Screen`
- 이 프로필을 **Default** 로 지정

### 마이크 권한 — `--clap` 을 쓸 때만

박수 반응(`aquarium --lounge --clap`)은 마이크를 쓴다. 안 쓸 거면 이 소절은
통째로 건너뛴다. 위 Command 의 `aquarium --lounge` 를 `aquarium --lounge --clap`
으로 바꾸면 켜진다.

**권한은 아쿠아리움이 아니라 터미널 앱에 붙는다.** 아쿠아리움은 번들 없는
명령줄 바이너리라 TCC 가 이걸 독립된 앱으로 보지 못하고, 대신 실행시킨 터미널
앱을 책임 프로세스로 잡는다. 그래서 권한 창이 "iTerm2이(가) 마이크에 접근하려
합니다"로 뜨고, 시스템 설정 → 개인정보 보호 및 보안 → 마이크 목록에도 터미널
앱 이름으로 올라간다. **그 목록에서 아쿠아리움을 아무리 찾아도 없다.**

**권한은 터미널 앱마다 따로다.** Terminal.app 에서 허용해둬도 iTerm2 는 처음부터
다시 묻는다. 실제로 수조를 띄울 그 앱으로 허용해야 한다.

실측해본 터미널 앱은 **전부 정상 작동했다** (2026-08-03, macOS 26.5):

| 터미널 앱 | 결과 |
|---|---|
| iTerm2 3.6.11 | ○ 권한 창 뜸, 허용 후 정상 |
| Terminal.app | ○ 권한 창 뜸, 허용 후 정상 |
| Ghostty · Warp · Otty | ○ (Otty 실측, 나머지는 정적 확인) |

> Info.plist 의 `NSMicrophoneUsageDescription` 유무로 미리 판별하려 들지 말 것.
> Terminal.app 은 그 키도 `com.apple.security.device.audio-input` entitlement 도
> **둘 다 없는데 정상 작동한다** (애플 사설 `tcc.allow-prompting` 이 대신 일한다).
> plist 검사는 예측 도구가 아니다 — 그냥 실행해서 권한 창이 뜨는지 보면 된다.

**첫 실행만은 사람이 봐야 한다.** 권한 창은 로그인한 사람이 눌러야 사라진다.
무인 재부팅에서는 뜨지 않고, 한 번 허용해두면 그 뒤로는 조용히 통과한다.
그래서 세팅 당일에 `--clap` 을 붙인 채로 **직접 한 번 띄워서 허용을 눌러야** 한다.
이 순서를 건너뛰면 전시가 몇 주 동안 죽은 마이크 앞에서 돈다.

**허용됐는지는 화면으로 확인한다.** 상태줄에 **👂** 가 떠 있으면 마이크가 실제로
소리를 듣고 있는 것이다. 이 표시는 플래그를 줬다고 뜨지 않는다 — 오디오 엔진이
돌고 **0 아닌 샘플이 실제로 들어와야** 뜬다. 그래서 음소거·입력 볼륨 0·신호
없는 가상 입력 장치도 전부 "👂 없음"으로 정직하게 드러난다.
15초 로테이션 힌트에 "박수를 두 번 쳐보세요"가 끼는 것도 같은 조건이다.

마이크가 잠깐 빠졌다 다시 꽂히면 **재시작 없이 저절로 살아난다** — 👂 가 다시
뜬다. 기동할 때 "소리가 전혀 들어오지 않습니다" 안내가 떴어도 마찬가지다.

**감도 조정 — `AQUARIUM_CLAP_THRESHOLD`.** 기본값 0.018 은 노트북 마이크 0.5m
거리 실측(사무실 정적 최대 0.0127 / 근거리 박수 피크 0.0968)에서 잡았다.
라운지는 마이크가 사람과 2~3m 떨어져 있어 같은 박수가 훨씬 약하게 들어오므로
현장에서 한 번 맞춰야 할 수 있다. 재빌드 없이 export 한 줄이면 된다:

```sh
export AQUARIUM_CLAP_THRESHOLD=0.012   # 반응이 둔하면 낮춘다
export AQUARIUM_CLAP_THRESHOLD=0.030   # 오탐이 잦으면 올린다
```

낮은 쪽으로 트는 걸 권한다. 임계가 낮으면 물고기가 가끔 괜히 놀라는 정도지만
(3초 불응기가 발작을 막는다), 높으면 먼 박수가 아예 안 잡혀서 전시가 죽은 것처럼
보인다.

**소리는 저장되지 않는다.** 버퍼에서 크기(RMS)만 계산하고 즉시 버린다. 디스크에
쓰지 않고, 네트워크로 나가지 않고, 음성 인식도 없다. 공용 공간에 상시 마이크를
두는 일이니 동료 안내문(11절)에도 한 줄 넣어두길 권한다.

### QR 주소

QR 기본값은 레포 주소다. 사내 안내 페이지로 바꾸려면 재빌드 없이 환경변수만
바꾸면 된다 — 위 Command의 export 줄에 추가한다:

```sh
export AQUARIUM_LOUNGE_QR="https://example.com/aquarium"
```

**공개 레포이므로 사내 주소를 코드에 박는 선택지는 없다.**

---

## 8. 재부팅 생존

라운지 맥은 정전이나 업데이트로 반드시 재부팅된다. 아래를 안 하면 그때부터
화면이 죽어 있다.

1. **자동 로그인 켜기** — 시스템 설정 → 사용자 및 그룹 → 자동으로 로그인
2. **FileVault 끄기** — FileVault가 켜져 있으면 자동 로그인이 **불가능**하다.
   > `~/Library/LaunchAgents` 는 `gui/<uid>` 도메인이라 **GUI 로그인 없이는 아예
   > 안 뜬다.** LaunchDaemon으로 바꾸면 root로 돌아 `HOME=/var/root` 가 되고
   > 아무도 읽지 않는 인박스에 쓰게 된다 — **도메인이 아니라 로그인을 고쳐야
   > 한다.**
   >
   > 트레이드오프를 정직하게 적어둔다: FileVault를 끄면 토큰이 암호화되지 않은
   > 디스크에 놓인다. 완화책은 (a) 봇 스코프가 읽기 + 리액션뿐이라 유출돼도
   > 글을 쓰거나 DM을 읽을 수 없고, (b) 맥이 분실되면 토큰을 즉시 폐기하면
   > 되고, (c) 이 기계에 다른 비밀을 두지 않는 것이다.
   > 보안 정책상 FileVault가 강제라면 "세팅 후 무인" 전제가 깨진다 —
   > 재부팅마다 사람이 콘솔에 가야 한다.
3. **잠들지 않게**
   ```sh
   sudo pmset -a sleep 0 displaysleep 0 disksleep 0 standby 0 hibernatemode 0 autorestart 1
   ```
   `autorestart 1` 은 정전 복구 후 자동 재시작이다. 화면 보호기도 끈다.
4. **수조 자동 실행** — 시스템 설정 → 일반 → 로그인 항목 에 **iTerm** 추가.
   (수조는 TTY와 보이는 창이 필요해서 launchd가 아니라 로그인 항목이다.)

---

## 9. 로그

| 파일 | 내용 | 정상 상태 |
|---|---|---|
| `~/.aquarium-lounge/poller.log` | 매 런 요약, 입양/무효/스킵, 페이지 수 | 계속 쌓인다. 2,000줄 넘으면 스크립트가 절반으로 자른다 |
| `~/.aquarium-lounge/launchd.err.log` | launchd가 잡은 표준에러 | **비어 있어야 정상.** 내용이 있으면 설정 오류다 |
| `~/.aquarium-lounge/launchd.out.log` | 표준출력 | 비어 있어야 정상 |

```sh
tail -f ~/.aquarium-lounge/poller.log
```

> 이 로그는 스크립트가 직접 회전시킨다. **launchd의 `StandardOutPath` 파일을
> 손으로 회전시키지 마라** — launchd가 그 fd를 붙잡고 있어서 파일을 갈아치우면
> 이후 출력이 사라진 inode로 조용히 흘러간다. 로그가 멈춘 것처럼 보이는데
> 어디에도 에러가 없다.

---

## 10. 문제 해결

| # | 증상 | 로그 | 조치 |
|---|---|---|---|
| 1 | 아무 반응 없음, err 로그에 FATAL | `채널을 찾을 수 없습니다` / `봇이 채널에 없습니다` | 채널 ID 오타, `/invite @봇` 누락, 또는 프라이빗인데 `groups:history` 없음 |
| 2 | 스코프를 넣었는데 계속 FATAL | `스코프 부족 (필요: …)` | **Reinstall to Workspace 를 안 했다.** 재설치 후 새 `xoxb-` 토큰으로 config 갱신 |
| 3 | 물고기는 들어오는데 🐠 가 안 붙음 | `리액션 실패 … missing_scope` / `already_reacted` | `reactions:write` 누락, 또는 이미 붙어 있음(정상) |
| 4 | 코드를 올렸는데 로그에 흔적조차 없음 | 아무것도 없음 | ① 스레드 답글에 올림 ② 기존 메시지를 **수정**해서 올림 ③ **파일·이미지를 첨부하면서 코멘트에 코드를 씀** ④ 봇/워크플로가 올림 ⑤ 첫 실행 기준점보다 오래된 메시지 (→ 12절) |
| 5 | 로그는 `입양 OK` 인데 화면에 없음 | `입양 OK ts=…` | ① **수조와 poller가 다른 계정** — `poller.log` 의 `런 시작 user=… HOME=…` 과 수조 터미널의 `whoami` 를 비교 ② 수조가 안 떠 있다(다음에 켜면 들어온다) ③ 같은 물고기가 이미 수조에 있다 |

| 6 | `--clap` 을 붙였는데 박수에 반응이 없음 | — (수조는 로그를 안 남긴다) | ① 상태줄에 **👂** 가 있는지 본다. **없으면** 마이크가 안 열렸거나 소리가 안 들어오는 것 → 시스템 설정 → 마이크에서 **터미널 앱**(아쿠아리움 아님)이 켜져 있는지, 입력 볼륨·음소거는 어떤지 (→ 7절 「마이크 권한」) ② **있는데** 반응이 없으면 감도 문제다 → `AQUARIUM_CLAP_THRESHOLD` 를 0.012 로 낮춰본다 ③ **두 번** 쳐야 한다. 단발은 무시하고, 3초 안에 여러 번 쳐도 한 번만 반응한다 |

`msgs=` 가 15에서 멈춘다면 → **2-3의 공개 배포 사고**를 의심한다.

---

## 11. 동료용 안내문 (채널 토픽/공지에 붙여넣기)

```
🐠 모두의 수조 — 라운지 화면에 내 물고기 보내기

1) brew install agiletalk/tap/aquarium
2) aquarium              ← 물고기를 키우고 이름을 지어주세요
3) aquarium --release <물고기이름>
4) 출력된 마지막 줄(AQUA1.… )을 이 채널에 그대로 붙여넣기

1~2분 안에 라운지 수조로 헤엄쳐 들어가고, 올린 메시지에 🐠 가 붙습니다.
⚠️ 가 붙으면 코드가 깨진 거예요 — 다시 --release 해서 새 코드를 올려주세요.

· 스레드 답글 말고 채널에 바로 올려주세요 (스레드는 못 읽어요)
· 메시지를 수정해서 고치면 인식이 안 됩니다 — 새 메시지로 올려주세요
· 한 번 보낸 물고기는 내 수조를 떠납니다. 라운지에서 잘 지낼 거예요 🫧

👏 화면 앞에서 박수를 두 번 쳐보세요 — 물고기마다 놀라는 방법이 달라요
   (마이크는 소리 크기만 재고 바로 버립니다. 녹음·저장·전송 없어요)
```

> 마지막 두 줄은 `--clap` 을 켰을 때만 붙인다. 안 켰으면 지우고 붙여넣는다.

---

## 12. 알려진 한계

- **스레드 답글은 읽지 않는다.** `conversations.history` 는 채널 최상위
  메시지만 돌려준다. 스레드에서 올려야 한다면 **"채널에도 게시"** 를 체크하면
  된다 (`thread_broadcast` 는 지원한다).
- **메시지를 수정해서 코드를 고치면 인식되지 않는다.** 수정해도 메시지의 `ts`
  는 그대로라 "이 시각 이후"로 훑는 poller의 시야에 다시 들어오지 않는다.
  새 메시지로 올려야 한다.
- **파일·이미지를 첨부하면서 코멘트에 코드를 쓰면 인식되지 않는다.** 그런
  메시지는 `subtype: file_share`가 붙는데, poller가 입장 알림 같은 시스템
  메시지를 걸러내려고 subtype 있는 메시지를 통째로 제외하기 때문이다.
  **코드는 첨부 없이 그냥 텍스트로 올려야 한다.** (필요해지면 허용 목록에
  `file_share` 한 단어를 추가하면 된다 — `scripts/lounge-slack-poller.sh`의
  jq `select((.subtype // "") | ...)` 줄)
- **봇·워크플로가 올린 메시지는 무시한다** (에코 루프 방지).
- **첫 실행 이전의 과거 메시지는 백필하지 않는다.**
- **같은 코드를 다시 올려도 물고기가 복제되지 않는다** — poller가 코드 해시를
  기록해 건너뛴다. 다만 그 기록은 이 기계의 `~/.aquarium-lounge/seen` 에만
  있으므로, 그 파일을 지우면 과거 코드가 다시 들어올 수 있다.
- **`--clap` 은 터미널 앱에서 띄운 수조에서만 검증했다.** 다만 8절이 권하는
  구성에서는 **문제가 되지 않는다** — 로그인 항목에 등록하는 건 iTerm2 이고
  수조는 그 안에서 도니까, 책임 프로세스가 검증한 경로와 똑같이 터미널 앱이다.
  launchd 로 도는 건 poller 뿐이고 poller 는 마이크를 쓰지 않는다.

  확인하지 못한 건 하나뿐이다: `aquarium --clap` 을 **LaunchAgent/LaunchDaemon
  으로 직접** 띄우는 경우. 그러면 책임 프로세스가 터미널이 아니게 되어 마이크
  권한 귀속이 어떻게 되는지 모른다. 애초에 수조는 TTY 와 보이는 창이 필요해서
  그렇게 띄울 수 없으니(8절 4항), 8절을 따르는 한 해당 없다.
- **박수 감지는 소리 크기만 본다.** 주파수나 파형을 보지 않으므로 300~600ms
  간격으로 크게 두 번 나는 소리(문 쾅쾅 등)는 오탐할 수 있다. 대가가 물고기가
  한 번 놀라는 것뿐이라 그대로 뒀다.

---

## 13. 유지보수

```sh
# 토큰 교체
chmod 600 ~/.aquarium-lounge/config && vi ~/.aquarium-lounge/config
launchctl kickstart -k gui/$(id -u)/com.agiletalk.aquarium.lounge-slack-poller

# 잠시 끄기 / 다시 켜기
launchctl bootout   gui/$(id -u)/com.agiletalk.aquarium.lounge-slack-poller
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.agiletalk.aquarium.lounge-slack-poller.plist

# 완전 제거 (수조 상태는 ~/.aquarium.json 에 그대로 남는다)
launchctl bootout gui/$(id -u)/com.agiletalk.aquarium.lounge-slack-poller
rm ~/Library/LaunchAgents/com.agiletalk.aquarium.lounge-slack-poller.plist
rm -rf ~/.aquarium-lounge
```

**업데이트**: `brew upgrade aquarium` 후 `cd ~/Aquarium && git pull`.
수조는 iTerm2의 재기동 루프가 다음 번에 새 바이너리를 집는다.

---

## 부록 — 워크스페이스 없이 검증하기

Slack 앱을 만들기 전에 poller 동작을 확인하고 싶다면:

```sh
cd ~/Aquarium
swift build -c release          # 소스에서 빌드한 경우
bash scripts/dev/test-poller.sh
```

가짜 Slack API(`scripts/dev/fake-slack.py`)를 띄우고 페이지네이션·429·중복·
에러·길이 폭탄·`exit 75` 재시도까지 49개 단언을 돌린다.
