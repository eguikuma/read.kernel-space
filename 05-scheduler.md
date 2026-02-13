<div align="right">
<img src="https://img.shields.io/badge/AI-ASSISTED_STUDY-3b82f6?style=for-the-badge&labelColor=1e293b&logo=bookstack&logoColor=white" alt="AI Assisted Study" />
</div>

# 05-scheduler：CPU 時間の配分

## はじめに

[04-process-management](./04-process-management.md) では、カーネルがプロセスを管理する仕組みを学びました

- プロセスの状態（R、S、D、T、Z）
- プロセスグループとセッション
- デーモンプロセスの仕組み
- プロセスの作成と終了

しかし、1 つ疑問が残りました

複数のプロセスが同時に実行可能（R 状態）のとき、カーネルはどのプロセスに CPU を使わせるのでしょうか？

このページでは、その答えを学びます

<strong>スケジューラ</strong>は、CPU という限られたリソースをプロセスに配分するカーネルのコンポーネントです

どのプロセスを次に実行するか、どれくらいの時間を割り当てるか、これらを決定します

### 日常の例え

スケジューラを「空港の搭乗ゲート」に例えてみましょう

<strong>ゲート係員（スケジューラ）</strong>は、どの乗客を先に搭乗させるかを決定します

<strong>搭乗グループ（スケジューリングポリシー）</strong>によって、搭乗順序が決まります

- ファーストクラス（リアルタイム FIFO）は最優先で搭乗します
- ビジネスクラス（リアルタイム RR）も優先されますが、時間制限があります
- エコノミークラス（通常プロセス）は公平に順番を待ちます
- スタンバイ（SCHED_IDLE）は空席があるときだけ搭乗できます

<strong>nice 値</strong>は、同じクラス内での優先度です

プレミアム会員（nice 値が低い）は、一般会員より早く搭乗できます

<strong>CPU アフィニティ</strong>は、「ゲート A のみ利用可」という制限に似ています

特定の CPU でのみ実行されるよう制限できます

### このページで学ぶこと

このページでは、以下の概念を学びます

- <strong>スケジューラとは何か</strong>
  - CPU 時間を配分する仕組み
- <strong>スケジューリングポリシー</strong>
  - SCHED_OTHER、SCHED_FIFO、SCHED_RR など 6 種類
- <strong>nice 値と優先度</strong>
  - -20 から +19 の範囲と意味
- <strong>CFS（Completely Fair Scheduler）</strong>
  - Linux の標準スケジューラの概念
- <strong>リアルタイムスケジューリング</strong>
  - 確定的な応答時間が必要な場合
- <strong>/proc でスケジューリング情報を観察</strong>
  - /proc/[pid]/sched、/proc/loadavg など
- <strong>CPU アフィニティ</strong>
  - プロセスを特定の CPU に割り当てる
- <strong>カーネルパラメータ</strong>
  - スケジューラの動作を調整する設定

---

## 目次

