# vhs demo.tape 로 README용 GIF를 다시 만들 수 있습니다.
Output demo.gif

Set Shell bash
Set FontSize 16
Set Width 1000
Set Height 560
Set Padding 12
Set Framerate 15
Set Theme "Catppuccin Mocha"

Hide
Type "rm -rf /tmp/aqua-demo && mkdir -p /tmp/aqua-demo && HOME=/tmp/aqua-demo .build/release/aquarium"
Enter
Sleep 500ms
Show

# 자동 → 밤 → 낮: 두 번 눌러 낮으로 고정
Type "nn"
Sleep 4s
Type "f"
Sleep 5s
Type "f"
Sleep 5s

# 낮 → 자동 → 밤: 두 번 눌러 밤으로 고정
Type "nn"
Sleep 6s
Type "f"
Sleep 5s

Hide
Type "q"
Sleep 500ms
