#!/usr/bin/env bash
# ZMK ローカルビルド検査スクリプト
# 使い方: ./scripts/build-local.sh [board] [shield] [snippet] [artifact-name]
# 例:     ./scripts/build-local.sh seeeduino_xiao_ble roBa_R zmk-usb-logging roBa_R-debug
#
# Docker が必要: docker pull zmkfirmware/zmk-dev-arm:3.5

set -euo pipefail

BOARD="${1:-seeeduino_xiao_ble}"
SHIELD="${2:-roBa_R}"
SNIPPET="${3:-}"
ARTIFACT="${4:-${SHIELD}}"
ZMK_IMAGE="zmkfirmware/zmk-dev-arm:3.5"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="/tmp/zmk-build-${ARTIFACT}"

echo "==> ビルド設定"
echo "    board   : ${BOARD}"
echo "    shield  : ${SHIELD}"
echo "    snippet : ${SNIPPET:-（なし）}"
echo "    出力先  : ${BUILD_DIR}"
echo ""

# --- 1. YAML 構文チェック ---
echo "==> build.yaml 構文チェック"
python3 - <<'PYEOF'
import yaml, sys
with open("build.yaml") as f:
    data = yaml.safe_load(f)
entries = data.get("include", [])
valid_snippets = {"zmk-usb-logging", "studio-rpc-usb-uart", "nrf52833-nosd", "nrf52840-nosd"}
errors = []
for e in entries:
    snippet = e.get("snippet", "")
    cmake  = e.get("cmake-args", "")
    # cmake-args で直接 USB_LOGGING を渡すと overlay が欠ける
    if "ZMK_USB_LOGGING" in cmake and snippet != "zmk-usb-logging":
        errors.append(
            f"  shield={e.get('shield')}: cmake-args に CONFIG_ZMK_USB_LOGGING=y を直接指定しています。\n"
            "  overlay が欠けるためビルドが失敗します。snippet: zmk-usb-logging を使ってください。"
        )
    if snippet and snippet not in valid_snippets:
        errors.append(f"  shield={e.get('shield')}: 未知のスニペット '{snippet}'")
if errors:
    print("エラー:")
    for e in errors: print(e)
    sys.exit(1)
print("  OK")
PYEOF

# --- 2. Docker チェック ---
echo "==> Docker 確認"
if ! command -v docker &>/dev/null; then
    echo "  Docker が見つかりません。YAML チェックのみ完了しました。"
    echo "  フルビルドには Docker をインストールしてください。"
    exit 0
fi

if ! docker image inspect "${ZMK_IMAGE}" &>/dev/null; then
    echo "  ZMK イメージを取得中: ${ZMK_IMAGE}"
    docker pull "${ZMK_IMAGE}"
fi

# --- 3. Docker でフルビルド ---
echo "==> ZMK ビルド開始 (Docker)"

SNIPPET_ARG=""
if [[ -n "${SNIPPET}" ]]; then
    SNIPPET_ARG="-DSNIPPET=${SNIPPET}"
fi

CMAKE_EXTRA="${5:-}"

docker run --rm \
    -v "${REPO_ROOT}":/zmk-config:ro \
    -v "${BUILD_DIR}":/build \
    "${ZMK_IMAGE}" \
    bash -c "
        set -e
        cd /zmk-config
        west init -l config
        west update
        west build \
            -b '${BOARD}' \
            -d /build \
            -- \
            -DSHIELD='${SHIELD}' \
            -DZMK_CONFIG='/zmk-config/config' \
            ${SNIPPET_ARG} \
            ${CMAKE_EXTRA}
    "

echo ""
echo "==> ビルド成功: ${BUILD_DIR}/zephyr/zmk.uf2"
