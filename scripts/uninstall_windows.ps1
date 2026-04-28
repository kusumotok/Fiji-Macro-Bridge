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

function Invoke-DeferredCleanup {
    param([string]$TargetDir)

    $cleanupBat = Join-Path $env:TEMP ("fiji-macro-bridge-cleanup-" + [guid]::NewGuid().ToString() + ".bat")
    $cleanupLines = @(
        "@echo off",
        "timeout /t 2 /nobreak >nul",
        ('rmdir /s /q "{0}"' -f $TargetDir),
        ('del /f /q "{0}"' -f $cleanupBat)
    )
    [System.IO.File]::WriteAllLines($cleanupBat, $cleanupLines, (New-Object System.Text.ASCIIEncoding))
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $cleanupBat -WindowStyle Hidden
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

function Remove-CodexManagedBlock {
    param([string]$ConfigPath)

    if (-not $ConfigPath -or -not (Test-Path $ConfigPath)) {
        return
    }

    $raw = Get-Content -Path $ConfigPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return
    }

    $begin = "# BEGIN Fiji Macro Bridge"
    $end = "# END Fiji Macro Bridge"
    $updated = [regex]::Replace($raw, [regex]::Escape($begin) + ".*?" + [regex]::Escape($end) + "(\r?\n)?", "", 'Singleline')
    Write-Utf8NoBom -Path $ConfigPath -Content $updated
}

if ($manifest.configured_clients) {
    foreach ($client in $manifest.configured_clients) {
        if ($client.name -eq "claude-desktop") {
            Remove-ClaudeServerEntry -ConfigPath $client.path
        } elseif ($client.name -eq "codex-app") {
            Remove-CodexManagedBlock -ConfigPath $client.path
        }
    }
}

if ($manifest.installed_jar -and (Test-Path $manifest.installed_jar)) {
    Remove-Item -Path $manifest.installed_jar -Force
}

if (Test-Path $InstallRoot) {
    Invoke-DeferredCleanup -TargetDir $InstallRoot
}

Write-Host ""
Write-Host "Removed Fiji Macro Bridge from:"
Write-Host "  $InstallRoot"
if ($manifest.installed_jar) {
    Write-Host "Removed plugin JAR:"
    Write-Host "  $($manifest.installed_jar)"
}
if ($manifest.configured_clients) {
    foreach ($client in $manifest.configured_clients) {
        Write-Host "Removed managed client config from:"
        Write-Host "  $($client.path)"
    }
}
Write-Host ""
Write-Host "Scheduled removal of the local install directory."
Write-Host "Restart your MCP client if it is running."
