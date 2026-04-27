# Fiji Macro Bridge v1 仕様

## 概要

Claude Desktop から GUI 動作中の Fiji を最小ツール面で操作する。

公開ツールは `launch_fiji`, `run_macro`, `get_results`, `get_image_content` の 4 つに限定する。  
Java 側は TCP + JSON の最小 bridge、Python 側は MCP 変換層のみを持つ。

## スコープ

- 対応操作は ImageJ Macro 実行、Results Table 読み出し、アクティブ画像の PNG 取得、Fiji 起動補助のみ
- `run_js`、ROI 専用ツール、window screenshot、`check_connection` ツールは v1 では扱わない
- Results Table は共有状態をそのまま返し、呼び出し単位の分離はしない

## 非対応

- Debug Window 相当の詳細診断情報の完全再現
- timeout 後の自動回復
- arbitrary Fiji version 互換
- 複数 Fiji インスタンスの同時制御
- old `fiji-mcp-bridge-1.0.0.jar` との同一ポート共存

## アーキテクチャ

`Claude Desktop -> MCP -> fiji_mcp_macro.py -> TCP:5048 -> FijiMacroBridge.java -> Fiji GUI`

- `launch_fiji` のみ Python から `subprocess.Popen` で Fiji を起動する
- Java/TCP の画像返却は bare base64、MCP 層では `ImageContent` に変換する

## リポジトリ構成

- `fiji_mcp_macro.py`
- `requirements.txt`
- `README.md`
- `SPEC.md`
- `plugin/pom.xml`
- `plugin/src/main/java/fiji/mcp/FijiMacroBridge.java`
- `plugin/src/main/resources/plugins.config`
- `.gitignore`

## 公開インターフェース

### `launch_fiji`

- 入力: なし
- 出力: `"Already connected"` または起動成功/失敗テキスト

### `run_macro`

- 入力: `{ "macro": string }`
- 成功時出力: `{"result": string, "log_lines_added": number, "log_total_lines": number, "new_images_opened": [{"id": number, "title": string}], "results_table_rows": number}`
- 失敗時出力: エラー文字列

### `get_results`

- 入力: `{}`
- 出力: compact JSON 配列を `TextContent` で返す

### `get_image_content`

- 入力: `{}`
- 出力: `ImageContent(type="image", data=..., mimeType="image/png")`

## Java Plugin 仕様

- クラス名は `fiji.mcp.FijiMacroBridge`
- メニュー登録は `Plugins>Macro Bridge, "Fiji Macro Bridge", fiji.mcp.FijiMacroBridge`
- 依存は `net.imagej:ij:1.54p` を `provided`、`org.json:json:20231013` を shade
- Java 8 target

### TCP プロトコル

- request: `{"command":"...","args":{...}}`
- success: `{"status":"success","result":...}`
- error: `{"status":"error","error":"...","stackTrace":"..."}`
- 1 接続 1 リクエスト
- UTF-8
- 改行終端 JSON
- 内部用コマンドとして `ping -> "pong"` を持ち、Python 側の readiness probe にのみ使う

### `run_macro`

- `Interpreter` を新規作成して `setIgnoreErrors(true)` を設定する
- `interpreter.run(args.getString("macro"), null)` を worker thread で実行する
- `interpreter.wasError()` が `true` の場合は `getErrorMessage()` と `getLineNumber()` を使って error response を返す
- `null` は `""` に正規化する
- `"[aborted]"` は success にせず `{"status":"error","error":"Macro aborted"}` を返す
- success 時は macro の戻り値文字列に加えて、実行前後の log 行数差分、新規オープン画像一覧、Results Table 行数を `JSONObject` で返す
- 実行中に操作不能な modal dialog が出た場合は監視スレッドで自動で閉じ、タイトルと本文を error response として返す
- ダイアログ本文は AWT / Swing コンポーネントの表示テキストから回収する
- Debug Window の追加情報は取得しない
- EDT ラップはしない
- timeout は `600000ms`
- timeout 時は worker thread を `interrupt()` するだけで停止保証はしない
- timeout 後も macro が裏で走り続ける可能性がある

### `get_image_content`

- `WindowManager.getCurrentImage()` が `null` なら error
- ROI または overlay がある場合は `flatten()`、なければ `getBufferedImage()`
- PNG 化して Base64 文字列を `result` に入れて返す
- window screenshot ではなく active image export と定義する

### `get_results`

- `ResultsTable.getResultsTable()` を読み、row object の `JSONArray` を返す
- 空テーブルは `[]`
- `getHeadings()` を走査し、`null` / 空文字 / `"Label"` はスキップする
- `getColumnIndex(heading) == ResultsTable.COLUMN_NOT_FOUND` はスキップする
- private `stringColumns` を reflection で取得する
- reflection 取得失敗時は silent fallback せず error response を返す
- `stringColumns` に存在する列は `getStringValue(col, row)` を JSON string として扱い、`null` は `JSONObject.NULL` にする
- それ以外の列は `getValueAsDouble(col, row)` を使い、有限値なら number、`NaN` / `Infinity` は `JSONObject.NULL` にする
- `rt.getLabel(row)` が非 `null` かつ非空なら `"Label"` を追加する
- 新規計測だけ欲しい場合は事前に `run_macro` で `run("Clear Results");` を呼ぶ
- 返るのは共有 Results Table 全体であり、呼び出し単位の分離はしない

