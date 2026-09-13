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
├── backups/       # 自動バックアップの保存先
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

## Windows側でMinecraftクライアントを導入する

この構成で使うバージョンは次のとおりです。

| 項目 | バージョン | 役割 |
| --- | --- | --- |
| Minecraft Java Edition | 26.2 | ゲーム本体のバージョン |
| NeoForge | 26.2.0.6-beta | MinecraftにMODを読み込ませるローダー |
| Javaランタイム | 25 | NeoForgeのインストーラーとクライアントを動かすJava |

Minecraftのバージョン番号と、WindowsにインストールするJavaのバージョン番号は別のものです。
このリポジトリのDockerサーバーはコンテナ内のJava 25を使うため、Windows側のJavaとは別に管理されます。

### Minecraft Launcherをインストールする

[Minecraft公式ダウンロードページ](https://www.minecraft.net/ja-jp/download)からMinecraft Launcherをインストールします。
Minecraft Java Editionを購入済みのMicrosoftアカウントでLauncherにサインインします。
`Minecraft: Java Edition`で`26.2`を選び、一度ゲームを起動します。
タイトル画面が表示されたらゲームを終了します。

### miseのJavaを確認する

PowerShellで実行します。

```powershell
mise use --global java@temurin-25
mise current java
java --version
```

`java`が認識されない場合は、現在のPowerShellセッションでmiseを有効にします。

```powershell
(& mise activate pwsh) | Out-String | Invoke-Expression
java --version
```

毎回有効にするには、PowerShellのプロファイルに次の行を追加します。

```powershell
if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $PROFILE) | Out-Null
    New-Item -ItemType File -Path $PROFILE | Out-Null
}
$activation = '(& mise activate pwsh) | Out-String | Invoke-Expression'
if (-not (Select-String -Path $PROFILE -SimpleMatch $activation -Quiet)) {
    Add-Content -Path $PROFILE -Value $activation
}
. $PROFILE
```

プロファイルを変更せずにJava 25を使う場合は、次のコマンドで確認できます。

```powershell
mise exec -- java --version
```

### NeoForgeクライアントをインストールする

Minecraft Launcherを終了してから、NeoForgeのインストーラーをダウンロードします。

```powershell
$version = "26.2.0.6-beta"
$installer = Join-Path $env:USERPROFILE "Downloads\neoforge-$version-installer.jar"
$url = "https://maven.neoforged.net/releases/net/neoforged/neoforge/$version/neoforge-$version-installer.jar"
Invoke-WebRequest -Uri $url -OutFile $installer
java -jar $installer
```

`java`がまだ認識されない場合は、最後の行を次に置き換えます。

```powershell
mise exec -- java -jar $installer
```

インストーラーで`Install client`を選び、インストールを完了します。
その後Minecraft Launcherを起動し、NeoForgeの`26.2.0.6-beta`プロファイルで一度ゲームを起動します。
タイトル画面が表示されたらゲームを終了します。

### DQM VIのクライアントMODを配置する

通常のMinecraft Launcherを使う場合、クライアントMODの配置先は`%APPDATA%\.minecraft\mods`です。
サーバー側のWSLにある`mods`ディレクトリとは別の場所です。

サーバー側で取得したバージョンをWSLで確認します。

```bash
cat mods/VERSIONS.txt
```

表示された本体と音声パックのバージョンに一致するjarを、[DQM VI Releases](https://github.com/GuriguriGuriguri/DQMVI/releases)からダウンロードします。
ダウンロードしたjarを、Windows側の`%APPDATA%\.minecraft\mods`へコピーします。

PowerShellで配置先を開くには次を実行します。

```powershell
explorer.exe (Join-Path $env:APPDATA ".minecraft\mods")
```

音声パックを使わない場合は、本体のjarだけを配置します。
クライアントをNeoForgeプロファイルで起動し、DQM VIが読み込まれることを確認します。

## Docker DesktopとWSL2を準備する

PowerShellでWSL2を更新します。

```powershell
wsl --update
wsl -l -v
```

Ubuntuがまだない場合は、管理者権限のPowerShellでインストールします。

```powershell
wsl --install -d Ubuntu
```

Docker Desktopの`Settings`で次を設定します。

1. `General`で`Use the WSL 2 based engine`を有効にする
2. `Resources`の`WSL Integration`で使用するUbuntuを有効にする
3. `Apply & Restart`を押す

Ubuntuを起動し、Docker Desktopとの接続を確認します。

```bash
docker version
docker compose version
```

Docker Desktopを使う場合、Ubuntuへ別のDocker Engineをインストールしません。
Minecraft EULAを確認し、同意したうえで使用します。

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

バックアップ用のRCONパスワードを`.env`の`RCON_PASSWORD`へ設定します。
英数字、ハイフン、アンダースコアだけを使用してください。

Windows側で公開するポートを変更する場合は、`.env`の`SERVER_PORT`を変更します。
コンテナ内部のNeoForgeは25565番を使い、Windows側では26789番で公開する設定にしています。

```text
SERVER_PORT=26789
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
127.0.0.1:26789
```

家庭内LANの別端末から接続する場合は、Windowsで`ipconfig`を実行し、WindowsのIPv4アドレスを指定します。

```text
192.168.x.x:26789
```

WSLやDockerコンテナの内部IPアドレスは接続先に使いません。

インターネット経由で接続する場合は、WindowsファイアウォールでTCP 26789を許可し、ルーターのTCP 26789をWindows PCへ転送します。
Docker内部の25565番と、Windows側で公開する26789番は別のポートです。
外部公開には不正アクセスのリスクがあるため、接続元を限定できる環境で運用します。

クライアントには、サーバーと同じMinecraft、NeoForge、DQM VI本体のバージョンを用意します。
音声パックを使う場合は、クライアント側にも`DQMVI-Voice`を配置します。

## サーバーを定期バックアップする

バックアップはComposeの`backup`サービスがサーバー実行中に作成します。
通常の`docker compose up -d`でサーバーと同時に起動し、10分ごとにバックアップします。
バックアップ前にRCON経由でワールドの保存処理を実行します。

バックアップは`backups`に保存し、最新10件を残します。
バックアップサービスが初回に起動してから10分後に最初のバックアップを作成します。

`.env`にRCON用のパスワードを設定します。
英数字、ハイフン、アンダースコアだけを使用してください。

```text
RCON_PASSWORD=十分に長いランダムなパスワード
RCON_PORT=25575
```

設定を反映します。

```bash
mkdir -p backups
docker compose up -d
docker compose ps
docker compose logs -f backup
```

RCONポートはComposeネットワーク内だけで使い、Windows側へ公開しません。
WSLのUbuntuとDocker Desktopが停止している間はバックアップも実行されません。
バックアップ中もMinecraftサーバーは停止しませんが、バックアップ処理中に書き換えられたファイルがある場合はログに警告が出ることがあります。

## バックアップから復元する

復元中は、Minecraftサーバーとバックアップサービスを停止します。
稼働中の`server-data`を置き換えると、ワールドや設定が壊れる可能性があります。

この構成のバックアップは`server-data`の内容を対象にします。
[itzg/mc-backup](https://github.com/itzg/docker-mc-backup)の既定設定ではjarファイルをバックアップから除外するため、`mods/`は別途、バックアップ作成時と同じバージョンのファイルを用意します。

### 復元するバックアップを選ぶ

バックアップ一覧を確認し、復元するファイル名を`BACKUP_FILE`へ設定します。

```bash
ls -lt backups/
BACKUP_FILE="backups/dqmvi-server-YYYY-MM-DD_HH-mm-ss.tgz"
tar -tzf "$BACKUP_FILE" | sed -n '1,20p'
```

一覧に`world/`や`server.properties`が表示されることを確認します。

### server-dataを退避して復元する

現在のデータを別名へ移動してから、バックアップを`server-data`へ展開します。
退避したディレクトリは、復元に失敗した場合や復元前へ戻す場合に使います。

```bash
RESTORE_ID="$(date +%Y%m%d-%H%M%S)"
docker compose stop dqmvi backup
mv server-data "server-data-before-restore-${RESTORE_ID}"
mkdir server-data
tar -xzf "$BACKUP_FILE" -C server-data
```

復元後にサーバーを起動し、ログを確認します。

```bash
docker compose up -d
docker compose ps
docker compose logs -f dqmvi
```

バックアップ作成時と同じMinecraft、NeoForge、DQM VI本体、MODのバージョンを使います。
`update-mods.sh`は最新版を取得するため、過去のバックアップへ戻すときに自動では実行しません。

### 復元前のデータへ戻す

復元後の起動に問題がある場合は、サーバーを停止して退避先と入れ替えます。
`RESTORE_ID`には、復元時に表示された値を指定します。

```bash
RESTORE_ID="復元時のRESTORE_ID"
docker compose stop dqmvi backup
mv server-data "server-data-failed-${RESTORE_ID}"
mv "server-data-before-restore-${RESTORE_ID}" server-data
docker compose up -d
```

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
