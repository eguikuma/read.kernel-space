<div align="right">
<img src="https://img.shields.io/badge/AI-ASSISTED_STUDY-3b82f6?style=for-the-badge&labelColor=1e293b&logo=bookstack&logoColor=white" alt="AI Assisted Study" />
</div>

# メモリ不足でプロセスが殺されるのはなぜか

## はじめに

ある日、重要なプロセスが突然消えました

ログを確認すると、こんなメッセージが残っていました

```
Out of memory: Killed process 12345 (myapp) total-vm:8000000kB, anon-rss:4000000kB
```

犯人は<strong>OOM Killer</strong>（Out-of-Memory Killer）でした

Linux カーネルは、メモリが不足すると、システム全体を守るためにプロセスを強制終了します

なぜこのような仕組みが必要なのでしょうか？

そして、自分のプロセスが殺されないようにするには、どうすればよいのでしょうか？

このドキュメントでは、OOM Killer の仕組みと対策を説明します

---

## 目次

- [OOM Killerとは](#oom-killerとは)
- [なぜOOM Killerが必要か](#なぜoom-killerが必要か)
- [どのプロセスが殺されるか](#どのプロセスが殺されるか)
- [OOM Killerの確認方法](#oom-killerの確認方法)
- [対策方法](#対策方法)
- [cgroupとOOM](#cgroupとoom)
- [まとめ](#まとめ)
- [参考資料](#参考資料)

---

## OOM Killerとは

### 基本的な説明

<strong>OOM Killer</strong>は、メモリ不足時にプロセスを強制終了するカーネルの機能です

Linux のマニュアルには、こう書かれています

> If the system runs out of memory, the OOM killer will select a process to kill based on the process's OOM score.

> システムがメモリ不足になると、OOM Killer はプロセスの OOM スコアに基づいて、終了させるプロセスを選択します

### 何が起きるか

```
1. システムのメモリが不足
2. カーネルがページを回収しようとする
3. それでも足りない場合、OOM Killer が起動
4. OOM スコアが最も高いプロセスを選択
5. SIGKILL（シグナル 9）でプロセスを強制終了
6. メモリが解放され、システムが継続動作
```

---

## なぜOOM Killerが必要か

### Overcommit とは

Linux は<strong>オーバーコミット</strong>（overcommit）を許可しています

これは、実際の物理メモリ + スワップより多くのメモリを「約束」できる機能です

```
例：
物理メモリ: 8GB
スワップ: 2GB
合計: 10GB

しかし、プロセス A が 6GB、プロセス B が 6GB を確保できる
→ 合計 12GB を「約束」している
```

### なぜOvercommitを許可するのか

多くのプログラムは、確保したメモリをすべて使うわけではありません

```c
char *buf = malloc(1000000000);  /* 1GB を確保 */
/* 実際には 100MB しか使わない */
```

オーバーコミットを許可しないと、実際には使わないメモリまで確保され、非効率になります

### Overcommitの問題

しかし、すべてのプロセスが確保したメモリを実際に使い始めると、メモリが足りなくなります

この時点で、カーネルには 2 つの選択肢があります

1. システム全体をフリーズさせる
2. プロセスを殺してメモリを確保する

Linux は後者を選びました

それが OOM Killer です

<strong>歴史的背景：なぜ Linux はオーバーコミットを選んだのか</strong>

1990 年代、Linux が広く使われ始めた頃、メモリは高価でした

当時の一般的なサーバーは 64MB〜256MB 程度のメモリしか搭載していませんでした

多くのプログラムは「とりあえず大きめのバッファを確保しておく」という設計でした

もしオーバーコミットを禁止すると、以下の問題が発生しました

| 問題                       | 影響                                                   |
| -------------------------- | ------------------------------------------------------ |
| fork() の失敗              | 子プロセスは親のメモリ空間のコピーを必要とするため     |
| 大きなプログラムが動かない | 実際には使わない部分まで物理メモリを予約する必要がある |
| メモリの無駄               | 「使うかもしれない」メモリが他のプロセスで使えない     |

<strong>fork() と Copy-on-Write</strong>

特に `fork()` システムコールでは、オーバーコミットが重要でした

```c
/* 2GB 使用中の親プロセスが fork() を呼ぶ */
pid_t child = fork();
/* オーバーコミットなし → 2GB の空き物理メモリが必要 */
/* オーバーコミットあり → 実際に書き込むまで物理メモリ不要（CoW） */
```

Copy-on-Write のおかげで、fork() 直後は親子で同じ物理ページを共有します

しかしオーバーコミットを禁止すると、「将来書き込むかもしれない」全メモリを事前に確保する必要があり、大きなプロセスの fork() が失敗しました

Linux はオーバーコミットを許可することで、この問題を解決しました

代償として、本当にメモリが足りなくなったときの「最後の手段」として OOM Killer が必要になりました

### Overcommitの設定

オーバーコミットの動作は `/proc/sys/vm/overcommit_memory` で制御できます

| 値  | 動作                                        |
| --- | ------------------------------------------- |
| 0   | ヒューリスティック（デフォルト）            |
| 1   | 常にオーバーコミットを許可                  |
| 2   | スワップ + 物理メモリ × 比率 の範囲内に制限 |

<strong>モード 0（ヒューリスティック）とは</strong>

デフォルトのモード 0 は、<strong>明らかに無理な要求だけを拒否</strong>します

「明らかに無理」の判断基準は公開されていませんが、以下のような動作をします

- 極端に大きなメモリ要求は拒否
- 適度なオーバーコミットは許可（スワップ使用を減らすため）
- 特権プロセスには若干多めのメモリを許可

「ある程度は許可するが、明らかな無理は拒否する」という実用的なバランスです

```bash
# 現在の設定を確認
cat /proc/sys/vm/overcommit_memory
```

---

## どのプロセスが殺されるか

### OOM Score

カーネルは各プロセスに<strong>OOM スコア</strong>を計算します

スコアが最も高いプロセスが、OOM Killer のターゲットになります

```bash
# プロセスの OOM スコアを確認
cat /proc/self/oom_score
```

### スコアの計算要素

| 要素               | 影響                      |
| ------------------ | ------------------------- |
| メモリ使用量       | 多いほどスコアが高い      |
| 子プロセスのメモリ | 子の使用量も加算          |
| nice 値            | nice が高いとスコアも高い |
| 特権プロセス       | スコアが低くなる（保護）  |
| oom_score_adj      | 手動調整（後述）          |

<strong>カーネル内部での計算ロジック</strong>

OOM Killer の選択ロジックは `mm/oom_kill.c` に実装されています

カーネルは以下の優先順位でターゲットを選択します

```
1. oom_score_adj が 1000 のプロセスを最優先で選択
2. 各プロセスの「悪さ」ポイント（badness）を計算
3. 最もポイントが高いプロセスを選択
```

<strong>badness ポイントの計算</strong>

カーネルの `oom_badness()` 関数は、以下のように badness を計算します

```
points = (RSS + ページテーブル + スワップ使用量) の合計ページ数
points = points × 1000 ÷ システム全体の利用可能メモリ（ページ数）
points = points + oom_score_adj
```

| 要素           | 説明                                             |
| -------------- | ------------------------------------------------ |
| RSS            | プロセスが実際に使用している物理メモリ           |
| ページテーブル | プロセスの仮想アドレス空間を管理するためのメモリ |
| スワップ使用量 | スワップに追い出されたページ数                   |
| 利用可能メモリ | 物理メモリ + スワップ − 予約済みメモリ           |

<strong>なぜ RSS だけでなくスワップも考慮するのか</strong>

スワップに追い出されたメモリも、そのプロセスが「消費している」リソースです

もしスワップを無視すると、大量のメモリを確保してスワップに追い出されたプロセスが、新しく起動した小さなプロセスより低いスコアになってしまいます

参考：[kernel.org - mm/oom_kill.c](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/mm/oom_kill.c)

<strong>特権プロセスの保護</strong>

CAP_SYS_ADMIN ケーパビリティを持つプロセスは、OOM スコアが若干低くなります

これは、システム管理に必要なプロセスを保護するためです

詳細は [capability](./capability.md) を参照してください

### oom_score_adj による調整

`oom_score_adj` を使って、OOM スコアを手動で調整できます

| 値    | 効果             |
| ----- | ---------------- |
| -1000 | 絶対に殺されない |
| -500  | 殺されにくい     |
| 0     | デフォルト       |
| +500  | 殺されやすい     |
| +1000 | 最優先で殺される |

<strong>スコアの計算方法</strong>

最終的な OOM スコア（`/proc/[pid]/oom_score`）は 0 から 1000 の範囲で計算されます

基本的な計算式（概算）

```
ベーススコア = (プロセスの物理メモリ使用量 / システム全体の利用可能メモリ) × 1000
最終スコア = ベーススコア + oom_score_adj
（0 〜 1000 の範囲にクリップ）
```

<strong>計算例</strong>

8GB のシステムで 2GB 使用しているプロセスの場合

```
ベーススコア = (2GB / 8GB) × 1000 = 250
oom_score_adj = 0（デフォルト）の場合 → 最終スコア = 250
oom_score_adj = -200 の場合 → 最終スコア = 50
oom_score_adj = +500 の場合 → 最終スコア = 750
```

oom_score_adj が -1000 の場合、計算結果に関係なくスコアは 0 になります

これにより、そのプロセスは OOM Killer から完全に保護されます（ただし、システム全体がフリーズするリスクがあります）

```bash
# 現在の値を確認
cat /proc/self/oom_score_adj

# 値を変更（root 権限が必要）
echo -500 > /proc/12345/oom_score_adj
```

### 重要なプロセスを保護する

データベースや重要なサービスは、OOM スコアを下げて保護できます

```bash
# MySQL を保護する例
echo -500 > /proc/$(pidof mysqld)/oom_score_adj
```

systemd を使う場合は、サービスファイルで設定できます

```ini
[Service]
OOMScoreAdjust=-500
```

---

## OOM Killerの確認方法

### dmesg で確認

OOM Killer が動作すると、カーネルログにメッセージが残ります

```bash
dmesg | grep -i "oom\|killed process"
```

出力例

```
[12345.678901] Out of memory: Killed process 12345 (myapp) total-vm:8000000kB, anon-rss:4000000kB
```

### /var/log/messages または journalctl

```bash
# 従来のログ
grep -i oom /var/log/messages

# systemd のジャーナル
journalctl -k | grep -i oom
```

### OOM のログの読み方

```
Out of memory: Killed process 12345 (myapp)
  total-vm:8000000kB      ← 仮想メモリサイズ（予約した合計）
  anon-rss:4000000kB      ← 無名ページの物理メモリ使用量
  file-rss:100000kB       ← ファイルマッピングの物理メモリ使用量
  shmem-rss:50000kB       ← 共有メモリの使用量
```

<strong>anon-rss とは</strong>

anon-rss（Anonymous Resident Set Size）は、<strong>ファイルに対応しないメモリ</strong>の物理使用量です

具体的には以下が含まれます

| 種類     | 説明                                           |
| -------- | ---------------------------------------------- |
| ヒープ   | malloc() や new で動的に確保したメモリ         |
| スタック | 関数呼び出しで使用される自動変数の領域         |
| 無名mmap | MAP_ANONYMOUS でファイルなしにマップしたメモリ |

anon-rss が大きいプロセスは、動的に多くのメモリを消費しているため、OOM Killer のターゲットになりやすくなります

---

## 対策方法

### 1. メモリを増やす

最も単純な解決策です

物理メモリを増設するか、スワップを追加します

### 2. メモリリークを修正する

アプリケーションがメモリを解放していない可能性があります

```bash
# メモリ使用量の推移を確認
while true; do
    ps -o pid,rss,comm -p 12345
    sleep 60
done
```

<strong>メモリリークの判断基準</strong>

| パターン               | 解釈                               |
| ---------------------- | ---------------------------------- |
| RSS が単調増加し続ける | メモリリークの可能性が高い         |
| RSS が増減を繰り返す   | 正常（GC やキャッシュの動作）      |
| RSS が一定値で安定     | 正常                               |
| RSS が急増後に安定     | 起動時の初期化（正常な場合が多い） |

注意点

- 長時間（数時間〜数日）監視することが重要
- 負荷テスト中に確認すると効果的
- アプリケーションの特性（キャッシュの有無など）を考慮する

### 3. oom_score_adj を調整

重要なプロセスを保護し、重要でないプロセスを優先的に殺されるようにします

```bash
# 重要なプロセスを保護
echo -500 > /proc/$(pidof important_app)/oom_score_adj

# 重要でないプロセスを犠牲に
echo 500 > /proc/$(pidof cache_worker)/oom_score_adj
```

### 4. Overcommitを制限

オーバーコミットを制限することで、メモリ不足を事前に防げます

```bash
# オーバーコミットを無効化
echo 2 > /proc/sys/vm/overcommit_memory

# コミット可能な比率を設定
echo 80 > /proc/sys/vm/overcommit_ratio
```

<strong>overcommit_memory=2 の計算式</strong>

モード 2 では、コミット可能な合計メモリ（CommitLimit）が以下の式で計算されます

```
CommitLimit = スワップ + 物理メモリ × (overcommit_ratio / 100)
```

例：物理メモリ 8GB、スワップ 2GB、overcommit_ratio=80 の場合

```
CommitLimit = 2GB + 8GB × 0.8 = 2GB + 6.4GB = 8.4GB
```

現在の CommitLimit は `/proc/meminfo` で確認できます

```bash
grep -E "CommitLimit|Committed_AS" /proc/meminfo
```

`Committed_AS` が `CommitLimit` を超えると、新たなメモリ確保が失敗します

ただし、一部のアプリケーション（JVM など）が動作しなくなる可能性があります

### 5. OOM Killerを無効化（非推奨）

特定のプロセスで OOM Killer を無効化できますが、<strong>推奨されません</strong>

```bash
# 絶対に殺されない
echo -1000 > /proc/12345/oom_score_adj
```

すべてのプロセスでこれを設定すると、システム全体がフリーズする可能性があります

---

## cgroupとOOM

### cgroup のメモリ制限

cgroup を使うと、プロセスグループごとにメモリを制限できます

制限を超えると、そのグループ内で OOM Killer が動作します

```bash
# cgroup v2 でメモリ制限を設定
echo 500M > /sys/fs/cgroup/mygroup/memory.max
```

### cgroup 内の OOM

cgroup 内で OOM が発生しても、システム全体には影響しません

```bash
# cgroup 内の OOM イベントを確認
cat /sys/fs/cgroup/mygroup/memory.events
```

出力例

```
low 0
high 0
max 5
oom 2
oom_kill 2
```

<strong>oom と oom_kill の違い</strong>

| カウンタ | 意味                                          |
| -------- | --------------------------------------------- |
| oom      | メモリ使用量が max 境界を超えそうになった回数 |
| oom_kill | 実際にプロセスが強制終了された回数            |

oom イベントは「メモリ不足の危機」を示し、oom_kill イベントは「実際にプロセスが殺された」ことを示します

oom > oom_kill となる場合があります（メモリ回収が成功して kill を回避できた場合など）

### コンテナと OOM

Docker や Kubernetes では、コンテナごとにメモリ制限を設定できます

```bash
# Docker でメモリ制限
docker run --memory 500m myapp

# Kubernetes でメモリ制限
resources:
  limits:
    memory: 500Mi
```

コンテナ内で OOM が発生すると、コンテナ内のプロセスだけが影響を受けます

詳細は [07-cgroup](../07-cgroup.md) を参照してください

---

## まとめ

<strong>OOM Killer とは</strong>

| ポイント                 | 説明                                         |
| ------------------------ | -------------------------------------------- |
| メモリ不足時の最後の手段 | システム全体を守るためにプロセスを殺す       |
| Overcommit が原因        | 実際の物理メモリより多くを約束できるため     |
| OOM スコアで選択         | メモリ使用量が多いプロセスが優先的に殺される |

<strong>覚えておくこと</strong>

| ポイント             | 説明                                  |
| -------------------- | ------------------------------------- |
| dmesg で確認         | OOM Killer のログはカーネルログに残る |
| oom_score_adj で調整 | 重要なプロセスを保護できる            |
| cgroup で隔離        | グループ内に OOM の影響を限定         |
| -1000 は慎重に       | システムフリーズの原因になりうる      |

---

## 参考資料

<strong>Linux マニュアル</strong>

- [proc(5) - Linux manual page](https://man7.org/linux/man-pages/man5/proc.5.html)
  - /proc/[pid]/oom_score、/proc/[pid]/oom_score_adj

<strong>Linux カーネルドキュメント</strong>

- [Memory Management - kernel.org](https://www.kernel.org/doc/html/latest/admin-guide/mm/)
  - メモリ管理の概要
- [Control Group v2 - kernel.org](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)
  - cgroup のメモリコントローラ

<strong>本編との関連</strong>

- [03-virtual-memory](../03-virtual-memory.md)
  - 仮想メモリとページング
- [07-cgroup](../07-cgroup.md)
  - cgroup によるメモリ制限
