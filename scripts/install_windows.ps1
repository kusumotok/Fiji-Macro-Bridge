param(
    [string]$BundleDir = "",
    [string]$FijiPath = ""
)

$ErrorActionPreference = "Stop"

try {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $script:GuiAvailable = $true
} catch {
    $script:GuiAvailable = $false
}

function Show-ResultDialog {
    param(
        [string]$Title,
        [string]$Message,
        [string]$Icon = "Information"
    )

    if (-not $script:GuiAvailable) {
        return
    }

    $buttons = [System.Windows.Forms.MessageBoxButtons]::OK
    $iconEnum = [System.Windows.Forms.MessageBoxIcon]::$Icon
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, $buttons, $iconEnum) | Out-Null
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
        "$env:USERPROFILE\Fiji.app\Fiji-windows-x64.exe",
        "$env:USERPROFILE\Fiji.app\Fiji-windows.exe",
        "$env:ProgramFiles\Fiji.app\ImageJ-win64.exe",
        "$env:ProgramFiles\Fiji.app\Fiji-windows-x64.exe",
        "${env:ProgramFiles(x86)}\Fiji.app\ImageJ-win32.exe",
        "${env:ProgramFiles(x86)}\Fiji.app\Fiji-windows.exe"
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
    $dialog.Filter = "Fiji executable (ImageJ-win*.exe;Fiji-windows*.exe)|ImageJ-win*.exe;Fiji-windows*.exe|Executable files (*.exe)|*.exe|All files (*.*)|*.*"
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

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Content
    )

    Ensure-ParentDir $Path
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

# PS 5.1's ConvertTo-Json aligns values to the colon, producing a staircase
# layout for nested objects.  Compress first, then re-indent cleanly.
function ConvertTo-Json2 {
    param([Parameter(ValueFromPipeline)][object]$InputObject, [int]$Depth = 10)
    process {
        $compressed = $InputObject | ConvertTo-Json -Depth $Depth -Compress
        Format-Json $compressed
    }
}

function Format-Json {
    param([string]$Json, [int]$IndentSize = 2)
    $indent = 0
    $sb = [System.Text.StringBuilder]::new()
    $inString = $false
    $escape = $false
    foreach ($ch in $Json.ToCharArray()) {
        if ($escape) {
            $sb.Append($ch) | Out-Null
            $escape = $false
            continue
        }
        if ($ch -eq '\' -and $inString) {
            $sb.Append($ch) | Out-Null
            $escape = $true
            continue
        }
        if ($ch -eq '"') { $inString = -not $inString }
        if ($inString) { $sb.Append($ch) | Out-Null; continue }
        switch ($ch) {
            '{' {
                $sb.Append($ch) | Out-Null; $indent++
                $sb.Append("`n" + (' ' * ($indent * $IndentSize))) | Out-Null
            }
            '[' {
                $sb.Append($ch) | Out-Null; $indent++
                $sb.Append("`n" + (' ' * ($indent * $IndentSize))) | Out-Null
            }
            '}' {
                $indent--
                $sb.Append("`n" + (' ' * ($indent * $IndentSize))) | Out-Null
                $sb.Append($ch) | Out-Null
            }
            ']' {
                $indent--
                $sb.Append("`n" + (' ' * ($indent * $IndentSize))) | Out-Null
                $sb.Append($ch) | Out-Null
            }
            ',' {
                $sb.Append($ch) | Out-Null
                $sb.Append("`n" + (' ' * ($indent * $IndentSize))) | Out-Null
            }
            ':' { $sb.Append(': ') | Out-Null }
            default { if ($ch -ne ' ') { $sb.Append($ch) | Out-Null } }
        }
    }
    $sb.ToString()
}

function Test-JsonFile {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Expected JSON file was not created: $Path"
    }

    $raw = Get-Content -Path $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "JSON file is empty: $Path"
    }

    $null = $raw | ConvertFrom-Json
}

