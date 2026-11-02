#!/bin/zsh
# Takes the README screenshots: builds Aicord (Debug), runs it in demo mode on
# an iPhone simulator and on this Mac, opens each screen, and saves light and
# dark shots.
#
#   scripts/screenshots.sh [ios|mac|all] [output directory]
#
# Defaults: all, screenshots/. The simulator "Aicord Demo" (iPhone 18 Pro) is
# made on first use, so a simulator signed in to a real account is never used.
# The Mac app is quit through AppleScript after each shot, which puts the real
# settings back (see Demo mode in .github/CONTRIBUTING.md). Saving the Mac
# window needs Screen Recording for the terminal.

set -euo pipefail

TARGET=${1:-all}
OUT=${2:-screenshots}
ROOT=${0:A:h:h}
BUILD=$ROOT/build/screenshots
BUNDLE=net.smigi.aicord
DEVICE_NAME="Aicord Demo"
DEVICE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro
# seconds from launch to a settled screen
SETTLE=8

# name, then the place to open (see DemoMode.openRequestedPlace)
IOS_SHOTS=(
  home ""
  server server
  chat swiftui
  showcase showcase
  dm @leopark
)
MAC_SHOTS=(
  chat swiftui
  showcase showcase
  dm @leopark
)

mkdir -p $OUT
OUT=${OUT:A}
TMP=$(mktemp -d)
trap 'rm -rf $TMP' EXIT
cd $ROOT

build() {
  echo "Building for $1"
  xcodebuild -workspace Aicord.xcworkspace -scheme Aicord -configuration Debug \
    -destination "$2" -derivedDataPath $BUILD/$1 build -quiet
}

launch_args() {
  local place=$1 scheme=$2
  local theme=Paicord.Light
  [[ $scheme == dark ]] && theme=Paicord.Dark
  local args=(-AicordDemo YES -Paicord.Theming.CurrentThemeID $theme)
  [[ -n $place ]] && args+=(-AicordDemoOpen $place)
  print -r -- "${args[@]}"
}

ios() {
  build ios 'generic/platform=iOS Simulator'
  local app=$BUILD/ios/Build/Products/Debug-iphonesimulator/Aicord.app
  local udid=$(xcrun simctl list devices -j | python3 -c "
import json, sys
for devices in json.load(sys.stdin)['devices'].values():
    for d in devices:
        if d['name'] == '$DEVICE_NAME' and d['isAvailable']:
            print(d['udid']); sys.exit()")
  if [[ -z $udid ]]; then
    local runtime=$(xcrun simctl list runtimes -j | python3 -c "
import json, sys
print([r['identifier'] for r in json.load(sys.stdin)['runtimes'] if r['platform'] == 'iOS' and r['isAvailable']][-1])")
    udid=$(xcrun simctl create "$DEVICE_NAME" $DEVICE_TYPE $runtime)
  fi
  xcrun simctl boot $udid 2>/dev/null || true
  xcrun simctl bootstatus $udid -b > /dev/null
  xcrun simctl install $udid $app
  xcrun simctl status_bar $udid override --time 9:41 --batteryState charged \
    --batteryLevel 100 --wifiBars 3 --cellularBars 4 --dataNetwork wifi

  for scheme in light dark; do
    xcrun simctl ui $udid appearance $scheme
    for name place in "${IOS_SHOTS[@]}"; do
      xcrun simctl terminate $udid $BUNDLE 2>/dev/null || true
      xcrun simctl launch $udid $BUNDLE ${(z)$(launch_args "$place" $scheme)} > /dev/null
      sleep $SETTLE
      # the simulator service may not write outside the home folder, so
      # the shot goes through a temporary file
      xcrun simctl io $udid screenshot --type png $TMP/shot.png > /dev/null 2>&1
      mv $TMP/shot.png $OUT/iphone-$name-$scheme.png
      echo "  iphone-$name-$scheme.png"
    done
  done
  xcrun simctl terminate $udid $BUNDLE 2>/dev/null || true
  xcrun simctl status_bar $udid clear
}

# Whether the Mac app is running (an iOS simulator's Aicord doesn't count).
mac_running() {
  pgrep -qf 'Aicord.app/Contents/MacOS/Aicord'
}

# The window number of the app's main window, for screencapture.
mac_window() {
  swift - <<'EOF'
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where (window[kCGWindowOwnerName as String] as? String) == "Aicord"
  && (window[kCGWindowLayer as String] as? Int) == 0 {
  print(window[kCGWindowNumber as String] as! Int)
  break
}
EOF
}

mac() {
  build mac 'platform=macOS'
  local app=$BUILD/mac/Build/Products/Debug/Aicord.app
  if mac_running; then
    echo "Quit Aicord first: the demo shares its settings." >&2
    exit 1
  fi
  for scheme in light dark; do
    for name place in "${MAC_SHOTS[@]}"; do
      open -n -a $app --args ${(z)$(launch_args "$place" $scheme)}
      sleep $SETTLE
      local window=$(mac_window)
      screencapture -l $window -x $OUT/mac-$name-$scheme.png
      echo "  mac-$name-$scheme.png"
      # a normal quit puts the real settings back
      osascript -e "tell application id \"$BUNDLE\" to quit"
      while mac_running; do sleep 0.5; done
    done
  done
}

case $TARGET in
  ios) ios ;;
  mac) mac ;;
  all) ios; mac ;;
  *) echo "usage: $0 [ios|mac|all] [output directory]" >&2; exit 2 ;;
esac
echo "Saved in $OUT"
