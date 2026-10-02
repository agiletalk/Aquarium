#!/bin/bash
# 데스크톱 앱 빌드·패키징.
#
#   scripts/release-desktop.sh personal   # Release — GitHub Releases + Homebrew cask (aquarium-desktop)
#   scripts/release-desktop.sh internal   # Release-Internal — 사내 스토어 업로드용 .app zip
#
# 둘 다 임시(ad-hoc) 서명이다. 개인 배포는 Cask의 postflight가 quarantine을 지운다.
# 이 스크립트는 산출물과 sha256만 만든다 — 태그·릴리스·Cask 갱신은 출력되는 안내대로 한다.
set -euo pipefail

kind="${1:-}"
case "$kind" in
  personal) config="Release";          suffix="" ;;
  internal) config="Release-Internal"; suffix="-internal" ;;
  *) echo "사용법: $0 personal|internal" >&2; exit 64 ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
desktop="$root/Desktop"
build="$desktop/build"
version="$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$desktop/AquariumDesktop.xcodeproj/project.pbxproj" | head -1)"
archive="$build/AquariumDesktop$suffix.xcarchive"
zip="$build/AquariumDesktop-$version$suffix.zip"

mkdir -p "$build"
rm -rf "$archive" "$zip"
xcodebuild -project "$desktop/AquariumDesktop.xcodeproj" -scheme AquariumDesktop \
  -configuration "$config" -archivePath "$archive" \
  -derivedDataPath "$build/DerivedData" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  archive | grep -E "error:|ARCHIVE"

app="$archive/Products/Applications/AquariumDesktop.app"
ditto -c -k --keepParent "$app" "$zip"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
echo ""
echo "구성      $config"
echo "번들 ID   $bundle_id"
echo "버전      $version"
echo "아키텍처  $(lipo -archs "$app/Contents/MacOS/AquariumDesktop")"
echo "산출물    $zip"
echo "sha256    $(shasum -a 256 "$zip" | cut -d' ' -f1)"

if [ "$kind" = personal ]; then
  cat <<NEXT

다음 단계 (개인 배포):
  1. gh release create desktop-v$version "$zip" --title "Aquarium Desktop $version" --notes "..."
     (터미널 릴리스 워크플로는 v* 태그에만 반응하므로 desktop-v* 태그는 건드리지 않는다)
  2. ~/Developer/homebrew-tap/Casks/aquarium-desktop.rb 의 version·sha256 갱신 후 푸시
  3. brew upgrade --cask aquarium-desktop 로 확인
NEXT
fi
