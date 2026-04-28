# v1.0.0

Initial public release of Fiji Macro Bridge.

## Included in the Windows release bundle

- `fiji-mcp-server.exe`
- `Fiji_Macro_Bridge.jar`
- `install.bat`
- `uninstall.bat`
- `setup_clients.bat`

## Installation

1. Download and unzip `fiji-macro-bridge-windows-x64.zip`
2. Run `install.bat`
3. Restart your MCP client

Detailed Windows install instructions are in [install-windows.md](./install-windows.md).

## Notes

- This first release is Windows first.
- The installer updates Claude Desktop config automatically and also generates a config snippet for other MCP clients.
- Client config setup is separated from file installation, and can target Claude Desktop and Codex app independently.
- The uninstaller is installed to `%LOCALAPPDATA%\FijiMacroBridge\uninstall.bat`.

## Known limitations

- Fiji must run with a GUI.
- After a timeout, Fiji may need to be restarted.
- Dialog-based macros such as `waitForUser` are not supported.
- Non-Claude MCP clients are not auto-configured; use the generated config snippet as a starting point.
