<div align="right">
<img src="https://img.shields.io/badge/AI-ASSISTED_STUDY-3b82f6?style=for-the-badge&labelColor=1e293b&logo=bookstack&logoColor=white" alt="AI Assisted Study" />
</div>

# 06-namespace：プロセスの隔離

## はじめに

[05-scheduler](./05-scheduler.md) では、カーネルがプロセスに CPU 時間を配分する仕組みを学びました

- スケジューリングポリシーの種類（SCHED_OTHER、SCHED_FIFO など）
- nice 値による優先度調整
- CFS（Completely Fair Scheduler）による公平な CPU 配分
- リアルタイムスケジューリングの概念

しかし、1 つ疑問が残ります

複数のプロセスが「別々のシステム」として動作するには、どうすればよいのでしょうか？

コンテナ技術では、プロセスは自分が独立したシステムで動いているかのように振る舞います

このページでは、その仕組みを学びます

<strong>namespace</strong>（名前空間）は、プロセスを隔離して、それぞれに独立したシステムリソースのビューを提供するカーネル機能です

namespace を使うと、プロセスは自分専用のプロセス ID 空間、ファイルシステム、ネットワークスタックを持っているかのように動作できます

### 日常の例え

namespace を「シェアオフィスビル」に例えてみましょう

<strong>ビル全体（ホストシステム）</strong>には、複数の会社（プロセス群）が入居しています

<strong>各フロア（namespace）</strong>は、入居する会社に独立した空間を提供します

- <strong>PID namespace</strong>は「社員番号体系」です
  - 各会社は自社の社員番号（PID）を 1 番から付けられます
  - A 社の社員 1 番と B 社の社員 1 番は別人です
  - ただし、ビル管理会社（ホスト OS）からは全フロアの社員が見えます
- <strong>Mount namespace</strong>は「ファイルキャビネット」です
  - 各会社は自社専用の書類棚を持ちます
  - 他社の書類は見えません
- <strong>Network namespace</strong>は「電話回線」です
  - 各会社は独自の電話番号（IP アドレス：ネットワーク上の住所にあたる番号）を持ちます
  - 各会社は独自の内線システム（ネットワークインターフェース：eth0 や lo のような通信の出入り口）を持ちます
- <strong>UTS namespace</strong>は「会社名の表札」です
  - 各会社は独自の社名（ホスト名）を掲げられます
- <strong>IPC namespace</strong>は「社内メール便」です（IPC は Inter-Process Communication、つまりプロセス間通信の略）
  - 各会社は独自の社内連絡手段を持ちます
  - 他社の社内メールは届きません
- <strong>User namespace</strong>は「役職体系」です
  - 各会社は独自の役職（UID/GID）を定義できます
  - A 社の社長（root）はビル全体の管理者ではありません

このように、namespace は「同じビルにいながら、別々の会社として独立して運営できる仕組み」を提供します

### このページで学ぶこと

このページでは、以下の概念を学びます

- <strong>namespace とは何か</strong>
  - プロセス隔離の基本概念
- <strong>Linux の namespace</strong>
  - PID、Mount、Network、UTS、IPC、User、Cgroup
- <strong>PID namespace</strong>
  - プロセス ID の隔離と階層構造
- <strong>Mount namespace</strong>
  - ファイルシステムのマウントポイント隔離
- <strong>Network namespace</strong>
  - ネットワークスタックの隔離
- <strong>UTS namespace</strong>
  - ホスト名とドメイン名の隔離
- <strong>IPC namespace</strong>
  - プロセス間通信リソースの隔離
- <strong>User namespace</strong>
  - ユーザー ID とグループ ID のマッピング
- <strong>Cgroup namespace</strong>
  - cgroup 階層ビューの隔離
- <strong>/proc での namespace 観察</strong>
  - /proc/[pid]/ns/ ディレクトリの活用
- <strong>namespace の操作</strong>
  - unshare コマンドと clone システムコール
- <strong>コンテナ技術との関係</strong>
  - Docker/Kubernetes での活用

---

## 目次

