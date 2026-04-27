# Fiji Macro Bridge

MCP client から GUI 動作中の Fiji を最小ツール面で操作するための bridge です。

一般利用者は source を clone せず、GitHub Releases の配布物を使ってください。

詳細仕様は [SPEC.md](./SPEC.md) を参照してください。

## Release-first

- 利用者向けの標準導線は release 配布物です
- source build は contributor / power user 向けです
- Windows 向けの exe packaging 手順は [docs/build-windows-release.md](./docs/build-windows-release.md) にまとめています

## Build From Source

```bash
pip install -r requirements.txt
cd plugin
mvn package
```

生成された `plugin/target/fiji-macro-bridge-1.0.0.jar` を Fiji の `plugins/` に配置してください。

その後、Fiji で `Plugins > Macro Bridge > Fiji Macro Bridge` を実行します。

## MCP Client 設定

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

source build では `python fiji_mcp_macro.py` を MCP server command に指定します。release 配布物では Python の代わりに bundled executable を指定します。

`launch_fiji` は内部で `ImageJ-win64.exe -eval "run('Fiji Macro Bridge', '5048');"` を使って plugin を起動します。

## 注意

- timeout 後は Fiji の再起動が必要になることがあります。
- dialog を出す macro（`waitForUser` 等）は非対応です。

## License

MIT
