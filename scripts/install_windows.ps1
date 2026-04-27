param(
    [string]$BundleDir = "",
    [string]$FijiPath = "",
    [string]$ClaudeConfigPath = "",
    [switch]$SkipClaudeConfig
)

$ErrorActionPreference = "Stop"

try {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $script:GuiAvailable = $true
} catch {
    $script:GuiAvailable = $false
}

function Resolve-BundleDir {
    param([string]$InputPath)

    if ($InputPath) {
        return (Resolve-Path $InputPath).Path
    }
    return (Resolve-Path $PSScriptRoot).Path
}

function Find-FijiPath {
    $candidates = @(
        "$env:USERPROFILE\Fiji.app\ImageJ-win64.exe",
        "$env:USERPROFILE\Fiji.app\ImageJ-win32.exe",
        "$env:ProgramFiles\Fiji.app\ImageJ-win64.exe",
        "${env:ProgramFiles(x86)}\Fiji.app\ImageJ-win32.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }
    return $null
}

function Select-FijiPathDialog {
    if (-not $script:GuiAvailable) {
        return $null
    }

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select Fiji executable"
    $dialog.Filter = "Fiji executable (ImageJ-win*.exe)|ImageJ-win*.exe|Executable files (*.exe)|*.exe|All files (*.*)|*.*"
    $dialog.Multiselect = $false

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    return $null
}

function Confirm-Or-SelectFijiPath {
    param([string]$DetectedPath)

    if (-not $DetectedPath) {
        $selected = Select-FijiPathDialog
        if ($selected) {
            return $selected
        }
        throw "Fiji executable not found automatically. Re-run with -FijiPath <path-to-ImageJ-win64.exe> or choose it from the dialog."
    }

    Write-Host ""
    Write-Host "Detected Fiji executable:"
    Write-Host "  $DetectedPath"
    Write-Host ""
    $choice = Read-Host "Press Enter to use it, type 'select' to choose another one, or type 'cancel' to abort"

    if ([string]::IsNullOrWhiteSpace($choice)) {
        return $DetectedPath
    }

    switch ($choice.Trim().ToLowerInvariant()) {
        "select" {
            $selected = Select-FijiPathDialog
            if ($selected) {
                return $selected
            }
            throw "No Fiji executable selected."
        }
        "cancel" {
            throw "Installation cancelled."
        }
        default {
            Write-Host "Unrecognized choice. Using detected Fiji path."
            return $DetectedPath
        }
    }
}

function Ensure-ParentDir {
    param([string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Write-ConfigSnippet {
    param(
        [string]$OutputPath,
        [string]$ExePath,
        [string]$ResolvedFijiPath
    )

    $snippet = [ordered]@{
        mcpServers = [ordered]@{
            "fiji-macro" = [ordered]@{
                command = $ExePath
                env = [ordered]@{
                    FIJI_PATH = $ResolvedFijiPath
                    FIJI_PORT = "5048"
                }
            }
        }
    }

    $snippet | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
}

function Remove-ClaudeServerEntry {
    param([string]$ConfigPath)

    if (-not (Test-Path $ConfigPath)) {
        return
    }

    $raw = Get-Content -Path $ConfigPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return
    }

    $config = $raw | ConvertFrom-Json
    if (-not ($config.PSObject.Properties.Name -contains "mcpServers")) {
        return
    }
    if (-not ($config.mcpServers.PSObject.Properties.Name -contains "fiji-macro")) {
        return
    }

    $config.mcpServers.PSObject.Properties.Remove("fiji-macro")
    $config | ConvertTo-Json -Depth 20 | Set-Content -Path $ConfigPath -Encoding UTF8
}

function Update-ClaudeConfig {
    param(
        [string]$ConfigPath,
        [string]$ExePath,
        [string]$ResolvedFijiPath
    )

    Ensure-ParentDir $ConfigPath

    if (Test-Path $ConfigPath) {
        $raw = Get-Content -Path $ConfigPath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            $config = [pscustomobject]@{}
        } else {
            $config = $raw | ConvertFrom-Json
        }
    } else {
        $config = [pscustomobject]@{}
    }

    if (-not ($config.PSObject.Properties.Name -contains "mcpServers")) {
        $config | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value ([pscustomobject]@{})
    }

    $serverEntry = [pscustomobject]@{
        command = $ExePath
        env = [pscustomobject]@{
            FIJI_PATH = $ResolvedFijiPath
            FIJI_PORT = "5048"
        }
    }
    $config.mcpServers | Add-Member -MemberType NoteProperty -Name "fiji-macro" -Value $serverEntry -Force

    $config | ConvertTo-Json -Depth 20 | Set-Content -Path $ConfigPath -Encoding UTF8
}

$resolvedBundleDir = Resolve-BundleDir $BundleDir

$bundledServerExe = Join-Path $resolvedBundleDir "fiji-mcp-server.exe"
if (-not (Test-Path $bundledServerExe)) {
    throw "Bundled MCP server executable not found: $bundledServerExe"
}
$bundledServerExe = (Resolve-Path $bundledServerExe).Path

$jarPath = Join-Path $resolvedBundleDir "fiji-macro-bridge-1.0.0.jar"
if (-not (Test-Path $jarPath)) {
    throw "Bundled Fiji plugin JAR not found: $jarPath"
}
$jarPath = (Resolve-Path $jarPath).Path

if (-not $FijiPath) {
    $FijiPath = Find-FijiPath
    $FijiPath = Confirm-Or-SelectFijiPath $FijiPath
}
if (-not $FijiPath) {
    throw "Fiji executable not found automatically. Re-run with -FijiPath <path-to-ImageJ-win64.exe>."
}
if (-not (Test-Path $FijiPath)) {
    throw "Configured Fiji executable does not exist: $FijiPath"
}
$FijiPath = (Resolve-Path $FijiPath).Path

$fijiRoot = Split-Path -Parent $FijiPath
$pluginsDir = Join-Path $fijiRoot "plugins"
if (-not (Test-Path $pluginsDir)) {
    throw "Fiji plugins directory not found: $pluginsDir"
}

$installRoot = Join-Path $env:LOCALAPPDATA "FijiMacroBridge"
if (-not (Test-Path $installRoot)) {
    New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
}

$installedExe = Join-Path $installRoot "fiji-mcp-server.exe"
Copy-Item -Path $bundledServerExe -Destination $installedExe -Force

$installedJar = Join-Path $pluginsDir "fiji-macro-bridge-1.0.0.jar"
Copy-Item -Path $jarPath -Destination $installedJar -Force

$snippetPath = Join-Path $resolvedBundleDir "fiji-macro-config-snippet.json"
Write-ConfigSnippet -OutputPath $snippetPath -ExePath $installedExe -ResolvedFijiPath $FijiPath

if (-not $SkipClaudeConfig) {
    if (-not $ClaudeConfigPath) {
        $ClaudeConfigPath = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
    }
    Update-ClaudeConfig -ConfigPath $ClaudeConfigPath -ExePath $installedExe -ResolvedFijiPath $FijiPath
}

$uninstallPs1Source = Join-Path $resolvedBundleDir "uninstall_windows.ps1"
$uninstallBatSource = Join-Path $resolvedBundleDir "uninstall.bat"
if (Test-Path $uninstallPs1Source) {
    Copy-Item -Path $uninstallPs1Source -Destination (Join-Path $installRoot "uninstall_windows.ps1") -Force
}
if (Test-Path $uninstallBatSource) {
    Copy-Item -Path $uninstallBatSource -Destination (Join-Path $installRoot "uninstall.bat") -Force
}

$manifest = [ordered]@{
    install_root = $installRoot
    installed_exe = $installedExe
    installed_jar = $installedJar
    fiji_path = $FijiPath
    claude_config_path = $ClaudeConfigPath
    claude_config_updated = (-not $SkipClaudeConfig)
}
($manifest | ConvertTo-Json -Depth 10) | Set-Content -Path (Join-Path $installRoot "install_manifest.json") -Encoding UTF8

Write-Host ""
Write-Host "Installed MCP server to: $installedExe"
Write-Host "Installed plugin JAR to: $installedJar"
Write-Host "Generated MCP config snippet: $snippetPath"
if (-not $SkipClaudeConfig) {
    Write-Host "Updated Claude Desktop config: $ClaudeConfigPath"
} else {
    Write-Host "Skipped Claude Desktop config update."
}
Write-Host "Uninstaller location: $(Join-Path $installRoot 'uninstall.bat')"
Write-Host ""
Write-Host "Restart your MCP client after installation."
