# vhs demo.tape 로 README용 GIF를 다시 만들 수 있습니다.
Output demo.gif

Set Shell bash
Set FontSize 14
Set Width 1500
Set Height 640
Set Padding 12
Set Framerate 15
Set Theme "Catppuccin Mocha"

Hide
Type "rm -rf /tmp/aqua-demo && mkdir -p /tmp/aqua-demo && HOME=/tmp/aqua-demo AQUARIUM_VISITOR=whale .build/release/aquarium"
Enter
Sleep 500ms
Show

# 자동 → 밤 → 낮: 두 번 눌러 낮으로 고정 (4초쯤 고래 등장)
Type "nn"
Sleep 5s
Type "g"
Sleep 5s

# 도감 패널
Type "i"
Sleep 4s
Type "i"
Sleep 2s

# 낮 → 자동 → 밤: 두 번 눌러 밤으로 고정
Type "nn"
Sleep 6s
Type "f"
Sleep 4s

Hide
Type "q"
Sleep 500ms
