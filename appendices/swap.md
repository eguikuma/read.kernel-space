---
layout: default
title: スワップはメモリを増やすのか
---

# [スワップはメモリを増やすのか](#does-swap-increase-memory) {#does-swap-increase-memory}

## [はじめに](#introduction) {#introduction}

[01-kernel](../../01-kernel/) の「sysinfo() システムコール」で、<strong>スワップ</strong>という仕組みが登場しました

「物理メモリが足りないとき、ディスクの一部をメモリの代わりに使う」と説明されていました

では、8GB のメモリと 8GB のスワップがあれば、16GB のメモリがあるのと同じでしょうか？

答えは<strong>「いいえ」</strong>です

スワップはメモリを「増やす」のではなく、<strong>メモリ不足時の「緊急避難場所」</strong>です

このドキュメントでは、スワップの正体と、その適切な使い方を説明します

---

## [目次](#table-of-contents) {#table-of-contents}

- [スワップとは](#what-is-swap)
- [スワップの仕組み](#swap-mechanism)
- [スワップの確認方法](#checking-swap)
- [swappiness パラメータ](#swappiness-parameter)
- [スワップファイル vs パーティション](#swap-file-vs-partition)
- [SSD時代のスワップ](#swap-in-ssd-era)
- [cgroupとスワップ](#cgroup-and-swap)
- [まとめ](#summary)
- [参考資料](#references)

---

## [スワップとは](#what-is-swap) {#what-is-swap}

### [基本的な説明](#basic-explanation) {#basic-explanation}

<strong>スワップ</strong>は、物理メモリ（RAM）が不足したときに、ディスクの一部をメモリの代わりに使う仕組みです

Linux のマニュアルには、こう書かれています

> Swap space in Linux is used when the amount of physical memory (RAM) is full.

> Linux のスワップ領域は、物理メモリ（RAM）がいっぱいになったときに使用されます

### [メモリとスワップの速度差](#speed-difference) {#speed-difference}

スワップはメモリの「代わり」ですが、速度は<strong>桁違いに遅い</strong>です

{: .labeled}
| 種類 | アクセス時間 | 比率 |
| -------- | ----------------- | ---------------- |
| DDR4 RAM | 約 10 ナノ秒 | 1 |
| NVMe SSD | 約 100 マイクロ秒 | 10,000 倍遅い |
| SATA SSD | 約 200 マイクロ秒 | 20,000 倍遅い |
| HDD | 約 10 ミリ秒 | 1,000,000 倍遅い |

スワップを使い始めると、システムは<strong>劇的に遅くなります</strong>

### [スワップの目的](#swap-purpose) {#swap-purpose}

スワップの本当の目的は「メモリを増やす」ことではありません

{: .labeled}
| 目的 | 説明 |
| -------------------------- | -------------------------------------- |
| OOM 回避 | メモリ不足でプロセスが殺されるのを防ぐ |
| 休眠のためのバッファ | ハイバネーション（休止状態）に使用 |
| 使用頻度の低いページの退避 | アクティブなプロセスにメモリを譲る |

---

## [スワップの仕組み](#swap-mechanism) {#swap-mechanism}

### [ページとは](#what-is-page) {#what-is-page}

スワップを理解するには、まず<strong>ページ</strong>を知る必要があります

ページとは、カーネルがメモリを管理する最小単位（通常 4KB）です

カーネルはメモリを 1 バイトずつではなく、ページという「小さなブロック」に分けて管理しています

詳細は [page.md](../page/) を参照してください

### [スワップアウトとスワップイン](#swap-in-and-out) {#swap-in-and-out}

{: .labeled}
| 操作 | 説明 |
| -------------- | ------------------------------------ |
| スワップアウト | メモリの内容をスワップ領域に書き出す |
| スワップイン | スワップ領域の内容をメモリに読み戻す |

スワップは<strong>ページ単位</strong>で行われます

### [どのページがスワップアウトされるか](#which-pages-swapped-out) {#which-pages-swapped-out}

カーネルは、<strong>使用頻度の低いページ</strong>を優先的にスワップアウトします

{: .labeled}
| ページの種類 | スワップアウトされやすさ |
| -------------------------- | ------------------------ |
| 長時間アクセスされていない | されやすい |
| 頻繁にアクセスされている | されにくい |
| mlock() でロックされている | されない |
| カーネル空間のページ | されない |

### [ページフォルトとスワップイン](#page-fault-and-swap-in) {#page-fault-and-swap-in}

スワップアウトされたページにアクセスすると、<strong>ページフォルト</strong>が発生します

```
1. プロセスがスワップアウトされたページにアクセス
2. ページフォルト発生
3. カーネルがスワップからページを読み込む（スワップイン）
4. ページテーブルを更新
5. プロセスの実行を再開
```

この処理はディスク I/O を伴うため、非常に遅くなります

---

## [スワップの確認方法](#checking-swap) {#checking-swap}

### [free コマンド](#free-command) {#free-command}

```bash
free -h
```

出力例

```
              total        used        free      shared  buff/cache   available
Mem:           7.7G        2.0G        3.0G        200M        2.7G        5.2G
Swap:          2.0G        100M        1.9G
```

### [/proc/swaps](#proc-swaps) {#proc-swaps}

```bash
cat /proc/swaps
```

出力例

```
Filename                Type        Size      Used    Priority
/swapfile               file        2097148   102400  -2
```

### [/proc/meminfo](#proc-meminfo) {#proc-meminfo}

```bash
grep -i swap /proc/meminfo
```

出力例

```
SwapCached:        10000 kB
SwapTotal:       2097148 kB
SwapFree:        1994748 kB
```

{: .labeled}
| フィールド | 説明 |
| ---------- | ---------------------------------------------------------- |
| SwapTotal | スワップ領域の総量 |
| SwapFree | 空きスワップ領域 |
| SwapCached | スワップから読み込まれ、メモリにキャッシュされているページ |

### [vmstat でリアルタイム監視](#realtime-monitoring-with-vmstat) {#realtime-monitoring-with-vmstat}

```bash
vmstat 1
```

`si`（スワップイン）と `so`（スワップアウト）列を確認します

```
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 1  0 102400 3000000 100000 2000000    0    0     0     0  100  500  5  2 93  0  0
```

`si` や `so` が継続的に 0 以外の場合、スワップが頻繁に使われています

---

## [swappiness パラメータ](#swappiness-parameter) {#swappiness-parameter}

### [swappiness とは](#what-is-swappiness) {#what-is-swappiness}

<strong>swappiness</strong> は、カーネルがスワップを使う「積極性」を制御するパラメータです

{: .labeled}
| 値 | 意味 |
| --- | ---------------------- |
| 0 | スワップをほぼ使わない |
| 60 | デフォルト |
| 100 | 積極的にスワップを使う |

<strong>swappiness=0 でもスワップは無効にならない</strong>

swappiness を 0 に設定しても、<strong>スワップが完全に無効になるわけではありません</strong>

OOM（メモリ不足）を回避するための最後の手段として、カーネルは swappiness=0 でもスワップを使用します

{: .labeled}
| 設定 | 動作 |
| --------------- | ------------------------------------------------ |
| swappiness=0 | 通常時はスワップしない（OOM 回避時のみスワップ） |
| swappiness=1〜9 | ほとんどスワップしない |
| swapoff -a | スワップ領域自体を無効化（完全に使わない） |

スワップを完全に無効にするには、`swapoff -a` でスワップ領域を無効化する必要があります

<strong>swappiness=0 の内部動作</strong>

カーネルは、スワップするかどうかを「anonymous pages」と「file-backed pages」のバランスで決定します

{: .labeled}
| ページの種類 | 説明 |
| --------------- | -------------------------------------------------- |
| anonymous pages | ヒープ、スタックなど（ファイルに対応しないメモリ） |
| file-backed | ファイルキャッシュ、mmap されたファイル |

swappiness は「anonymous pages をどれだけ積極的にスワップするか」を制御します

```
swappiness=100 → anonymous と file-backed を均等に回収
swappiness=60  → file-backed をやや優先的に回収（デフォルト）
swappiness=0   → anonymous pages を回収しない（file-backed のみ回収）
              → ただし、file-backed を回収し尽くしたら anonymous もスワップ
```

つまり swappiness=0 でも、ファイルキャッシュを削除できなくなったら、OOM を避けるためにスワップが発生します

<strong>歴史的変更点</strong>

Linux 3.5 以前と以降で swappiness=0 の動作が変わりました

{: .labeled}
| バージョン | swappiness=0 の動作 |
| -------------- | --------------------------------------- |
| Linux 3.4 以前 | anonymous pages のスワップ確率を減らす |
| Linux 3.5 以降 | OOM 状況以外では anonymous を回収しない |

現在は「swappiness=0 = OOM 回避時以外はスワップしない」と理解して問題ありません

### [確認方法](#confirmation-methods) {#confirmation-methods}

```bash
cat /proc/sys/vm/swappiness
```

### [変更方法](#changing-swappiness) {#changing-swappiness}

```bash
# 一時的に変更
sudo sysctl vm.swappiness=10

# 永続的に変更
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### [推奨値](#recommended-values) {#recommended-values}

{: .labeled}
| ユースケース | 推奨 swappiness |
| ---------------------------- | ---------------- |
| デスクトップ | 10〜30 |
| サーバー（メモリに余裕） | 10〜30 |
| サーバー（メモリがギリギリ） | 60（デフォルト） |
| データベースサーバー | 1〜10 |

データベースなど、遅延に敏感なアプリケーションでは、swappiness を低くするのが一般的です

---

## [スワップファイル vs パーティション](#swap-file-vs-partition) {#swap-file-vs-partition}

### [2つの形式](#two-formats) {#two-formats}

{: .labeled}
| 形式 | 説明 |
| ---------------------- | ---------------------------------- |
| スワップパーティション | ディスクの専用領域 |
| スワップファイル | 通常のファイルシステム上のファイル |

### [スワップパーティション](#swap-partition) {#swap-partition}

```bash
# パーティションを作成（fdisk、parted など）
# スワップとしてフォーマット
sudo mkswap /dev/sdb1

# 有効化
sudo swapon /dev/sdb1
```

### [スワップファイル](#swap-file) {#swap-file}

```bash
# ファイルを作成（2GB の例）
sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
sudo chmod 600 /swapfile

# スワップとしてフォーマット
sudo mkswap /swapfile

# 有効化
sudo swapon /swapfile
```

### [比較](#comparison) {#comparison}

{: .labeled}
| 観点 | パーティション | ファイル |
| -------------- | ------------------------ | -------------------- |
| パフォーマンス | わずかに良い | わずかに劣る |
| 柔軟性 | サイズ変更が難しい | 簡単にサイズ変更可能 |
| 管理 | パーティション管理が必要 | ファイル操作だけ |

現代では、スワップファイルが推奨されることが多いです

---

## [SSD時代のスワップ](#swap-in-ssd-era) {#swap-in-ssd-era}

### [SSD でのスワップ](#swap-on-ssd) {#swap-on-ssd}

SSD はランダムアクセスが高速なため、HDD よりスワップに適しています

しかし、SSD には書き込み寿命があります

### [書き込み寿命への影響](#impact-on-write-lifetime) {#impact-on-write-lifetime}

頻繁なスワップは、SSD の寿命を縮める可能性があります

ただし、現代の SSD は書き込み寿命が長いため、通常の使用では問題になりません

{: .labeled}
| 対策 | 説明 |
| ------------------- | ---------------------------------- |
| swappiness を下げる | スワップの使用を減らす |
| メモリを増やす | スワップの必要性を減らす |
| zswap を使う | スワップ前に圧縮（書き込み量削減） |

### [zswap と zram](#zswap-and-zram) {#zswap-and-zram}

{: .labeled}
| 機能 | 説明 |
| ----- | ---------------------------------------------------------------- |
| zswap | スワップアウト時にメモリ上で圧縮、圧縮できた分だけスワップを削減 |
| zram | 圧縮された RAM ディスクをスワップとして使用 |

これらにより、実際のディスクへの書き込みを減らせます

<strong>なぜ圧縮が有効なのか</strong>

メモリの内容は、多くの場合圧縮可能です

{: .labeled}
| データの種類 | 典型的な圧縮率 |
| ---------------------- | -------------- |
| 0 で埋まったページ | 99% 以上 |
| テキストデータ | 50〜70% |
| すでに圧縮されたデータ | ほぼ 0% |
| 平均的なワークロード | 30〜50% |

4KB のページが 2KB に圧縮できれば、同じメモリで 2 倍のページを保持できます

<strong>zswap の仕組み</strong>

zswap は、スワップアウトされるページを<strong>メモリ内で圧縮して保持</strong>するキャッシュです

```
従来のスワップ:
ページ → ディスクに書き込み（遅い）

zswap 有効時:
ページ → メモリ内で圧縮 → 圧縮プールに保持
       └→ プールがいっぱい → 古いページをディスクに書き込み
```

ディスク I/O を削減できるため、スワップ使用時のパフォーマンスが向上します

```bash
# zswap の有効化
echo 1 > /sys/module/zswap/parameters/enabled
echo lz4 > /sys/module/zswap/parameters/compressor  # 圧縮アルゴリズム
echo 20 > /sys/module/zswap/parameters/max_pool_percent  # メモリの20%まで使用
```

<strong>zram の仕組み</strong>

zram は、<strong>圧縮された RAM ディスク</strong>をスワップデバイスとして使います

```
通常のスワップ:
ページ → /dev/sda（物理ディスク）

zram スワップ:
ページ → /dev/zram0（圧縮された RAM ディスク）→ 物理ディスクは不要
```

zram は SSD の寿命を気にする必要がなく、高速です

ただし、物理メモリの一部を消費するため、メモリが少ない環境では注意が必要です

<strong>zswap vs zram の選択</strong>

{: .labeled}
| 観点 | zswap | zram |
| ---------------- | ---------------------------- | -------------------------- |
| バックエンド | 既存のスワップ領域を併用 | RAM のみ（ディスク不要） |
| メモリ消費 | 圧縮プールサイズ分 | zram デバイスサイズ分 |
| ディスク I/O | 削減（プール溢れ時のみ発生） | なし |
| 推奨ユースケース | 既存スワップの高速化 | ディスクレス、SSD 寿命重視 |

---

## [cgroupとスワップ](#cgroup-and-swap) {#cgroup-and-swap}

### [cgroup v2 でのスワップ制限](#cgroup-v2-swap-limit) {#cgroup-v2-swap-limit}

cgroup v2 では、グループごとにスワップを制限できます

```bash
# メモリ制限
echo 500M > /sys/fs/cgroup/mygroup/memory.max

# スワップ制限
echo 100M > /sys/fs/cgroup/mygroup/memory.swap.max
```

### [コンテナでのスワップ](#swap-in-containers) {#swap-in-containers}

Docker では、`--memory-swap` オプションでスワップを制限できます

```bash
# メモリ 500MB、スワップ 100MB（合計 600MB）
docker run --memory 500m --memory-swap 600m myapp

# スワップを無効化
docker run --memory 500m --memory-swap 500m myapp
```

詳細は [07-cgroup](../../07-cgroup/) を参照してください

---

## [まとめ](#summary) {#summary}

<strong>スワップとは</strong>

{: .labeled}
| ポイント | 説明 |
| ------------------------ | ------------------------------- |
| メモリの「増設」ではない | 緊急避難場所 |
| 桁違いに遅い | RAM の 10,000〜1,000,000 倍遅い |
| OOM 回避が主目的 | プロセスが殺されるのを防ぐ |

<strong>覚えておくこと</strong>

{: .labeled}
| ポイント | 説明 |
| ---------------------- | --------------------------------- |
| swappiness で調整 | 低いほどスワップを使わない |
| スワップファイルが簡単 | サイズ変更が容易 |
| vmstat で監視 | si/so が継続的に 0 以外なら要注意 |
| cgroup で制限可能 | コンテナごとにスワップを制御 |

---

## [参考資料](#references) {#references}

<strong>Linux マニュアル</strong>

- [swapon(8) - Linux manual page](https://man7.org/linux/man-pages/man8/swapon.8.html){:target="\_blank"}
  - スワップの有効化
- [mkswap(8) - Linux manual page](https://man7.org/linux/man-pages/man8/mkswap.8.html){:target="\_blank"}
  - スワップ領域の作成
- [proc(5) - Linux manual page](https://man7.org/linux/man-pages/man5/proc.5.html){:target="\_blank"}
  - /proc/swaps、/proc/meminfo

<strong>Linux カーネルドキュメント</strong>

- [zswap - kernel.org](https://www.kernel.org/doc/html/latest/admin-guide/mm/zswap.html){:target="\_blank"}
  - zswap の詳細

<strong>本編との関連</strong>

- [01-kernel](../../01-kernel/)
  - sysinfo() でのスワップ情報取得
- [03-virtual-memory](../../03-virtual-memory/)
  - 仮想メモリとページング
- [07-cgroup](../../07-cgroup/)
  - cgroup でのスワップ制限
