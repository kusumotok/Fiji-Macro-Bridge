param(
    [string]$InstallRoot = ""
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Content
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

if (-not $InstallRoot) {
    $InstallRoot = Join-Path $env:LOCALAPPDATA "FijiMacroBridge"
}

$manifestPath = Join-Path $InstallRoot "install_manifest.json"
if (-not (Test-Path $manifestPath)) {
    throw "Install manifest not found: $manifestPath"
}

$manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json

function Remove-ClaudeServerEntry {
    param([string]$ConfigPath)

    if (-not $ConfigPath -or -not (Test-Path $ConfigPath)) {
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
    $json = $config | ConvertTo-Json -Depth 20
    Write-Utf8NoBom -Path $ConfigPath -Content $json
}

if ($manifest.claude_config_updated) {
    Remove-ClaudeServerEntry -ConfigPath $manifest.claude_config_path
}

if ($manifest.installed_jar -and (Test-Path $manifest.installed_jar)) {
    Remove-Item -Path $manifest.installed_jar -Force
}

if (Test-Path $InstallRoot) {
    Remove-Item -Path $InstallRoot -Recurse -Force
}

Write-Host ""
Write-Host "Removed Fiji Macro Bridge from:"
Write-Host "  $InstallRoot"
if ($manifest.installed_jar) {
    Write-Host "Removed plugin JAR:"
    Write-Host "  $($manifest.installed_jar)"
}
if ($manifest.claude_config_updated) {
    Write-Host "Removed Claude Desktop MCP entry from:"
    Write-Host "  $($manifest.claude_config_path)"
}
Write-Host ""
Write-Host "Restart your MCP client if it is running."