1. [namespace とは何か](#namespace-とは何か)
2. [Linux の namespace](#linux-の-namespace)
3. [PID namespace](#pid-namespace)
4. [Mount namespace](#mount-namespace)
5. [Network namespace](#network-namespace)
6. [UTS namespace](#uts-namespace)
7. [IPC namespace](#ipc-namespace)
8. [User namespace](#user-namespace)
9. [Cgroup namespace](#cgroup-namespace)
10. [/proc での namespace 観察](#proc-での-namespace-観察)
11. [namespace の操作](#namespace-の操作)
12. [コンテナ技術との関係](#コンテナ技術との関係)
13. [用語集](#用語集)
14. [参考資料](#参考資料)
15. [次のステップ](#次のステップ)

---

## namespace とは何か

### 隔離の必要性

複数のアプリケーションを 1 台のサーバーで動かすとき、問題が発生することがあります

- アプリケーション A が使用するポート番号を、アプリケーション B も使いたい
- アプリケーション A の設定ファイルと、アプリケーション B の設定ファイルが衝突する
- アプリケーション A がシステム全体に影響を与えてしまう

これらの問題を解決するために、<strong>隔離</strong>（isolation）が必要です

### namespace の役割

<strong>namespace</strong>は、カーネルリソースを分割して、プロセスグループごとに独立したビューを提供します

Linux の公式マニュアルには、こう書かれています

> A namespace wraps a global system resource in an abstraction that makes it appear to the processes within the namespace that they have their own isolated instance of the global resource.

> namespace は、グローバルなシステムリソースを抽象化でラップし、namespace 内のプロセスにはグローバルリソースの独立したインスタンスを持っているように見せます

### namespace の特徴

namespace には以下の特徴があります

- <strong>軽量</strong>：仮想マシンと異なり、カーネルを共有するためオーバーヘッドが小さい
- <strong>階層構造</strong>：namespace は親子関係を持てる（特に PID namespace）
- <strong>柔軟</strong>：必要な種類の namespace だけを作成できる
- <strong>カーネル機能</strong>：ユーザー空間のプログラムではなく、カーネルが直接提供する

### namespace vs 仮想マシン

| 特性         | namespace（コンテナ）                                                  | 仮想マシン                  |
| ------------ | ---------------------------------------------------------------------- | --------------------------- |
| カーネル     | ホストと共有                                                           | ゲスト OS が独自に持つ      |
| 起動時間     | ミリ秒〜秒                                                             | 秒〜分                      |
| メモリ効率   | 高い（カーネル共有）                                                   | 低い（OS ごとにメモリ必要） |
| 隔離レベル   | プロセスレベル                                                         | ハードウェアレベル          |
| セキュリティ | カーネルを共有するためリスクあり（カーネルの脆弱性が全コンテナに影響） | 強い隔離                    |

namespace は「軽量な隔離」を提供しますが、カーネルを共有するため、仮想マシンほどの強い隔離は提供しません

---

## Linux の namespace

### namespace の種類

Linux には 8 種類の namespace があります

| namespace | フラグ          | 隔離対象                             | 導入バージョン |
| --------- | --------------- | ------------------------------------ | -------------- |
| Mount     | CLONE_NEWNS     | ファイルシステムのマウントポイント   | Linux 2.4.19   |
| UTS       | CLONE_NEWUTS    | ホスト名とドメイン名                 | Linux 2.6.19   |
| IPC       | CLONE_NEWIPC    | System V IPC、POSIX メッセージキュー | Linux 2.6.19   |
| PID       | CLONE_NEWPID    | プロセス ID                          | Linux 2.6.24   |
| Network   | CLONE_NEWNET    | ネットワークデバイス、スタック等     | Linux 2.6.29   |
| User      | CLONE_NEWUSER   | ユーザー ID とグループ ID            | Linux 3.8      |
| Cgroup    | CLONE_NEWCGROUP | cgroup ルートディレクトリ            | Linux 4.6      |
| Time      | CLONE_NEWTIME   | ブート時刻とモノトニック時刻         | Linux 5.6      |

表中の「System V IPC」と「POSIX メッセージキュー」については、IPC namespace のセクションで詳しく説明します

Time namespace は比較的新しいため、このページでは主に 7 種類を扱います

### namespace の識別

各 namespace は<strong>inode 番号</strong>で識別されます

inode 番号とは、Linux がファイルやリソースを一意に識別するために使う番号です

namespace も内部的にはファイルのように扱われるため、この番号で区別できます

同じ inode 番号を持つプロセスは、同じ namespace に属しています

```bash
ls -la /proc/self/ns/
```

出力例：

```
lrwxrwxrwx 1 user user 0 Jan 31 12:00 cgroup -> 'cgroup:[4026531835]'
lrwxrwxrwx 1 user user 0 Jan 31 12:00 ipc -> 'ipc:[4026531839]'
lrwxrwxrwx 1 user user 0 Jan 31 12:00 mnt -> 'mnt:[4026531840]'
lrwxrwxrwx 1 user user 0 Jan 31 12:00 net -> 'net:[4026531992]'
lrwxrwxrwx 1 user user 0 Jan 31 12:00 pid -> 'pid:[4026531836]'
lrwxrwxrwx 1 user user 0 Jan 31 12:00 user -> 'user:[4026531837]'
lrwxrwxrwx 1 user user 0 Jan 31 12:00 uts -> 'uts:[4026531838]'
```

`[4026531836]` のような数値が namespace の inode 番号です

---

## PID namespace

### PID namespace とは

<strong>PID namespace</strong>は、プロセス ID（PID）を隔離します

異なる PID namespace に属するプロセスは、同じ PID を持つことができます

Linux の公式マニュアルには、こう書かれています

> PID namespaces isolate the process ID number space, meaning that processes in different PID namespaces can have the same PID.

> PID namespace はプロセス ID の番号空間を隔離します
>
> これは、異なる PID namespace のプロセスが同じ PID を持てることを意味します

### PID namespace の階層構造

PID namespace は階層構造を持ちます

```
初期 PID namespace（ホスト）
├── PID 1（init/systemd）
├── PID 1234（bash）
│   └── 子 PID namespace
│       ├── PID 1（コンテナ内の init）
│       └── PID 2（コンテナ内のアプリ）
```

<strong>親 namespace</strong>からは子 namespace のプロセスが見えます

<strong>子 namespace</strong>からは親 namespace のプロセスは見えません

なお、PID namespace のネスト深度には制限があり、<strong>最大 32 階層</strong>までです（Linux 3.7 以降）

<strong>なぜ 32 階層なのか</strong>

この制限は、カーネル内部のデータ構造に起因します

PID namespace の階層関係を追跡するために、カーネルは各プロセスに対して「各階層での PID」を配列で保持しています

この配列のサイズが 32 に固定されているため、最大 32 階層となっています

実用上、32 階層は十分な深さです

コンテナの中にコンテナを作り（入れ子）、さらにその中にコンテナを作るような極端なケースでも、32 階層あれば対応できます

一般的な用途では、2〜3 階層で十分です

### PID 1 の特別な役割

各 PID namespace には<strong>PID 1</strong>のプロセスが存在します

PID 1 には特別な役割があります

- 孤児プロセス（親が終了したプロセス）の親になる
- PID 1 が終了すると、その namespace 内の全プロセスが終了する
- シグナルの扱いが特殊（下記参照）

<strong>PID 1 のシグナル扱い</strong>

PID 1 は通常のプロセスとは異なるシグナルの扱いを受けます

- <strong>同じ namespace 内から送られるシグナル</strong>：PID 1 が明示的にハンドラを設定したシグナルのみ受信します（ハンドラ未設定のシグナルは無視されます）
- <strong>SIGKILL/SIGSTOP について</strong>：同じ namespace 内からは、これらのシグナルも無視されます（通常のプロセスでは無視できないシグナルです）
- <strong>祖先 namespace からのシグナル</strong>：親や祖先の namespace からの SIGKILL/SIGSTOP は強制的に配信されます

この仕組みにより、PID 1 は namespace 内からは簡単に終了させられませんが、ホスト（祖先 namespace）からは制御できます

コンテナでは、アプリケーションが PID 1 として実行されることが多いです

### PID namespace での PID の見え方

プロセスは複数の PID を持つことがあります

```
ホスト側で見た PID: 12345
コンテナ内で見た PID: 1
```

同じプロセスでも、どの namespace から見るかで PID が異なります

```bash
# ホスト側から見た Docker コンテナのプロセス
ps aux | grep nginx
# user  12345 ... nginx: master process
```

```bash
# コンテナ内から見た同じプロセス
docker exec container ps aux
# root  1 ... nginx: master process
```

---

## Mount namespace

### Mount namespace とは

<strong>マウント</strong>（mount）とは、ディスクやパーティションなどのストレージをディレクトリツリーに接続する操作です

例えば USB メモリを `/mnt/usb` に「マウント」すると、USB の中身が `/mnt/usb` 以下に見えるようになります

<strong>Mount namespace</strong>は、このマウントポイント（接続先）を隔離します

異なる Mount namespace に属するプロセスは、異なるファイルシステム構造を見ることができます

Linux の公式マニュアルには、こう書かれています

> Mount namespaces provide isolation of the list of mounts seen by the processes in each namespace instance.

> Mount namespace は、各 namespace インスタンス内のプロセスから見えるマウントのリストを隔離します

### Mount namespace の用途

Mount namespace は以下の用途に使われます

- <strong>コンテナのルートファイルシステム</strong>：コンテナに独自の `/` を提供
- <strong>プライベートな /tmp</strong>：プロセスごとに独立した一時ディレクトリ
- <strong>読み取り専用マウント</strong>：特定のディレクトリを変更不可にする

### コンテナ環境での具体的ユースケース

<strong>例 1：/etc/resolv.conf のマウント</strong>

コンテナは通常、ホストとは異なる DNS 設定を持ちます

Docker などのコンテナランタイムは、Mount namespace を使って、コンテナ固有の `/etc/resolv.conf` をマウントします

```
ホスト側：/etc/resolv.conf → ホストの DNS 設定
コンテナ内：/etc/resolv.conf → コンテナ固有の DNS 設定（別のファイル）
```

<strong>例 2：機密ファイルの隠蔽</strong>

ホストの `/etc/shadow`（パスワードハッシュ）をコンテナから見えなくしたい場合、空のファイルやダミーファイルを上からマウントできます

```bash
# /etc/shadow を空ファイルでマスク
mount --bind /dev/null /etc/shadow
```

コンテナ内からは `/etc/shadow` にアクセスしても、実際のパスワードハッシュは見えません

<strong>例 3：読み取り専用の /proc と /sys</strong>

セキュリティ強化のため、コンテナ内の `/proc` や `/sys` の一部を読み取り専用にマウントすることがあります

これにより、コンテナ内のプロセスがカーネル設定を変更することを防ぎます

### マウントの伝播

Mount namespace 間でマウントイベントがどう伝播するかを制御できます

伝播タイプを理解するために、まず<strong>バインドマウント</strong>について説明します

バインドマウントとは、既存のディレクトリを別の場所にも見えるようにする仕組みです

たとえば `/home/user/data` を `/mnt/data` にバインドマウントすると、同じ内容が両方の場所からアクセスできます

| 伝播タイプ | 説明                                                    |
| ---------- | ------------------------------------------------------- |
| shared     | マウント/アンマウントが双方向に伝播                     |
| private    | マウント/アンマウントは伝播しない（独立）               |
| slave      | マスター → スレーブへ一方向に伝播（逆方向は伝播しない） |
| unbindable | private と同様だが、バインドマウントの対象にもできない  |

```bash
# マウントの伝播タイプを確認
cat /proc/self/mountinfo | head -5
```

### chroot との違い

<strong>chroot</strong>は、プロセスのルートディレクトリを変更する仕組みです

Version 7 Unix から存在する歴史ある機能ですが、セキュリティ目的で設計されたものではありません

root 権限を持つプロセスは chroot 環境から「脱出」できる既知の手法があり、隔離としては不完全です

Mount namespace は chroot より強力な隔離を提供する現代的な代替です

| 特性           | chroot                 | Mount namespace           |
| -------------- | ---------------------- | ------------------------- |
| 隔離範囲       | ルートディレクトリのみ | 全マウントポイント        |
| 脱出の難易度   | 比較的容易             | 困難                      |
| 他の namespace | 連携しない             | 他の namespace と連携可能 |
| /proc の隔離   | されない               | 可能                      |

---

## Network namespace

### Network namespace とは

<strong>Network namespace</strong>は、ネットワークスタック全体を隔離します

ネットワークスタックとは、ネットワーク通信に必要な機能の集まりで、IP アドレスの管理、パケットの送受信、ルーティング（経路選択）などを担当します

各 Network namespace は独自のネットワークデバイス、IP アドレス、ルーティングテーブル、ファイアウォールルールを持ちます

Linux の公式マニュアルには、こう書かれています

> Network namespaces provide isolation of the system resources associated with networking: network devices, IPv4 and IPv6 protocol stacks, IP routing tables, firewall rules, the /proc/net directory, and various other network-related resources.

> Network namespace は、ネットワーキングに関連するシステムリソースの隔離を提供します
>
> ネットワークデバイス、IPv4/IPv6 プロトコルスタック、IP ルーティングテーブル、ファイアウォールルール、/proc/net ディレクトリ、その他のネットワーク関連リソースが含まれます

### Network namespace で隔離されるもの

- ネットワークデバイス（eth0、lo など）
- IP アドレス
- ルーティングテーブル
- ファイアウォールルール（iptables/nftables：Linux でパケットフィルタリング、つまり通信の許可/拒否を設定するツール）
- ソケット
- /proc/net および /sys/class/net

### 新しい Network namespace の状態

新しく作成された Network namespace には、ループバックインターフェース（lo）のみが存在します

ただし、lo はデフォルトで DOWN 状態です

```bash
# 新しい Network namespace で ip link を実行
sudo unshare --net ip link
```

出力例：

```
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
```

### veth ペア

異なる Network namespace 間で通信するには、<strong>veth</strong>（virtual ethernet）ペアを使用します

veth は、2 つの仮想ネットワークインターフェースをペアで作成し、一方に送信したパケットがもう一方から出力されます

```
ホスト Network namespace          コンテナ Network namespace
┌─────────────────────┐          ┌─────────────────────┐
│                     │          │                     │
│  eth0   veth-host ──┼──────────┼── veth-container    │
│                     │          │                     │
└─────────────────────┘          └─────────────────────┘
```

Docker はこの仕組みを使ってコンテナネットワークを実現しています

---

## UTS namespace

### UTS namespace とは

<strong>UTS namespace</strong>は、ホスト名（hostname）とドメイン名（domainname）を隔離します

UTS は「UNIX Time-sharing System」の略です

この名前は、uname(2) システムコールが返す構造体 `struct utsname` に由来します

utsname 構造体にはホスト名やドメイン名が含まれており、UTS namespace はこの構造体の値を隔離します

Linux の公式マニュアルには、こう書かれています

> UTS namespaces provide isolation of two system identifiers: the hostname and the NIS domain name.

> UTS namespace は、2 つのシステム識別子（ホスト名と NIS ドメイン名）の隔離を提供します

### UTS namespace の用途

UTS namespace は比較的シンプルですが、重要な用途があります

- <strong>コンテナのホスト名</strong>：各コンテナに固有のホスト名を設定
- <strong>識別</strong>：ログやプロンプトでコンテナを識別

### ホスト名の変更

新しい UTS namespace でホスト名を変更しても、ホストシステムには影響しません

```bash
# 現在のホスト名を確認
hostname
# myhost

# 新しい UTS namespace でシェルを起動
sudo unshare --uts /bin/bash

# （新しい namespace 内で）ホスト名を変更
hostname container-1

# （新しい namespace 内で）変更を確認
hostname
# container-1

# シェルを終了して元の namespace に戻る
exit

# ホスト側では変更されていない
hostname
# myhost
```

---

## IPC namespace

### IPC namespace とは

<strong>IPC namespace</strong>は、プロセス間通信（IPC）リソースを隔離します

IPC は「Inter-Process Communication」の略です

Linux の公式マニュアルには、こう書かれています

> IPC namespaces isolate certain IPC resources, namely, System V IPC objects and POSIX message queues.

> IPC namespace は、特定の IPC リソース（System V IPC オブジェクトと POSIX メッセージキュー）を隔離します

### 隔離される IPC リソース

IPC リソースには<strong>System V 系</strong>と<strong>POSIX 系</strong>の 2 種類があります

System V は古くから Unix で使われている API、POSIX は標準化された移植性の高い API です

- <strong>セマフォ</strong>：複数のプロセスが同時にリソースにアクセスしないよう制御する仕組み（排他制御）
- <strong>メッセージキュー</strong>：プロセス間でメッセージをやり取りする仕組み（郵便受けのようなもの）
- <strong>共有メモリ</strong>：複数のプロセスが同じメモリ領域を読み書きする仕組み（最も高速な IPC）

IPC namespace で隔離されるのは以下のリソースです

- System V セマフォ
- System V メッセージキュー
- System V 共有メモリ
- POSIX メッセージキュー

### IPC リソースの確認

```bash
# System V IPC リソースの確認
ipcs
```

出力例：

```
------ Message Queues --------
key        msqid      owner      perms      used-bytes   messages

------ Shared Memory Segments --------
key        shmid      owner      perms      bytes      nattch     status

------ Semaphore Arrays --------
key        semid      owner      perms      nsems
```

異なる IPC namespace に属するプロセスは、互いの IPC リソースにアクセスできません

---

## User namespace

### User namespace とは

<strong>User namespace</strong>は、ユーザー ID（UID）とグループ ID（GID）を隔離します

User namespace を使うと、namespace 内では root（UID 0）として動作しながら、ホスト側では一般ユーザーとして動作できます

Linux の公式マニュアルには、こう書かれています

> User namespaces isolate security-related identifiers and attributes, in particular, user IDs and group IDs, the root directory, keys, and capabilities.

> User namespace は、セキュリティ関連の識別子と属性を隔離します
>
> 特に、ユーザー ID、グループ ID、ルートディレクトリ、キー、ケーパビリティが含まれます

<strong>ケーパビリティ</strong>（capability）とは、root 権限を細分化した仕組みです

従来は「root か、そうでないか」の 2 択でしたが、ケーパビリティにより「ネットワーク設定の変更だけ許可」のような細かい制御ができます

User namespace 内の root は、その namespace 内でのみケーパビリティを持ちます

ホストシステム全体に影響を与える操作はできません

### UID/GID マッピング

User namespace では、UID/GID のマッピングを設定します

```
namespace 内 UID → ホスト UID
      0         →   1000
      1         →   1001
      ...
```

これにより、namespace 内では root として動作しながら、ホスト側では非特権ユーザーとして動作できます

### マッピングの確認

```bash
# UID マッピングの確認
cat /proc/self/uid_map

# GID マッピングの確認
cat /proc/self/gid_map
```

出力例（通常のプロセス）：

```
         0          0 4294967295
```

この出力は 3 つのフィールドで構成されています

| フィールド | 値         | 意味                            |
| ---------- | ---------- | ------------------------------- |
| 第 1       | 0          | namespace 内の UID 開始値       |
| 第 2       | 0          | マップ先（ホスト）の UID 開始値 |
| 第 3       | 4294967295 | マップする UID の個数           |

この例では「namespace 内の UID 0 から始まる 4294967295 個の UID が、ホストの UID 0 から始まる範囲にマップされる」ことを意味します（つまり、1 対 1 でそのままマップ）

なお、uid_map と gid_map は<strong>一度だけ書き込み可能</strong>です

一度マッピングを設定すると、その後の書き込みはエラー（EPERM）になります

<strong>もしマッピングを変更できたら？</strong>

この制限がなかったら、どのような攻撃が可能でしょうか？

<strong>攻撃シナリオ：権限昇格</strong>

1. 攻撃者が User namespace を作成し、自分を namespace 内の UID 0（root）にマップする
2. namespace 内で root としてファイルを作成する
3. マッピングを変更して、namespace 内の UID 0 をホストの UID 0 にマップし直す
4. さっき作成したファイルは、突然ホストの root が所有していることになる
5. そのファイルに SUID ビットが設定されていれば、ホストで root 権限を取得できる

このような攻撃を防ぐため、マッピングは一度だけ設定可能で、後から変更できない設計になっています

また、マッピングの設定には以下の制限もあります

- 自分自身の UID/GID にのみマップできる（他のユーザーの UID/GID にはマップできない）
- または、CAP_SETUID/CAP_SETGID ケーパビリティが必要

もし後からマッピングを変更できると、プロセスが自分の UID を自由に変えられてしまい、権限チェックを回避できる危険があります

### rootless コンテナ

User namespace は<strong>rootless コンテナ</strong>（非 root ユーザーで実行するコンテナ）の基盤です

- コンテナ内では root として動作（UID 0）
- ホスト側では一般ユーザーとして動作
- ホストの root 権限を必要としない
- セキュリティが向上する

---

## Cgroup namespace

### Cgroup namespace とは

<strong>Cgroup namespace</strong>は、cgroup（Control Group）の階層ビューを隔離します

プロセスは自分が cgroup 階層のルートにいるかのように見えます

Linux の公式マニュアルには、こう書かれています

> Cgroup namespaces virtualize the view of a process's cgroups as seen via /proc/pid/cgroup and /proc/pid/mountinfo.

> Cgroup namespace は、/proc/pid/cgroup と /proc/pid/mountinfo を通じて見えるプロセスの cgroup ビューを仮想化します

### Cgroup namespace の目的

Cgroup namespace には 2 つの主な目的があります

- <strong>情報の隠蔽</strong>：コンテナにホストの cgroup パスを見せない
- <strong>移行の容易さ</strong>：コンテナを別ホストに移行しやすくする

<strong>なぜホスト情報を隠す必要があるのか</strong>

コンテナ内のプロセスが `/proc/self/cgroup` を見ると、cgroup パスが表示されます

Cgroup namespace がなければ、このパスにはホストの情報が含まれます

```
0::/docker/a1b2c3d4e5f6.../
```

このパスから、以下の情報が漏洩する可能性があります

- コンテナランタイムの種類（docker、containerd など）
- コンテナ ID
- ホストの cgroup 構造

攻撃者がこれらの情報を使って、ホストシステムの構造を推測したり、他のコンテナを特定したりできる可能性があります

<strong>コンテナ移行への影響</strong>

cgroup パスがホスト固有の場合、コンテナを別のホストに移行（マイグレーション）すると、パスが変わってしまいます

コンテナ内のアプリケーションが cgroup パスを参照している場合、問題が発生する可能性があります

Cgroup namespace を使えば、コンテナ内からは常に `/` がルートに見えるため、ホストに依存しません

### cgroup パスの違い

Cgroup namespace なしの場合：

```bash
cat /proc/self/cgroup
# 0::/user.slice/user-1000.slice/session-1.scope
```

Cgroup namespace ありの場合：

```bash
cat /proc/self/cgroup
# 0::/
```

コンテナ内のプロセスは、自分が cgroup のルートにいるように見えます

### cgroup との関係

Cgroup namespace は cgroup の「見え方」を隔離するだけです

<strong>リソース制限</strong>自体は cgroup（Control Group）が担当します

cgroup については、次のトピック [07-cgroup](./07-cgroup.md) で詳しく学びます

---

## /proc での namespace 観察

### /proc/[pid]/ns ディレクトリ

各プロセスの namespace 情報は `/proc/[pid]/ns/` ディレクトリで確認できます

```bash
ls -la /proc/self/ns/
```

各ファイルは namespace へのシンボリックリンクで、namespace の inode 番号を含んでいます

### namespace の inode 番号を比較

2 つのプロセスが同じ namespace に属しているかは、inode 番号を比較して確認できます

```bash
# シェルの PID namespace
readlink /proc/self/ns/pid
# pid:[4026531836]

# 別のターミナルで同じコマンド
readlink /proc/self/ns/pid
# pid:[4026531836]  # 同じ番号なら同じ namespace
```

### lsns コマンド

`lsns` コマンドで、システム上の全 namespace を一覧表示できます

```bash
lsns
```

出力例：

```
        NS TYPE   NPROCS   PID USER    COMMAND
4026531835 cgroup    123     1 root    /sbin/init
4026531836 pid       123     1 root    /sbin/init
4026531837 user      123     1 root    /sbin/init
4026531838 uts       123     1 root    /sbin/init
4026531839 ipc       123     1 root    /sbin/init
4026531840 mnt       100     1 root    /sbin/init
4026531992 net       123     1 root    /sbin/init
```

### 特定のタイプの namespace を表示

```bash
# PID namespace のみ
lsns -t pid

# 特定のプロセスの namespace
lsns -p $$
```

### /proc/[pid]/status での確認

`/proc/[pid]/status` にも namespace 関連の情報があります

```bash
grep -i ns /proc/self/status
```

出力例：

```
NSpid:  12345
NStgid: 12345
NSsid:  12345
NSpgid: 12345
```

これらは、各 PID namespace でのプロセス ID を示しています

---

## namespace の操作

### unshare コマンド

`unshare` コマンドで、新しい namespace を作成してコマンドを実行できます

```bash
# 新しい UTS namespace でシェルを起動
sudo unshare --uts /bin/bash

# 新しい PID namespace でシェルを起動（--fork と --mount-proc が必要）
# --mount-proc：/proc を新しい PID namespace 用に再マウントする
# （/proc は PID と密接に関係しており、再マウントしないと ps コマンドなどが正しく動作しない）
sudo unshare --pid --fork --mount-proc /bin/bash

# 複数の namespace を同時に作成
sudo unshare --uts --pid --net --fork --mount-proc /bin/bash
```

### unshare のオプション

| オプション   | namespace | 説明                         |
| ------------ | --------- | ---------------------------- |
| --mount, -m  | Mount     | Mount namespace を作成       |
| --uts, -u    | UTS       | UTS namespace を作成         |
| --ipc, -i    | IPC       | IPC namespace を作成         |
| --net, -n    | Network   | Network namespace を作成     |
| --pid, -p    | PID       | PID namespace を作成         |
| --user, -U   | User      | User namespace を作成        |
| --cgroup, -C | Cgroup    | Cgroup namespace を作成      |
| --fork, -f   | -         | 子プロセスをフォークして実行 |
| --mount-proc | -         | 新しい /proc をマウント      |

### nsenter コマンド

`nsenter` コマンドで、既存のプロセスの namespace に入ることができます

```bash
# プロセス 12345 の全 namespace に入る
sudo nsenter -t 12345 -a /bin/bash

# 特定の namespace のみに入る
sudo nsenter -t 12345 --pid --mount /bin/bash
```

Docker コンテナに入る場合：

```bash
# コンテナのプロセス ID を取得
docker inspect --format '{{.State.Pid}}' container_name

# そのプロセスの namespace に入る
sudo nsenter -t <pid> -a /bin/bash
```

### clone システムコール

プログラムから namespace を作成するには、`clone()` システムコールを使用します

```c
/*
 * clone() で新しい namespace を持つ子プロセスを作成します
 *
 * CLONE_NEWPID：新しい PID namespace を作成
 * CLONE_NEWNS：新しい Mount namespace を作成
 * CLONE_NEWNET：新しい Network namespace を作成
 */
pid_t pid = clone(child_func, stack + STACK_SIZE,
                  CLONE_NEWPID | CLONE_NEWNS | CLONE_NEWNET | SIGCHLD,
                  NULL);
```

### unshare システムコール

`unshare()` システムコールで、呼び出し元プロセス自身を新しい namespace に移動できます

```c
/*
 * unshare() で新しい namespace を作成します
 *
 * このプロセス自身が新しい namespace に移動します
 */
if (unshare(CLONE_NEWUTS) == -1) {
    perror("unshare");
    exit(1);
}
```

### setns システムコール

`setns()` システムコールで、既存の namespace に参加できます

```c
/*
 * setns() で既存の namespace に参加します
 *
 * fd は /proc/[pid]/ns/xxx から取得したファイルディスクリプタ
 */
int fd = open("/proc/12345/ns/net", O_RDONLY);
if (setns(fd, CLONE_NEWNET) == -1) {
    perror("setns");
    exit(1);
}
close(fd);
```

---

## コンテナ技術との関係

### namespace とコンテナ

<strong>コンテナ</strong>（Docker、Kubernetes など）は、namespace を組み合わせて実現されています

典型的なコンテナは以下の namespace を使用します

| namespace | コンテナでの用途                         |
| --------- | ---------------------------------------- |
| PID       | コンテナ内のプロセスを隔離               |
| Mount     | コンテナ専用のファイルシステムを提供     |
| Network   | コンテナ専用のネットワークスタックを提供 |
| UTS       | コンテナ固有のホスト名を設定             |
| IPC       | コンテナ内の IPC リソースを隔離          |
| User      | rootless コンテナの実現                  |
| Cgroup    | cgroup パスの仮想化                      |

### Docker がコンテナを作成する流れ

Docker がコンテナを作成する際、おおまかに以下の処理が行われます

1. 新しい namespace（PID、Mount、Network、UTS、IPC）を作成
2. コンテナイメージからルートファイルシステムを準備
3. veth ペアでネットワークを接続
4. cgroup でリソース制限を設定
5. コンテナ内で指定されたコマンドを PID 1 として実行

### namespace だけではコンテナにならない

namespace は「隔離」を提供しますが、コンテナには他の要素も必要です

- <strong>cgroup</strong>：リソース制限（CPU、メモリなど）
- <strong>イメージ</strong>：ファイルシステムのテンプレート
- <strong>ランタイム</strong>：コンテナのライフサイクル管理
- <strong>ネットワーク</strong>：コンテナ間通信の設定

namespace と cgroup は「コンテナの基盤技術」です

cgroup については、次のトピックで詳しく学びます

---

## 用語集

| 用語              | 英語               | 説明                                                         |
| ----------------- | ------------------ | ------------------------------------------------------------ |
| namespace         | Namespace          | カーネルリソースを隔離する機能                               |
| PID namespace     | PID Namespace      | プロセス ID を隔離する namespace                             |
| Mount namespace   | Mount Namespace    | ファイルシステムのマウントポイントを隔離する namespace       |
| Network namespace | Network Namespace  | ネットワークスタックを隔離する namespace                     |
| UTS namespace     | UTS Namespace      | ホスト名とドメイン名を隔離する namespace                     |
| IPC namespace     | IPC Namespace      | プロセス間通信リソースを隔離する namespace                   |
| User namespace    | User Namespace     | ユーザー ID とグループ ID を隔離する namespace               |
| Cgroup namespace  | Cgroup Namespace   | cgroup 階層ビューを隔離する namespace                        |
| inode 番号        | Inode Number       | namespace を識別するための番号                               |
| veth              | Virtual Ethernet   | 仮想ネットワークインターフェースのペア                       |
| chroot            | Change Root        | プロセスのルートディレクトリを変更する機能                   |
| rootless コンテナ | Rootless Container | root 権限なしで実行するコンテナ                              |
| マウントの伝播    | Mount Propagation  | namespace 間でマウントイベントが伝播する方式                 |
| unshare           | Unshare            | 新しい namespace を作成するコマンド/システムコール           |
| nsenter           | Namespace Enter    | 既存の namespace に入るコマンド                              |
| setns             | Set Namespace      | 既存の namespace に参加するシステムコール                    |
| clone             | Clone              | 新しいプロセスを作成するシステムコール（namespace 作成可能） |
| コンテナ          | Container          | namespace と cgroup を使った軽量な仮想化技術                 |
| 隔離              | Isolation          | リソースを分離して独立した環境を作ること                     |

---

## 参考資料

このページの内容は、以下のソースに基づいています

<strong>namespace 概要</strong>

- [namespaces(7) - Linux manual page](https://man7.org/linux/man-pages/man7/namespaces.7.html)
  - namespace の概要と種類

<strong>各 namespace の詳細</strong>

- [pid_namespaces(7) - Linux manual page](https://man7.org/linux/man-pages/man7/pid_namespaces.7.html)
  - PID namespace の詳細
- [mount_namespaces(7) - Linux manual page](https://man7.org/linux/man-pages/man7/mount_namespaces.7.html)
  - Mount namespace の詳細
- [network_namespaces(7) - Linux manual page](https://man7.org/linux/man-pages/man7/network_namespaces.7.html)
  - Network namespace の詳細
- [uts_namespaces(7) - Linux manual page](https://man7.org/linux/man-pages/man7/uts_namespaces.7.html)
  - UTS namespace の詳細
- [ipc_namespaces(7) - Linux manual page](https://man7.org/linux/man-pages/man7/ipc_namespaces.7.html)
  - IPC namespace の詳細
- [user_namespaces(7) - Linux manual page](https://man7.org/linux/man-pages/man7/user_namespaces.7.html)
  - User namespace の詳細
- [cgroup_namespaces(7) - Linux manual page](https://man7.org/linux/man-pages/man7/cgroup_namespaces.7.html)
  - Cgroup namespace の詳細

<strong>namespace 操作</strong>

- [unshare(1) - Linux manual page](https://man7.org/linux/man-pages/man1/unshare.1.html)
  - unshare コマンド
- [unshare(2) - Linux manual page](https://man7.org/linux/man-pages/man2/unshare.2.html)
  - unshare システムコール
- [clone(2) - Linux manual page](https://man7.org/linux/man-pages/man2/clone.2.html)
  - clone システムコール
- [setns(2) - Linux manual page](https://man7.org/linux/man-pages/man2/setns.2.html)
  - setns システムコール
- [nsenter(1) - Linux manual page](https://man7.org/linux/man-pages/man1/nsenter.1.html)
  - nsenter コマンド

<strong>疑似ファイルシステム</strong>

- [proc(5) - Linux manual page](https://man7.org/linux/man-pages/man5/proc.5.html)
  - /proc/[pid]/ns/ ディレクトリ

---

## 次のステップ

このトピックでは、プロセスを隔離する namespace の仕組みを学びました

- Linux namespace（PID、Mount、Network、UTS、IPC、User、Cgroup）
- 各 namespace が隔離するリソース
- /proc/[pid]/ns/ での namespace の観察
- unshare、nsenter コマンドによる namespace の操作
- コンテナ技術との関係

しかし、1 つ疑問が残ります

プロセスを隔離できても、リソースの「使用量」を制限するにはどうすればよいのでしょうか？

あるコンテナがメモリを使い果たしたり、CPU を独占したりしないようにするには？

次の [07-cgroup](./07-cgroup.md) では、リソースを「制限」する仕組みを学びます

- cgroup とは何か
- cgroup v1 と cgroup v2 の違い
- CPU、メモリ、I/O の制限
- /sys/fs/cgroup での cgroup 観察
- コンテナ技術での活用

これらの疑問に答えます