### 実行制約

- 非対話 macro のみ対応
- `waitForUser` など dialog を出す macro は v1 非対応
- modal dialog は可能な限り回収して error response に変換するが、すべての UI 差分を保証しない
- `NaN` / `Infinity` は IJM 上の正常値として扱われるため、`run_macro` では汎用的な error にはしない
- timeout や dialog hang 後の Fiji 状態は不定
- 必要なら Fiji を再起動する

## Python MCP Server 仕様

- 依存は `mcp>=1.0.0` のみ
- `.env` や `python-dotenv` は使わない
- `FIJI_PATH` は必須
- `FIJI_PORT` は任意、既定値は `5048`
- `FIJI_TIMEOUT` は任意、既定値は `600`
- host は `localhost` 固定

### `_send_command`

- `socket.connect -> sendall(json + "\n") -> 改行まで recv -> json.loads`
- Java error response は Python 側で例外化する
- `ConnectionRefusedError` は `"Fiji is not running. Use launch_fiji first."` のメッセージで例外化し、通常結果にはしない

### `launch_fiji`

- 先に protocol-level probe を送って既存 bridge 応答を確認する
- probe 成功なら `"Already connected"` を返して新規起動しない
- 未接続時のみ `[FIJI_PATH, "-eval", f"run('Fiji Macro Bridge', '{self.fiji_port}');"]` で起動する
- Windows では `CREATE_NEW_PROCESS_GROUP | DETACHED_PROCESS`
- 起動後は `LAUNCH_WAIT_SEC = 30`, `RETRY_INTERVAL = 2` で同じ probe を使って readiness を確認する

### `run_macro`

- `{"command":"run_macro","args":{"macro":"..."}}` を送る
- success の result object を compact JSON にして `TextContent` で返す
- error は `Error: ...` の形で `TextContent` にする

### `get_results`

- `{"command":"get_results","args":{}}` を送る
- `json.dumps(result, ensure_ascii=False, separators=(",", ":"))` で compact JSON にして `TextContent` で返す

### `get_image_content`

- `{"command":"get_image_content","args":{}}` を送る
- Java/TCP では bare base64 string を受け取る
- MCP では `ImageContent(type="image", data=result, mimeType="image/png")` に変換する

## ビルド/配布仕様

- `pom.xml` は `maven-shade-plugin` で `org.json` のみ同梱する
- `plugins.config` を JAR に含める
- 生成物は `fiji-macro-bridge-1.0.0.jar`
- `requirements.txt` は `mcp>=1.0.0`

## Claude Desktop 設定

- `command` は `python`
- `args` は `["path/to/Fiji_Macro_Bridge/fiji_mcp_macro.py"]`
- `env` に `FIJI_PATH` と `FIJI_PORT` を渡す
- `FIJI_PATH` の例は `path/to/Fiji.app/ImageJ-win64.exe`

設定例:

```json
{
  "mcpServers": {
    "fiji-macro": {
      "command": "python",
      "args": ["path/to/Fiji_Macro_Bridge/fiji_mcp_macro.py"],
      "env": {
        "FIJI_PATH": "path/to/Fiji.app/ImageJ-win64.exe",
        "FIJI_PORT": "5048"
      }
    }
  }
}
```

## テスト/受け入れ基準

- `mvn package` が成功し、JAR に `plugins.config` と shaded `org.json` が含まれる
- Fiji で `Plugins > Macro Bridge > Fiji Macro Bridge` 実行後に TCP `5048` が待受になる
- `run_macro("getTitle()")` で `result` を含む JSON object が返る
- `run_macro('open("..."); run("Clear Results"); run("Measure");')` が成功する
- macro 異常系では `Interpreter` または dialog monitor により Java error response になる
- `get_results` は compact JSON 配列を返す
- 数値列 `NaN` は JSON `null`
- Label がある行では `"Label"` キーが返る
- `get_image_content` は Java/TCP では bare base64、MCP では画像として返る
- `launch_fiji` は未接続時のみ起動し、接続済み再実行では `"Already connected"` を返す
- timeout を起こす macro では error が返り、README の制約説明どおり Fiji 再起動が必要になりうる

## 制約と前提

- v1 は Windows + Claude Desktop を主対象とする
- arbitrary string column 対応は `ij 1.54p` の private `stringColumns` 反射に依存する
- reflection が使えない別バージョン互換は v1 では追わない
- `run_js` は追加しない
- host は `localhost` 固定、port は `FIJI_PORT` で上書き可能

## 参照元

- 前身実装: https://github.com/kusumotok/fiji-mcp-bridge
