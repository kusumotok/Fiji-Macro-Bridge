# Build Windows Release

This document is for maintainers preparing a Windows release bundle.

## Goal

Produce a release directory containing:

- `fiji-mcp-server.exe`
- `fiji-macro-bridge-1.0.0.jar`
- `install_windows.ps1`
- `install.bat`
- `uninstall_windows.ps1`
- `uninstall.bat`
- `LICENSE.txt`
- `THIRD_PARTY_NOTICES.md`
- `PYTHON_BUNDLE_LICENSES.md`
- `requirements-lock.txt`

## Prerequisites

- Windows
- `py` launcher available
- Java / Maven available if `plugin/target/fiji-macro-bridge-1.0.0.jar` is not already built

## One-command build

From the repository root:

```bat
scripts\build_windows_release.bat
```

The script will:

1. Create `.venv-release` if missing
2. Install `server/requirements-build.txt`
3. Freeze Python dependency versions to `requirements-lock.txt`
4. Generate `PYTHON_BUNDLE_LICENSES.md`
5. Build `dist\fiji-mcp-server.exe` with `server/fiji_mcp_macro.spec`
6. Build the plugin JAR if needed
7. Collect release assets into `release\windows-x64`

## Notes

- The bundled executable redistributes Python dependencies, so `PYTHON_BUNDLE_LICENSES.md` should be shipped with the release assets.
- The plugin JAR already embeds `META-INF/LICENSE` and `META-INF/THIRD_PARTY_NOTICES`.
- Commit source changes, but do not commit `dist/`, `build/`, `.venv-release/`, or `release/`.