1. [スケジューラとは何か](#スケジューラとは何か)
2. [スケジューリングポリシー](#スケジューリングポリシー)
3. [nice 値と優先度](#nice-値と優先度)
4. [CFS（Completely Fair Scheduler）](#cfs-completely-fair-scheduler)
5. [リアルタイムスケジューリング](#リアルタイムスケジューリング)
6. [/proc でスケジューリング情報を観察](#proc-でスケジューリング情報を観察)
7. [CPU アフィニティ](#cpu-アフィニティ)
8. [カーネルパラメータ](#カーネルパラメータ)
9. [用語集](#用語集)
10. [参考資料](#参考資料)

---

## スケジューラとは何か

### なぜスケジューラが必要か

現代のコンピュータでは、多くのプロセスが同時に動作しています

しかし、CPU のコア数は限られています

たとえば、4 コアの CPU で 100 個のプロセスを動かすには、CPU 時間を分け合う必要があります

<strong>スケジューラ</strong>は、どのプロセスにいつ CPU を使わせるかを決定するカーネルのコンポーネントです

Linux の公式マニュアルには、こう書かれています

> The scheduler is the kernel component that decides which runnable thread will be executed by the CPU next.

> スケジューラは、実行可能なスレッドのうち次に CPU で実行されるものを決定するカーネルコンポーネントです

### スケジューラの役割

スケジューラは以下のことを決定します

- <strong>選択</strong>：どのプロセスを次に実行するか
- <strong>割り当て</strong>：そのプロセスにどれくらいの時間を与えるか
- <strong>切り替え</strong>：いつ別のプロセスに切り替えるか

### タイムシェアリング

<strong>タイムシェアリング</strong>（時分割）は、CPU 時間を細かく分割して複数のプロセスに配分する方式です

各プロセスは短い時間（数ミリ秒）だけ CPU を使用し、次のプロセスに譲ります

これが高速に繰り返されるため、人間には複数のプロセスが同時に動いているように見えます

### プリエンプション

<strong>プリエンプション</strong>（横取り）は、実行中のプロセスを強制的に中断して別のプロセスを実行することです

以下の場合にプリエンプションが発生します

- プロセスに割り当てられた時間を使い切った
- より優先度の高いプロセスが実行可能になった
- プロセスが I/O 待ちなどでブロックした

### 実行可能キュー

スケジューラは<strong>実行可能キュー</strong>（run queue）を管理しています

これは、CPU を使用する準備ができているプロセス（R 状態）のリストです

スケジューラは、このキューから次に実行するプロセスを選択します

---

## スケジューリングポリシー

### ポリシーとは

<strong>スケジューリングポリシー</strong>は、プロセスの実行順序を決定するルールです

Linux には 6 種類のポリシーがあります

Linux の公式マニュアルには、こう書かれています

> The scheduler is the kernel component that decides which runnable thread will be executed by the CPU next. Each thread has an associated scheduling policy and a static scheduling priority.

> スケジューラは、実行可能なスレッドのうち次に CPU で実行されるものを決定するカーネルコンポーネントです
>
> 各スレッドには、関連付けられたスケジューリングポリシーと静的スケジューリング優先度があります

### 6 つのスケジューリングポリシー

| ポリシー       | 種類         | 静的優先度 | 説明                                   |
| -------------- | ------------ | ---------- | -------------------------------------- |
| SCHED_OTHER    | 通常         | 0 のみ     | デフォルトのタイムシェアリング（CFS）  |
| SCHED_BATCH    | 通常         | 0 のみ     | CPU 集約型バッチ処理向け               |
| SCHED_IDLE     | 通常         | 0 のみ     | 非常に低い優先度のバックグラウンド処理 |
| SCHED_FIFO     | リアルタイム | 1〜99      | 先入れ先出し、時間制限なし             |
| SCHED_RR       | リアルタイム | 1〜99      | ラウンドロビン、時間制限あり           |
| SCHED_DEADLINE | リアルタイム | なし       | デッドライン指定スケジューリング       |

### 通常ポリシー vs リアルタイムポリシー

<strong>通常ポリシー</strong>（SCHED_OTHER、SCHED_BATCH、SCHED_IDLE）

- 一般的なアプリケーション向け
- 静的優先度は 0 固定
- nice 値で優先度を調整
- CFS（Completely Fair Scheduler）が管理

<strong>リアルタイムポリシー</strong>（SCHED_FIFO、SCHED_RR、SCHED_DEADLINE）

- 確定的な応答時間が必要なアプリケーション向け
- 静的優先度 1〜99（数値が大きいほど高優先度）
- 通常プロセスより常に優先される
- 設定には特権（CAP_SYS_NICE）が必要

### 現在のポリシーを確認する

`chrt` コマンドで現在のプロセスのポリシーを確認できます

```bash
chrt -p $$
```

出力例：

```
pid 12345's current scheduling policy: SCHED_OTHER
pid 12345's current scheduling priority: 0
```

### 利用可能なポリシーを確認する

```bash
chrt -m
```

出力例：

```
SCHED_OTHER min/max priority    : 0/0
SCHED_FIFO min/max priority     : 1/99
SCHED_RR min/max priority       : 1/99
SCHED_BATCH min/max priority    : 0/0
SCHED_IDLE min/max priority     : 0/0
SCHED_DEADLINE min/max priority : 0/0
```

---

## nice 値と優先度

### nice 値とは

<strong>nice 値</strong>は、通常プロセス（SCHED_OTHER など）の優先度を調整する値です

nice 値は、スケジューリング決定においてプロセスの優先度を調整する属性です

値が低いほど優先度が高く、より多くの CPU 時間を得られます

### nice 値の範囲

nice 値は -20 から +19 の範囲です

| nice 値 | 意味                                  |
| ------- | ------------------------------------- |
| -20     | 最も高い優先度（最も「nice でない」） |
| 0       | デフォルト                            |
| +19     | 最も低い優先度（最も「nice」）        |

名前の由来は、nice 値が高いプロセスは他のプロセスに CPU を譲る「お人好し」だからです

### nice 値と CPU 時間の関係

nice 値が 1 違うと、CPU 時間の配分比率は約 1.25 倍変わります

たとえば、nice 値 0 のプロセス A と nice 値 5 のプロセス B が CPU を取り合う場合：

- プロセス A（nice 0）：約 75% の CPU 時間
- プロセス B（nice 5）：約 25% の CPU 時間

プロセス A はプロセス B の<strong>約 3 倍</strong>の CPU 時間を得ます（1.25^5 ≒ 3.05）

### nice 値の確認方法

<strong>ps コマンドで確認</strong>

```bash
ps -o pid,ni,comm
```

NI 列に nice 値が表示されます

<strong>/proc/[pid]/stat で確認</strong>

```bash
cat /proc/self/stat | awk '{print $19}'
```

19 番目のフィールドが nice 値です

### nice 値の変更方法

<strong>新しいプロセスを指定した nice 値で起動</strong>

```bash
nice -n 10 ./my_program
```

<strong>実行中のプロセスの nice 値を変更</strong>

```bash
renice 10 -p 12345
```

<strong>nice 値を下げる（優先度を上げる）には root 権限が必要</strong>

```bash
sudo renice -5 -p 12345
```

### 静的優先度と動的優先度

<strong>静的優先度</strong>

- リアルタイムプロセス用
- 1〜99 の範囲
- ユーザーが明示的に設定
- 変動しない

<strong>動的優先度</strong>

- 通常プロセス用
- nice 値に基づいて計算される
- スケジューラが内部的に調整することがある

---

## CFS（Completely Fair Scheduler）

### CFS とは

<strong>CFS</strong>（Completely Fair Scheduler）は、Linux 2.6.23 以降で使用されている標準スケジューラです

「完全に公平」という名前のとおり、すべてのプロセスに公平に CPU 時間を配分することを目指しています

### なぜ CFS が必要だったのか：歴史的背景

CFS を理解するには、それ以前のスケジューラの問題を知る必要があります

<strong>O(1) スケジューラの時代（Linux 2.6.0〜2.6.22）</strong>

Linux 2.6.0 から 2.6.22 まで使われていた「O(1) スケジューラ」は、プロセス数に関係なく一定時間（O(1)）で次に実行するプロセスを選択できました

しかし、いくつかの問題がありました

1. <strong>対話型プロセスの判定が難しい</strong>：キーボード入力を待つエディタと、計算を続けるコンパイラを区別するために、複雑なヒューリスティック（経験則）が必要でした

2. <strong>タイムスライスの硬直性</strong>：固定長のタイムスライスを前提とした設計のため、実行可能なプロセス数が増えると、各プロセスの実行間隔が長くなり、結果として応答性が低下しました

3. <strong>公平性の問題</strong>：nice 値の差が実際の CPU 配分にどう影響するかが予測しにくく、調整が困難でした

<strong>CFS の設計思想</strong>

CFS は、これらの問題を根本的に解決するため、固定的なタイムスライスを中心とした設計を廃止しました

代わりに、「理想的な公平」を目指すシンプルなアルゴリズムを採用しました

### CFS の基本概念

従来のスケジューラでは、固定長のタイムスライスを順番に配分していました

しかし、CFS は<strong>仮想実行時間</strong>（vruntime）という概念を導入しました

各プロセスは、実際に使用した CPU 時間に基づいて vruntime を持ちます

CPU を使うたびに vruntime が増加します

スケジューラは、vruntime が最も小さいプロセスを次に実行します

つまり、「まだあまり CPU を使っていないプロセス」が優先されます

これにより、長期的にはすべてのプロセスが同じくらいの CPU 時間を得られます

### nice 値と vruntime

nice 値は vruntime の増加速度に影響します

- nice 値が<strong>低い</strong>プロセス：vruntime がゆっくり増加 → より多くの CPU 時間を得る
- nice 値が<strong>高い</strong>プロセス：vruntime が速く増加 → より少ない CPU 時間を得る

### CFS の公平性

同じ nice 値のプロセスが 2 つある場合、それぞれに 50% ずつ CPU 時間が配分されます

nice 値が異なる場合は、前述の 1.25 倍ルールに従って配分比率が変わります

### グループスケジューリング

CFS は<strong>グループスケジューリング</strong>もサポートしています

これは、マルチユーザー環境やコンテナ環境で「ユーザー単位」や「コンテナ単位」で公平に CPU を配分したい場合に使用されます

プロセスをグループにまとめ、グループ間で公平に CPU を配分します

たとえば、ユーザー A が 100 個のプロセスを、ユーザー B が 1 個のプロセスを実行している場合：

- グループスケジューリングなし：A が 99%、B が 1% の CPU を使用
- グループスケジューリングあり：A と B がそれぞれ 50% の CPU を使用

---

## リアルタイムスケジューリング

### リアルタイムとは

<strong>リアルタイムスケジューリング</strong>は、<strong>確定的な応答時間</strong>が必要なアプリケーション向けです

「確定的」とは、「一定時間内に必ず処理が開始される」ことを保証できるという意味です

通常のスケジューリングでは、他のプロセスの状況によって実行開始までの時間が変動しますが、リアルタイムスケジューリングでは優先度が高いプロセスが確実に先に実行されます

### なぜリアルタイムが必要なのか：音声処理の例

音声処理を例に、リアルタイムスケジューリングの必要性を考えてみましょう

<strong>音声再生の仕組み</strong>

1. アプリケーションが音声データをサウンドカードのバッファに書き込む
2. サウンドカードがバッファからデータを読み取り、スピーカーに出力
3. バッファが空になる前に、次のデータを書き込む必要がある

<strong>レイテンシ要件</strong>

一般的なサウンドカードのバッファは 10〜50 ミリ秒程度です

例えば、バッファサイズが 20 ミリ秒の場合、アプリケーションは 20 ミリ秒以内に次のデータを書き込まなければなりません

もしスケジューラがアプリケーションを 20 ミリ秒以上待たせると、バッファが空になり「音飛び」や「プチプチ」というノイズが発生します

<strong>通常のスケジューリングの問題</strong>

通常のスケジューリング（CFS）では、他のプロセスが多い場合、音声処理アプリケーションが実行されるまでに 100 ミリ秒以上かかることがあります

これでは安定した音声再生ができません

<strong>リアルタイムスケジューリングの解決策</strong>

リアルタイムスケジューリングを使用すると、音声処理アプリケーションは他のプロセスより優先的に実行されます

これにより、「最大でも数ミリ秒以内に実行される」という確定的な動作が保証されます

JACK（音楽制作用オーディオサーバー）や PulseAudio などの音声システムは、リアルタイムスケジューリングを活用しています

### SCHED_FIFO

<strong>SCHED_FIFO</strong>（First In, First Out）は、以下の特徴を持ちます

- 時間制限がない（自発的に CPU を譲るまで実行し続ける）
- 同じ優先度のプロセス間では、先に実行可能になったものが優先
- より高い優先度のプロセスにはプリエンプトされる

### SCHED_RR

<strong>SCHED_RR</strong>（Round Robin）は、SCHED_FIFO に時間制限を追加したものです

- 一定時間（タイムスライス）ごとに同じ優先度の次のプロセスに切り替え
- デフォルトのタイムスライスは 100 ミリ秒

```bash
cat /proc/sys/kernel/sched_rr_timeslice_ms
```

### リアルタイム優先度

リアルタイムポリシーでは、静的優先度を 1〜99 の範囲で設定します

数値が大きいほど優先度が高くなります

| 優先度 | 説明                                                   |
| ------ | ------------------------------------------------------ |
| 99     | 最高優先度（カーネルスレッド用に予約されることが多い） |
| 50     | 中程度の優先度                                         |
| 1      | 最低のリアルタイム優先度                               |

### リアルタイムプロセスの設定

リアルタイムポリシーを設定するには、CAP_SYS_NICE ケーパビリティが必要です

```bash
# SCHED_FIFO、優先度 50 で実行
sudo chrt -f 50 ./my_program

# 実行中のプロセスを SCHED_RR、優先度 30 に変更
sudo chrt -r -p 30 12345
```

### RT スロットリング

リアルタイムプロセスが暴走すると、システム全体が応答不能になる可能性があります

<strong>システム応答不能の具体例</strong>

以下のコードを SCHED_FIFO で実行したとします

```c
while (1) {
    /* 無限ループ */
}
```

リアルタイムプロセスは通常プロセスより常に優先されるため、このプロセスが CPU を完全に占有します

その結果

- SSH でリモート接続しても、シェルのプロセスが実行されない
- キーボードから Ctrl+C を押しても、シグナル処理のプロセスが実行されない
- `kill` コマンドを実行しても、kill コマンド自体が実行されない

物理的に電源を切るか、RT スロットリングがなければ復旧できなくなります

<strong>RT スロットリングによる保護</strong>

Linux には<strong>RT スロットリング</strong>という安全機構があります

```bash
# RT 期間（マイクロ秒）
cat /proc/sys/kernel/sched_rt_period_us
# デフォルト：1000000（1 秒）

# RT ランタイム（マイクロ秒）
cat /proc/sys/kernel/sched_rt_runtime_us
# デフォルト：950000（0.95 秒）
```

これにより、リアルタイムプロセスは 1 秒あたり最大 0.95 秒しか CPU を使用できません

残りの 0.05 秒は通常プロセスに確保されます

この 0.05 秒の間に、SSH や kill コマンドなどの通常プロセスが実行されるため、システムの復旧が可能です

---

## /proc でスケジューリング情報を観察

### /proc/[pid]/sched

`/proc/[pid]/sched` には、プロセスの詳細なスケジューリング統計が含まれています

```bash
cat /proc/self/sched
```

主要なフィールド：

| フィールド              | 説明                           |
| ----------------------- | ------------------------------ |
| se.vruntime             | 仮想実行時間                   |
| policy                  | スケジューリングポリシー       |
| prio                    | 優先度                         |
| nr_switches             | コンテキストスイッチの総数     |
| nr_voluntary_switches   | 自発的なコンテキストスイッチ   |
| nr_involuntary_switches | 非自発的なコンテキストスイッチ |

<strong>自発的なコンテキストスイッチ</strong>は、プロセスが I/O 待ちやスリープなどで自ら CPU を譲った場合に発生します

<strong>非自発的なコンテキストスイッチ</strong>は、タイムスライスを使い切った場合や、より高い優先度のプロセスに横取り（プリエンプト）された場合に発生します

### /proc/[pid]/schedstat

`/proc/[pid]/schedstat` は、簡潔なスケジューリング統計を提供します

```bash
cat /proc/self/schedstat
```

3 つの値がスペース区切りで表示されます

| 位置 | 意味                                 |
| ---- | ------------------------------------ |
| 1    | 実行時間（ナノ秒）                   |
| 2    | 実行可能キューで待った時間（ナノ秒） |
| 3    | 実行された回数（タイムスライス数）   |

### /proc/[pid]/stat のスケジューリング関連フィールド

`/proc/[pid]/stat` には、スケジューリングに関連するフィールドがあります

| 位置 | フィールド | 説明                     |
| ---- | ---------- | ------------------------ |
| 18   | priority   | カーネル内部の優先度     |
| 19   | nice       | nice 値                  |
| 41   | policy     | スケジューリングポリシー |

```bash
# nice 値を表示
cat /proc/self/stat | awk '{print "nice:", $19}'

# ポリシーを表示
cat /proc/self/stat | awk '{print "policy:", $41}'
```

### /proc/loadavg

`/proc/loadavg` は、システム全体の負荷を表示します

```bash
cat /proc/loadavg
```

出力例：

```
0.25 0.18 0.12 1/128 12345
```

| 位置 | 意味                           |
| ---- | ------------------------------ |
| 1    | 1 分間のロードアベレージ       |
| 2    | 5 分間のロードアベレージ       |
| 3    | 15 分間のロードアベレージ      |
| 4    | 実行中/総プロセス数            |
| 5    | 最後に作成されたプロセスの PID |

<strong>ロードアベレージ</strong>は、実行可能状態（R）または割り込み不可能なスリープ状態（D、通常は I/O 待ち）にあるプロセス数の時間平均です

Linux ではこの両方を含めるため、ディスク I/O 負荷が高い場合もロードアベレージが上昇します

CPU コア数と比較して解釈します

- ロードアベレージ < CPU コア数：余裕がある
- ロードアベレージ = CPU コア数：フル稼働
- ロードアベレージ > CPU コア数：過負荷

### /proc/stat の CPU 時間

`/proc/stat` には、CPU 時間の内訳が含まれています

```bash
cat /proc/stat | head -1
```

出力例：

```
cpu  12345 6789 54321 987654 1234 567 89 0 0 0
```

| フィールド | 意味                                                                |
| ---------- | ------------------------------------------------------------------- |
| user       | ユーザー空間での実行時間                                            |
| nice       | nice 値が正のプロセスの実行時間                                     |
| system     | カーネル空間での実行時間                                            |
| idle       | アイドル時間                                                        |
| iowait     | I/O 待ち時間                                                        |
| irq        | ハードウェア割り込み処理時間                                        |
| softirq    | ソフトウェア割り込み処理時間                                        |
| steal      | 仮想化環境（VMware, VirtualBox など）で他の仮想マシンに取られた時間 |

### ps コマンドでスケジューリング情報を確認

```bash
ps -eo pid,ni,pri,rtprio,cls,comm --sort=-ni | head -20
```

| 列     | 説明                   |
| ------ | ---------------------- |
| PID    | プロセス ID            |
| NI     | nice 値                |
| PRI    | 優先度                 |
| RTPRIO | リアルタイム優先度     |
| CLS    | スケジューリングクラス |
| COMM   | コマンド名             |

CLS 列の値：

| 値  | 意味           |
| --- | -------------- |
| TS  | SCHED_OTHER    |
| FF  | SCHED_FIFO     |
| RR  | SCHED_RR       |
| B   | SCHED_BATCH    |
| IDL | SCHED_IDLE     |
| DLN | SCHED_DEADLINE |

---

## CPU アフィニティ

### CPU アフィニティとは

<strong>CPU アフィニティ</strong>は、プロセスを特定の CPU コアに割り当てる設定です

デフォルトでは、プロセスはどの CPU でも実行できます

CPU アフィニティを設定すると、指定した CPU でのみ実行されます

### なぜ CPU アフィニティを使うのか

<strong>キャッシュ局所性</strong>

CPU には<strong>キャッシュ</strong>と呼ばれる高速な一時記憶領域があり、最近アクセスしたデータを保持しています

<strong>キャッシュはコアごとに専有</strong>されています（L1、L2 キャッシュは各コア専用、L3 キャッシュは複数コアで共有）

プロセスが同じ CPU で実行され続けると、このキャッシュを有効活用できます

逆に、プロセスが別の CPU に移動すると、新しい CPU のキャッシュには必要なデータがないため、メモリからデータを読み込む必要があります

これを<strong>キャッシュミス</strong>と呼び、パフォーマンスが低下します

<strong>NUMA 環境での重要性</strong>

大規模なサーバーでは、<strong>NUMA（Non-Uniform Memory Access）</strong>アーキテクチャが使われることがあります

NUMA では、各 CPU が「ローカルメモリ」を持ち、他の CPU のメモリ（「リモートメモリ」）へのアクセスはローカルメモリより遅くなります

```
[CPU 0] --- [ローカルメモリ 0]
    │
    └─── 遅いリンク ───┐
                       │
[CPU 1] --- [ローカルメモリ 1]
```

NUMA 環境では、プロセスを特定の CPU に固定し、そのローカルメモリを使用することで、パフォーマンスを最大化できます

CPU アフィニティを適切に設定しないと、プロセスが頻繁に別の CPU に移動し、リモートメモリへのアクセスが増加してパフォーマンスが低下します

CPU 間を移動すると、移動先の CPU にはそのプロセスのデータがキャッシュされていないため、メインメモリから再読み込みが必要になります

<strong>リソース分離</strong>

特定のプロセスを特定の CPU に固定し、他のプロセスと干渉しないようにできます

### CPU アフィニティの確認

<strong>/proc/[pid]/status で確認</strong>

```bash
cat /proc/self/status | grep Cpus_allowed
```

出力例：

```
Cpus_allowed:   f
Cpus_allowed_list:      0-3
```

- Cpus_allowed：16 進数のビットマスク（各ビットが CPU に対応、f = 1111 = CPU 0〜3 が許可）
- Cpus_allowed_list：許可された CPU のリスト

<strong>taskset コマンドで確認</strong>

```bash
taskset -p $$
```

出力例：

```
pid 12345's current affinity mask: f
```

### CPU アフィニティの設定

<strong>新しいプロセスを特定の CPU で起動</strong>

```bash
# CPU 0 と 1 でのみ実行
taskset -c 0,1 ./my_program

# ビットマスクで指定（0x3 = CPU 0 と 1）
taskset 0x3 ./my_program
```

<strong>実行中のプロセスの CPU アフィニティを変更</strong>

```bash
taskset -p -c 0,1 12345
```

### システムの CPU 情報

```bash
# CPU 数を確認
nproc

# 詳細な CPU 情報
cat /proc/cpuinfo | grep "processor"

# CPU のトポロジー
lscpu
```

---

## カーネルパラメータ

### スケジューラ関連のカーネルパラメータ

`/proc/sys/kernel/` 以下にスケジューラの動作を調整するパラメータがあります

### RT スロットリングパラメータ

| パラメータ          | デフォルト値 | 説明                                  |
| ------------------- | ------------ | ------------------------------------- |
| sched_rt_period_us  | 1000000      | RT スロットリングの期間（マイクロ秒） |
| sched_rt_runtime_us | 950000       | 期間内の最大 RT 実行時間              |

```bash
# RT スロットリングを無効化（危険）
echo -1 | sudo tee /proc/sys/kernel/sched_rt_runtime_us
```

### SCHED_RR タイムスライス

```bash
# ラウンドロビンのタイムスライス（ミリ秒）
cat /proc/sys/kernel/sched_rr_timeslice_ms
# デフォルト：100
```

### その他のパラメータ

| パラメータ              | 説明                                       |
| ----------------------- | ------------------------------------------ |
| sched_child_runs_first  | fork 後に子プロセスを先に実行するか        |
| sched_autogroup_enabled | 自動グループスケジューリングを有効にするか |

```bash
# 自動グループスケジューリングの状態を確認
cat /proc/sys/kernel/sched_autogroup_enabled
```

---

## 用語集

| 用語                         | 英語                      | 説明                                                                                                           |
| ---------------------------- | ------------------------- | -------------------------------------------------------------------------------------------------------------- |
| スケジューラ                 | Scheduler                 | CPU 時間を配分するカーネルコンポーネント                                                                       |
| スケジューリングポリシー     | Scheduling Policy         | プロセスの実行順序を決定するルール                                                                             |
| nice 値                      | Nice Value                | 通常プロセスの優先度を調整する値（-20 から +19）                                                               |
| 優先度                       | Priority                  | スケジューラがプロセスを選択する基準                                                                           |
| 静的優先度                   | Static Priority           | リアルタイムプロセスの固定優先度（1〜99）                                                                      |
| 動的優先度                   | Dynamic Priority          | nice 値に基づいて変動する優先度                                                                                |
| タイムスライス               | Time Slice                | プロセスに割り当てられる CPU 時間の単位                                                                        |
| プリエンプション             | Preemption                | 実行中のプロセスを中断して別のプロセスを実行すること                                                           |
| CFS                          | Completely Fair Scheduler | Linux の標準スケジューラ                                                                                       |
| vruntime                     | Virtual Runtime           | CFS が使用する仮想実行時間                                                                                     |
| リアルタイムスケジューリング | Real-time Scheduling      | 確定的な応答時間を保証するスケジューリング                                                                     |
| CPU アフィニティ             | CPU Affinity              | プロセスを特定の CPU に割り当てる設定                                                                          |
| ロードアベレージ             | Load Average              | 実行可能状態または I/O 待ち状態のプロセス数の時間平均                                                          |
| コンテキストスイッチ         | Context Switch            | 実行中のプロセスの状態（レジスタ、プログラムカウンタなど）を保存し、次のプロセスの状態を復元して切り替えること |
| 実行可能キュー               | Run Queue                 | CPU を待っているプロセスのキュー                                                                               |
| RT スロットリング            | RT Throttling             | リアルタイムプロセスの CPU 使用率を制限する機構                                                                |

---

## 参考資料

このページの内容は、以下のソースに基づいています

<strong>スケジューリング概要</strong>

- [sched(7) - Linux manual page](https://man7.org/linux/man-pages/man7/sched.7.html)
  - スケジューリングポリシーと優先度の概要

<strong>nice 値と優先度</strong>

- [nice(2) - Linux manual page](https://man7.org/linux/man-pages/man2/nice.2.html)
  - nice 値の変更
- [setpriority(2) - Linux manual page](https://man7.org/linux/man-pages/man2/setpriority.2.html)
  - 優先度の取得と設定
- [getpriority(2) - Linux manual page](https://man7.org/linux/man-pages/man2/getpriority.2.html)
  - 優先度の取得

<strong>スケジューリングポリシーの設定</strong>

- [sched_setscheduler(2) - Linux manual page](https://man7.org/linux/man-pages/man2/sched_setscheduler.2.html)
  - スケジューリングポリシーの設定
- [sched_getscheduler(2) - Linux manual page](https://man7.org/linux/man-pages/man2/sched_getscheduler.2.html)
  - スケジューリングポリシーの取得

<strong>CPU アフィニティ</strong>

- [sched_setaffinity(2) - Linux manual page](https://man7.org/linux/man-pages/man2/sched_setaffinity.2.html)
  - CPU アフィニティの設定
- [sched_getaffinity(2) - Linux manual page](https://man7.org/linux/man-pages/man2/sched_getaffinity.2.html)
  - CPU アフィニティの取得

<strong>疑似ファイルシステム</strong>

- [proc(5) - Linux manual page](https://man7.org/linux/man-pages/man5/proc.5.html)
  - /proc/[pid]/sched、/proc/[pid]/schedstat、/proc/loadavg

---

## 次のステップ

このトピックでは、カーネルがプロセスに CPU 時間を配分する仕組みを学びました

- スケジューリングポリシーの種類と使い分け
- nice 値による優先度調整
- CFS による公平な CPU 配分
- リアルタイムスケジューリングの概念

しかし、1 つ疑問が残ります

複数のプロセスが「別々のシステム」として動作するには、どうすればよいのでしょうか？

コンテナ技術では、プロセスは自分が独立したシステムで動いているかのように振る舞います

次の [06-namespace](./06-namespace.md) では、プロセスを「隔離」する仕組みを学びます

- namespace とは何か
- PID namespace：プロセス ID の隔離
- Mount namespace：ファイルシステムの隔離
- Network namespace：ネットワークの隔離
- コンテナ技術との関係

これらの疑問に答えます
