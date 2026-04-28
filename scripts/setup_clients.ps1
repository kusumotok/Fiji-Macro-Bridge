param(
    [string]$InstallRoot = "",
    [string]$BundleDir = "",
    [string]$FijiPath = "",
    [string]$ServerExePath = "",
    [string]$ManifestPath = ""
)

$ErrorActionPreference = "Stop"

try {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    Add-Type -AssemblyName System.Drawing | Out-Null
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

function Ensure-ParentDir {
    param([string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    Ensure-ParentDir $Path
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Backup-File {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$Path.bak-$stamp"
    Copy-Item -Path $Path -Destination $backupPath -Force
    return $backupPath
}

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
        if ($escape) { $sb.Append($ch) | Out-Null; $escape = $false; continue }
        if ($ch -eq '\' -and $inString) { $sb.Append($ch) | Out-Null; $escape = $true; continue }
        if ($ch -eq '"') { $inString = -not $inString }
        if ($inString) { $sb.Append($ch) | Out-Null; continue }
        switch ($ch) {
            '{' { $sb.Append($ch) | Out-Null; $indent++; $sb.Append("`n" + (' ' * ($indent * $IndentSize))) | Out-Null }
            '[' { $sb.Append($ch) | Out-Null; $indent++; $sb.Append("`n" + (' ' * ($indent * $IndentSize))) | Out-Null }
            '}' { $indent--; $sb.Append("`n" + (' ' * ($indent * $IndentSize))) | Out-Null; $sb.Append($ch) | Out-Null }
            ']' { $indent--; $sb.Append("`n" + (' ' * ($indent * $IndentSize))) | Out-Null; $sb.Append($ch) | Out-Null }
            ',' { $sb.Append($ch) | Out-Null; $sb.Append("`n" + (' ' * ($indent * $IndentSize))) | Out-Null }
            ':' { $sb.Append(': ') | Out-Null }
            default { if ($ch -ne ' ') { $sb.Append($ch) | Out-Null } }
        }
    }
    $sb.ToString()
}

function Escape-TomlString {
    param([string]$Value)
    return ($Value -replace '\\', '\\' -replace '"', '\"')
}

function Find-ClaudeConfigPath {
    $candidates = @(
        (Join-Path $env:APPDATA "Claude\claude_desktop_config.json"),
        (Join-Path $env:LOCALAPPDATA "Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\claude_desktop_config.json")
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }
    return $candidates[0]
}

function Find-CodexConfigPath {
    return (Join-Path $env:USERPROFILE ".codex\config.toml")
}

function Write-ClaudeSnippet {
    param([string]$Path, [string]$ExePath, [string]$ResolvedFijiPath)
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
    $json = $snippet | ConvertTo-Json2 -Depth 10
    Write-Utf8NoBom -Path $Path -Content $json
}

function Write-CodexSnippet {
    param([string]$Path, [string]$ExePath, [string]$ResolvedFijiPath)
    $content = @"
[mcp_servers.fiji-macro]
command = "$([string](Escape-TomlString $ExePath))"

[mcp_servers.fiji-macro.env]
FIJI_PATH = "$([string](Escape-TomlString $ResolvedFijiPath))"
FIJI_PORT = "5048"
"@
    Write-Utf8NoBom -Path $Path -Content $content
}

function Update-ClaudeConfig {
    param([string]$ConfigPath, [string]$ExePath, [string]$ResolvedFijiPath)
    Ensure-ParentDir $ConfigPath
    $backupPath = Backup-File $ConfigPath
    if (Test-Path $ConfigPath) {
        $raw = Get-Content -Path $ConfigPath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { $config = [pscustomobject]@{} } else { $config = $raw | ConvertFrom-Json }
    } else {
        $config = [pscustomobject]@{}
    }
    if (-not ($config.PSObject.Properties.Name -contains "mcpServers")) {
        $config | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value ([pscustomobject]@{})
    }
    $entry = [pscustomobject]@{
        command = $ExePath
        env = [pscustomobject]@{
            FIJI_PATH = $ResolvedFijiPath
            FIJI_PORT = "5048"
        }
    }
    $config.mcpServers | Add-Member -MemberType NoteProperty -Name "fiji-macro" -Value $entry -Force
    $json = $config | ConvertTo-Json2 -Depth 20
    Write-Utf8NoBom -Path $ConfigPath -Content $json
    return $backupPath
}

function Update-CodexConfig {
    param([string]$ConfigPath, [string]$ExePath, [string]$ResolvedFijiPath)
    Ensure-ParentDir $ConfigPath
    $backupPath = Backup-File $ConfigPath
    $begin = "# BEGIN Fiji Macro Bridge"
    $end = "# END Fiji Macro Bridge"
    $block = @"
$begin
[mcp_servers.fiji-macro]
command = "$([string](Escape-TomlString $ExePath))"

[mcp_servers.fiji-macro.env]
FIJI_PATH = "$([string](Escape-TomlString $ResolvedFijiPath))"
FIJI_PORT = "5048"
$end
"@
    $existing = ""
    if (Test-Path $ConfigPath) {
        $existing = Get-Content -Path $ConfigPath -Raw
    }
    if ($existing -match [regex]::Escape($begin) + ".*?" + [regex]::Escape($end)) {
        $updated = [regex]::Replace($existing, [regex]::Escape($begin) + ".*?" + [regex]::Escape($end), [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block }, 'Singleline')
    } else {
        if ($existing -and -not $existing.EndsWith("`n")) { $existing += "`r`n" }
        if ($existing) { $existing += "`r`n" }
        $updated = $existing + $block + "`r`n"
    }
    Write-Utf8NoBom -Path $ConfigPath -Content $updated
    return $backupPath
}

function Show-ClientSelectionDialog {
    param([string]$ClaudePath, [string]$CodexPath, [string]$CustomJsonPath)

    if (-not $script:GuiAvailable) {
        return [pscustomobject]@{
            Action = "skip"
            ClaudeSelected = $false
            CodexSelected = $false
            CustomJsonSelected = $false
            ClaudePath = $ClaudePath
            CodexPath = $CodexPath
            CustomJsonPath = $CustomJsonPath
        }
    }

    $result = [pscustomobject]@{
        Action = "cancel"
        ClaudeSelected = $false
        CodexSelected = $false
        CustomJsonSelected = $false
        ClaudePath = $ClaudePath
        CodexPath = $CodexPath
        CustomJsonPath = $CustomJsonPath
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Set Up MCP Clients"
    $form.Size = New-Object System.Drawing.Size(560, 280)
    $form.StartPosition = "CenterScreen"

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Choose which desktop apps to configure automatically."
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.Size = New-Object System.Drawing.Size(500, 20)
    $form.Controls.Add($label)

    $chkClaude = New-Object System.Windows.Forms.CheckBox
    $chkClaude.Text = "Claude Desktop"
    $chkClaude.Location = New-Object System.Drawing.Point(30, 60)
    $chkClaude.Size = New-Object System.Drawing.Size(220, 24)
    $chkClaude.Checked = $true
    $form.Controls.Add($chkClaude)

    $chkCodex = New-Object System.Windows.Forms.CheckBox
    $chkCodex.Text = "Codex app"
    $chkCodex.Location = New-Object System.Drawing.Point(30, 90)
    $chkCodex.Size = New-Object System.Drawing.Size(220, 24)
    $form.Controls.Add($chkCodex)

    $chkCustom = New-Object System.Windows.Forms.CheckBox
    $chkCustom.Text = "Custom JSON config"
    $chkCustom.Location = New-Object System.Drawing.Point(30, 120)
    $chkCustom.Size = New-Object System.Drawing.Size(170, 24)
    $form.Controls.Add($chkCustom)

    $txtCustom = New-Object System.Windows.Forms.TextBox
    $txtCustom.Location = New-Object System.Drawing.Point(200, 120)
    $txtCustom.Size = New-Object System.Drawing.Size(250, 23)
    $txtCustom.Text = $CustomJsonPath
    $form.Controls.Add($txtCustom)

    $btnCustom = New-Object System.Windows.Forms.Button
    $btnCustom.Text = "Browse..."
    $btnCustom.Location = New-Object System.Drawing.Point(460, 118)
    $btnCustom.Size = New-Object System.Drawing.Size(75, 26)
    $btnCustom.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtCustom.Text = $dlg.FileName
            $chkCustom.Checked = $true
        }
    })
    $form.Controls.Add($btnCustom)

    $info = New-Object System.Windows.Forms.Label
    $info.Text = "Skip leaves configs untouched and writes copy-paste snippets with the detected FIJI_PATH."
    $info.Location = New-Object System.Drawing.Point(20, 160)
    $info.Size = New-Object System.Drawing.Size(510, 36)
    $form.Controls.Add($info)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "OK"
    $ok.Location = New-Object System.Drawing.Point(295, 210)
    $ok.Add_Click({
        $result.Action = "ok"
        $result.ClaudeSelected = $chkClaude.Checked
        $result.CodexSelected = $chkCodex.Checked
        $result.CustomJsonSelected = $chkCustom.Checked
        $result.CustomJsonPath = $txtCustom.Text
        $form.Close()
    })
    $form.Controls.Add($ok)

    $skip = New-Object System.Windows.Forms.Button
    $skip.Text = "Skip"
    $skip.Location = New-Object System.Drawing.Point(375, 210)
    $skip.Add_Click({
        $result.Action = "skip"
        $result.CustomJsonPath = $txtCustom.Text
        $form.Close()
    })
    $form.Controls.Add($skip)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancel"
    $cancel.Location = New-Object System.Drawing.Point(455, 210)
    $cancel.Add_Click({
        $result.Action = "cancel"
        $form.Close()
    })
    $form.Controls.Add($cancel)

    $form.ShowDialog() | Out-Null
    return $result
}

function Load-Manifest {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return [ordered]@{} }
    $raw = Get-Content -Path $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return [ordered]@{} }
    $obj = $raw | ConvertFrom-Json
    $manifest = [ordered]@{}
    foreach ($prop in $obj.PSObject.Properties) {
        $manifest[$prop.Name] = $prop.Value
    }
    return $manifest
}

