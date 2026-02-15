<div align="right">
<img src="https://img.shields.io/badge/AI-ASSISTED_STUDY-3b82f6?style=for-the-badge&labelColor=1e293b&logo=bookstack&logoColor=white" alt="AI Assisted Study" />
</div>

# 02-syscall：システムコールの仕組み

## はじめに

01-kernel では、カーネルとは何か、そしてカーネル空間とユーザー空間の分離について学びました

- カーネルは OS の中核として、ハードウェアの抽象化とリソースの管理を行う
- セキュリティと安定性のため、カーネル空間とユーザー空間は分離されている
- ユーザー空間のプログラムは、直接カーネルの機能を使うことができない

では、ユーザー空間のプログラムは、どのようにしてカーネルの機能を使うのでしょうか？

このページでは、ユーザー空間からカーネルへの「扉」である<strong>システムコール</strong>について学びます

### 日常の例え

銀行の窓口を想像してみてください

<strong>ユーザー空間のプログラム</strong>は「お客さん」です

お客さんは、金庫室に直接入ることはできません

代わりに、窓口で「お金を引き出したい」「振り込みをしたい」と伝えます

<strong>システムコール</strong>は、その「窓口」に相当します

- お客さん（プログラム）は窓口（システムコール）に依頼を伝える
- 銀行員（カーネル）が金庫室で作業を行う
- 結果を窓口経由でお客さんに返す

窓口には決まった手続きがあり、それに従わないと処理してもらえません

システムコールも同様に、決まった形式で呼び出す必要があります

### このページで学ぶこと

このページでは、以下の概念を学びます

- <strong>システムコールとは何か</strong>
  - ユーザー空間からカーネルへの唯一のインターフェース
- <strong>システムコールの仕組み</strong>
  - CPU のモード切り替えがどのように行われるか
- <strong>ライブラリ関数とシステムコールの違い</strong>
  - printf() と write() の関係
- <strong>errno によるエラー処理</strong>
  - システムコールが失敗したときの対処法
- <strong>strace によるシステムコールの観察</strong>
  - プログラムが発行するシステムコールを追跡する方法
- <strong>システムコールのオーバーヘッド</strong>
  - モード切り替えのコスト
- <strong>vDSO による最適化</strong>
  - カーネル遷移なしでシステムコールを実行する仕組み
- <strong>ptrace によるシステムコールの傍受</strong>
  - デバッガや strace がシステムコールを追跡する仕組み

---

## 目次

