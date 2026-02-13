<div align="right">
<img src="https://img.shields.io/badge/AI-ASSISTED_STUDY-3b82f6?style=for-the-badge&labelColor=1e293b&logo=bookstack&logoColor=white" alt="AI Assisted Study" />
</div>

# マウントはなぜ伝播するのか

## はじめに

[06-namespace](../06-namespace.md) の「Mount namespace」で、プロセスごとに異なるファイルシステムビューを持てることを学びました

しかし、新しい namespace を作っても、マウントが「見えたり見えなかったり」することがあります

```bash
# namespace を分離したはずなのに...
unshare --mount bash
mount /dev/sdb1 /mnt  # このマウントが他に見える？
```

これは<strong>マウント伝播</strong>（mount propagation）という仕組みが関係しています

このドキュメントでは、マウント伝播の仕組みと、コンテナでの活用方法を説明します

---

## 目次

- [マウント伝播とは](#マウント伝播とは)
- [伝播モード](#伝播モード)
- [確認方法](#確認方法)
- [設定方法](#設定方法)
- [コンテナでの活用](#コンテナでの活用)
- [まとめ](#まとめ)
- [参考資料](#参考資料)

---

## マウント伝播とは

### 基本的な概念

<strong>マウント伝播</strong>は、あるマウントポイントでの<strong>mount / umount 操作</strong>が、関連する他のマウントポイントに「伝わる」仕組みです

伝播するのは<strong>マウント操作そのもの</strong>です

ファイルの内容や変更が伝播するわけではありません

日常の例えで言えば、「情報の流れ」のようなものです

組織での情報伝達に例えると

- 双方向に共有する（shared）：会議室のホワイトボードのように、誰が書いても全員に見える
- 一方向に受け取る（slave）：メールマガジンの購読者のように、受け取るだけで発信はできない
- 完全に独立する（private）：自分のメモ帳のように、他の人とは共有しない

マウント伝播は、「どこまで伝えるか」を制御します

### なぜ必要か

Mount namespace が導入される前は、マウントは全プロセスで共有されていました

namespace 導入後、「分離するか」「共有するか」を細かく制御する必要が生まれました

例えば

- USB デバイスを挿したら、すべての namespace で見えてほしい
- コンテナ内のマウントは、ホストに見えてほしくない

これを実現するのがマウント伝播です

---

## 伝播モード

### ピアグループとは（先に理解すべき概念）

伝播モードを理解するには、まず<strong>ピアグループ</strong>を知る必要があります

ピアグループとは、「マウントイベントを共有するマウントポイントの集まり」です

```
ピアグループ 1
├── /mnt（namespace A）
├── /mnt（namespace B）
└── /mnt（namespace C）

→ A で mount すると、B と C にも伝播する
→ B で umount すると、A と C にも伝播する
```

同じピアグループに属するマウントポイントは、どれか 1 つでマウント/アンマウント操作が行われると、他のメンバーにも伝播します

<strong>なぜピアグループが必要になったのか</strong>

Mount namespace が導入される前（Linux 2.4 以前）、マウントはシステム全体で 1 つでした

namespace 導入後、各 namespace は独自のマウントツリーを持ちますが、問題が生じました

```
問題：USB デバイスをホストでマウントしたい
     → すべてのコンテナで見えてほしい
     → でも各コンテナのマウントは独立している...
```

この問題を解決するため、「どの namespace のマウントが連動するか」をグループ化する仕組みが必要になりました

それがピアグループです

ピアグループは、「マウントの見え方を共有する範囲」を柔軟に定義できるようにしたのです

### 4つのモード

| モード     | 説明                                 |
| ---------- | ------------------------------------ |
| shared     | マウントイベントを双方向に伝播       |
| private    | マウントイベントを伝播しない         |
| slave      | 親からは受け取るが、子には伝播しない |
| unbindable | private + バインドマウント不可       |

### shared（共有）

<strong>shared</strong> モードでは、マウントイベントが<strong>双方向</strong>に伝播します

```
namespace A <──────> namespace B
     │                    │
  マウント ────────> 見える
  アンマウント ────────> 見えなくなる
```

例：USB デバイスをマウントしたら、すべての namespace で見える

### private（プライベート）

<strong>private</strong> モードでは、マウントイベントが<strong>伝播しません</strong>

```
namespace A          namespace B
     │                    │
  マウント ─────X───> 見えない
```

例：コンテナ内のマウントがホストに見えない

### slave（スレーブ）

<strong>slave</strong> モードでは、<strong>一方向</strong>にのみ伝播します

```
namespace A ──────> namespace B（slave）
     │                    │
  マウント ────────> 見える

namespace B ──────> namespace A
     │                    │
  マウント ─────X───> 見えない
```

例：ホストのマウントはコンテナで見えるが、コンテナのマウントはホストで見えない

<strong>slave とピアグループ</strong>

slave マウントは、マスターピアグループからイベントを受け取ります

```
┌─────────────────────────────────────────┐
│ ピアグループ 1（shared）                │
│   マウント A ←→ マウント B              │
└────────────────┬────────────────────────┘
                 │ 伝播（一方向）
                 ↓
┌─────────────────────────────────────────┐
│ スレーブ C                              │
│   （ピアグループ 1 のスレーブ）          │
└─────────────────────────────────────────┘
```

ピアグループ 1 でマウントイベントが発生すると、スレーブ C にも伝播します

しかし、スレーブ C でのマウントイベントは、ピアグループ 1 には伝播しません

### unbindable（バインド不可）

<strong>unbindable</strong> は、private に加えて<strong>再帰的バインドマウントで複製されない</strong>という特性を持ちます

<strong>バインドマウントとは</strong>

バインドマウントは、ある場所を別の場所からもアクセスできるようにする機能です

```bash
# /src を /dst からもアクセスできるようにする
mount --bind /src /dst
```

これにより、`/src/file.txt` と `/dst/file.txt` は同じファイルを指します

<strong>なぜ unbindable が必要か</strong>

再帰的バインドマウント（`--rbind`）は、バインドマウントをサブマウントも含めて再帰的に行います

```
例：/A を /B に再帰的バインドした後、/B を /C にバインド

/A ─rbind→ /B ─rbind→ /C ...

マウントポイントが指数関数的に増加する可能性
```

unbindable に設定されたマウントは、再帰的バインド操作で<strong>自動的にスキップ</strong>されます

```bash
# unbindable なマウントポイント
mount --make-unbindable /mnt/skip

# 再帰的バインドでコピーしても
mount --rbind /mnt /backup

# /mnt/skip は /backup 以下に複製されない
```

これにより、マウント構造の指数関数的な増加を防ぎ、システムを安定させます

<strong>実際のトラブル事例：unbindable がない場合</strong>

以下は、unbindable を使わなかった場合に起こりうる問題の具体例です

```bash
# 1. /backup を /mnt に rbind
mount --rbind /backup /mnt

# 2. /mnt が /backup を含むようになる
#    /mnt/backup が存在する（/backup へのバインド）

# 3. 再度 /backup を更新すると...
mount --rbind /backup /mnt
# → /mnt/backup/backup/backup/... と増殖する可能性
```

この「マウントポイントの指数関数的増加」は、実際にシステムをフリーズさせることがあります

systemd はこの問題を認識しており、多くのシステムマウントポイントをデフォルトで shared ではなく private にしています

unbindable は「絶対にコピーされてほしくないマウントポイント」に設定する安全策です

---

## 確認方法

### /proc/self/mountinfo

マウントポイントの伝播モードは `/proc/self/mountinfo` で確認できます

```bash
cat /proc/self/mountinfo | grep ' / '
```

出力例

```
1 0 8:1 / / rw,relatime shared:1 - ext4 /dev/sda1 rw
```

`shared:1` の部分が伝播モードを示しています

### フィールドの読み方

| 表記             | 意味                                                                 |
| ---------------- | -------------------------------------------------------------------- |
| shared:N         | shared モード、ピアグループ N に属する                               |
| master:N         | slave モード、ピアグループ N から伝播を受ける                        |
| propagate_from:N | マスターマウントポイントに到達できない場合の、最も近い伝播元グループ |
| unbindable       | unbindable モード                                                    |
| （なし）         | private モード                                                       |

<strong>propagate_from:N について</strong>

`propagate_from:N` は特殊なケースで表示されます

通常、slave マウントは `master:N` でマスターグループを示します

しかし、chroot 環境などでマスターマウントポイントのパスに到達できない場合、プロセスから見えるファイルシステム階層内で最も近い支配的なピアグループが `propagate_from:N` として表示されます

### findmnt コマンド

```bash
findmnt -o TARGET,PROPAGATION
```

出力例

```
TARGET         PROPAGATION
/              shared
├─/sys         shared
├─/proc        shared
├─/dev         shared
├─/run         shared
└─/mnt         private
```

---

## 設定方法

### mount コマンドで設定

```bash
# private に設定
mount --make-private /mnt

# shared に設定
mount --make-shared /mnt

# slave に設定
mount --make-slave /mnt

# unbindable に設定
mount --make-unbindable /mnt
```

### 再帰的に設定（r- prefix）

サブマウントも含めて設定するには、`-r` オプション（または `--make-r*`）を使います

```bash
# /mnt 以下すべてを private に
mount --make-rprivate /mnt

# /mnt 以下すべてを shared に
mount --make-rshared /mnt
```

<strong>なぜ再帰的設定が必要か</strong>

マウントポイントには、その下にさらにマウントポイント（サブマウント）があることがあります

```
/mnt             ← ここだけ private にしても...
├── /mnt/usb     ← ここは shared のまま
└── /mnt/nfs     ← ここも shared のまま
```

`--make-private` は指定したマウントポイント<strong>だけ</strong>を変更します

`--make-rprivate` はサブマウントも含めて<strong>再帰的に</strong>変更します

| コマンド        | 対象                                            |
| --------------- | ----------------------------------------------- |
| --make-private  | 指定したマウントポイントのみ                    |
| --make-rprivate | 指定したマウントポイント + すべてのサブマウント |
| --make-slave    | 指定したマウントポイントのみ                    |
| --make-rslave   | 指定したマウントポイント + すべてのサブマウント |

Docker のボリュームマウントでは、デフォルトで `rprivate` が使われます

### マウント時の設定 vs 既存マウントへの設定

伝播モードの設定には 2 つのタイミングがあります

<strong>新規マウント時に設定</strong>

```bash
# private としてマウント（マウントと同時に設定）
mount -o private /dev/sdb1 /mnt
```

<strong>既存マウントの設定を変更</strong>

```bash
# 既存のマウントを slave に変更
mount --make-slave /mnt
```

| 操作                | 説明                             |
| ------------------- | -------------------------------- |
| mount -o [mode]     | 新規マウント時に伝播モードを指定 |
| mount --make-[mode] | 既存マウントの伝播モードを変更   |

bind マウントの場合は、2 段階の操作が必要なことが多いです

```bash
# 1. まず bind マウントを作成
mount --bind /src /dst

# 2. 次に伝播モードを設定
mount --make-slave /dst
```

---

## コンテナでの活用

### Docker のボリュームマウント

Docker でボリュームをマウントする際、伝播モードを指定できます

```bash
# rprivate（デフォルト）
docker run -v /host:/container:rprivate ...

# rslave
docker run -v /host:/container:rslave ...

# rshared
docker run -v /host:/container:rshared ...
```

### モードの選び方

| モード   | ユースケース                           |
| -------- | -------------------------------------- |
| rprivate | デフォルト、コンテナ内のマウントを隔離 |
| rslave   | ホストのマウントをコンテナに反映したい |
| rshared  | 双方向で共有したい（稀なケース）       |

### 例：ホストの USB デバイスをコンテナで使う

```bash
# rslave でマウントすると、後から挿した USB も見える
docker run -v /media:/media:rslave ...

# rprivate だと、コンテナ起動時のマウントのみ見える
docker run -v /media:/media:rprivate ...
```

### Kubernetes の mountPropagation

Kubernetes でも同様の設定が可能です

```yaml
volumeMounts:
  - name: host-mount
    mountPath: /mnt
    mountPropagation: Bidirectional # shared 相当
    # または: HostToContainer（slave 相当）、None（private 相当）
```

---

## まとめ

<strong>マウント伝播とは</strong>

| ポイント                   | 説明                                    |
| -------------------------- | --------------------------------------- |
| マウントイベントの伝わり方 | 他の namespace にマウントが見えるか制御 |
| 4 つのモード               | shared、private、slave、unbindable      |

<strong>覚えておくこと</strong>

| モード     | 伝播方向         | ユースケース                     |
| ---------- | ---------------- | -------------------------------- |
| shared     | 双方向           | USB デバイスの共有               |
| private    | なし             | コンテナの隔離                   |
| slave      | 親→子のみ        | ホストのマウントをコンテナに反映 |
| unbindable | なし + bind 禁止 | 再帰防止                         |

---

## 参考資料

<strong>Linux マニュアル</strong>

- [mount(8) - Linux manual page](https://man7.org/linux/man-pages/man8/mount.8.html)
  - マウントコマンドの詳細
- [mount_namespaces(7) - Linux manual page](https://man7.org/linux/man-pages/man7/mount_namespaces.7.html)
  - Mount namespace とマウント伝播

<strong>Linux カーネルドキュメント</strong>

- [Shared Subtrees - kernel.org](https://www.kernel.org/doc/Documentation/filesystems/sharedsubtree.txt)
  - マウント伝播の詳細仕様

<strong>本編との関連</strong>

- [06-namespace](../06-namespace.md)
  - Mount namespace の概要
