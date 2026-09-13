# DQM VI サーバー

WindowsのDocker DesktopとWSL2上のUbuntuで、DQM VIのNeoForgeサーバーを動かす構成です。

DQM VI本体と音声パックは、起動前に`update-mods.sh`でGitHub Releasesから取得します。
ワールド、設定、ログは`server-data`に保存し、MODは`mods`に分離します。

## 構成

```text
.
├── Dockerfile
├── compose.yaml
├── docker-entrypoint.sh
├── update-mods.sh
├── mods/
└── server-data/
```

DockerイメージにはJava 25とNeoForgeサーバーを入れます。
初期設定のNeoForgeは`26.2.0.6-beta`です。
DQM VIのjarはイメージに含めず、次の固定名で`mods`に保存します。

```text
mods/DQMVI.jar
mods/DQMVI-Voice.jar
```

## 前提

- WindowsにDocker Desktopをインストールする
- Docker DesktopでWSL2 based engineを有効にする
- Docker DesktopのWSL Integrationで使用するUbuntuを有効にする
- Minecraft Java EditionとNeoForgeの対応バージョンをクライアント側にも用意する
- Minecraft EULAを確認し、同意したうえで使用する

Ubuntu側でDockerを確認します。

```bash
docker version
docker compose version
```

Docker Desktopを使う場合、Ubuntuへ別のDocker Engineをインストールしません。

## 初回セットアップ

リポジトリをWSL側のLinuxファイルシステムへ配置します。
`/mnt/c`配下よりも、ホームディレクトリ配下のほうがファイルアクセスの負荷を抑えやすくなります。

```bash
cd ~
git clone https://github.com/tosaka07/dqmvi-docker.git
cd dqmvi-docker
```

GitHub APIのJSONを読むために`jq`をインストールします。

```bash
sudo apt-get update
sudo apt-get install -y jq
```

設定を変更する場合は`.env.example`を`.env`へコピーします。

```bash
cp .env.example .env
```

DQM VIの最新版を取得します。

```bash
./update-mods.sh
```

GitHub APIのレート制限に達した場合は、`GITHUB_TOKEN`を指定すると認証済みAPIとして取得できます。

```bash
GITHUB_TOKEN=トークン ./update-mods.sh
```

NeoForgeサーバーをビルドして起動します。

```bash
docker compose build
docker compose up -d
docker compose logs -f dqmvi
```

ログに`Done`が表示され、`docker compose ps`でコンテナが`Up`になれば接続できます。

```bash
docker compose ps
```

## Minecraftから接続する

同じWindows PCから接続する場合は、サーバーアドレスに次を指定します。

```text
127.0.0.1:25565
```

家庭内LANの別端末から接続する場合は、Windowsで`ipconfig`を実行し、WindowsのIPv4アドレスを指定します。

```text
192.168.x.x:25565
```

WSLやDockerコンテナの内部IPアドレスは接続先に使いません。

インターネット経由で接続する場合は、WindowsファイアウォールでTCP 25565を許可し、ルーターのTCP 25565をWindows PCへ転送します。
外部公開には不正アクセスのリスクがあるため、接続元を限定できる環境で運用します。

クライアントには、サーバーと同じMinecraft、NeoForge、DQM VI本体のバージョンを用意します。
音声パックを使う場合は、クライアント側にも`DQMVI-Voice`を配置します。

## MODを更新する

MODを更新するときは、先にサーバーを停止してからワールドをバックアップします。

```bash
docker compose stop
tar -czf "dqmvi-backup-$(date +%F).tar.gz" server-data
./update-mods.sh
docker compose up -d
docker compose logs -f dqmvi
```

`update-mods.sh`は本体と音声パックをそれぞれ最新版として取得し、`mods/DQMVI.jar`と`mods/DQMVI-Voice.jar`を置き換えます。
古いバージョン名のjarが`mods`に残っている場合は、二重ロードを避けるためスクリプトを停止します。

## よく使う操作

```bash
# 起動
docker compose start

# 停止
docker compose stop

# 再起動
docker compose restart

# ログ確認
docker compose logs -f dqmvi

# コンテナを削除して作り直す
docker compose down
docker compose up -d
```

`docker compose down`では、バインドマウントしている`mods`と`server-data`は削除されません。
`docker compose down -v`はこの構成では通常使いません。

## NeoForgeを更新する

NeoForgeのバージョンを変更する場合は、`.env`の`NEOFORGE_VERSION`を変更してイメージを再ビルドします。

```bash
docker compose build --no-cache
docker compose up -d
```

既存の`server-data`にある`run.sh`は初回起動時にだけ作成されます。
そのため、NeoForgeの更新ではワールドのバックアップと公式の移行手順を確認してから適用します。

## トラブルシューティング

### `UnsupportedClassVersionError`が出る

Java、NeoForge、Minecraftの対応バージョンを確認します。

### 同じMODの重複ロードエラーが出る

`mods`に`DQMVI-0.29.67.jar`のような古いバージョン名のjarが残っていないか確認します。
使用するjarは`DQMVI.jar`と`DQMVI-Voice.jar`の2つにそろえます。

### メモリが足りない

`.env`の`MEMORY`を変更してからコンテナを再起動します。

```text
MEMORY=8G
```

### 音声パックでサーバーが起動しない

いったん`mods/DQMVI-Voice.jar`を別の場所へ移し、サーバー側の音声パックなしで起動を確認します。
音声を使うクライアントには音声パックを残します。

## 公式ドキュメント

- [DQM VI 導入方法](https://dqmvi.kj-apps.com/install)
- [DQM VI Releases](https://github.com/GuriguriGuriguri/DQMVI/releases)
- [NeoForge Server](https://docs.neoforged.net/user/docs/server/)
