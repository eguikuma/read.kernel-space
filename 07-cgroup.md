<div align="right">
<img src="https://img.shields.io/badge/AI-ASSISTED_STUDY-3b82f6?style=for-the-badge&labelColor=1e293b&logo=bookstack&logoColor=white" alt="AI Assisted Study" />
</div>

# 07-cgroup：リソースの制限

## はじめに

[06-namespace](./06-namespace.md) では、プロセスを隔離する namespace の仕組みを学びました

- Linux namespace（PID、Mount、Network、UTS、IPC、User、Cgroup）
- 各 namespace が隔離するリソース
- /proc/[pid]/ns/ での namespace の観察
- unshare、nsenter コマンドによる namespace の操作
- コンテナ技術との関係

しかし、1 つ疑問が残ります

隔離されたプロセスが、CPU やメモリを独占しないようにするにはどうすればよいのでしょうか？

namespace は「見え方」を隔離しますが、「使用量」を制限しません

あるコンテナがメモリを使い果たせば、ホストシステム全体に影響を与えます

あるコンテナが CPU を独占すれば、他のコンテナの処理が遅くなります

このページでは、その問題を解決する仕組みを学びます

<strong>cgroup</strong>（Control Group）は、プロセスグループのリソース使用量を制限・管理するカーネル機能です

cgroup を使うと、プロセスが使用できる CPU 時間、メモリ量、I/O 帯域幅などに上限を設けることができます

### 日常の例え

cgroup を「ホテルのリソース管理」に例えてみましょう

<strong>ホテル（ホストシステム）</strong>には、複数のツアーグループ（プロセス群）が宿泊しています

<strong>namespace</strong>は「部屋割り」です

- 各グループは別々のフロアに滞在し、互いのエリアには入れません
- 自分のグループの部屋しか見えません

<strong>cgroup</strong>は「リソースの割り当て」です

- <strong>CPU コントローラ</strong>は「スタッフの対応時間」です
  - 各グループがスタッフに対応してもらえる時間に上限を設けます
  - A グループは 1 時間、B グループは 30 分、というように
- <strong>メモリコントローラ</strong>は「使える部屋数」です
  - 各グループが使用できる部屋数を制限します
  - A グループは 10 部屋まで、B グループは 5 部屋まで
- <strong>I/O コントローラ</strong>は「エレベーターの利用枠」です
  - 各グループがエレベーターを使える回数を制限します
  - 1 グループがエレベーターを独占しないように
- <strong>PID コントローラ</strong>は「参加人数の上限」です
  - 各グループの最大人数を制限します
  - 無限に人数が増えないように

このように、namespace が「どこにいるか」を隔離するのに対し、cgroup は「どれだけ使えるか」を制限します

### このページで学ぶこと

このページでは、以下の概念を学びます

- <strong>cgroup とは何か</strong>
  - リソース制限の基本概念
- <strong>cgroup v1 と cgroup v2</strong>
  - 複数階層 vs 統一階層
- <strong>主要なコントローラ</strong>
  - cpu、memory、io、pids
- <strong>CPU の制限</strong>
  - cpu.weight、cpu.max による制限
- <strong>メモリの制限</strong>
  - memory.max、memory.high、memory.low
- <strong>I/O の制限</strong>
  - io.weight、io.max
- <strong>PID の制限</strong>
  - pids.max によるプロセス数制限
- <strong>/sys/fs/cgroup での cgroup 観察</strong>
  - cgroup.procs、cgroup.controllers
- <strong>プロセスの cgroup 所属</strong>
  - /proc/[pid]/cgroup
- <strong>cgroup の操作</strong>
  - mkdir、echo による cgroup の作成とプロセスの移動
- <strong>コンテナ技術との関係</strong>
  - Docker/Kubernetes での活用

---

## 目次

