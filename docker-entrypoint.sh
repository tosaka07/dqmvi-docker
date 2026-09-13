#!/bin/sh
set -eu

SERVER_DIR="${SERVER_DIR:-/data}"
MEMORY="${MEMORY:-6G}"
RCON_PASSWORD="${RCON_PASSWORD:-}"
RCON_PORT="${RCON_PORT:-25575}"

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

if [ -n "$RCON_PASSWORD" ]; then
    case "$RCON_PORT" in
        ''|*[!0-9]*)
            echo "RCON_PORTは数字で設定してください。" >&2
            exit 1
            ;;
    esac

    case "$RCON_PASSWORD" in
        *[!A-Za-z0-9_-]*)
            echo "RCON_PASSWORDは英数字、ハイフン、アンダースコアだけで設定してください。" >&2
            exit 1
            ;;
    esac

    properties_file="${SERVER_DIR}/server.properties"
    touch "$properties_file"

    set_property() {
        key="$1"
        value="$2"
        if grep -q "^${key}=" "$properties_file"; then
            sed -i "s|^${key}=.*|${key}=${value}|" "$properties_file"
        else
            printf '%s=%s\n' "$key" "$value" >> "$properties_file"
        fi
    }

    set_property enable-rcon true
    set_property rcon.port "$RCON_PORT"
    set_property rcon.password "$RCON_PASSWORD"
fi

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
