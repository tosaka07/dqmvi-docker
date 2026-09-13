#!/usr/bin/env bash
set -euo pipefail

REPO="GuriguriGuriguri/DQMVI"
API="https://api.github.com/repos/${REPO}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
MODS_DIR="${1:-${SCRIPT_DIR}/mods}"
TMP_DIR="$(mktemp -d)"
STAGED_CORE="${MODS_DIR}/.DQMVI.jar.tmp"
STAGED_VOICE="${MODS_DIR}/.DQMVI-Voice.jar.tmp"
STAGED_VERSIONS="${MODS_DIR}/.VERSIONS.txt.tmp"

cleanup() {
    rm -rf "$TMP_DIR"
    rm -f -- "$STAGED_CORE" "$STAGED_VOICE" "$STAGED_VERSIONS"
}
trap cleanup EXIT

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "必要なコマンドが見つかりません: $1" >&2
        exit 1
    fi
}

require_command curl
require_command jq
require_command sort
require_command install

mkdir -p "$MODS_DIR"

# 固定名のjarと古いバージョン名のjarを同時に置くと、同じMODが二重に読み込まれる。
legacy_jars="$(
    find "$MODS_DIR" -maxdepth 1 -type f \
        \( -name 'DQMVI-*.jar' -o -name 'DQMVI-Voice-*.jar' \) \
        ! -name 'DQMVI.jar' \
        ! -name 'DQMVI-Voice.jar' \
        -print
)"
if [ -n "$legacy_jars" ]; then
    echo "古いファイル名のDQM VI jarが残っています。重複ロードを避けるため移動または削除してください。" >&2
    printf '%s\n' "$legacy_jars" >&2
    exit 1
fi

github_get() {
    local url="$1"
    local headers=(
        -H "Accept: application/vnd.github+json"
        -H "X-GitHub-Api-Version: 2022-11-28"
    )

    if [ -n "${GITHUB_TOKEN:-}" ]; then
        headers+=( -H "Authorization: Bearer ${GITHUB_TOKEN}" )
    fi

    curl -fsSL --retry 5 "${headers[@]}" "$url"
}

echo "DQM VI本体の最新版を確認しています..."
if ! core_release="$(github_get "${API}/releases/tags/DQMVI")"; then
    echo "DQM VI本体のリリース情報を取得できませんでした。" >&2
    exit 1
fi

CORE_URL="$(
    printf '%s' "$core_release" |
        jq -r '.assets[]? | select(.name | test("^DQMVI-[0-9.]+\\.jar$")) | .browser_download_url' |
        LC_ALL=C sort -V |
        tail -n 1
)"

echo "音声パックの最新版を確認しています..."
if ! voice_releases="$(github_get "${API}/releases?per_page=100")"; then
    echo "音声パックのリリース情報を取得できませんでした。" >&2
    exit 1
fi

VOICE_URL="$(
    printf '%s' "$voice_releases" |
        jq -r '.[]? | select(.tag_name | test("^voice-v[0-9]")) | .assets[]? | select(.name | test("^DQMVI-Voice-[0-9.]+\\.jar$")) | .browser_download_url' |
        LC_ALL=C sort -V |
        tail -n 1
)"

if [ -z "$CORE_URL" ]; then
    echo "DQM VI本体のjarが見つかりません。" >&2
    exit 1
fi

if [ -z "$VOICE_URL" ]; then
    echo "音声パックのjarが見つかりません。" >&2
    exit 1
fi

download_mod() {
    local url="$1"
    local destination="$2"
    local download_path="${TMP_DIR}/${destination}"

    echo "Download: $(basename -- "$url")"
    curl -fL --retry 5 -o "$download_path" "$url"
}

stage_mod() {
    local destination="$1"
    local staged_path="${MODS_DIR}/.${destination}.tmp"

    install -m 0644 "${TMP_DIR}/${destination}" "$staged_path"
}

download_mod "$CORE_URL" "DQMVI.jar"
download_mod "$VOICE_URL" "DQMVI-Voice.jar"
stage_mod "DQMVI.jar"
stage_mod "DQMVI-Voice.jar"
mv -f -- "$STAGED_CORE" "${MODS_DIR}/DQMVI.jar"
mv -f -- "$STAGED_VOICE" "${MODS_DIR}/DQMVI-Voice.jar"

version_file="${TMP_DIR}/VERSIONS.txt"
{
    printf 'core=%s\n' "$(basename -- "$CORE_URL")"
    printf 'voice=%s\n' "$(basename -- "$VOICE_URL")"
    printf 'updated_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$version_file"
install -m 0644 "$version_file" "$STAGED_VERSIONS"
mv -f -- "$STAGED_VERSIONS" "${MODS_DIR}/VERSIONS.txt"

echo
echo "更新完了"
cat "${MODS_DIR}/VERSIONS.txt"
