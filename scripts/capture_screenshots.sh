#!/bin/zsh
# Capture current SimpliXio UI, then generate strict App Store assets.
# iPhone and iPad use XCTest attachments. macOS launches the real app directly
# so asset generation does not depend on the host's UI-automation service.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/CortexOSApp"
PROJECT="$APP_DIR/CortexOS.xcodeproj"
RESULT_DIR="$APP_DIR/screenshot_results"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/simplixio-screenshots.XXXXXX")"
WORK_DIR="$(cd "$WORK_DIR" && pwd -P)"
IOS_DERIVED_DATA="${SCREENSHOT_IOS_DERIVED_DATA:-$WORK_DIR/ios-derived-data}"
MAC_DERIVED_DATA="${SCREENSHOT_MAC_DERIVED_DATA:-$WORK_DIR/mac-derived-data}"
CAPTURE_TARGETS="${1:-iphone,ipad,mac}"

capture_target_enabled() {
    local target="$1"
    [[ ",$CAPTURE_TARGETS," == *",$target,"* ]]
}

for target in ${(s:,:)CAPTURE_TARGETS}; do
    case "$target" in
        iphone|ipad|mac) ;;
        *)
            echo "Unknown capture target: $target" >&2
            echo "Usage: $0 [iphone,ipad,mac]" >&2
            exit 2
            ;;
    esac
done

mkdir -p "$IOS_DERIVED_DATA" "$MAC_DERIVED_DATA"
IOS_DERIVED_DATA="$(cd "$IOS_DERIVED_DATA" && pwd -P)"
MAC_DERIVED_DATA="$(cd "$MAC_DERIVED_DATA" && pwd -P)"

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

for command_name in xcodebuild xcodegen; do
    require_command "$command_name"
done
if capture_target_enabled iphone || capture_target_enabled ipad; then
    for command_name in xcrun jq; do
        require_command "$command_name"
    done
fi
if capture_target_enabled mac; then
    for command_name in osascript pgrep screencapture swiftc; do
        require_command "$command_name"
    done
fi

if [[ ! -f "$APP_DIR/local.yml" ]]; then
    echo "Missing CortexOSApp/local.yml. Copy local.yml.example and add your Apple Developer Team ID." >&2
    exit 1
fi

echo "==================================================="
echo " SimpliXio App Store Screenshot Capture"
echo "==================================================="
echo "Temporary XCTest artifacts: $WORK_DIR"
echo "Capture targets: $CAPTURE_TARGETS"

cd "$APP_DIR"
LOCAL_YAML=1 xcodegen generate

SIMULATORS_JSON=""
IPHONE_SIM_ID="${IPHONE_SIM_ID:-}"
IPAD_SIM_ID="${IPAD_SIM_ID:-}"

pick_simulator() {
    local pattern="$1"
    print -r -- "$SIMULATORS_JSON" | jq -r --arg pattern "$pattern" '
        [
          .devices
          | to_entries[]
          | .value[]
          | select(.isAvailable == true)
          | select(.name | test($pattern; "i"))
        ]
        | last
        | .udid // empty
    '
}

if capture_target_enabled iphone || capture_target_enabled ipad; then
    SIMULATORS_JSON="$(xcrun simctl list devices available -j)"

    if capture_target_enabled iphone; then
        default_iphone_id="$(pick_simulator "iPhone.*Pro Max")"
        [[ -n "$default_iphone_id" ]] || default_iphone_id="$(pick_simulator "iPhone")"
        IPHONE_SIM_ID="${IPHONE_SIM_ID:-$default_iphone_id}"
        if [[ -z "$IPHONE_SIM_ID" ]]; then
            echo "No available iPhone simulator. Set IPHONE_SIM_ID to an installed simulator UUID." >&2
            exit 1
        fi
    fi

    if capture_target_enabled ipad; then
        default_ipad_id="$(pick_simulator "iPad Pro 13-inch")"
        [[ -n "$default_ipad_id" ]] || default_ipad_id="$(pick_simulator "iPad")"
        IPAD_SIM_ID="${IPAD_SIM_ID:-$default_ipad_id}"
        if [[ -z "$IPAD_SIM_ID" ]]; then
            echo "No available iPad simulator. Set IPAD_SIM_ID to an installed simulator UUID." >&2
            exit 1
        fi
    fi
fi

