<div align="right">
<img src="https://img.shields.io/badge/AI-ASSISTED_STUDY-3b82f6?style=for-the-badge&labelColor=1e293b&logo=bookstack&logoColor=white" alt="AI Assisted Study" />
</div>

# なぜrootでなくても特権操作ができるのか

## はじめに

[04-process-management](../04-process-management.md) の「プロセスの資格情報」で、プロセスには UID や GID 以外に<strong>ケーパビリティ</strong>という情報があることを学びました

従来の Unix では、権限は単純でした

- root（UID 0）→ 何でもできる
- 一般ユーザー → 制限される

しかし、この「全か無か」の設計には問題があります

例えば、Web サーバーが 80 番ポート（特権ポート）を開くためだけに root で動かすのは危険です

もし脆弱性があれば、攻撃者はシステム全体を乗っ取れてしまいます

<strong>ケーパビリティ</strong>は、この問題を解決するために導入されました

「特定の操作だけ」を許可できるようにしたのです

このドキュメントでは、ケーパビリティの仕組みと、実際の使い方を説明します

---

## 目次

- [ケーパビリティとは](#ケーパビリティとは)
- [主要なケーパビリティ](#主要なケーパビリティ)
- [ケーパビリティの確認方法](#ケーパビリティの確認方法)
- [ケーパビリティの設定方法](#ケーパビリティの設定方法)
- [コンテナとケーパビリティ](#コンテナとケーパビリティ)
- [まとめ](#まとめ)
- [参考資料](#参考資料)

---

## ケーパビリティとは

### 従来の権限モデルの問題

従来の Unix では、root 権限は「全能」でした

```
root の権限（一部）
- ファイルの所有者を変更する
- 特権ポート（1024未満）をバインドする
- プロセスを任意に kill する
- カーネルモジュールをロードする
- 時刻を変更する
```

問題は、これらが<strong>分離できない</strong>ことでした

80 番ポートを開きたいだけなのに、カーネルモジュールをロードする権限まで与えられてしまいます

### ケーパビリティによる解決

<strong>ケーパビリティ</strong>は、root 権限を<strong>細分化</strong>したものです

Linux のマニュアルには、こう書かれています

> For the purpose of performing permission checks, traditional UNIX implementations distinguish two categories of processes: privileged processes and unprivileged processes. Linux divides the privileges traditionally associated with superuser into distinct units, known as capabilities.

> 権限チェックの目的で、従来の UNIX 実装では特権プロセスと非特権プロセスの 2 つのカテゴリを区別していました

> Linux は、スーパーユーザーに関連付けられた特権を、ケーパビリティと呼ばれる個別の単位に分割します

### ケーパビリティの効果

```
例：Web サーバー

従来
- root で起動 → 全ての特権を持つ → 危険

ケーパビリティ使用
- 一般ユーザーで起動
- CAP_NET_BIND_SERVICE だけ付与 → 80 番ポートだけ開ける
- 他の特権操作は不可 → 安全
```

---

## 主要なケーパビリティ

### よく使われるケーパビリティ

| ケーパビリティ       | 説明                             |
| -------------------- | -------------------------------- |
| CAP_NET_BIND_SERVICE | 1024 未満のポートをバインド      |
| CAP_NET_RAW          | RAW ソケットを使用（ping など）  |
| CAP_NET_ADMIN        | ネットワーク設定の変更           |
| CAP_SYS_ADMIN        | 多くの管理操作（mount など）     |
| CAP_SYS_PTRACE       | 他プロセスのトレース（デバッグ） |
| CAP_SYS_CHROOT       | chroot の使用                    |
| CAP_CHOWN            | ファイルの所有者変更             |
| CAP_DAC_OVERRIDE     | ファイル権限チェックのバイパス   |
| CAP_SETUID           | UID の変更                       |
| CAP_SETGID           | GID の変更                       |
| CAP_KILL             | 任意のプロセスにシグナル送信     |
| CAP_IPC_LOCK         | メモリのロック（mlock）          |

### CAP_SYS_ADMIN の特別さ

CAP_SYS_ADMIN は「雑多な管理操作」を許可するケーパビリティです

非常に多くの操作が含まれているため、「新しい root」とも呼ばれます

| 操作             | 説明                       |
| ---------------- | -------------------------- |
| mount / umount   | ファイルシステムのマウント |
| swapon / swapoff | スワップの有効化/無効化    |
| sethostname      | ホスト名の変更             |
| quotactl         | ディスククォータの操作     |
| ...              | その他多数                 |

セキュリティの観点からは、できるだけ<strong>避けるべき</strong>ケーパビリティです

<strong>なぜ CAP_SYS_ADMIN は肥大化したのか</strong>

ケーパビリティが Linux 2.2（1999 年）で導入されたとき、開発者は既存のシステムコールを分類する必要がありました

問題は、多くの管理操作が「どのカテゴリにも当てはまらない」ことでした

```
開発者の選択肢
1. 新しいケーパビリティを毎回定義する → ケーパビリティの数が爆発
2. CAP_SYS_ADMIN に入れる → 簡単だが権限が粗い
```

多くの場合、開発者は「簡単な選択肢」を選びました

その結果、CAP_SYS_ADMIN には 2025 年時点で 100 以上の異なる操作が含まれています

<strong>分割の試み</strong>

この問題を認識して、新しいケーパビリティが追加されています

| ケーパビリティ         | 導入バージョン | 分離された操作                 |
| ---------------------- | -------------- | ------------------------------ |
| CAP_SYSLOG             | Linux 2.6.37   | syslog の読み書き              |
| CAP_WAKE_ALARM         | Linux 3.0      | RTC ウェイクアラームの設定     |
| CAP_BLOCK_SUSPEND      | Linux 3.5      | システムサスペンドのブロック   |
| CAP_PERFMON            | Linux 5.8      | パフォーマンスモニタリング     |
| CAP_BPF                | Linux 5.8      | BPF 操作                       |
| CAP_CHECKPOINT_RESTORE | Linux 5.9      | プロセスのチェックポイント復元 |

しかし後方互換性のため、既存の操作を CAP_SYS_ADMIN から削除することは困難です

---

## ケーパビリティの確認方法

### プロセスのケーパビリティを確認

```bash
# 現在のプロセス
cat /proc/self/status | grep Cap

# 特定のプロセス
cat /proc/12345/status | grep Cap
```

出力例

```
CapInh: 0000000000000000
CapPrm: 0000000000000000
CapEff: 0000000000000000
CapBnd: 000001ffffffffff
CapAmb: 0000000000000000
```

### フィールドの意味

| フィールド | 名前        | 説明                     |
| ---------- | ----------- | ------------------------ |
| CapInh     | Inheritable | 継承可能なケーパビリティ |
| CapPrm     | Permitted   | 許可されたケーパビリティ |
| CapEff     | Effective   | 現在有効なケーパビリティ |
| CapBnd     | Bounding    | 取得可能な上限           |
| CapAmb     | Ambient     | 継承されるケーパビリティ |

<strong>5つのセットの関係</strong>

これらのセットは、プロセスがどのような権限を「持てるか」「使えるか」「渡せるか」を制御します

| セット                  | 役割                                                                              | 例え                     |
| ----------------------- | --------------------------------------------------------------------------------- | ------------------------ |
| Permitted（許可）       | 「持てる最大範囲」（このセットにあるケーパビリティだけが Effective に追加できる） | 持っている資格証明書     |
| Effective（有効）       | 「今使える権限」（権限チェックはこのセットに対して行われる）                      | 今見せている資格証明書   |
| Inheritable（継承可能） | 「execve() で子に渡せる権限」（実行ファイルの Inheritable との AND で計算）       | 子供に教えられる技術     |
| Bounding（境界）        | 「これ以上は絶対に取得できない上限」（削除のみ可能で追加は不可）                  | 取得可能な資格の最大範囲 |
| Ambient（環境）         | 「execve() 後も自動的に残る権限」（setcap なしの実行ファイルでも継承される）      | 自動的に付いてくる権限   |

<strong>Effective と Permitted の違い</strong>

Permitted は「許可されているが、今は使っていない」権限を含みます

プログラムは必要なときだけ Effective に追加し、不要になったら外すことで、攻撃を受けたときのリスクを最小化できます

```
例：Web サーバー
1. 起動時：Permitted = {CAP_NET_BIND_SERVICE}, Effective = {CAP_NET_BIND_SERVICE}
2. 80 番ポートを開く
3. ポートを開いた後：Effective = {} （空にする）
→ 以降は特権操作ができなくなり、脆弱性があっても被害を限定できる
```

<strong>Effective/Permitted の実践例</strong>

以下は、実際のアプリケーションがどのようにケーパビリティを使い分けるかの例です

| アプリケーション | Permitted に保持           | Effective のタイミング          |
| ---------------- | -------------------------- | ------------------------------- |
| nginx            | CAP_NET_BIND_SERVICE       | listen() の呼び出し時のみ有効化 |
| tcpdump          | CAP_NET_RAW                | パケットキャプチャ中のみ有効化  |
| chronyd（NTP）   | CAP_SYS_TIME               | 時刻調整時のみ有効化            |
| wireshark        | CAP_NET_RAW, CAP_NET_ADMIN | キャプチャ開始時のみ有効化      |

<strong>C コードでの権限の切り替え</strong>

libcap を使うと、プログラム内でケーパビリティを操作できます

```c
#include <sys/capability.h>

void drop_effective_caps(void) {
    cap_t caps = cap_get_proc();
    cap_clear_flag(caps, CAP_EFFECTIVE);  /* Effective を空にする */
    cap_set_proc(caps);
    cap_free(caps);
}

void restore_cap(cap_value_t cap) {
    cap_t caps = cap_get_proc();
    cap_set_flag(caps, CAP_EFFECTIVE, 1, &cap, CAP_SET);
    cap_set_proc(caps);
    cap_free(caps);
}
```

このパターンを使うと、特権が必要な瞬間だけ Effective を有効にし、それ以外の時間は権限を落とすことができます

### 16進数をデコード

```bash
# capsh コマンドで人間が読める形式に変換
capsh --decode=000001ffffffffff
```

出力例

```
0x000001ffffffffff=cap_chown,cap_dac_override,...
```

### 実行ファイルのケーパビリティを確認

```bash
# getcap コマンド
getcap /usr/bin/ping
```

出力例

```
/usr/bin/ping cap_net_raw=ep
```

`=ep` は「effective」と「permitted」の両方に設定されていることを意味します

---

## ケーパビリティの設定方法

### 実行ファイルにケーパビリティを設定

```bash
# setcap コマンド（root 権限が必要）
sudo setcap cap_net_bind_service=ep /usr/local/bin/myapp
```

### ケーパビリティのフラグ

| フラグ | 意味                    |
| ------ | ----------------------- |
| e      | effective（有効）       |
| p      | permitted（許可）       |
| i      | inheritable（継承可能） |

### 設定の削除

```bash
sudo setcap -r /usr/local/bin/myapp
```

### capsh でシェルを起動

```bash
# 特定のケーパビリティを落としてシェルを起動
capsh --drop=cap_net_raw -- -c "ping localhost"  # 失敗する
```

### 実用例：Node.js で 80 番ポートを開く

```bash
# Node.js にケーパビリティを設定
sudo setcap cap_net_bind_service=ep /usr/bin/node

# 一般ユーザーで 80 番ポートを使用可能
node server.js  # ポート 80 で起動
```

---

## コンテナとケーパビリティ

### コンテナのセキュリティ

Docker などのコンテナランタイムは、ケーパビリティを積極的に利用しています

コンテナはデフォルトで<strong>必要最小限のケーパビリティ</strong>だけを持ちます

### Docker のデフォルトケーパビリティ

Docker コンテナには、以下のケーパビリティがデフォルトで付与されます

| ケーパビリティ       | 理由                             |
| -------------------- | -------------------------------- |
| CAP_CHOWN            | ファイル所有者の変更             |
| CAP_DAC_OVERRIDE     | ファイル権限のバイパス           |
| CAP_FSETID           | setuid/setgid ビットの保持       |
| CAP_FOWNER           | ファイル所有者チェックのバイパス |
| CAP_MKNOD            | デバイスファイルの作成           |
| CAP_NET_RAW          | RAW ソケット                     |
| CAP_SETGID           | GID の変更                       |
| CAP_SETUID           | UID の変更                       |
| CAP_SETFCAP          | ケーパビリティの設定             |
| CAP_SETPCAP          | ケーパビリティの操作             |
| CAP_NET_BIND_SERVICE | 特権ポートのバインド             |
| CAP_SYS_CHROOT       | chroot の使用                    |
| CAP_KILL             | シグナル送信                     |
| CAP_AUDIT_WRITE      | 監査ログへの書き込み             |

### ケーパビリティの追加・削除

```bash
# ケーパビリティを追加
docker run --cap-add SYS_ADMIN ...

# ケーパビリティを削除
docker run --cap-drop NET_RAW ...

# 全てのケーパビリティを削除
docker run --cap-drop ALL ...

# 必要なものだけ追加
docker run --cap-drop ALL --cap-add NET_BIND_SERVICE ...
```

### rootless コンテナ

Podman などの「rootless コンテナ」は、ケーパビリティを活用して root 権限なしでコンテナを実行します

User namespace と組み合わせることで、コンテナ内で root に見えても、ホストでは一般ユーザーとして動作します

詳細は [06-namespace](../06-namespace.md) を参照してください

---

## まとめ

<strong>ケーパビリティとは</strong>

| ポイント          | 説明                       |
| ----------------- | -------------------------- |
| root 権限の細分化 | 必要な権限だけを付与できる |
| 最小権限の原則    | 攻撃を受けても被害を限定   |
| POSIX.1e 由来     | 標準化の試みから発展       |

<strong>覚えておくこと</strong>

| ポイント                       | 説明                               |
| ------------------------------ | ---------------------------------- |
| CAP_NET_BIND_SERVICE           | 1024 未満のポートを開く            |
| CAP_SYS_ADMIN                  | 多くの管理操作（できれば避ける）   |
| getcap / setcap                | ファイルのケーパビリティ確認・設定 |
| /proc/[pid]/status             | プロセスのケーパビリティ確認       |
| コンテナはケーパビリティを活用 | デフォルトで制限されている         |

---

## 参考資料

<strong>Linux マニュアル</strong>

- [capabilities(7) - Linux manual page](https://man7.org/linux/man-pages/man7/capabilities.7.html)
  - ケーパビリティの詳細
- [getcap(8) - Linux manual page](https://man7.org/linux/man-pages/man8/getcap.8.html)
  - ファイルのケーパビリティ確認
- [setcap(8) - Linux manual page](https://man7.org/linux/man-pages/man8/setcap.8.html)
  - ファイルのケーパビリティ設定
- [capsh(1) - Linux manual page](https://man7.org/linux/man-pages/man1/capsh.1.html)
  - ケーパビリティのシェルラッパー

<strong>本編との関連</strong>

- [04-process-management](../04-process-management.md)
  - プロセスの資格情報
- [06-namespace](../06-namespace.md)
  - User namespace とケーパビリティ
- [07-cgroup](../07-cgroup.md)
  - リソース制限との組み合わせ