1. [システムコールとは何か](#システムコールとは何か)
2. [システムコールの仕組み](#システムコールの仕組み)
3. [システムコールの呼び出し方](#システムコールの呼び出し方)
4. [ライブラリ関数とシステムコールの違い](#ライブラリ関数とシステムコールの違い)
5. [errno によるエラー処理](#errno-によるエラー処理)
6. [strace によるシステムコールの観察](#strace-によるシステムコールの観察)
7. [システムコールのオーバーヘッド](#システムコールのオーバーヘッド)
8. [vDSO による最適化](#vdso-による最適化)
9. [ptrace によるシステムコールの傍受](#ptrace-によるシステムコールの傍受)
10. [用語集](#用語集)
11. [参考資料](#参考資料)

---

## システムコールとは何か

### 基本的な説明

<strong>システムコール（System Call）</strong>は、ユーザー空間のプログラムがカーネルの機能を呼び出すための仕組みです

Linux の公式マニュアルには、こう書かれています

> The system call is the fundamental interface between an application and the Linux kernel.

> システムコールは、アプリケーションと Linux カーネル間の基本的なインターフェースです

### システムコールが必要な理由

01-kernel で学んだように、ユーザー空間とカーネル空間は分離されています

ユーザー空間のプログラムは、以下の操作を直接行うことができません

- ファイルの読み書き
- ネットワーク通信
- プロセスの作成
- メモリの確保（大きな領域）
- 時刻の取得

これらの操作は、すべてカーネルを経由する必要があります

システムコールは、その「経由」を実現する唯一の方法です

### システムコールの種類

Linux には数百のシステムコールが存在します

主要なカテゴリと代表的なシステムコールを以下に示します

| カテゴリ       | システムコールの例                    |
| -------------- | ------------------------------------- |
| ファイル操作   | open, read, write, close, stat, lseek |
| プロセス管理   | fork, exec, exit, wait, getpid        |
| メモリ管理     | mmap, munmap, brk, mprotect           |
| ネットワーク   | socket, connect, bind, listen, accept |
| 時刻           | time, gettimeofday, clock_gettime     |
| シグナル       | kill, sigaction, sigprocmask          |
| プロセス間通信 | pipe, shmget, msgget, semget          |

---

## システムコールの仕組み

### モード切り替え

システムコールを呼び出すと、CPU のモードが切り替わります

<strong>1. ユーザーモードからカーネルモードへ</strong>

プログラムがシステムコールを呼び出すと、以下の処理が行われます

- CPU に割り込み（またはシステムコール命令）が発生
- CPU が特権モード（カーネルモード）に切り替わる
- カーネルのシステムコールハンドラが呼び出される

<strong>2. カーネルでの処理</strong>

カーネルは以下の処理を行います

- システムコール番号から、対応する処理を特定
- 引数の検証（不正な値がないか確認）
- 実際の処理を実行
- 結果を準備

<strong>3. ユーザーモードへの復帰</strong>

処理が完了すると、以下が行われます

- 結果をユーザー空間に返す
- CPU がユーザーモードに戻る
- プログラムの実行が再開

### x86_64 でのシステムコール

x86_64 アーキテクチャでは、`syscall` 命令を使ってシステムコールを発行します

<strong>レジスタ</strong>とは、CPU 内部にある高速な記憶領域です

計算に使うデータを一時的に保持します

- <strong>rax レジスタ</strong>：システムコール番号を指定
- <strong>rdi, rsi, rdx, r10, r8, r9</strong>：引数（第1〜第6引数）
- <strong>rax レジスタ</strong>：戻り値が格納される

これらの詳細を覚える必要はありません

「CPU には決まった場所に値をセットする規則がある」ことだけ理解しておけば十分です

---

## システムコールの呼び出し方

### 方法 1：ライブラリ関数を使う（推奨）

通常は、C ライブラリ（glibc）が提供するラッパー関数を使います

```c
#include <unistd.h>

ssize_t result = write(STDOUT_FILENO, "Hello\n", 6);
```

ライブラリ関数を使うメリット

- 使いやすいインターフェース
- エラー処理が標準化されている
- 移植性が高い

### 方法 2：syscall() を使う

`syscall()` 関数を使うと、システムコール番号を直接指定できます

```c
#include <unistd.h>
#include <sys/syscall.h>

long result = syscall(SYS_write, STDOUT_FILENO, "Hello\n", 6);
```

syscall() を使う場面

- 新しいシステムコールをライブラリがサポートしていない場合
- システムコールの動作を学習する場合
- 特殊な用途（セキュリティツールなど）

---

## ライブラリ関数とシステムコールの違い

### 関係性

多くのライブラリ関数は、内部でシステムコールを呼び出しています

しかし、すべてのライブラリ関数がシステムコールを呼び出すわけではありません

| ライブラリ関数 | 内部で呼び出すシステムコール |
| -------------- | ---------------------------- |
| printf()       | write()                      |
| fopen()        | open()                       |
| malloc()       | brk() または mmap()          |
| strlen()       | なし（純粋な計算）           |
| sqrt()         | なし（純粋な計算）           |

### 違いのまとめ

| 項目           | ライブラリ関数               | システムコール       |
| -------------- | ---------------------------- | -------------------- |
| 実行場所       | ユーザー空間                 | カーネル空間         |
| バッファリング | あり（printf など）          | なし                 |
| オーバーヘッド | 関数呼び出しのみ             | モード切り替えが発生 |
| 移植性         | 高い                         | OS 依存              |
| 機能           | 追加処理（フォーマットなど） | 最小限の処理         |

### 具体例：printf() と write()

`printf()` は便利な機能を提供しますが、最終的には `write()` を呼び出します

<strong>printf() の処理</strong>

1. フォーマット文字列を解析（%d, %s など）
2. 引数を文字列に変換
3. バッファに格納
4. バッファが一杯になったら write() を呼び出し

<strong>write() の処理</strong>

1. 引数を検証
2. カーネルにデータを渡す
3. カーネルがデバイスに書き込み

---

## errno によるエラー処理

### なぜエラー処理が必要なのか

システムコールは、常に成功するとは限りません

例えば

- 存在しないファイルを開こうとした
- 権限のないディレクトリにアクセスしようとした
- メモリが不足している
- ディスク容量がいっぱい

このような状況で、プログラムは「何が問題だったのか」を知る必要があります

「失敗した」だけでは情報が不十分です

「なぜ失敗したのか」が分からなければ、適切な対処ができません

<strong>errno</strong> は、この「なぜ失敗したのか」を伝えるための仕組みです

### errno とは

`errno` は、システムコールやライブラリ関数のエラー番号を格納する変数です

現代の実装では、errno は<strong>スレッドローカル</strong>（各スレッドが独自の値を持つ）になっています

スレッドとは、1つのプロセス内で複数の処理を同時に行うための仕組みです

あるスレッドで errno を設定しても、他のスレッドの errno には影響しません

Linux の公式マニュアルには、こう書かれています

> The <errno.h> header file defines the integer variable errno, which is set by system calls and some library functions in the event of an error.

> <errno.h> ヘッダファイルは整数変数 errno を定義します
>
> これはシステムコールや一部のライブラリ関数がエラー時に設定します

### エラー処理の基本パターン

```c
#include <errno.h>
#include <fcntl.h>
#include <string.h>

int fd = open("/nonexistent", O_RDONLY);
if (fd == -1) {
    printf("エラー番号: %d\n", errno);
    printf("エラーメッセージ: %s\n", strerror(errno));
    perror("open");  /* 別の方法 */
}
```

### よく使うエラー番号

| 定数   | 値  | 意味                             |
| ------ | --- | -------------------------------- |
| ENOENT | 2   | ファイルまたはディレクトリがない |
| EACCES | 13  | 権限がない                       |
| EBADF  | 9   | 不正なファイルディスクリプタ     |
| EINVAL | 22  | 無効な引数                       |
| ENOMEM | 12  | メモリ不足                       |
| EEXIST | 17  | ファイルが既に存在               |
| EPERM  | 1   | 操作が許可されていない           |
| EAGAIN | 11  | リソースが一時的に利用不可       |

### errno の注意点

<strong>1. 成功時は errno を確認しない</strong>

システムコールが成功しても、errno は変更されないことがあります

さらに、成功した関数が errno を変更することも許可されています

したがって、必ず戻り値でエラーを検出してから errno を確認してください

<strong>2. errno は呼び出し直後に確認する</strong>

次のシステムコールで errno が上書きされる可能性があります

```c
int fd = open("file", O_RDONLY);
if (fd == -1) {
    int saved_errno = errno;  /* 保存しておく */
    /* 他の処理 */
    printf("エラー: %s\n", strerror(saved_errno));
}
```

---

## strace によるシステムコールの観察

### strace とは

`strace` は、プログラムが発行するシステムコールを追跡するツールです

Linux の公式マニュアルには、こう書かれています

> strace is a useful diagnostic, instructional, and debugging tool.

> strace は、診断、教育、デバッグに役立つツールです

### 基本的な使い方

```bash
strace ./program
```

出力例

```
execve("./program", ["./program"], ...) = 0
brk(NULL)                               = 0x55555555a000
write(1, "Hello\n", 6)                  = 6
exit_group(0)                           = ?
```

### 便利なオプション

| オプション       | 説明                               |
| ---------------- | ---------------------------------- |
| -e trace=write   | 特定のシステムコールのみ表示       |
| -e trace=file    | ファイル関連のシステムコールを表示 |
| -e trace=process | プロセス関連のシステムコールを表示 |
| -c               | システムコールの統計を表示         |
| -f               | 子プロセスも追跡                   |
| -t               | タイムスタンプを表示               |
| -o filename      | 結果をファイルに出力               |

### strace の出力の読み方

```
write(1, "Hello\n", 6) = 6
│     │  │         │    │
│     │  │         │    └─ 戻り値（書き込んだバイト数）
│     │  │         └────── 第3引数（バイト数）
│     │  └──────────────── 第2引数（データ）
│     └─────────────────── 第1引数（ファイルディスクリプタ）
└───────────────────────── システムコール名
```

エラー時の出力

```
open("/nonexistent", O_RDONLY) = -1 ENOENT (No such file or directory)
```

---

## システムコールのオーバーヘッド

### オーバーヘッドとは

システムコールを呼び出すと、以下の処理が発生します

- CPU のモード切り替え（ユーザーモード → カーネルモード）
- レジスタの保存・復元
- セキュリティチェック
- TLB のフラッシュ（TLB はアドレス変換を高速化するキャッシュで、「フラッシュ」とはキャッシュをクリア（消去）する操作のこと、モード切り替え時にクリアが必要な場合がある）

これらの処理には時間がかかります

通常の関数呼び出しは数ナノ秒で完了しますが、システムコールは数十〜数百ナノ秒かかることがあります

### オーバーヘッドを減らす方法

<strong>1. システムコールの回数を減らす</strong>

```c
/* 悪い例：1バイトずつ書き込み */
for (int i = 0; i < 1000; i++) {
    write(fd, &buffer[i], 1);  /* 1000回のシステムコール */
}

/* 良い例：まとめて書き込み */
write(fd, buffer, 1000);  /* 1回のシステムコール */
```

<strong>2. バッファリングを活用する</strong>

stdio ライブラリ（printf, fwrite など）はバッファリングを行い、システムコールの回数を減らします

<strong>3. vDSO を活用する</strong>

一部のシステムコールは、vDSO により高速化されています

---

## vDSO による最適化

### なぜ vDSO が必要なのか

先ほど説明した通り、システムコールにはオーバーヘッドがあります

通常の関数呼び出しは数ナノ秒で完了しますが、システムコールは 50〜500 ナノ秒程度かかることがあります

しかし、あるシステムコールは非常に頻繁に呼び出されます

その代表が<strong>時刻取得</strong>です

プログラムは、ログのタイムスタンプ、パフォーマンス測定、タイムアウト判定など、さまざまな場面で現在時刻を取得します

例えば、1 秒間に 10 万回 `gettimeofday()` を呼び出すプログラムを考えてみましょう

もし 1 回の呼び出しに 200 ナノ秒かかるとすると、時刻取得だけで 1 秒間に 20 ミリ秒（= 200ns × 100,000）を消費することになります

これは CPU 時間の 2% に相当します

<strong>もし vDSO がなかったら？</strong>

高頻度で時刻を取得するアプリケーション（データベース、ウェブサーバーなど）では、システムコールのオーバーヘッドがボトルネックになる可能性があります

vDSO は、この問題を解決するために導入されました

### vDSO とは

<strong>vDSO（Virtual Dynamic Shared Object）</strong>は、カーネルがユーザー空間にマップする特殊な共有ライブラリです

Linux の公式マニュアルには、こう書かれています

> The vDSO is a small shared library that the kernel automatically maps into the address space of all user-space applications.

> vDSO は、カーネルがすべてのユーザー空間アプリケーションのアドレス空間に自動的にマップする小さな共有ライブラリです

### vDSO の効果

vDSO を使うと、カーネルモードに切り替えることなく一部のシステムコールを実行できます

これにより、処理時間は 50〜500 ナノ秒から、わずか <strong>10〜20 ナノ秒</strong>程度に短縮されます

<strong>vDSO で高速化されるシステムコール</strong>

- clock_gettime()
- gettimeofday()
- time()
- getcpu()（x86_64）

### vDSO の仕組み

vDSO は<strong>vvar 領域</strong>と組み合わせて動作します

vvar は、カーネルが更新するデータ（現在時刻など）を格納する読み取り専用のメモリ領域です

1. カーネル起動時に vDSO 領域と vvar 領域が作成される
2. プロセス起動時にユーザー空間にマップされる
3. 動的リンカ（プログラム起動時に共有ライブラリを読み込む仕組み）が vDSO 内の関数を使用する
4. 時刻情報は vvar 領域からコピーなしで読み取る

### vDSO の確認方法

```bash
cat /proc/self/maps | grep -E 'vdso|vvar'
```

出力例

```
7fff12345000-7fff12346000 r-xp 00000000 00:00 0   [vdso]
7fff12344000-7fff12345000 r--p 00000000 00:00 0   [vvar]
```

---

## ptrace によるシステムコールの傍受

### なぜ ptrace が必要なのか

プログラムのバグを見つけたいとき、どうすればよいでしょうか？

printf() を埋め込んで確認する方法もありますが、限界があります

- コードを変更して再コンパイルする必要がある
- 変更によってバグの再現性が変わることがある
- 外部のライブラリやシステムコールの動作は確認できない

<strong>デバッガの具体的なシーン</strong>

例えば、「ファイルを開けない」というバグを調査しているとします

プログラムを gdb（デバッガ）で実行し、`open()` システムコールの直前で停止させます

```
(gdb) break open
(gdb) run
Breakpoint 1, open(file="/tmp/data.txt", oflag=0)
```

ここで「どのファイルを開こうとしているか」「どのフラグで開こうとしているか」を確認できます

さらに実行を進めて、システムコールの戻り値を確認します

```
(gdb) finish
$1 = -1
(gdb) print errno
$2 = 2  /* ENOENT: ファイルが存在しない */
```

このような調査を可能にするのが ptrace です

### ptrace とは

`ptrace` は、プロセスの実行を制御するシステムコールです

Linux の公式マニュアルには、こう書かれています

> The ptrace() system call provides a means by which one process (the "tracer") may observe and control the execution of another process (the "tracee").

> ptrace() システムコールは、あるプロセス（トレーサー）が別のプロセス（トレーシー）の実行を観察・制御する手段を提供します

### ptrace の用途

- <strong>デバッガ</strong>：gdb は ptrace を使ってブレークポイントを設定し、プログラムの実行を一時停止・再開する
- <strong>strace</strong>：ptrace を使ってシステムコールの発行を検知し、引数と戻り値を記録する
- <strong>サンドボックス</strong>：プロセスの動作を監視し、危険なシステムコールをブロックする

### ptrace の主要な操作

| 操作           | 説明                       |
| -------------- | -------------------------- |
| PTRACE_TRACEME | 子プロセスが親に追跡を許可 |
| PTRACE_SYSCALL | 次のシステムコールで停止   |
| PTRACE_GETREGS | レジスタの値を取得         |
| PTRACE_SETREGS | レジスタの値を設定         |
| PTRACE_CONT    | 実行を継続                 |

---

## 用語集

| 用語                   | 英語               | 説明                                                 |
| ---------------------- | ------------------ | ---------------------------------------------------- |
| システムコール         | System Call        | ユーザー空間からカーネルに処理を依頼する仕組み       |
| システムコール番号     | System Call Number | 各システムコールに割り当てられた一意の番号           |
| ラッパー関数           | Wrapper Function   | システムコールを呼び出すためのライブラリ関数         |
| errno                  | errno              | システムコールのエラー番号を格納する変数             |
| strace                 | strace             | システムコールを追跡するツール                       |
| vDSO                   | Virtual DSO        | カーネルがユーザー空間にマップする仮想共有ライブラリ |
| vvar                   | vvar               | vDSO が参照するデータ領域                            |
| ptrace                 | ptrace             | プロセスの実行を制御するシステムコール               |
| オーバーヘッド         | Overhead           | 処理に付随する追加のコスト                           |
| モード切り替え         | Mode Switch        | ユーザーモードとカーネルモード間の遷移               |
| バッファリング         | Buffering          | データを一時的に蓄えてまとめて処理する手法           |
| ファイルディスクリプタ | File Descriptor    | カーネルがファイルを識別するための番号               |
| トレーサー             | Tracer             | ptrace で他のプロセスを監視するプロセス              |
| トレーシー             | Tracee             | ptrace で監視されるプロセス                          |

---

## 参考資料

このページの内容は、以下のソースに基づいています

<strong>システムコール</strong>

- [syscall(2) - Linux manual page](https://man7.org/linux/man-pages/man2/syscall.2.html)
  - syscall() 関数の詳細
- [syscalls(2) - Linux manual page](https://man7.org/linux/man-pages/man2/syscalls.2.html)
  - Linux システムコールの一覧
- [write(2) - Linux manual page](https://man7.org/linux/man-pages/man2/write.2.html)
  - write システムコール
- [getpid(2) - Linux manual page](https://man7.org/linux/man-pages/man2/getpid.2.html)
  - プロセス ID の取得

<strong>エラー処理</strong>

- [errno(3) - Linux manual page](https://man7.org/linux/man-pages/man3/errno.3.html)
  - errno の詳細

<strong>ツール</strong>

- [strace(1) - Linux manual page](https://man7.org/linux/man-pages/man1/strace.1.html)
  - strace コマンド
- [ptrace(2) - Linux manual page](https://man7.org/linux/man-pages/man2/ptrace.2.html)
  - ptrace システムコール

<strong>最適化</strong>

- [vdso(7) - Linux manual page](https://man7.org/linux/man-pages/man7/vdso.7.html)
  - vDSO の詳細

---

## 次のステップ

このトピックでは、システムコールの仕組みと使い方を学びました

次の [03-virtual-memory](./03-virtual-memory.md) では、カーネルがプロセスごとにメモリ空間を分離する「仮想メモリ」の仕組みを学びます

- プロセスごとに独立したアドレス空間がどのように実現されているか
- mmap() によるメモリマッピングの仕組み
- /proc/self/maps でメモリレイアウトを確認する方法

これらの疑問に答えます
