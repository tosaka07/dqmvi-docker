#!/bin/sh
set -eu

SERVER_DIR="${SERVER_DIR:-/data}"
MEMORY="${MEMORY:-6G}"

if [ "${EULA:-FALSE}" != "TRUE" ]; then
    echo "Minecraft EULAに同意する場合は EULA=TRUE を設定してください。" >&2
    exit 1
fi

mkdir -p "$SERVER_DIR"

# 初回起動時だけ、イメージ内のNeoForge一式を永続領域へコピーする。
if [ ! -f "$SERVER_DIR/run.sh" ]; then
    cp -a /opt/server-template/. "$SERVER_DIR/"
fi

mkdir -p "$SERVER_DIR/mods"
cd "$SERVER_DIR"

printf 'eula=true\n' > eula.txt

if [ -n "$MEMORY" ]; then
    if [ -f user_jvm_args.txt ]; then
        sed -i -E '/^[[:space:]]*-Xm[ sx]/d' user_jvm_args.txt
    else
        : > user_jvm_args.txt
    fi

    printf '%s\n' "-Xms${MEMORY}" "-Xmx${MEMORY}" >> user_jvm_args.txt
fi

chmod +x run.sh
exec ./run.sh nogui
