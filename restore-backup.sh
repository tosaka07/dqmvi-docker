#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${BACKUP_DIR:-${SCRIPT_DIR}/backups}"
SERVER_DIR="${SERVER_DIR:-${SCRIPT_DIR}/server-data}"
RESTORE_ID="$(date +%Y%m%d-%H%M%S)"
PREVIOUS_SERVER_DIR="${SERVER_DIR}-before-restore-${RESTORE_ID}"
FAILED_SERVER_DIR="${SERVER_DIR}-failed-${RESTORE_ID}"

cd "$SCRIPT_DIR"

if ! command -v docker >/dev/null 2>&1; then
    echo "dockerコマンドが見つかりません。Docker Desktopを起動してください。" >&2
    exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
    echo "tarコマンドが見つかりません。" >&2
    exit 1
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "バックアップディレクトリが見つかりません: $BACKUP_DIR" >&2
    exit 1
fi

mapfile -t BACKUP_FILES < <(
    find "$BACKUP_DIR" -maxdepth 1 -type f \
        \( -name '*.tgz' -o -name '*.tar.gz' -o -name '*.tar' \) \
        -printf '%T@ %p\n' |
        sort -nr |
        sed 's/^[^ ]* //'
)

if (( ${#BACKUP_FILES[@]} == 0 )); then
    echo "復元できるバックアップがありません: $BACKUP_DIR" >&2
    exit 1
fi

echo "復元するバックアップを選択してください。"
for index in "${!BACKUP_FILES[@]}"; do
    printf '%2d) %s\n' "$((index + 1))" "${BACKUP_FILES[index]##*/}"
done

while true; do
    read -r -p "番号 (1-${#BACKUP_FILES[@]}): " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] &&
        (( selection >= 1 && selection <= ${#BACKUP_FILES[@]} )); then
        break
    fi
    echo "一覧にある番号を入力してください。" >&2
done

BACKUP_FILE="${BACKUP_FILES[$((selection - 1))]}"

echo
echo "選択: ${BACKUP_FILE##*/}"
echo "アーカイブの内容を確認します。"
if ! tar -tf "$BACKUP_FILE" >/dev/null; then
    echo "バックアップの読み取りに失敗しました: $BACKUP_FILE" >&2
    exit 1
fi
tar -tf "$BACKUP_FILE" | sed -n '1,20p'

if [[ ! -d "$SERVER_DIR" ]]; then
    echo "現在のserver-dataが見つかりません: $SERVER_DIR" >&2
    exit 1
fi

if [[ -e "$PREVIOUS_SERVER_DIR" || -e "$FAILED_SERVER_DIR" ]]; then
    echo "復元用の退避先がすでに存在します。日時が重複していないか確認してください。" >&2
    exit 1
fi

read -r -p "現在のserver-dataを退避して復元しますか？ (yes/no): " confirmation
if [[ "$confirmation" != "yes" ]]; then
    echo "復元を中止しました。"
    exit 0
fi

rollback() {
    local status="$1"

    trap - ERR
    set +e

    if [[ -e "$SERVER_DIR" ]]; then
        mv -- "$SERVER_DIR" "$FAILED_SERVER_DIR"
    fi
    if [[ -e "$PREVIOUS_SERVER_DIR" ]]; then
        mv -- "$PREVIOUS_SERVER_DIR" "$SERVER_DIR"
    fi

    echo "復元に失敗したため、現在のデータを元に戻しました。" >&2
    echo "展開途中のデータ: $FAILED_SERVER_DIR" >&2
    exit "$status"
}

echo "Minecraftサーバーとバックアップサービスを停止します。"
docker compose stop dqmvi backup

echo "現在のserver-dataを退避します: $PREVIOUS_SERVER_DIR"
mv -- "$SERVER_DIR" "$PREVIOUS_SERVER_DIR"
trap 'rollback "$?"' ERR
mkdir -- "$SERVER_DIR"

echo "バックアップを展開します。"
if ! tar -xf "$BACKUP_FILE" -C "$SERVER_DIR"; then
    rollback 1
fi

if [[ ! -f "$SERVER_DIR/run.sh" ]]; then
    echo "server-data/run.shが見つかりません。バックアップの形式を確認してください。" >&2
    rollback 1
fi

trap - ERR

echo "復元が完了しました。退避先は $PREVIOUS_SERVER_DIR です。"
echo "サーバーとバックアップサービスを起動します。"
if ! docker compose up -d dqmvi backup; then
    echo "起動に失敗しました。退避先を削除せず、ログを確認してください。" >&2
    exit 1
fi

docker compose ps
echo "必要に応じて次のコマンドでサーバーログを確認してください。"
echo "docker compose logs -f dqmvi"
