#!/usr/bin/env bash
set -e

# ─── Config ──────────────────────────────────────────────────────────
ANDROID_SDK="D:/Software/AndroidSDK"
AVD_NAME="Medium_Phone_API_36.1"
EMULATOR="$ANDROID_SDK/emulator/emulator.exe"
ADB="$ANDROID_SDK/platform-tools/adb.exe"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AVD_HOME="${AVD_HOME:-C:/Users/15941/.android/avd}"
ADB_EMU=("$ADB" -e)

# ─── 1. Start emulator ──────────────────────────────────────────────
echo "[1/4] Starting emulator: $AVD_NAME ..."
emulator_pid=$(tasklist //FI "IMAGENAME eq emulator.exe" //NH 2>/dev/null | grep emulator | awk '{print $2}')
if [ -n "$emulator_pid" ]; then
  echo "  Emulator already running (PID $emulator_pid), skipping launch."
else
  ANDROID_AVD_HOME="$AVD_HOME" "$EMULATOR" -avd "$AVD_NAME" -no-audio &
  echo "  Emulator launching..."
fi

echo "[2/4] Waiting for boot..."
for i in $(seq 1 90); do
  state=$("${ADB_EMU[@]}" get-state 2>/dev/null || true)
  if [ "$state" = "device" ]; then
    boot=$("${ADB_EMU[@]}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
    if [ "$boot" = "1" ]; then
      echo "  Boot completed (~${i}s)"
      break
    fi
  fi
  sleep 2
  if [ "$i" -eq 90 ]; then
    echo "  ERROR: Emulator failed to boot in time."
    exit 1
  fi
done

# ─── 2. Build APK ───────────────────────────────────────────────────
echo "[3/4] Building debug APK..."
cd "$PROJECT_DIR"
flutter build apk --debug 2>&1 | tail -5
echo "  Build OK"

# ─── 3. Install & launch ────────────────────────────────────────────
echo "[4/4] Installing and launching..."
"${ADB_EMU[@]}" install -r "build/app/outputs/flutter-apk/app-debug.apk" 2>&1
"${ADB_EMU[@]}" shell am start -n "com.bmb.app.bmb_app/.MainActivity" 2>&1
echo "  Done!"
