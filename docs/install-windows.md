# Install On Windows

This document is for end users installing a prepared Windows release bundle.

## Expected bundle contents

- `fiji-mcp-server.exe`
- `Fiji_Macro_Bridge.jar`
- `install_windows.ps1`
- `install.bat`
- `setup_clients.ps1`
- `setup_clients.bat`
- `uninstall_windows.ps1`
- `uninstall.bat`
- `LICENSE.txt`
- `THIRD_PARTY_NOTICES.md`

## Default install path

The installer will:

1. Copy `fiji-mcp-server.exe` into `%LOCALAPPDATA%\FijiMacroBridge\`
2. Copy `Fiji_Macro_Bridge.jar` into Fiji's `plugins` directory
3. Run `setup_clients` to configure Claude Desktop and/or Codex app
4. Generate copy-paste snippets for manual setup, including the detected `FIJI_PATH`
5. If Fiji is auto-detected, show the detected path and let you accept it or choose another executable
6. Install an uninstaller into `%LOCALAPPDATA%\FijiMacroBridge\`
7. Run a small smoke test that validates installed files and manifest data

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
Use the `Skip` button in the client setup dialog. The installer will still generate manual setup snippets.
```

## Uninstall

Run:

```bat
%LOCALAPPDATA%\FijiMacroBridge\uninstall.bat
```

This removes:

1. `%LOCALAPPDATA%\FijiMacroBridge\`
2. `Fiji_Macro_Bridge.jar` from Fiji's `plugins` directory
3. The `fiji-macro` entry from Claude Desktop config if the installer added it
4. The managed `Fiji Macro Bridge` block from Codex app config if the installer added it

## Troubleshooting

### Fiji was not found automatically

- Use `install.bat -FijiPath "C:\path\to\Fiji.app\ImageJ-win64.exe"`
- Or type `select` when prompted and choose the Fiji executable manually

### Claude Desktop config update failed

- Use the generated `manual-setup-claude-desktop.json` manually
- If you use the packaged Claude Desktop build, the config may live under `AppData\Local\Packages\...\LocalCache\Roaming\Claude\`
- If the config was modified, a timestamped backup should exist next to the original file

### Codex app config update failed

- Use the generated `manual-setup-codex-app.toml` manually
- The default config path is `%USERPROFILE%\.codex\config.toml`

### The plugin does not appear in Fiji

- Confirm that `Fiji_Macro_Bridge.jar` exists in Fiji's `plugins` directory
- Restart Fiji after installation

## Notes

- Restart Claude Desktop or your MCP client after installation.
- The installer smoke test only checks installed files and generated JSON; it does not prove that Fiji is already connected.
- If you press `Skip`, use the generated manual setup snippets as the basis for your client-specific config.
