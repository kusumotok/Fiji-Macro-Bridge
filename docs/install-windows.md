# Install On Windows

This document is for end users installing a prepared Windows release bundle.

## Expected bundle contents

- `fiji-mcp-server.exe`
- `fiji-macro-bridge-1.0.0.jar`
- `install_windows.ps1`
- `install.bat`
- `LICENSE.txt`
- `THIRD_PARTY_NOTICES.md`

## Default install path

The installer will:

1. Copy `fiji-mcp-server.exe` into `%LOCALAPPDATA%\FijiMacroBridge\`
2. Copy `fiji-macro-bridge-1.0.0.jar` into Fiji's `plugins` directory
3. Update Claude Desktop's MCP config at `%APPDATA%\Claude\claude_desktop_config.json`
4. Generate `fiji-macro-config-snippet.json` for other MCP clients
5. If Fiji is auto-detected, show the detected path and let you accept it or choose another executable
6. Install an uninstaller into `%LOCALAPPDATA%\FijiMacroBridge\`

## Run it

Double-click `install.bat`, or run:

```bat
install.bat
```

If Fiji is found automatically, press Enter to accept the detected executable, type `select` to choose a different Fiji executable, or type `cancel` to stop.
The installer accepts both `ImageJ-win*.exe` and `Fiji-windows*.exe`.

If Fiji is not installed in a standard location, pass the executable path explicitly:

```bat
install.bat -FijiPath "C:\path\to\Fiji.app\ImageJ-win64.exe"
```

If you do not want the script to edit Claude Desktop config automatically:

```bat
install.bat -SkipClaudeConfig
```

## Uninstall

Run:

```bat
%LOCALAPPDATA%\FijiMacroBridge\uninstall.bat
```

This removes:

1. `%LOCALAPPDATA%\FijiMacroBridge\`
2. `fiji-macro-bridge-1.0.0.jar` from Fiji's `plugins` directory
3. The `fiji-macro` entry from Claude Desktop config if the installer added it

## Troubleshooting

### Fiji was not found automatically

- Use `install.bat -FijiPath "C:\path\to\Fiji.app\ImageJ-win64.exe"`
- Or type `select` when prompted and choose the Fiji executable manually

### Claude Desktop config update failed

- Re-run with `-SkipClaudeConfig`
- Use the generated `fiji-macro-config-snippet.json` manually
- If you use the packaged Claude Desktop build, the config may live under `AppData\Local\Packages\...\LocalCache\Roaming\Claude\`

### The plugin does not appear in Fiji

- Confirm that `fiji-macro-bridge-1.0.0.jar` exists in Fiji's `plugins` directory
- Restart Fiji after installation

## Notes

- Restart Claude Desktop or your MCP client after installation.
- For non-Claude clients, use the generated `fiji-macro-config-snippet.json` as the basis for your client-specific config.