extract_named_attachments() {
    local result_bundle="$1"
    local raw_directory="$2"
    local exported_directory="$3"
    local canonical_name=""

    mkdir -p "$raw_directory" "$exported_directory"
    xcrun xcresulttool export attachments \
        --path "$result_bundle" \
        --output-path "$exported_directory"

    while IFS=$'\t' read -r exported_name suggested_name; do
        [[ -n "$exported_name" && -n "$suggested_name" ]] || continue
        canonical_name="$(print -r -- "$suggested_name" | sed -E 's/_[0-9]+_[[:xdigit:]-]+\.png$/.png/')"
        [[ "$canonical_name" == *.png ]] || continue
        cp "$exported_directory/$exported_name" "$raw_directory/$canonical_name"
        echo "Captured $canonical_name"
    done < <(
        jq -r '.[] | .attachments[] | [.exportedFileName, .suggestedHumanReadableName] | @tsv' \
            "$exported_directory/manifest.json"
    )
}

verify_files() {
    local directory="$1"
    shift
    local missing=0

    for name in "$@"; do
        if [[ ! -s "$directory/$name" ]]; then
            echo "Missing screenshot: $directory/$name" >&2
            missing=1
        fi
    done

    (( missing == 0 )) || exit 1
}

clear_png_captures() {
    local directory="$1"
    mkdir -p "$directory"
    find "$directory" -maxdepth 1 -type f -name '*.png' -delete
}

terminate_capture_process() {
    local process_id="${1:-}"
    [[ -n "$process_id" ]] || return 0
    kill "$process_id" 2>/dev/null || true
    wait "$process_id" 2>/dev/null || true
}

prepare_simulator() {
    local simulator_id="$1"
    xcrun simctl boot "$simulator_id" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$simulator_id" -b
    xcrun simctl ui "$simulator_id" appearance light
    xcrun simctl status_bar "$simulator_id" override \
        --time "9:41" \
        --batteryLevel 100 \
        --batteryState charged \
        --cellularBars 4 \
        --wifiBars 3 >/dev/null 2>&1 || true
}

run_ios_capture() {
    local simulator_id="$1"
    local device_label="$2"
    local raw_directory="$3"
    local result_bundle="$WORK_DIR/$device_label.xcresult"
    local exported_directory="$WORK_DIR/$device_label-attachments"

    echo ""
    echo "Capturing $device_label on $simulator_id"
    prepare_simulator "$simulator_id"

    xcodebuild test \
        -project "$PROJECT" \
        -scheme CortexOS-iOS \
        -destination "platform=iOS Simulator,id=$simulator_id" \
        -derivedDataPath "$IOS_DERIVED_DATA" \
        -resultBundlePath "$result_bundle" \
        -quiet \
        ONLY_ACTIVE_ARCH=YES \
        -only-testing:CortexOS-iOS-UITests/ScreenshotTests/testCaptureFocusTab \
        -only-testing:CortexOS-iOS-UITests/ScreenshotTests/testCapturePriorityDetail \
        -only-testing:CortexOS-iOS-UITests/ScreenshotTests/testCaptureCaptureTab \
        -only-testing:CortexOS-iOS-UITests/ScreenshotTests/testCaptureSettings

    extract_named_attachments "$result_bundle" "$raw_directory" "$exported_directory"
    verify_files "$raw_directory" \
        01_focus.png 02_decide.png 03_capture.png 04_settings.png
}

