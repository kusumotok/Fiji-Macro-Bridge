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

function Show-AdvancedOptionsDialog {
    param([string]$ClaudePath, [string]$CodexPath)

    if (-not $script:GuiAvailable) {
        return [pscustomobject]@{ ClaudePath = $ClaudePath; CodexPath = $CodexPath; Accepted = $true }
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Advanced Config Paths"
    $form.Size = New-Object System.Drawing.Size(640, 220)
    $form.StartPosition = "CenterScreen"

    $label1 = New-Object System.Windows.Forms.Label
    $label1.Text = "Claude Desktop config path"
    $label1.Location = New-Object System.Drawing.Point(20, 20)
    $label1.AutoSize = $true
    $form.Controls.Add($label1)

    $txtClaude = New-Object System.Windows.Forms.TextBox
    $txtClaude.Location = New-Object System.Drawing.Point(20, 45)
    $txtClaude.Size = New-Object System.Drawing.Size(500, 23)
    $txtClaude.Text = $ClaudePath
    $form.Controls.Add($txtClaude)

    $btnClaude = New-Object System.Windows.Forms.Button
    $btnClaude.Text = "Browse"
    $btnClaude.Location = New-Object System.Drawing.Point(530, 43)
    $btnClaude.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtClaude.Text = $dlg.FileName }
    })
    $form.Controls.Add($btnClaude)

    $label2 = New-Object System.Windows.Forms.Label
    $label2.Text = "Codex app config path"
    $label2.Location = New-Object System.Drawing.Point(20, 85)
    $label2.AutoSize = $true
    $form.Controls.Add($label2)

    $txtCodex = New-Object System.Windows.Forms.TextBox
    $txtCodex.Location = New-Object System.Drawing.Point(20, 110)
    $txtCodex.Size = New-Object System.Drawing.Size(500, 23)
    $txtCodex.Text = $CodexPath
    $form.Controls.Add($txtCodex)

    $btnCodex = New-Object System.Windows.Forms.Button
    $btnCodex.Text = "Browse"
    $btnCodex.Location = New-Object System.Drawing.Point(530, 108)
    $btnCodex.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "TOML files (*.toml)|*.toml|All files (*.*)|*.*"
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtCodex.Text = $dlg.FileName }
    })
    $form.Controls.Add($btnCodex)

    $result = [pscustomobject]@{ ClaudePath = $ClaudePath; CodexPath = $CodexPath; Accepted = $false }

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "OK"
    $ok.Location = New-Object System.Drawing.Point(430, 150)
    $ok.Add_Click({
        $result.ClaudePath = $txtClaude.Text
        $result.CodexPath = $txtCodex.Text
        $result.Accepted = $true
        $form.Close()
    })
    $form.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancel"
    $cancel.Location = New-Object System.Drawing.Point(520, 150)
    $cancel.Add_Click({ $form.Close() })
    $form.Controls.Add($cancel)

    $form.ShowDialog() | Out-Null
    return $result
}

function Show-ClientSelectionDialog {
    param([string]$ClaudePath, [string]$CodexPath)

    if (-not $script:GuiAvailable) {
        return [pscustomobject]@{
            Action = "skip"
            ClaudeSelected = $false
            CodexSelected = $false
            ClaudePath = $ClaudePath
            CodexPath = $CodexPath
        }
    }

    $result = [pscustomobject]@{
        Action = "cancel"
        ClaudeSelected = $false
        CodexSelected = $false
        ClaudePath = $ClaudePath
        CodexPath = $CodexPath
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Set Up MCP Clients"
    $form.Size = New-Object System.Drawing.Size(500, 250)
    $form.StartPosition = "CenterScreen"

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Choose which desktop apps to configure automatically."
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.Size = New-Object System.Drawing.Size(440, 20)
    $form.Controls.Add($label)

    $chkClaude = New-Object System.Windows.Forms.CheckBox
    $chkClaude.Text = "Claude Desktop"
    $chkClaude.Location = New-Object System.Drawing.Point(30, 60)
    $chkClaude.Checked = $true
    $form.Controls.Add($chkClaude)

    $chkCodex = New-Object System.Windows.Forms.CheckBox
    $chkCodex.Text = "Codex app"
    $chkCodex.Location = New-Object System.Drawing.Point(30, 90)
    $form.Controls.Add($chkCodex)

    $info = New-Object System.Windows.Forms.Label
    $info.Text = "Skip leaves configs untouched and writes copy-paste snippets with the detected FIJI_PATH."
    $info.Location = New-Object System.Drawing.Point(20, 130)
    $info.Size = New-Object System.Drawing.Size(440, 35)
    $form.Controls.Add($info)

    $advanced = New-Object System.Windows.Forms.Button
    $advanced.Text = "Advanced Options"
    $advanced.Location = New-Object System.Drawing.Point(20, 175)
    $advanced.Add_Click({
        $advancedResult = Show-AdvancedOptionsDialog -ClaudePath $result.ClaudePath -CodexPath $result.CodexPath
        if ($advancedResult.Accepted) {
            $result.ClaudePath = $advancedResult.ClaudePath
            $result.CodexPath = $advancedResult.CodexPath
        }
    })
    $form.Controls.Add($advanced)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "OK"
    $ok.Location = New-Object System.Drawing.Point(220, 175)
    $ok.Add_Click({
        $result.Action = "ok"
        $result.ClaudeSelected = $chkClaude.Checked
        $result.CodexSelected = $chkCodex.Checked
        $form.Close()
    })
    $form.Controls.Add($ok)

    $skip = New-Object System.Windows.Forms.Button
    $skip.Text = "Skip"
    $skip.Location = New-Object System.Drawing.Point(300, 175)
    $skip.Add_Click({
        $result.Action = "skip"
        $form.Close()
    })
    $form.Controls.Add($skip)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancel"
    $cancel.Location = New-Object System.Drawing.Point(380, 175)
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

$resolvedBundleDir = (Resolve-Path $BundleDir).Path
$resolvedFijiPath = (Resolve-Path $FijiPath).Path
$resolvedServerExe = (Resolve-Path $ServerExePath).Path

$manifest = Load-Manifest $ManifestPath
if (-not $manifest.ContainsKey("configured_clients")) {
    $manifest["configured_clients"] = [System.Collections.ArrayList]@()
}
$configuredClients = [System.Collections.ArrayList]@()
foreach ($item in @($manifest["configured_clients"])) {
    [void]$configuredClients.Add($item)
}

$claudePath = Find-ClaudeConfigPath
$codexPath = Find-CodexConfigPath
$selection = Show-ClientSelectionDialog -ClaudePath $claudePath -CodexPath $codexPath

if ($selection.Action -eq "cancel") {
    throw "Client setup cancelled."
}

$claudeSnippetPath = Join-Path $resolvedBundleDir "manual-setup-claude-desktop.json"
$codexSnippetPath = Join-Path $resolvedBundleDir "manual-setup-codex-app.toml"
Write-ClaudeSnippet -Path $claudeSnippetPath -ExePath $resolvedServerExe -ResolvedFijiPath $resolvedFijiPath
Write-CodexSnippet -Path $codexSnippetPath -ExePath $resolvedServerExe -ResolvedFijiPath $resolvedFijiPath

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
}

$manifest["configured_clients"] = $configuredClients
$manifest["manual_setup_files"] = @(
    [ordered]@{ client = "claude-desktop"; path = $claudeSnippetPath },
    [ordered]@{ client = "codex-app"; path = $codexSnippetPath }
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
