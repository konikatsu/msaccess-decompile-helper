# MS Access Decompile Helper

Microsoft Access の `/decompile` 起動を簡単にする小さな Windows 用ツールです。

> これは Access ファイルから VBA ソースコードを抽出する「逆コンパイラ」ではありません。  
> Access の隠し起動オプション `/decompile` を使って、VBA の古いコンパイル済み状態を破棄するための補助ツールです。

## ダウンロード

[リリースページを開く](https://github.com/konikatsu/msaccess-decompile-helper/releases)

リリースページの `Assets` から `msaccess-decompile-helper-vX.Y.Z.zip` をダウンロードしてください。

## できること

- `.accdb` / `.mdb` を右クリックして `Access Decompile` を実行
- `MSACCESS.EXE` を自動検索
- Access が複数ある環境では、使用する Access を番号で選択
- 実行前に対象DBのバックアップを作成
- `.laccdb` ロックファイルや Access 起動中をチェック
- 管理者権限なしで右クリックメニューを登録/解除

## インストール

1. [リリースページ](https://github.com/konikatsu/msaccess-decompile-helper/releases) を開き、`Assets` から `msaccess-decompile-helper-vX.Y.Z.zip` をダウンロードします。
2. zipを任意の場所に展開します。例: `C:\Tools\msaccess-decompile-helper`
3. `installExplorerDecompileMenu.bat` をダブルクリックします。
4. `.accdb` または `.mdb` ファイルを右クリックし、`Access Decompile` を選びます。

右クリックメニューの登録はユーザー単位で行うため、通常は管理者権限は不要です。

Windows 11 では、最初の右クリックメニューに出ない場合があります。その場合は `その他のオプションを確認` から `Access Decompile` を選んでください。

## 使い方

右クリックメニューを使わない場合は、対象ファイルを `decompileAccess.bat` にドラッグ&ドロップしても実行できます。

コマンドラインから使う場合:

```bat
decompileAccess.bat "C:\path\to\your.accdb"
```

Access の検出結果だけ確認する場合:

```bat
decompileAccess.bat -ListAccess
```

Access が複数入っている環境で、使うAccessを固定する場合:

```bat
decompileAccess.bat "C:\path\to\your.accdb" -AccessIndex 2
```

Access のパスを直接指定する場合:

```bat
decompileAccess.bat "C:\path\to\your.accdb" -AccessPath "C:\Program Files\Microsoft Office\root\Office16\MSACCESS.EXE"
```

## 実行時の流れ

1. 対象DBを確認
2. `.laccdb` ロックファイルを確認
3. Access が起動中でないか確認
4. `decompile-backup` フォルダへバックアップを作成
5. `MSACCESS.EXE "対象DB" /decompile` を実行

バックアップは対象DBと同じフォルダの `decompile-backup` に作成されます。

## 実行後にすること

Access が起動したら、通常は以下を行います。

1. VBA エディタを開く
2. `Debug` > `Compile` を実行
3. 必要に応じて `Compact and Repair` を実行

## アンインストール

右クリックメニューを解除するには、`uninstallExplorerDecompileMenu.bat` をダブルクリックしてください。

展開したフォルダ自体も不要であれば削除できます。

## 注意

- `/decompile` は Microsoft の正式なGUI機能ではなく、Access の起動オプションとして使われるメンテナンス手法です。
- 実行前には必ずバックアップを確認してください。このツールも自動バックアップしますが、重要なDBでは別途バックアップを推奨します。
- 共有フォルダ上のDBを直接操作する場合は、他の利用者が開いていないことを確認してください。

## ライセンス

MIT License
