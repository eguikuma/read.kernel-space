<div align="right">
<img src="https://img.shields.io/badge/AI-ASSISTED_STUDY-3b82f6?style=for-the-badge&labelColor=1e293b&logo=bookstack&logoColor=white" alt="AI Assisted Study" />
</div>

# /sysと/procは何が違うのか

## はじめに

[01-kernel](../01-kernel.md) の「/sys ファイルシステム」で、`/sys` という疑似ファイルシステムがあることを学びました

しかし、すでに `/proc` という疑似ファイルシステムがあるのに、なぜ `/sys` が別に存在するのでしょうか？

<strong>疑似ファイルシステムとは</strong>

`/proc` と `/sys` は「疑似ファイルシステム」と呼ばれます

これらは<strong>ディスク上には存在しません</strong>

カーネルが「ファイルのように見える」インターフェースを動的に生成しています

ファイルを読むと、その瞬間のカーネルの状態が返されます

どちらも「カーネルの情報を見る窓口」のように見えますが、実は<strong>設計思想が異なります</strong>

このドキュメントでは、`/proc` と `/sys` の違いを明確にし、それぞれをいつ使うべきかを説明します

---

## 目次

- [歴史的な経緯](#歴史的な経緯)
- [設計思想の違い](#設計思想の違い)
- [/proc の特徴](#proc-の特徴)
- [/sys の特徴](#sys-の特徴)
- [実用例](#実用例)
- [まとめ](#まとめ)
- [参考資料](#参考資料)

---

## 歴史的な経緯

### /proc の誕生

`/proc` は 1984 年の UNIX System V で導入されました

当初の目的は「プロセス情報をファイルとして見られるようにする」ことでした

`/proc/[pid]/` というディレクトリ構造で、各プロセスの情報にアクセスできます

しかし、時間が経つにつれて、プロセス以外の情報も `/proc` に追加されるようになりました

- `/proc/meminfo`（メモリ情報）
- `/proc/cpuinfo`（CPU 情報）
- `/proc/sys/`（カーネルパラメータ）
- `/proc/net/`（ネットワーク情報）

その結果、`/proc` は「なんでも入れる場所」になってしまいました

### /sys の登場

2002 年、Linux 2.6 で `/sys`（sysfs）が導入されました

導入の理由は、`/proc` が以下の問題を抱えていたからです

- <strong>構造が不規則</strong>
  - ファイルごとにフォーマットが異なる
  - 解析するプログラムを書くのが大変
- <strong>情報が混在</strong>
  - プロセス情報、デバイス情報、カーネル設定がすべて同じ場所にある
- <strong>デバイスツリーがない</strong>
  - デバイス間の親子関係や接続関係が分からない

`/sys` は、これらの問題を解決するために設計されました

<strong>/proc の具体的な問題例</strong>

/proc のファイルフォーマットは統一されていません

| ファイル      | フォーマット                           |
| ------------- | -------------------------------------- |
| /proc/cpuinfo | key: value 形式（ただし改行で区切り）  |
| /proc/meminfo | key: value 単位 形式                   |
| /proc/stat    | 空白区切り、最初の単語がカテゴリ       |
| /proc/net/dev | ヘッダー行 + コロン区切り + 空白区切り |

これらを解析するには、ファイルごとに異なるパーサーを書く必要がありました

さらに、カーネルのバージョンアップでフォーマットが変わることもあり、スクリプトが壊れる原因になりました

/sys は「1 ファイル 1 属性」「数値は単位なし」という一貫したルールで、この問題を解消しました

---

## 設計思想の違い

### 核心的な違い

| 観点       | /proc                              | /sys                     |
| ---------- | ---------------------------------- | ------------------------ |
| 主な目的   | プロセス情報 + カーネル統計        | デバイスとドライバの情報 |
| 情報の構造 | ファイルごとにフォーマットが異なる | 1ファイル1属性の原則     |
| 階層構造   | フラットな配置が多い               | デバイスツリーを反映     |
| 歴史       | 1984 年（UNIX 由来）               | 2002 年（Linux 2.6）     |

### 「1ファイル1属性」の原則

`/sys` の最大の特徴は<strong>「1ファイル1属性」</strong>の原則です

`/proc/meminfo` を見てみましょう

```bash
cat /proc/meminfo
```

出力例

```
MemTotal:       16384000 kB
MemFree:         8192000 kB
MemAvailable:   12288000 kB
Buffers:          512000 kB
Cached:          2048000 kB
...
```

複数の情報が1つのファイルに含まれています

一方、`/sys` では、各情報が別々のファイルになっています

```bash
cat /sys/block/sda/size      # ディスクサイズだけ
cat /sys/block/sda/removable # リムーバブルかどうかだけ
```

各ファイルは1つの値だけを返すので、プログラムで解析しやすくなっています

<strong>なぜ「1ファイル1属性」なのか</strong>

/proc/meminfo を解析するには、行を分割し、ラベルと値を分離し、単位を処理する必要があります

```python
# /proc/meminfo の解析（面倒）
for line in open('/proc/meminfo'):
    if line.startswith('MemTotal:'):
        value = line.split()[1]  # "16384000"
        unit = line.split()[2]   # "kB"
```

/sys は 1 ファイル 1 値なので、解析が簡単です

```python
# /sys の読み取り（簡単）
size = int(open('/sys/block/sda/size').read())
```

<strong>シェルスクリプトでの利点</strong>

```bash
# /proc の場合（grep + awk が必要）
mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')

# /sys の場合（cat だけ）
disk_size=$(cat /sys/block/sda/size)
```

この設計により、プログラムやスクリプトからの自動処理が格段に楽になります

---

## /proc の特徴

### 得意なこと

<strong>1. プロセス情報</strong>

`/proc` の本来の目的です

```bash
# プロセス一覧
ls /proc | grep '^[0-9]'

# 特定プロセスの情報
cat /proc/self/status
```

<strong>2. システム全体の統計情報</strong>

```bash
cat /proc/loadavg    # ロードアベレージ
cat /proc/uptime     # システム稼働時間
cat /proc/stat       # CPU 統計
```

<strong>3. カーネルパラメータの読み書き</strong>

```bash
# 現在の設定を確認
cat /proc/sys/net/ipv4/ip_forward

# 設定を変更（root 権限が必要）
echo 1 > /proc/sys/net/ipv4/ip_forward
```

### /proc の主要なパス

| パス          | 説明                         |
| ------------- | ---------------------------- |
| /proc/[pid]/  | プロセスごとの情報           |
| /proc/self/   | 自分自身のプロセス           |
| /proc/meminfo | メモリ使用状況               |
| /proc/cpuinfo | CPU 情報                     |
| /proc/loadavg | ロードアベレージ             |
| /proc/sys/    | カーネルパラメータ（sysctl） |
| /proc/net/    | ネットワーク統計             |

---

## /sys の特徴

### 得意なこと

<strong>1. デバイス情報</strong>

接続されているハードウェアの情報を取得できます

```bash
# ブロックデバイス（ディスク）の一覧
ls /sys/block/

# ネットワークインターフェースの一覧
ls /sys/class/net/
```

<strong>2. デバイスの階層構造</strong>

`/sys/devices/` はデバイスの物理的な接続関係を反映しています

```bash
# PCI デバイスの階層
ls /sys/devices/pci0000:00/
```

<strong>3. デバイスの属性操作</strong>

```bash
# ディスプレイの明るさを確認
cat /sys/class/backlight/*/brightness

# 明るさを変更（root 権限が必要）
echo 50 > /sys/class/backlight/intel_backlight/brightness
```

### /sys の主要なディレクトリ

| パス          | 説明                                   |
| ------------- | -------------------------------------- |
| /sys/block/   | ブロックデバイス（ディスク、SSD など） |
| /sys/class/   | デバイスをクラスごとに分類             |
| /sys/devices/ | すべてのデバイスの階層構造             |
| /sys/fs/      | ファイルシステム関連                   |
| /sys/kernel/  | カーネル全体の設定                     |
| /sys/module/  | ロード済みカーネルモジュール           |
| /sys/bus/     | バス（PCI、USB など）ごとのデバイス    |

### /sys/class vs /sys/devices

この 2 つは、<strong>同じデバイスへの異なるビュー</strong>を提供します

<strong>/sys/devices - 物理的な階層構造</strong>

/sys/devices/ は、デバイスの<strong>物理的な接続関係</strong>を反映しています

```
/sys/devices/pci0000:00/0000:00:14.0/usb1/1-2/1-2:1.0/host0/target0:0:0/0:0:0:0/block/sda
                │          │          │    │
                │          │          │    └── USB ポート 2 に接続
                │          │          └── USB コントローラ 1
                │          └── PCI デバイス 00:14.0（USB ホストコントローラ）
                └── PCI バス 0000:00
```

このパスを見れば「どの USB ポートに挿さっているか」が分かります

<strong>/sys/class - 論理的な分類</strong>

/sys/class/ は、デバイスを<strong>機能</strong>でグループ化しています

```
/sys/class/block/sda  → ブロックデバイスとしてアクセス
/sys/class/net/eth0   → ネットワークデバイスとしてアクセス
```

実際には、これらは /sys/devices/ へのシンボリックリンクです

```bash
ls -l /sys/class/block/sda
# lrwxrwxrwx 1 root root 0 ... /sys/class/block/sda -> ../../devices/pci0000:00/.../block/sda
```

<strong>どちらを使うべきか</strong>

| ユースケース                             | 使用するパス  |
| ---------------------------------------- | ------------- |
| 特定の種類のデバイスを列挙したい         | /sys/class/   |
| デバイスの物理的な接続関係を知りたい     | /sys/devices/ |
| 安定したパスでデバイスにアクセスしたい   | /sys/class/   |
| ホットプラグイベントの発生元を特定したい | /sys/devices/ |

通常のスクリプトでは /sys/class/ を使うのが簡単で安定しています

/sys/devices/ のパスは物理構成に依存するため、同じデバイスでも接続ポートが変わるとパスが変わります

### /sys/class の例

`/sys/class/` は、デバイスを種類ごとにグループ化しています

| パス                  | 説明                               |
| --------------------- | ---------------------------------- |
| /sys/class/net/       | ネットワークインターフェース       |
| /sys/class/block/     | ブロックデバイス                   |
| /sys/class/input/     | 入力デバイス（キーボード、マウス） |
| /sys/class/tty/       | ターミナルデバイス                 |
| /sys/class/backlight/ | バックライト制御                   |

### /sys/fs/cgroup

cgroup（コントロールグループ）の設定は `/sys/fs/cgroup/` にあります

```bash
# cgroup v2 のコントローラ一覧
cat /sys/fs/cgroup/cgroup.controllers
```

cgroup の詳細は [07-cgroup](../07-cgroup.md) を参照してください

---

## 実用例

### 例1：ディスク情報の取得

<strong>/proc を使う場合</strong>

```bash
cat /proc/partitions
```

出力例

```
major minor  #blocks  name
   8        0  500107608 sda
   8        1     524288 sda1
   8        2  499582631 sda2
```

複数の情報が1つのファイルに含まれています

<strong>/sys を使う場合</strong>

```bash
# ディスクサイズ（512バイト単位のセクタ数）
cat /sys/block/sda/size

# パーティション一覧
ls /sys/block/sda/sda*/

# 特定パーティションのサイズ
cat /sys/block/sda/sda1/size
```

各ファイルが1つの属性だけを返します

### 例2：ネットワークインターフェース情報

<strong>/sys を使う場合</strong>

```bash
# インターフェース一覧
ls /sys/class/net/

# MAC アドレス
cat /sys/class/net/eth0/address

# リンク状態
cat /sys/class/net/eth0/operstate
```

### 例3：CPU 情報

<strong>/proc を使う場合</strong>

```bash
# CPU 詳細情報
cat /proc/cpuinfo

# オンラインの CPU 数
cat /proc/stat | grep '^cpu' | wc -l
```

<strong>/sys を使う場合</strong>

```bash
# CPU トポロジー
ls /sys/devices/system/cpu/

# CPU0 がオンラインかどうか
cat /sys/devices/system/cpu/cpu0/online
```

---

## まとめ

<strong>/proc と /sys の使い分け</strong>

| 知りたい情報         | 使うべき場所                 |
| -------------------- | ---------------------------- |
| プロセスの情報       | /proc/[pid]/                 |
| メモリ、CPU の統計   | /proc/meminfo、/proc/cpuinfo |
| カーネルパラメータ   | /proc/sys/                   |
| デバイスの一覧と属性 | /sys/class/、/sys/block/     |
| デバイスの階層構造   | /sys/devices/                |
| cgroup の設定        | /sys/fs/cgroup/              |

<strong>覚えておくこと</strong>

| ポイント                | 説明                                                   |
| ----------------------- | ------------------------------------------------------ |
| /proc は歴史が長い      | プロセス情報が本来の目的、後から様々な情報が追加された |
| /sys は構造化されている | 「1ファイル1属性」の原則で、プログラムから扱いやすい   |
| 両者は補完関係          | どちらかが完全に置き換わるわけではない                 |

---

## 参考資料

<strong>Linux マニュアル</strong>

- [proc(5) - Linux manual page](https://man7.org/linux/man-pages/man5/proc.5.html)
  - /proc ファイルシステムの詳細
- [sysfs(5) - Linux manual page](https://man7.org/linux/man-pages/man5/sysfs.5.html)
  - /sys ファイルシステムの詳細

<strong>Linux カーネルドキュメント</strong>

- [The sysfs Filesystem - kernel.org](https://www.kernel.org/doc/html/latest/filesystems/sysfs.html)
  - sysfs の公式ドキュメント
- [Rules on how to access information in sysfs](https://www.kernel.org/doc/html/latest/admin-guide/sysfs-rules.html)
  - sysfs へのアクセスルール

<strong>本編との関連</strong>

- [01-kernel](../01-kernel.md)
  - /proc と /sys の概要
- [07-cgroup](../07-cgroup.md)
  - /sys/fs/cgroup の詳細