function Save-Manifest {
    param([string]$Path, [hashtable]$Manifest)
    $json = $Manifest | ConvertTo-Json2 -Depth 20
    Write-Utf8NoBom -Path $Path -Content $json
}

function Upsert-ConfiguredClient {
    param(
        [System.Collections.ArrayList]$ConfiguredClients,
        [hashtable]$Entry
    )
    for ($i = 0; $i -lt $ConfiguredClients.Count; $i++) {
        if ($ConfiguredClients[$i].name -eq $Entry.name) {
            $ConfiguredClients[$i] = $Entry
            return
        }
    }
    [void]$ConfiguredClients.Add($Entry)
}

if (-not $InstallRoot) { throw "InstallRoot is required." }
if (-not $BundleDir) { throw "BundleDir is required." }
if (-not $FijiPath) { throw "FijiPath is required." }
if (-not $ServerExePath) { throw "ServerExePath is required." }
if (-not $ManifestPath) { throw "ManifestPath is required." }
try {
    $resolvedBundleDir = (Resolve-Path $BundleDir).Path
    $resolvedFijiPath = (Resolve-Path $FijiPath).Path
    $resolvedServerExe = (Resolve-Path $ServerExePath).Path

    $manifest = Load-Manifest $ManifestPath
    if (-not $manifest.Contains("configured_clients")) {
        $manifest["configured_clients"] = [System.Collections.ArrayList]@()
    }
    $configuredClients = [System.Collections.ArrayList]@()
    foreach ($item in @($manifest["configured_clients"])) {
        [void]$configuredClients.Add($item)
    }

    $claudePath = Find-ClaudeConfigPath
    $codexPath = Find-CodexConfigPath
    $customJsonPath = Join-Path $resolvedBundleDir "custom-mcp-config.json"
    $selection = Show-ClientSelectionDialog -ClaudePath $claudePath -CodexPath $codexPath -CustomJsonPath $customJsonPath

    if ($selection.Action -eq "cancel") {
        throw "Client setup cancelled."
    }

    $claudeSnippetPath = Join-Path $resolvedBundleDir "manual-setup-claude-desktop.json"
    $codexSnippetPath = Join-Path $resolvedBundleDir "manual-setup-codex-app.toml"
    $customJsonSnippetPath = Join-Path $resolvedBundleDir "manual-setup-custom-json.json"
    Write-ClaudeSnippet -Path $claudeSnippetPath -ExePath $resolvedServerExe -ResolvedFijiPath $resolvedFijiPath
    Write-CodexSnippet -Path $codexSnippetPath -ExePath $resolvedServerExe -ResolvedFijiPath $resolvedFijiPath
    Write-ClaudeSnippet -Path $customJsonSnippetPath -ExePath $resolvedServerExe -ResolvedFijiPath $resolvedFijiPath

    $configuredNow = @()

    if ($selection.Action -eq "ok") {
        if ($selection.ClaudeSelected) {
            $backup = Update-ClaudeConfig -ConfigPath $selection.ClaudePath -ExePath $resolvedServerExe -ResolvedFijiPath $resolvedFijiPath
            $entry = [ordered]@{
                name = "claude-desktop"
                format = "json"
                path = $selection.ClaudePath
                backup_path = $backup
                managed_key = "mcpServers.fiji-macro"
            }
            Upsert-ConfiguredClient -ConfiguredClients $configuredClients -Entry $entry
            $configuredNow += "Claude Desktop"
        }
        if ($selection.CodexSelected) {
            $backup = Update-CodexConfig -ConfigPath $selection.CodexPath -ExePath $resolvedServerExe -ResolvedFijiPath $resolvedFijiPath
            $entry = [ordered]@{
                name = "codex-app"
                format = "toml"
                path = $selection.CodexPath
                backup_path = $backup
                managed_block = "Fiji Macro Bridge"
            }
            Upsert-ConfiguredClient -ConfiguredClients $configuredClients -Entry $entry
            $configuredNow += "Codex app"
        }
        if ($selection.CustomJsonSelected) {
            $backup = Update-ClaudeConfig -ConfigPath $selection.CustomJsonPath -ExePath $resolvedServerExe -ResolvedFijiPath $resolvedFijiPath
            $entry = [ordered]@{
                name = "custom-json"
                format = "json"
                path = $selection.CustomJsonPath
                backup_path = $backup
                managed_key = "mcpServers.fiji-macro"
            }
            Upsert-ConfiguredClient -ConfiguredClients $configuredClients -Entry $entry
            $configuredNow += "Custom JSON config"
        }
    }

    $manifest["configured_clients"] = $configuredClients
    $manifest["manual_setup_files"] = @(
        [ordered]@{ client = "claude-desktop"; path = $claudeSnippetPath },
        [ordered]@{ client = "codex-app"; path = $codexSnippetPath },
        [ordered]@{ client = "custom-json"; path = $customJsonSnippetPath }
    )
    Save-Manifest -Path $ManifestPath -Manifest $manifest

    Write-Host ""
    if ($configuredNow.Count -gt 0) {
        Write-Host ("Configured clients: " + ($configuredNow -join ", "))
    } else {
        Write-Host "No client configs were modified."
    }
    Write-Host "Manual setup snippets:"
    Write-Host "  Claude Desktop: $claudeSnippetPath"
    Write-Host "  Codex app:      $codexSnippetPath"
    Write-Host "  Custom JSON:    $customJsonSnippetPath"

    $summary = if ($configuredNow.Count -gt 0) {
        "Configured: " + ($configuredNow -join ", ") + "`n`n"
    } else {
        "No client configs were modified.`n`n"
    }
    $summary += "Manual setup snippets:`n"
    $summary += "Claude Desktop: $claudeSnippetPath`n"
    $summary += "Codex app: $codexSnippetPath`n"
    $summary += "Custom JSON: $customJsonSnippetPath"
    Show-ResultDialog -Title "Client Setup Complete" -Message $summary -Icon "Information"
}
catch {
    Show-ResultDialog -Title "Client Setup Failed" -Message $_.Exception.Message -Icon "Error"
    throw
}