run_mac_capture() {
    local raw_directory="$RESULT_DIR/mac_raw"
    local app_path="$MAC_DERIVED_DATA/Build/Products/Debug/SimpliXio.app"
    local executable_path="$app_path/Contents/MacOS/SimpliXio"
    local section_id=""
    local screenshot_name=""
    local app_pid=""
    local window_id=""
    local window_geometry=""
    local window_id_tool="$WORK_DIR/macos-window-id"

    echo ""
    echo "Capturing macOS workbench"
    xcodebuild build \
        -project "$PROJECT" \
        -scheme CortexOS-macOS \
        -destination "platform=macOS,arch=$(uname -m)" \
        -derivedDataPath "$MAC_DERIVED_DATA" \
        -allowProvisioningUpdates \
        -quiet \
        ONLY_ACTIVE_ARCH=YES

    [[ -x "$executable_path" ]] || {
        echo "Missing built macOS executable: $executable_path" >&2
        exit 1
    }

    swiftc \
        -O \
        -module-cache-path "$WORK_DIR/swift-module-cache" \
        "$ROOT/scripts/macos_window_id.swift" \
        -o "$window_id_tool"

    clear_png_captures "$raw_directory"
    trap 'terminate_capture_process "${app_pid:-}"' EXIT INT TERM

    while IFS=$'\t' read -r section_id screenshot_name; do
        open \
            -F \
            -n \
            --stdout "$WORK_DIR/mac-$section_id.log" \
            --stderr "$WORK_DIR/mac-$section_id.log" \
            "$app_path" \
            --args \
            -UITests \
            -Screenshots \
            -mac-section "$section_id"

        window_geometry=""
        for _ in {1..40}; do
            app_pid="$(
                pgrep -n -f "$executable_path.*-mac-section $section_id" 2>/dev/null || true
            )"
            if [[ -z "$app_pid" ]]; then
                sleep 0.25
                continue
            fi
            if ! kill -0 "$app_pid" 2>/dev/null; then
                echo "SimpliXio exited before rendering $section_id." >&2
                cat "$WORK_DIR/mac-$section_id.log" >&2
                exit 1
            fi

            window_geometry="$(
                osascript -e \
                    "tell application \"System Events\" to tell first process whose unix id is $app_pid to get {position, size} of window 1" \
                    2>/dev/null || true
            )"
            [[ -n "$window_geometry" ]] && break
            sleep 0.25
        done

        if [[ -z "$window_geometry" ]]; then
            terminate_capture_process "$app_pid"
            app_pid=""
            echo "Timed out waiting for the SimpliXio $section_id window." >&2
            exit 1
        fi

        # Demo content is populated asynchronously after launch. Let the selected
        # section settle before capturing its real, visible app window.
        sleep 3
        osascript \
            -e "tell application \"System Events\" to tell first process whose unix id is $app_pid" \
            -e 'perform action "AXRaise" of window 1' \
            -e 'set frontmost to true' \
            -e 'repeat 20 times' \
            -e 'if frontmost then exit repeat' \
            -e 'delay 0.1' \
            -e 'end repeat' \
            -e 'if not frontmost then error "SimpliXio did not become frontmost"' \
            -e 'end tell' \
            >/dev/null

        window_id="$("$window_id_tool" "$app_pid")"
        if [[ -z "$window_id" ]]; then
            terminate_capture_process "$app_pid"
            app_pid=""
            echo "Unable to resolve the SimpliXio $section_id window ID." >&2
            exit 1
        fi

        screencapture \
            -x \
            -o \
            -l "$window_id" \
            "$raw_directory/$screenshot_name"

        terminate_capture_process "$app_pid"
        app_pid=""
        echo "Captured $screenshot_name"
    done <<'MAC_SCREENSHOTS'
focus	01_focus.png
weeklyReview	02_weekly_review.png
decisionReplay	03_decision_replay.png
memory	04_memory.png
decisions	05_decisions.png
settings	06_settings.png
MAC_SCREENSHOTS

    trap - EXIT INT TERM

    verify_files "$raw_directory" \
        01_focus.png 02_weekly_review.png 03_decision_replay.png \
        04_memory.png 05_decisions.png 06_settings.png
}

if capture_target_enabled iphone; then
    clear_png_captures "$RESULT_DIR/iphone_raw"
    run_ios_capture "$IPHONE_SIM_ID" iphone "$RESULT_DIR/iphone_raw"
fi
if capture_target_enabled ipad; then
    clear_png_captures "$RESULT_DIR/ipad_raw"
    run_ios_capture "$IPAD_SIM_ID" ipad "$RESULT_DIR/ipad_raw"
fi
if capture_target_enabled mac; then
    clear_png_captures "$RESULT_DIR/mac_raw"
    run_mac_capture
fi

echo ""
echo "Generating current-version App Store assets"
cd "$ROOT"
if [[ -x "$ROOT/.venv/bin/python" ]]; then
    "$ROOT/.venv/bin/python" "$ROOT/scripts/generate_store_assets.py"
else
    python3 "$ROOT/scripts/generate_store_assets.py"
fi

echo ""
echo "Current iPhone, iPad, and macOS assets are in $APP_DIR/store_assets."
echo "Watch assets remain separate so this command never substitutes iPhone UI for watchOS UI."