try {
    $resolvedBundleDir = Resolve-BundleDir $BundleDir

    $bundledServerExe = Join-Path $resolvedBundleDir "fiji-mcp-server.exe"
    if (-not (Test-Path $bundledServerExe)) {
        throw "Bundled MCP server executable not found: $bundledServerExe"
    }
    $bundledServerExe = (Resolve-Path $bundledServerExe).Path

    $jarPath = Join-Path $resolvedBundleDir "Fiji_Macro_Bridge.jar"
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
    $exeAlreadyPresent = Test-Path $installedExe
    Copy-Item -Path $bundledServerExe -Destination $installedExe -Force

    $installedJar = Join-Path $pluginsDir "Fiji_Macro_Bridge.jar"
    $jarAlreadyPresent = Test-Path $installedJar
    Copy-Item -Path $jarPath -Destination $installedJar -Force

    $uninstallPs1Source = Join-Path $resolvedBundleDir "uninstall_windows.ps1"
    $uninstallBatSource = Join-Path $resolvedBundleDir "uninstall.bat"
    $setupPs1Source = Join-Path $resolvedBundleDir "setup_clients.ps1"
    $setupBatSource = Join-Path $resolvedBundleDir "setup_clients.bat"
    if (Test-Path $uninstallPs1Source) {
        Copy-Item -Path $uninstallPs1Source -Destination (Join-Path $installRoot "uninstall_windows.ps1") -Force
    }
    if (Test-Path $uninstallBatSource) {
        Copy-Item -Path $uninstallBatSource -Destination (Join-Path $installRoot "uninstall.bat") -Force
    }
    if (Test-Path $setupPs1Source) {
        Copy-Item -Path $setupPs1Source -Destination (Join-Path $installRoot "setup_clients.ps1") -Force
    }
    if (Test-Path $setupBatSource) {
        Copy-Item -Path $setupBatSource -Destination (Join-Path $installRoot "setup_clients.bat") -Force
    }

    $manifest = [ordered]@{
        install_root = $installRoot
        installed_exe = $installedExe
        installed_jar = $installedJar
        fiji_path = $FijiPath
        configured_clients = @()
    }
    $manifestJson = $manifest | ConvertTo-Json2 -Depth 10
    $manifestPath = Join-Path $installRoot "install_manifest.json"
    Write-Utf8NoBom -Path $manifestPath -Content $manifestJson
    Test-JsonFile $manifestPath

    if (-not (Test-Path $installedExe)) {
        throw "Installed MCP server executable is missing: $installedExe"
    }
    if (-not (Test-Path $installedJar)) {
        throw "Installed plugin JAR is missing: $installedJar"
    }

    $setupScriptPath = Join-Path $installRoot "setup_clients.ps1"
    if (Test-Path $setupScriptPath) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $setupScriptPath `
            -InstallRoot $installRoot `
            -BundleDir $resolvedBundleDir `
            -FijiPath $FijiPath `
            -ServerExePath $installedExe `
            -ManifestPath $manifestPath
        if ($LASTEXITCODE -ne 0) {
            throw "Client setup failed."
        }
    }

    Write-Host ""
    if ($exeAlreadyPresent -or $jarAlreadyPresent) {
        Write-Host "Updated existing Fiji Macro Bridge installation."
    } else {
        Write-Host "Installed Fiji Macro Bridge."
    }
    Write-Host "MCP server path: $installedExe"
    Write-Host "Plugin JAR path: $installedJar"
    Write-Host "Client setup helper: $(Join-Path $installRoot 'setup_clients.bat')"
    Write-Host "Uninstaller location: $(Join-Path $installRoot 'uninstall.bat')"
    Write-Host "Smoke test: installed files and base manifest parsed successfully."
    Write-Host ""
    Write-Host "Restart your MCP client after installation."
}
catch {
    Show-ResultDialog -Title "Installation Failed" -Message $_.Exception.Message -Icon "Error"
    throw
}