1. [cgroup とは何か](#cgroup-とは何か)
2. [cgroup v1 と cgroup v2](#cgroup-v1-と-cgroup-v2)
3. [主要なコントローラ](#主要なコントローラ)
4. [CPU の制限](#cpu-の制限)
5. [メモリの制限](#メモリの制限)
6. [I/O の制限](#io-の制限)
7. [PID の制限](#pid-の制限)
8. [/sys/fs/cgroup での cgroup 観察](#sysfscgroup-での-cgroup-観察)
9. [プロセスの cgroup 所属](#プロセスの-cgroup-所属)
10. [cgroup の操作](#cgroup-の操作)
11. [コンテナ技術との関係](#コンテナ技術との関係)
12. [まとめ：このリポジトリで学んだこと](#まとめこのリポジトリで学んだこと)
13. [用語集](#用語集)
14. [参考資料](#参考資料)

---

## cgroup とは何か

### リソース制限の必要性

複数のアプリケーションを 1 台のサーバーで動かすとき、リソースの問題が発生することがあります

- アプリケーション A がメモリを使い果たし、システム全体がクラッシュする
- アプリケーション B が CPU を独占し、他のアプリケーションが応答しなくなる
- アプリケーション C が大量のプロセスを生成し、システムが停止する（これは fork bomb と呼ばれる攻撃で、プロセスが自分自身を無限にコピーし続けることでシステムリソースを枯渇させる）

これらの問題を解決するために、<strong>リソース制限</strong>が必要です

### cgroup の役割

<strong>cgroup</strong>（Control Group）は、プロセスをグループ化し、そのグループのリソース使用量を制限・管理するカーネル機能です

Linux の公式マニュアルには、こう書かれています

> Control groups, usually referred to as cgroups, are a Linux kernel feature which allow processes to be organized into hierarchical groups whose usage of various types of resources can then be limited and monitored.

> コントロールグループ（通常 cgroup と呼ばれる）は、プロセスを階層的なグループに編成し、さまざまな種類のリソースの使用を制限および監視できる Linux カーネル機能です

### cgroup の特徴

cgroup には以下の特徴があります

- <strong>階層構造</strong>：cgroup はツリー構造を形成し、子は親の制限を継承する
- <strong>コントローラ</strong>：リソースの種類ごとに独立したコントローラがある
- <strong>動的変更</strong>：実行中のプロセスの制限を動的に変更できる
- <strong>カーネル機能</strong>：ユーザー空間のプログラムではなく、カーネルが直接提供する

### cgroup vs ulimit

従来からある `ulimit` コマンドとの違いを確認しましょう

| 特性         | cgroup                           | ulimit                 |
| ------------ | -------------------------------- | ---------------------- |
| 対象         | プロセスグループ                 | 単一プロセス           |
| 継承         | 階層構造で制限を継承             | 子プロセスに継承       |
| リソース種類 | CPU、メモリ、I/O、プロセス数など | ファイル数、メモリなど |
| 設定方法     | ファイルシステム経由             | シェルコマンド         |
| 動的変更     | 可能                             | 制限あり               |

cgroup は、ulimit よりも柔軟で強力なリソース制限を提供します

---

## cgroup v1 と cgroup v2

### cgroup の歴史

cgroup は 2 つのバージョンが存在します

- <strong>cgroup v1</strong>：Linux 2.6.24 で導入
- <strong>cgroup v2</strong>：Linux 4.5 で導入、Linux 5.0 以降で本格運用

### cgroup v1 の特徴

cgroup v1 では、各コントローラが独自の階層（ツリー）を持ちます

```
/sys/fs/cgroup/
├── cpu/           # CPU コントローラの階層
│   ├── group_a/
│   └── group_b/
├── memory/        # メモリコントローラの階層
│   ├── group_a/
│   └── group_c/
└── pids/          # PID コントローラの階層
    └── group_a/
```

この設計には問題がありました

- 同じ名前のグループでも、コントローラごとに別の実体
- プロセスを複数のグループに同時に配置できるため、管理が複雑
- コントローラ間の連携が困難

### cgroup v2 の特徴

cgroup v2 では、すべてのコントローラが<strong>統一階層</strong>（unified hierarchy）を共有します

```
/sys/fs/cgroup/
├── cgroup.controllers    # 利用可能なコントローラ
├── cgroup.procs         # ルート cgroup のプロセス
├── group_a/             # グループ A
│   ├── cgroup.procs
│   ├── cpu.max
│   └── memory.max
└── group_b/             # グループ B
    ├── cgroup.procs
    ├── cpu.max
    └── memory.max
```

Linux の公式カーネルドキュメントには、こう書かれています

> cgroup v2 has a single unified hierarchy.

> cgroup v2 は単一の統一された階層を持ちます

### v1 と v2 の比較

| 特性             | cgroup v1                  | cgroup v2                |
| ---------------- | -------------------------- | ------------------------ |
| 階層構造         | コントローラごとに複数階層 | 統一された単一階層       |
| 導入バージョン   | Linux 2.6.24               | Linux 4.5                |
| プロセス配置     | 内部ノードにも配置可能     | 原則リーフノードのみ     |
| スレッド制御     | スレッドごとに異なる配置   | プロセス単位（例外あり） |
| コントローラ連携 | 困難                       | 容易                     |

### No Internal Processes ルール

cgroup v2 には重要なルールがあります

> A cgroup can't both have member processes and have child cgroups.

> cgroup は、メンバープロセスと子 cgroup の両方を同時に持つことはできません

これは「No Internal Processes」ルールと呼ばれます

```
良い例：
/sys/fs/cgroup/
├── cgroup.procs          # プロセスなし
└── group_a/              # 子 cgroup
    └── cgroup.procs      # プロセスはここに配置

悪い例（エラーになる）：
/sys/fs/cgroup/
├── cgroup.procs          # プロセスあり ← NG
└── group_a/              # 子 cgroup もある
```

このルールにより、リソース配分がシンプルになります

<strong>もしこのルールがなかったら？</strong>

cgroup v1 ではこのルールがなく、親 cgroup と子 cgroup の両方にプロセスを配置できました

その結果、以下のような混乱が生じていました

<strong>問題 1：リソース計算の曖昧さ</strong>

親 cgroup に 500MB、子 cgroup に 300MB のメモリ制限を設定した場合：

- 親のプロセスは何 MB 使えるのか？（500MB 全体？500-300=200MB？）
- 子のプロセスと親のプロセスが競合したらどうなるのか？
- 親のメモリ使用量に、子のメモリ使用量は含まれるのか？

<strong>問題 2：管理の複雑化</strong>

cgroup の階層構造を変更するとき、プロセスがどこにいるかを追跡するのが困難でした

例えば、「子 cgroup を削除したい」とき、その前に子のプロセスをどこに移動すべきか判断が必要でした

<strong>cgroup v2 の解決策</strong>

cgroup v2 では「プロセスは末端（リーフ）の cgroup にのみ配置」というルールを導入しました

これにより

- リソース計算が明確になる（リーフのプロセスの合計が親の制限を超えないように管理）
- 階層構造の管理が簡単になる
- コントローラ間の連携が容易になる

### 現在の推奨

現代のシステムでは cgroup v2 が推奨されています

- systemd は cgroup v2 をデフォルトで使用
- Docker は cgroup v2 をサポート
- Kubernetes は cgroup v2 をサポート

このページでは、主に cgroup v2 を扱います

---

## 主要なコントローラ

### コントローラとは

<strong>コントローラ</strong>は、特定の種類のリソースを制限・管理するカーネルコンポーネントです

cgroup v2 では、以下のコントローラが利用可能です

表に含まれる専門用語について先に説明します

- <strong>NUMA ノード</strong>：マルチプロセッサシステムで、CPU とメモリの配置を表す単位、CPU は近くのメモリに高速アクセスできるため、どの NUMA ノードを使うかがパフォーマンスに影響します
- <strong>HugeTLB ページ</strong>：通常より大きなサイズ（2MB や 1GB）のメモリページで、大量のメモリを使うアプリケーションでアドレス変換のオーバーヘッドを削減できます

| コントローラ | 説明                     | 制限対象                          |
| ------------ | ------------------------ | --------------------------------- |
| cpu          | CPU 時間の配分           | プロセスが使用できる CPU 時間     |
| cpuset       | CPU とメモリノードの固定 | 使用できる CPU コアと NUMA ノード |
| memory       | メモリ使用量             | 物理メモリとスワップ              |
| io           | I/O 帯域幅               | ブロックデバイスの読み書き速度    |
| pids         | プロセス数               | 作成できるプロセスの最大数        |
| hugetlb      | HugeTLB ページ           | HugeTLB ページの使用量            |

このページでは、cpu、memory、io、pids の 4 つのコントローラを中心に扱います

### 利用可能なコントローラの確認

システムで利用可能なコントローラを確認できます

```bash
cat /sys/fs/cgroup/cgroup.controllers
```

出力例：

```
cpuset cpu io memory hugetlb pids rdma misc
```

### 子 cgroup で有効なコントローラ

子 cgroup で使用するコントローラは、親で有効化する必要があります

```bash
cat /sys/fs/cgroup/cgroup.subtree_control
```

出力例：

```
cpu memory pids
```

この例では、子 cgroup で cpu、memory、pids コントローラが使用可能です

---

## CPU の制限

### CPU コントローラの役割

<strong>cpu コントローラ</strong>は、プロセスグループが使用できる CPU 時間を制限します

2 つの制限方式があります

- <strong>cpu.weight</strong>：他のグループとの相対的な CPU 配分
- <strong>cpu.max</strong>：絶対的な CPU 帯域幅の上限

### cpu.weight による配分

cpu.weight は、CPU 時間の配分比率を設定します

Linux のカーネルドキュメントには、こう書かれています

> cpu.weight: A read-write single value file which exists on non-root cgroups. The default is "100".

> cpu.weight：非ルート cgroup に存在する単一の読み書き可能な値です
>
> デフォルトは「100」です

設定可能な値は 1 から 10000 です

```bash
# グループ A の weight を 200 に設定
echo 200 > /sys/fs/cgroup/group_a/cpu.weight

# グループ B の weight を 100 に設定（デフォルト）
echo 100 > /sys/fs/cgroup/group_b/cpu.weight
```

この場合、CPU が競合したとき、グループ A はグループ B の 2 倍の CPU 時間を得ます

### cpu.max による帯域幅制限

cpu.max は、CPU 帯域幅の絶対的な上限を設定します

形式は `$MAX $PERIOD` です

```
$MAX    ：期間内に使用できる最大マイクロ秒
$PERIOD ：期間の長さ（マイクロ秒、デフォルト 100000 = 100ms）
```

```bash
# 100ms あたり 50ms まで（50% の CPU 使用率）
echo "50000 100000" > /sys/fs/cgroup/group_a/cpu.max

# 無制限に戻す
echo "max 100000" > /sys/fs/cgroup/group_a/cpu.max
```

### CPU 統計の確認

cpu.stat で CPU 使用統計を確認できます

```bash
cat /sys/fs/cgroup/cpu.stat
```

出力例：

```
usage_usec 123456789
user_usec 100000000
system_usec 23456789
nr_periods 12345
nr_throttled 100
throttled_usec 5000000
```

cpu.max が設定されている場合、プロセスが上限に達すると<strong>スロットリング</strong>（throttling：リソースの使用制限を超えた場合に、カーネルがプロセスの処理速度を意図的に落とすこと）が発生します

| 項目           | 説明                                |
| -------------- | ----------------------------------- |
| usage_usec     | 総 CPU 使用時間（マイクロ秒）       |
| user_usec      | ユーザー空間での CPU 使用時間       |
| system_usec    | カーネル空間での CPU 使用時間       |
| nr_periods     | 期間の総数（※）                     |
| nr_throttled   | スロットリングされた期間の数（※）   |
| throttled_usec | スロットリングされた時間の合計（※） |

※ nr_periods、nr_throttled、throttled_usec は cpu.max が設定されている場合のみ表示されます（nr_throttled が大きい場合、プロセスが頻繁に制限に達していることを示す）

### weight と max の使い分け

| 方式       | 用途                                        |
| ---------- | ------------------------------------------- |
| cpu.weight | 公平な CPU 配分（CPU が余っていれば使える） |
| cpu.max    | 厳密な CPU 上限（余っていても使えない）     |

<strong>実務での選択基準</strong>

| シナリオ                     | 推奨設定                       | 理由                                 |
| ---------------------------- | ------------------------------ | ------------------------------------ |
| バッチ処理（夜間ジョブなど） | cpu.weight のみ                | CPU が空いていれば全部使いたい       |
| マルチテナント環境           | cpu.max のみ                   | 他のテナントへの影響を確実に防ぎたい |
| 一般的なコンテナ             | 両方を組み合わせ               | 最低保証と上限の両方を設定           |
| レイテンシ重視のサービス     | cpu.weight 高め + cpu.max なし | 応答時間を優先、リソースをフル活用   |
| コスト管理が重要             | cpu.max のみ                   | 使用量を予測可能にしたい             |

<strong>組み合わせの例</strong>

```bash
# Web サーバー：最低保証 + 上限
echo 150 > /sys/fs/cgroup/web/cpu.weight   # 他より優先
echo "100000 100000" > /sys/fs/cgroup/web/cpu.max  # 1 CPU まで

# バッチ処理：低優先度、上限なし
echo 50 > /sys/fs/cgroup/batch/cpu.weight  # 他より低優先
# cpu.max は設定しない（CPU が空いていれば使える）
```

コンテナでは、両方を組み合わせることが多いです

---

## メモリの制限

### memory コントローラの役割

<strong>memory コントローラ</strong>は、プロセスグループが使用できるメモリ量を制限します

4 つの制限レベルがあります

| 設定        | 役割                                   |
| ----------- | -------------------------------------- |
| memory.min  | 絶対保護（この量は奪われない）         |
| memory.low  | ソフト保護（メモリ不足時のみ奪われる） |
| memory.high | ソフト制限（超過時スロットリング）     |
| memory.max  | ハード制限（超過時 OOM キラー発動）    |

### memory.max（ハード制限）

memory.max は、メモリ使用量の絶対的な上限です

Linux のカーネルドキュメントには、こう書かれています

> memory.max: A read-write single value file which exists on non-root cgroups. The default is "max".

> memory.max：非ルート cgroup に存在する単一の読み書き可能な値です
>
> デフォルトは「max」（無制限）です

```bash
# メモリ上限を 512MB に設定
echo 536870912 > /sys/fs/cgroup/group_a/memory.max

# メモリ上限を 1GB に設定
echo 1073741824 > /sys/fs/cgroup/group_a/memory.max
```

memory.max を超えてメモリを確保しようとすると、<strong>OOM キラー</strong>（Out-of-Memory Killer）が発動し、プロセスが強制終了されます

OOM キラーとは、メモリ不足時にシステム全体を守るため、プロセスを強制終了するカーネルの機能です

<strong>cgroup 内 OOM とシステム全体 OOM の違い</strong>

| 項目       | cgroup 内 OOM                   | システム全体 OOM                       |
| ---------- | ------------------------------- | -------------------------------------- |
| 発動条件   | cgroup の memory.max を超過     | システム全体のメモリ + スワップが枯渇  |
| 影響範囲   | その cgroup 内のプロセスのみ    | システム全体のプロセスが対象           |
| 選択基準   | cgroup 内のプロセスからのみ選択 | OOM スコアに基づいて選択               |
| 他への影響 | 他の cgroup には影響なし        | 他のプロセスも強制終了の対象になりうる |

<strong>コンテナ環境での重要性</strong>

cgroup の memory.max を適切に設定することで、1 つのコンテナがメモリを使い過ぎても、他のコンテナやホストシステムに影響を与えません

もし memory.max を設定しなければ、暴走したコンテナがシステム全体のメモリを消費し、システム全体の OOM を引き起こす可能性があります

詳細は [OOM キラーの仕組み](./appendices/oom.md) を参照してください

### memory.high（ソフト制限）

memory.high は、メモリ使用量のソフト制限です

この値を超えると、カーネルはプロセスに対して<strong>メモリ再利用</strong>を強制します

具体的には、プロセスがメモリを確保しようとするたびに、カーネルは既存のメモリページを解放させようとします

この結果、プロセスの処理速度が低下します（スロットリング）

```bash
# ソフト制限を 256MB に設定
echo 268435456 > /sys/fs/cgroup/group_a/memory.high
```

memory.high は「警告レベル」として使用できます

OOM キラーで即座に終了するのではなく、まずメモリ使用量を抑制して対応させます

### memory.low と memory.min（保護）

memory.low と memory.min は、メモリの<strong>保護</strong>を提供します

- <strong>memory.min</strong>：絶対保護（他のグループに奪われない）
- <strong>memory.low</strong>：ソフト保護（システム全体がメモリ不足の場合のみ奪われる）

```bash
# 最低でも 128MB は確保
echo 134217728 > /sys/fs/cgroup/group_a/memory.low

# 絶対に 64MB は奪われない
echo 67108764 > /sys/fs/cgroup/group_a/memory.min
```

<strong>メモリ不足時の reclaim（回収）の優先順位</strong>

システム全体でメモリが不足すると、カーネルは「メモリ回収」（reclaim）を行います

どの cgroup からメモリを回収するかは、memory.low と memory.min の設定に従います

1. <strong>memory.low も memory.min も設定されていない cgroup</strong>
   - 最優先で回収される
   - 空きメモリを作るために積極的にページを解放

2. <strong>memory.low が設定されている cgroup</strong>
   - memory.low の量までは保護される
   - それ以下になると回収対象になる
   - ただし、他に回収できる cgroup がない場合は、memory.low 以下からも回収される

3. <strong>memory.min が設定されている cgroup</strong>
   - memory.min の量は絶対に保護される
   - システム全体がどれだけメモリ不足でも、memory.min 以下からは回収されない

<strong>具体例</strong>

```
システム全体：8GB
├── group_a（memory.min=1GB、memory.low=2GB）：現在 3GB 使用
├── group_b（memory.low=1GB）：現在 2GB 使用
└── group_c（保護なし）：現在 2GB 使用
```

メモリが不足した場合

1. まず group_c から回収（保護なし）
2. 次に group_b の 1GB を超えた部分から回収
3. 次に group_a の 2GB を超えた部分から回収
4. さらに不足すれば、group_b の memory.low 以下から回収（ソフト保護が破られる）
5. group_a の memory.min（1GB）は絶対に回収されない

### 制限の階層

メモリ制限は階層的に適用されます

```
memory.min（絶対保護）
    ↓
memory.low（ソフト保護）
    ↓
（通常の使用範囲）
    ↓
memory.high（ソフト制限）
    ↓
memory.max（ハード制限）
```

### メモリ使用量の確認

```bash
# 現在のメモリ使用量
cat /sys/fs/cgroup/group_a/memory.current

# メモリ統計
cat /sys/fs/cgroup/group_a/memory.stat
```

memory.stat の主要な項目：

表中の「pgfault」は<strong>ページフォルト</strong>（プロセスがまだ物理メモリに割り当てられていないページにアクセスしたときに発生する例外）の回数を示し、カーネルはページフォルトを検知して必要なページを物理メモリに割り当てます

詳細は [03-virtual-memory](./03-virtual-memory.md) を参照してください

| 項目    | 説明                     |
| ------- | ------------------------ |
| anon    | 匿名メモリ（ヒープなど） |
| file    | ファイルキャッシュ       |
| shmem   | 共有メモリ               |
| pgfault | ページフォルト回数       |

---

## I/O の制限

### io コントローラの役割

<strong>io コントローラ</strong>は、プロセスグループのブロック I/O を制限します

2 つの制限方式があります

- <strong>io.weight</strong>：他のグループとの相対的な I/O 配分
- <strong>io.max</strong>：絶対的な I/O 帯域幅と IOPS の上限

### io.weight による配分

io.weight は、I/O の配分比率を設定します

```bash
# デフォルトの weight を 50 に設定（デフォルトは 100）
echo "default 50" > /sys/fs/cgroup/group_a/io.weight
```

### io.max による帯域幅制限

io.max は、特定のブロックデバイスに対する I/O 上限を設定します

形式は `MAJOR:MINOR [rbps=BYTES] [wbps=BYTES] [riops=NUMBER] [wiops=NUMBER]` です

| 項目  | 説明                        |
| ----- | --------------------------- |
| rbps  | 読み取り帯域幅（バイト/秒） |
| wbps  | 書き込み帯域幅（バイト/秒） |
| riops | 読み取り IOPS（操作数/秒）  |
| wiops | 書き込み IOPS（操作数/秒）  |

```bash
# デバイス 8:0 の読み取りを 10MB/s に制限
echo "8:0 rbps=10485760" > /sys/fs/cgroup/group_a/io.max

# デバイス 8:0 の読み書きを 100 IOPS に制限
echo "8:0 riops=100 wiops=100" > /sys/fs/cgroup/group_a/io.max
```

### デバイスのメジャー番号とマイナー番号の確認

io.max でデバイスを指定するには、<strong>メジャー番号</strong>と<strong>マイナー番号</strong>が必要です

これらは、カーネルがデバイスを識別するための番号です

- <strong>メジャー番号</strong>：デバイスドライバの種類を示します（例：8 は SCSI ディスク）
- <strong>マイナー番号</strong>：同じドライバ内の特定デバイスを区別します（例：0 は最初のディスク）

<strong>なぜデバイス名（/dev/sda）ではなく番号を使うのか</strong>

この設計は Unix V7 にまで遡る歴史あるものです

当時、デバイス名（/dev/sda など）は単なるシンボリックな名前であり、カーネル内部では番号でデバイスを管理していました

番号を使う理由は以下のとおりです

1. <strong>カーネル内部での効率</strong>：文字列の比較より数値の比較が高速
2. <strong>一意性の保証</strong>：デバイス名は変更できるが、同じデバイスの番号は変わらない
3. <strong>シンプルな API</strong>：カーネルとユーザー空間のインターフェースがシンプル

現代の Linux でも、udev がデバイス名を動的に割り当てますが、カーネル内部ではメジャー/マイナー番号で管理されています

```bash
# /dev/sda のメジャー番号とマイナー番号を確認
ls -l /dev/sda
# brw-rw---- 1 root disk 8, 0 Jan 31 12:00 /dev/sda
```

出力の `8, 0` がメジャー番号（8）とマイナー番号（0）です

### I/O 統計の確認

```bash
cat /sys/fs/cgroup/group_a/io.stat
```

出力例：

```
8:0 rbytes=1234567 wbytes=7654321 rios=100 wios=50
```

---

## PID の制限

### pids コントローラの役割

<strong>pids コントローラ</strong>は、プロセスグループが作成できるプロセス数を制限します

これは<strong>fork bomb</strong>（無限にプロセスを生成する攻撃）への対策として重要です

### pids.max の設定

```bash
# 最大 100 プロセスに制限
echo 100 > /sys/fs/cgroup/group_a/pids.max

# 無制限に戻す
echo max > /sys/fs/cgroup/group_a/pids.max
```

Linux のカーネルドキュメントには、こう書かれています

> pids.max: A read-write single value file which exists on non-root cgroups. The default is "max".

> pids.max：非ルート cgroup に存在する単一の読み書き可能な値です
>
> デフォルトは「max」（無制限）です

### 現在のプロセス数の確認

```bash
cat /sys/fs/cgroup/group_a/pids.current
```

### fork bomb 対策

fork bomb は、以下のようなコードで無限にプロセスを生成します

```bash
:(){ :|:& };:
```

pids.max を設定することで、fork bomb によるシステムダウンを防げます

```bash
# ユーザーあたり 500 プロセスに制限
echo 500 > /sys/fs/cgroup/user.slice/user-1000.slice/pids.max
```

---

## /sys/fs/cgroup での cgroup 観察

### cgroup ファイルシステム

cgroup は `/sys/fs/cgroup` にマウントされた疑似ファイルシステムで操作します

```bash
mount | grep cgroup
```

出力例：

```
cgroup2 on /sys/fs/cgroup type cgroup2 (rw,nosuid,nodev,noexec,relatime,nsdelegate,memory_recursiveprot)
```

`cgroup2` と表示されれば、cgroup v2 が使用されています

### ディレクトリ構造

```
/sys/fs/cgroup/
├── cgroup.controllers      # 利用可能なコントローラ
├── cgroup.max.depth        # 階層の最大深さ
├── cgroup.max.descendants  # 子孫 cgroup の最大数
├── cgroup.procs            # このグループのプロセス
├── cgroup.stat             # cgroup の統計
├── cgroup.subtree_control  # 子で有効なコントローラ
├── cgroup.threads          # このグループのスレッド
├── cpu.stat                # CPU 統計
├── io.stat                 # I/O 統計
├── memory.current          # 現在のメモリ使用量
├── memory.stat             # メモリ統計
├── pids.current            # 現在のプロセス数
├── user.slice/             # ユーザーセッション用
│   └── user-1000.slice/    # UID 1000 のユーザー
├── system.slice/           # systemd サービス用
└── docker/                 # Docker コンテナ用（Docker 使用時）
```

### 主要なファイルの役割

| ファイル               | 説明                               |
| ---------------------- | ---------------------------------- |
| cgroup.controllers     | この階層で利用可能なコントローラ   |
| cgroup.subtree_control | 子 cgroup で有効なコントローラ     |
| cgroup.procs           | この cgroup に属するプロセス ID    |
| cgroup.events          | cgroup の状態（populated、frozen） |
| cgroup.stat            | cgroup の統計情報                  |

### cgroup.events の確認

```bash
cat /sys/fs/cgroup/cgroup.events
```

出力例：

```
populated 1
frozen 0
```

| 項目      | 説明                           |
| --------- | ------------------------------ |
| populated | 1 ならプロセスが存在、0 なら空 |
| frozen    | 1 なら凍結状態、0 なら通常状態 |

<strong>凍結状態（frozen）とは</strong>

凍結状態とは、cgroup 内のすべてのプロセスが一時停止している状態です

cgroup.freeze ファイルに 1 を書き込むと、その cgroup と子孫の cgroup に属するプロセスが停止します

コンテナの一時停止（docker pause）などで使用されます

### 実際の cgroup 構造を確認

```bash
# ルート cgroup の内容
ls /sys/fs/cgroup/

# user.slice の内容
ls /sys/fs/cgroup/user.slice/

# 自分の cgroup を確認
cat /proc/self/cgroup
```

---

## プロセスの cgroup 所属

### /proc/[pid]/cgroup

各プロセスの cgroup 所属は `/proc/[pid]/cgroup` で確認できます

```bash
cat /proc/self/cgroup
```

出力例：

```
0::/user.slice/user-1000.slice/session-1.scope
```

### 形式の説明

```
階層ID:コントローラリスト:パス
```

| 項目               | cgroup v2 での値              |
| ------------------ | ----------------------------- |
| 階層ID             | 常に 0                        |
| コントローラリスト | 常に空（統一階層のため）      |
| パス               | /sys/fs/cgroup からの相対パス |

### 複数プロセスの cgroup を比較

```bash
# シェルの cgroup
cat /proc/$$/cgroup
# 0::/user.slice/user-1000.slice/session-1.scope

# systemd の cgroup
cat /proc/1/cgroup
# 0::/init.scope
```

### Docker コンテナの場合

Docker コンテナ内のプロセスは、専用の cgroup に配置されます

```bash
# コンテナの PID を取得
docker inspect --format '{{.State.Pid}}' container_name

# コンテナプロセスの cgroup を確認
cat /proc/<pid>/cgroup
# 0::/docker/abc123def456...
```

---

## cgroup の操作

### cgroup の作成

cgroup の作成は、ディレクトリを作成するだけです

```bash
# 新しい cgroup を作成
sudo mkdir /sys/fs/cgroup/mygroup
```

作成すると、自動的に制御ファイルが生成されます

```bash
ls /sys/fs/cgroup/mygroup/
# cgroup.controllers  cgroup.events  cgroup.procs  ...
```

### コントローラの有効化

子 cgroup でコントローラを使用するには、親で有効化する必要があります

```bash
# ルートで cpu と memory を有効化
echo "+cpu +memory" | sudo tee /sys/fs/cgroup/cgroup.subtree_control
```

「No Internal Processes」ルールにより、プロセスが配置されている cgroup では有効化できません

### プロセスの移動

プロセスを cgroup に移動するには、PID を cgroup.procs に書き込みます

```bash
# 現在のシェルを mygroup に移動
echo $$ | sudo tee /sys/fs/cgroup/mygroup/cgroup.procs
```

移動後、/proc/self/cgroup で確認できます

```bash
cat /proc/self/cgroup
# 0::/mygroup
```

### リソース制限の設定

```bash
# CPU を 50% に制限
echo "50000 100000" | sudo tee /sys/fs/cgroup/mygroup/cpu.max

# メモリを 256MB に制限
echo 268435456 | sudo tee /sys/fs/cgroup/mygroup/memory.max

# プロセス数を 50 に制限
echo 50 | sudo tee /sys/fs/cgroup/mygroup/pids.max
```

### cgroup の削除

cgroup を削除するには、プロセスを移動してからディレクトリを削除します

```bash
# プロセスをルートに戻す
echo $$ | sudo tee /sys/fs/cgroup/cgroup.procs

# cgroup を削除
sudo rmdir /sys/fs/cgroup/mygroup
```

プロセスが残っていると削除できません

---

## コンテナ技術との関係

### namespace と cgroup の組み合わせ

コンテナ技術は、namespace と cgroup を組み合わせて実現されています

| 技術      | 役割                       |
| --------- | -------------------------- |
| namespace | リソースの「見え方」を隔離 |
| cgroup    | リソースの「使用量」を制限 |

```
namespace（隔離）+ cgroup（制限）= コンテナ
```

### コンテナが使用する主な技術

| 要素     | namespace の役割           | cgroup の役割      |
| -------- | -------------------------- | ------------------ |
| PID      | プロセス ID を隔離         | プロセス数を制限   |
| メモリ   | -                          | メモリ使用量を制限 |
| CPU      | -                          | CPU 時間を制限     |
| ネット   | ネットワークスタックを隔離 | -                  |
| ファイル | マウントポイントを隔離     | I/O 帯域幅を制限   |
| ユーザー | UID/GID を隔離             | -                  |

### Docker でのリソース制限

Docker は cgroup を使ってリソース制限を実装しています

```bash
# メモリを 512MB に制限
docker run --memory 512m nginx

# CPU を 0.5 コア相当に制限
docker run --cpus 0.5 nginx

# プロセス数を 100 に制限
docker run --pids-limit 100 nginx
```

これらのオプションは、内部的に cgroup ファイルに書き込まれます

| Docker オプション | cgroup ファイル |
| ----------------- | --------------- |
| --memory 512m     | memory.max      |
| --cpus 0.5        | cpu.max         |
| --pids-limit 100  | pids.max        |

### Docker コンテナの cgroup を確認

```bash
# コンテナの cgroup パスを確認
docker inspect --format '{{.HostConfig.CgroupParent}}' container_name

# コンテナの cgroup 制限を確認
cat /sys/fs/cgroup/docker/<container_id>/memory.max
```

### Kubernetes でのリソース制限

Kubernetes の Pod 定義でもリソース制限を設定できます

```yaml
resources:
  limits: # これ以上は使えない上限値
    memory: "512Mi"
    cpu: "500m"
  requests: # 最低限確保したい値（スケジューリング時に使用）
    memory: "256Mi"
    cpu: "250m"
```

- <strong>limits</strong>：これ以上は使えない上限値（超えるとプロセスが強制終了されることがある）
- <strong>requests</strong>：最低限確保したい値（Kubernetes がどのノードに配置するか決める際に使用）

これらも内部的に cgroup を使用しています

---

## まとめ：このリポジトリで学んだこと

このリポジトリでは、「カーネルがどう動いているか」を学びました

### 学んだトピック

| トピック              | 内容                   |
| --------------------- | ---------------------- |
| 01-kernel             | カーネルとは何か       |
| 02-syscall            | システムコールの仕組み |
| 03-virtual-memory     | 仮想メモリの仕組み     |
| 04-process-management | カーネルのプロセス管理 |
| 05-scheduler          | CPU 時間の配分         |
| 06-namespace          | プロセスの隔離         |
| 07-cgroup             | リソースの制限         |

### 全体像

```
┌─────────────────────────────────────────┐
│           ユーザーのプログラム            │
├─────────────────────────────────────────┤
│           libc / システムコール           │
├─────────────────────────────────────────┤
│              OS（カーネル）               │
│  ・カーネルの役割 (01)                   │
│  ・システムコール (02)                   │
│  ・仮想メモリ (03)                       │
│  ・プロセス管理 (04)                     │
│  ・スケジューラ (05)                     │
│  ・namespace (06)                        │
│  ・cgroup (07)                           │
├─────────────────────────────────────────┤
│             ハードウェア                  │
└─────────────────────────────────────────┘
```

namespace（隔離）と cgroup（制限）を学ぶことで、コンテナ技術の基盤を理解することに繋がります

```
コンテナ = namespace + cgroup + イメージ + ランタイム
```

- <strong>namespace</strong>：リソースの「見え方」を隔離
- <strong>cgroup</strong>：リソースの「使用量」を制限

「OS 自身がどう動いているか」を理解することで、その上で動くコンテナやアプリケーションの仕組みが、より深く理解できるようになります

---

## 用語集

| 用語           | 英語                      | 説明                                             |
| -------------- | ------------------------- | ------------------------------------------------ |
| cgroup         | Control Group             | プロセスのリソースを制限・管理する仕組み         |
| コントローラ   | Controller                | 特定のリソースを制御するカーネルコンポーネント   |
| 階層           | Hierarchy                 | cgroup のツリー構造                              |
| 統一階層       | Unified Hierarchy         | cgroup v2 の単一ツリー構造                       |
| NUMA ノード    | NUMA Node                 | マルチプロセッサシステムでメモリの配置を表す単位 |
| HugeTLB ページ | HugeTLB Page              | 通常より大きなサイズ（2MB や 1GB）のメモリページ |
| cpu.weight     | CPU Weight                | CPU 時間の配分比率                               |
| cpu.max        | CPU Max                   | CPU 帯域幅の絶対的な上限                         |
| memory.max     | Memory Max                | メモリ使用量のハード制限                         |
| memory.high    | Memory High               | メモリ使用量のソフト制限                         |
| memory.low     | Memory Low                | メモリのソフト保護                               |
| memory.min     | Memory Min                | メモリの絶対保護                                 |
| io.weight      | IO Weight                 | I/O の配分比率                                   |
| io.max         | IO Max                    | I/O 帯域幅と IOPS の上限                         |
| pids.max       | PIDs Max                  | 作成できるプロセス数の上限                       |
| OOM キラー     | OOM Killer                | メモリ不足時にプロセスを強制終了する仕組み       |
| スロットリング | Throttling                | リソース使用を制限して処理速度を落とすこと       |
| 凍結状態       | Frozen                    | cgroup 内のプロセスが一時停止している状態        |
| ページフォルト | Page Fault                | 未割り当てページへのアクセス時に発生する例外     |
| メジャー番号   | Major Number              | デバイスドライバの種類を示す番号                 |
| マイナー番号   | Minor Number              | 同じドライバ内の特定デバイスを区別する番号       |
| リーフノード   | Leaf Node                 | 子を持たない末端の cgroup                        |
| fork bomb      | Fork Bomb                 | 無限にプロセスを生成してシステムを停止させる攻撃 |
| IOPS           | I/O Operations Per Second | 1秒あたりの I/O 操作数                           |

---

## 参考資料

このページの内容は、以下のソースに基づいています

<strong>cgroup 概要</strong>

- [cgroups(7) - Linux manual page](https://man7.org/linux/man-pages/man7/cgroups.7.html)
  - cgroup の概要と基本的な使い方

<strong>cgroup v2 詳細</strong>

- [Control Group v2 - The Linux Kernel documentation](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)
  - cgroup v2 の公式カーネルドキュメント
  - コントローラごとの詳細な説明

<strong>疑似ファイルシステム</strong>

- [proc(5) - Linux manual page](https://man7.org/linux/man-pages/man5/proc.5.html)
  - /proc/[pid]/cgroup の説明

<strong>関連するカーネルドキュメント</strong>

- [Memory Resource Controller - The Linux Kernel documentation](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v1/memory.html)
  - メモリコントローラの詳細
- [CPU Controller - The Linux Kernel documentation](https://www.kernel.org/doc/html/latest/scheduler/sched-bwc.html)
  - CPU 帯域幅制御の詳細
