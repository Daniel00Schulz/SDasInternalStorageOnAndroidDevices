#requires -Version 5.1
<#
  Cartão SD via ADB — ferramenta gráfica para listar o cartão de memória de um
  aparelho Android, formatá-lo como armazenamento interno (adotado) ou voltá-lo
  ao modo portátil.

  Uso: abra pelo "Cartao SD ADB.bat" ou rode:
    powershell -NoProfile -ExecutionPolicy Bypass -STA -File sd_adb_tool.ps1
  Com -NoGui só carrega as funções (para testes).
#>
param([switch]$NoGui)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

function Find-Adb {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        $(if ($env:ANDROID_HOME) { "$env:ANDROID_HOME\platform-tools\adb.exe" }),
        $(if ($env:ANDROID_SDK_ROOT) { "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe" }),
        "C:\platform-tools\adb.exe",
        "$env:USERPROFILE\platform-tools\adb.exe"
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

$script:Adb = Find-Adb

# Roda o adb sem travar a janela (processa eventos enquanto espera).
function Invoke-Adb {
    param([string[]]$Arguments, [int]$TimeoutSec = 60)
    if (-not $script:Adb) { throw 'adb.exe não encontrado. Instale o Android SDK Platform-Tools.' }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:Adb
    $psi.Arguments = ($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync()
    $err = $p.StandardError.ReadToEndAsync()
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while (-not $p.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
        if ((Get-Date) -gt $deadline) {
            try { $p.Kill() } catch {}
            throw "Tempo esgotado ($TimeoutSec s) em: adb $($psi.Arguments)"
        }
    }
    $p.WaitForExit()
    [pscustomobject]@{
        ExitCode = $p.ExitCode
        Output   = $out.Result.TrimEnd()
        Error    = $err.Result.TrimEnd()
        Command  = "adb $($psi.Arguments)"
    }
}

function Get-AdbDevices {
    $r = Invoke-Adb @('devices', '-l')
    foreach ($line in ($r.Output -split "`r?`n" | Select-Object -Skip 1)) {
        if ($line -match '^(\S+)\s+(\S+)(.*)$') {
            $serial = $Matches[1]; $state = $Matches[2]; $rest = $Matches[3]
            $model = if ($rest -match 'model:(\S+)') { $Matches[1] } else { '' }
            [pscustomobject]@{ Serial = $serial; State = $state; Model = $model }
        }
    }
}

function Format-Size([double]$bytes) {
    if ($bytes -ge 1GB) { '{0:N1} GB' -f ($bytes / 1GB) }
    elseif ($bytes -ge 1MB) { '{0:N0} MB' -f ($bytes / 1MB) }
    else { '{0:N0} KB' -f ($bytes / 1KB) }
}

# Lê "dumpsys mount" e devolve um objeto por cartão (disco removível).
function Get-SdCards {
    param([string]$Serial)
    $dump = (Invoke-Adb @('-s', $Serial, 'shell', 'dumpsys mount')).Output -split "`r?`n"

    $disks = [ordered]@{}
    $volumes = @()
    $section = ''
    $cur = $null
    foreach ($line in $dump) {
        if ($line -match '^(Disks|Volumes|Records):') { $section = $Matches[1]; $cur = $null; continue }
        if ($line -match '^\S') { $section = ''; $cur = $null; continue }
        if ($section -eq 'Disks') {
            if ($line -match 'DiskInfo\{(disk:[^}]+)\}') {
                $cur = [pscustomobject]@{ Id = $Matches[1]; Size = 0; Flags = ''; Volumes = @() }
                $disks[$cur.Id] = $cur
            } elseif ($cur -and $line -match 'flags=(\S*)\s+size=(\d+)') {
                $cur.Flags = $Matches[1]; $cur.Size = [double]$Matches[2]
            }
        } elseif ($section -eq 'Volumes') {
            if ($line -match 'VolumeInfo\{([^}]+)\}') {
                $cur = [pscustomobject]@{ Id = $Matches[1]; Type = ''; DiskId = ''; State = ''; Uuid = ''; Path = '' }
                $volumes += $cur
            } elseif ($cur) {
                if ($line -match 'type=(\S+)\s+diskId=(\S+)') { $cur.Type = $Matches[1]; $cur.DiskId = $Matches[2] }
                if ($line -match 'state=(\S+)') { $cur.State = $Matches[1] }
                if ($line -match 'fsUuid=(\S*)') { $cur.Uuid = $Matches[1] }
                if ($line -match '^\s+path=(\S+)') { $cur.Path = $Matches[1] }
            }
        }
    }

    foreach ($v in $volumes) {
        if ($v.DiskId -and $disks.Contains($v.DiskId)) { $disks[$v.DiskId].Volumes += $v }
    }

    foreach ($d in $disks.Values) {
        $types = @($d.Volumes | ForEach-Object { $_.Type })
        $mode = if ($types -contains 'PRIVATE' -and $types -contains 'PUBLIC') { 'Misto' }
                elseif ($types -contains 'PRIVATE') { 'Armazenamento interno' }
                elseif ($types -contains 'PUBLIC') { 'Portátil' }
                else { 'Sem volume montado' }

        $usage = @()
        foreach ($v in $d.Volumes) {
            if ($v.State -eq 'MOUNTED' -and $v.Path -and $v.Path -ne 'null') {
                $df = (Invoke-Adb @('-s', $Serial, 'shell', "df -k $($v.Path)")).Output -split "`r?`n" | Select-Object -Last 1
                $f = $df -split '\s+'
                if ($f.Count -ge 4 -and $f[1] -match '^\d+$') {
                    $usage += '{0}: {1} usados de {2}' -f $v.Type.ToLower(), (Format-Size ([double]$f[2] * 1KB)), (Format-Size ([double]$f[1] * 1KB))
                }
            }
        }

        [pscustomobject]@{
            DiskId     = $d.Id
            Size       = $d.Size
            SizeText   = Format-Size $d.Size
            Adoptable  = $d.Flags -match 'ADOPTABLE'
            Mode       = $mode
            VolumeText = ($d.Volumes | ForEach-Object { "$($_.Id) ($($_.State.ToLower()))" }) -join ', '
            UsageText  = $usage -join '; '
        }
    }
}

if ($NoGui) { return }

# ---------------------------------------------------------------- Interface

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Cartão SD via ADB'
$form.Size = New-Object System.Drawing.Size(900, 620)
$form.MinimumSize = New-Object System.Drawing.Size(760, 520)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)

$lblDevice = New-Object System.Windows.Forms.Label
$lblDevice.Text = 'Aparelho:'
$lblDevice.Location = '12,16'; $lblDevice.AutoSize = $true

$cmbDevice = New-Object System.Windows.Forms.ComboBox
$cmbDevice.DropDownStyle = 'DropDownList'
$cmbDevice.Location = '85,12'; $cmbDevice.Width = 420

$btnDevices = New-Object System.Windows.Forms.Button
$btnDevices.Text = 'Atualizar aparelhos'
$btnDevices.Location = '515,11'; $btnDevices.Size = '150,28'

$btnList = New-Object System.Windows.Forms.Button
$btnList.Text = 'Listar cartões'
$btnList.Location = '675,11'; $btnList.Size = '120,28'

$btnTips = New-Object System.Windows.Forms.Button
$btnTips.Text = 'Dicas'
$btnTips.Location = '802,11'; $btnTips.Size = '70,28'
$btnTips.Anchor = 'Top,Right'

$lblAdb = New-Object System.Windows.Forms.Label
$lblAdb.Location = '12,46'; $lblAdb.AutoSize = $true
$lblAdb.ForeColor = [System.Drawing.Color]::DimGray

$list = New-Object System.Windows.Forms.ListView
$list.View = 'Details'; $list.FullRowSelect = $true; $list.MultiSelect = $false; $list.HideSelection = $false
$list.Location = '12,72'; $list.Size = '860,150'
$list.Anchor = 'Top,Left,Right'
[void]$list.Columns.Add('Cartão', 110)
[void]$list.Columns.Add('Tamanho', 80)
[void]$list.Columns.Add('Modo atual', 160)
[void]$list.Columns.Add('Volumes', 270)
[void]$list.Columns.Add('Uso', 230)

$btnInternal = New-Object System.Windows.Forms.Button
$btnInternal.Text = 'Formatar como armazenamento interno'
$btnInternal.Location = '12,232'; $btnInternal.Size = '280,32'

$btnPortable = New-Object System.Windows.Forms.Button
$btnPortable.Text = 'Voltar ao modo portátil'
$btnPortable.Location = '302,232'; $btnPortable.Size = '200,32'

$lblWarn = New-Object System.Windows.Forms.Label
$lblWarn.Text = 'As duas opções APAGAM todo o conteúdo do cartão.'
$lblWarn.Location = '515,240'; $lblWarn.AutoSize = $true
$lblWarn.ForeColor = [System.Drawing.Color]::Firebrick

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true; $log.ReadOnly = $true; $log.ScrollBars = 'Vertical'
$log.Font = New-Object System.Drawing.Font('Consolas', 9)
$log.BackColor = [System.Drawing.Color]::White
$log.Location = '12,276'; $log.Size = '860,290'
$log.Anchor = 'Top,Bottom,Left,Right'

$form.Controls.AddRange(@($lblDevice, $cmbDevice, $btnDevices, $btnList, $btnTips, $lblAdb, $list, $btnInternal, $btnPortable, $lblWarn, $log))

function Write-Log([string]$text) {
    $log.AppendText(('[{0:HH:mm:ss}] {1}' -f (Get-Date), $text) + "`r`n")
}

function Write-Result($r) {
    Write-Log "$ $($r.Command)"
    if ($r.Output) { $log.AppendText(($r.Output -replace "`r?`n", "`r`n") + "`r`n") }
    if ($r.Error) { $log.AppendText(($r.Error -replace "`r?`n", "`r`n") + "`r`n") }
}

function Set-Busy([bool]$busy) {
    $form.UseWaitCursor = $busy
    foreach ($c in @($cmbDevice, $btnDevices, $btnList, $list)) { $c.Enabled = -not $busy }
    Update-ActionButtons -Busy $busy
}

function Update-ActionButtons([bool]$Busy = $false) {
    $sel = if ($list.SelectedItems.Count) { $list.SelectedItems[0].Tag } else { $null }
    $ok = (-not $Busy) -and $sel -and $script:SdkLevel -ge 23
    $btnInternal.Enabled = $ok -and $sel.Adoptable -and $script:HasAdoptable -and $sel.Mode -ne 'Armazenamento interno'
    $btnPortable.Enabled = $ok -and $sel.Mode -ne 'Portátil'
}

function Get-SelectedSerial {
    if ($cmbDevice.SelectedItem) { return $cmbDevice.SelectedItem.Serial }
    return $null
}

function Refresh-Devices {
    $cmbDevice.Items.Clear()
    $cmbDevice.DisplayMember = 'Label'
    try {
        $devs = @(Get-AdbDevices)
    } catch { Write-Log "Erro: $($_.Exception.Message)"; return }
    foreach ($d in $devs) {
        $label = if ($d.Model) { "$($d.Model)  ($($d.Serial))  - $($d.State)" } else { "$($d.Serial)  - $($d.State)" }
        $d | Add-Member -NotePropertyName Label -NotePropertyValue $label
        [void]$cmbDevice.Items.Add($d)
    }
    if ($devs.Count -eq 0) {
        Write-Log 'Nenhum aparelho encontrado. Confira o cabo, a Depuração USB e o aviso "Permitir depuração USB?".'
    } else {
        $ready = $devs | Where-Object State -eq 'device' | Select-Object -First 1
        $cmbDevice.SelectedItem = if ($ready) { $ready } else { $devs[0] }
        Write-Log "$($devs.Count) aparelho(s) encontrado(s)."
        foreach ($d in $devs | Where-Object State -ne 'device') {
            Write-Log "$($d.Serial) está '$($d.State)'. Desbloqueie o aparelho e aceite o aviso de depuração."
        }
    }
}

function Refresh-Cards {
    $list.Items.Clear()
    Update-ActionButtons
    $serial = Get-SelectedSerial
    if (-not $serial) { Write-Log 'Selecione um aparelho primeiro.'; return }
    if ($cmbDevice.SelectedItem.State -ne 'device') { Write-Log "O aparelho está '$($cmbDevice.SelectedItem.State)' e ainda não aceita comandos."; return }
    Set-Busy $true
    try {
        $ver = (Invoke-Adb @('-s', $serial, 'shell', 'getprop ro.build.version.release; getprop ro.build.version.sdk')).Output -split "`r?`n"
        $script:SdkLevel = [int]($ver[1] -replace '\D', '')
        Write-Log "Android $($ver[0]) (API $script:SdkLevel)."
        if ($script:SdkLevel -lt 23) {
            Write-Log 'Esta versão do Android não suporta usar o cartão como armazenamento interno (requer Android 6.0 ou mais novo). Veja "Dicas".'
            return
        }
        $adopt = Invoke-Adb @('-s', $serial, 'shell', 'sm has-adoptable')
        $script:HasAdoptable = $adopt.Output -eq 'true'
        $cards = @(Get-SdCards -Serial $serial)
        Write-Log ("Suporte a armazenamento interno (adotável): {0}" -f $(if ($script:HasAdoptable) { 'sim' } else { "não ($($adopt.Output)). O fabricante bloqueou o recurso; só o modo portátil está disponível." }))
        if ($cards.Count -eq 0) { Write-Log 'Nenhum cartão encontrado. Confira se ele está inserido.' }
        foreach ($c in $cards) {
            $item = New-Object System.Windows.Forms.ListViewItem($c.DiskId)
            [void]$item.SubItems.Add($c.SizeText)
            [void]$item.SubItems.Add($c.Mode)
            [void]$item.SubItems.Add($c.VolumeText)
            [void]$item.SubItems.Add($c.UsageText)
            $item.Tag = $c
            [void]$list.Items.Add($item)
            Write-Log "$($c.DiskId): $($c.SizeText), modo $($c.Mode). $($c.UsageText)"
        }
        if ($list.Items.Count -eq 1) { $list.Items[0].Selected = $true }
    } catch {
        Write-Log "Erro: $($_.Exception.Message)"
    } finally {
        Set-Busy $false
    }
}

function Invoke-Partition([string]$target) {
    $serial = Get-SelectedSerial
    $card = $list.SelectedItems[0].Tag
    if ($target -eq 'private') {
        $title = 'Formatar como armazenamento interno'
        $msg = "O cartão $($card.DiskId) ($($card.SizeText)) será APAGADO e formatado como armazenamento interno.`n`n" +
               "- Ele ficará criptografado e só funcionará neste aparelho.`n" +
               "- Apps movidos para ele param de funcionar se o cartão for removido ou falhar.`n`n" +
               "Continuar?"
    } else {
        $title = 'Voltar ao modo portátil'
        $msg = "O cartão $($card.DiskId) ($($card.SizeText)) será APAGADO e formatado como portátil (exFAT/FAT).`n`n" +
               "- Apps e dados que estiverem nele serão perdidos e precisarão ser reinstalados.`n" +
               "- Antes, mova os apps de volta para o armazenamento interno (Configurações > Apps > [app] > Armazenamento > Alterar).`n`n" +
               "Continuar?"
    }
    $answer = [System.Windows.Forms.MessageBox]::Show($form, $msg, $title, 'YesNo', 'Warning', 'Button2')
    if ($answer -ne 'Yes') { Write-Log 'Operação cancelada.'; return }

    Set-Busy $true
    try {
        Write-Log "Formatando $($card.DiskId) como '$target'. Isso pode levar alguns minutos; não desconecte o cabo."
        $r = Invoke-Adb @('-s', $serial, 'shell', "sm partition $($card.DiskId) $target") -TimeoutSec 1800
        Write-Result $r
        if ($r.ExitCode -eq 0 -and -not $r.Error) { Write-Log 'Concluído.' }
        else { Write-Log "O comando terminou com código $($r.ExitCode)." }
    } catch {
        Write-Log "Erro: $($_.Exception.Message)"
    } finally {
        Set-Busy $false
    }
    Refresh-Cards
}

# ---------------------------------------------------------------- Tela de dicas

$script:ConfigPath = Join-Path $env:APPDATA 'CartaoSdAdb\config.json'

function Get-ShowTips {
    try {
        if (Test-Path $script:ConfigPath) { return [bool](Get-Content $script:ConfigPath -Raw | ConvertFrom-Json).ShowTips }
    } catch {}
    return $true
}

function Set-ShowTips([bool]$value) {
    try {
        New-Item -ItemType Directory -Force (Split-Path $script:ConfigPath) | Out-Null
        @{ ShowTips = $value } | ConvertTo-Json | Out-File $script:ConfigPath -Encoding utf8
    } catch {}
}

# Cada item: '#' = título, '-' = tópico, '' = linha em branco, resto = parágrafo.
function New-TipsPage([string]$title, [string[]]$lines) {
    $page = New-Object System.Windows.Forms.TabPage($title)
    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.Dock = 'Fill'; $rtb.ReadOnly = $true; $rtb.BorderStyle = 'None'
    $rtb.BackColor = [System.Drawing.Color]::White
    $rtb.DetectUrls = $false
    $normal = New-Object System.Drawing.Font('Segoe UI', 10)
    $head = New-Object System.Drawing.Font('Segoe UI Semibold', 11.5)
    $rtb.Font = $normal
    $rtb.BulletIndent = 12
    foreach ($l in $lines) {
        $kind = if ($l.StartsWith('#')) { 'head' } elseif ($l.StartsWith('-')) { 'bullet' } else { 'text' }
        $text = switch ($kind) { 'head' { $l.TrimStart('#', ' ') } 'bullet' { $l.Substring(1).Trim() } default { $l } }
        $start = $rtb.TextLength
        $rtb.AppendText($text + "`n")
        $rtb.Select($start, $text.Length + 1)
        $rtb.SelectionBullet = $kind -eq 'bullet'
        $rtb.SelectionIndent = if ($kind -eq 'bullet') { 8 } else { 0 }
        if ($kind -eq 'head') {
            $rtb.SelectionFont = $head
            $rtb.SelectionColor = [System.Drawing.Color]::FromArgb(30, 70, 140)
        } else {
            $rtb.SelectionFont = $normal
            $rtb.SelectionColor = [System.Drawing.Color]::Black
        }
    }
    $rtb.Select(0, 0)
    $pad = New-Object System.Windows.Forms.Panel
    $pad.Dock = 'Fill'; $pad.Padding = '12,10,8,6'; $pad.BackColor = [System.Drawing.Color]::White
    $pad.Controls.Add($rtb)
    $page.Controls.Add($pad)
    return $page
}

function Show-Tips {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Dicas antes de começar'
    $dlg.Size = New-Object System.Drawing.Size(700, 600)
    $dlg.MinimumSize = New-Object System.Drawing.Size(560, 460)
    $dlg.StartPosition = 'CenterParent'
    $dlg.Font = $form.Font
    $dlg.MinimizeBox = $false; $dlg.ShowInTaskbar = $false

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = 'Fill'

    $tabs.TabPages.Add((New-TipsPage 'Preparar o aparelho' @(
        '# 1. Ative as Opções do desenvolvedor'
        'No aparelho, abra Configurações > Sobre o tablet (ou Sobre o telefone) e toque 7 vezes em "Número da versão". Pode ser pedido o PIN da tela de bloqueio.'
        '- Samsung: Sobre o telefone > Informações do software > Número de compilação.'
        '- Xiaomi/Redmi: Sobre o telefone > Versão do MIUI / HyperOS.'
        '- Motorola, TCL e Android puro: Sobre o telefone > Número da versão.'
        ''
        '# 2. Ative a Depuração USB'
        'Configurações > Sistema > Opções do desenvolvedor > Depuração USB. Em alguns aparelhos o menu fica direto em Configurações.'
        ''
        '# 3. Conecte e autorize este computador'
        '- Use um cabo de dados, ligado direto numa porta do PC (sem hub).'
        '- Desbloqueie a tela e aceite o aviso "Permitir depuração USB?", marcando "Sempre permitir deste computador".'
        '- Clique em "Atualizar aparelhos". O estado "device" significa pronto; "unauthorized" significa que falta aceitar o aviso; "offline", que é preciso reconectar o cabo.'
        ''
        '# 4. Quando terminar'
        'Com a Depuração USB ligada, qualquer computador autorizado tem acesso amplo ao aparelho. Depois das alterações, desligue a Depuração USB e, se quiser, use "Revogar autorizações de depuração USB". O cartão continua funcionando normalmente depois disso.'
    )))

    $tabs.TabPages.Add((New-TipsPage 'Versões do Android' @(
        '# Usar o cartão como armazenamento interno'
        'O recurso (chamado de "armazenamento adotável") foi criado no Android 6.0. Ao clicar em "Listar cartões", a ferramenta mostra a versão do aparelho e se ele aceita o recurso.'
        ''
        '- Android 5.1 ou anterior: não suportado. O cartão só funciona como portátil.'
        '- Android 6.0 a 8.1: suportado. Costuma aparecer no menu do cartão como "Formatar como interno".'
        '- Android 9 a 15: suportado pelo sistema, mas muitos fabricantes e operadoras escondem a opção do menu. Nesses casos, a formatação pela ferramenta costuma funcionar.'
        '- Versões mais novas que o Android 15: não verificadas com esta ferramenta.'
        ''
        '# Quando não funciona'
        '- Se "Suporte a armazenamento interno" aparecer como "não", o fabricante bloqueou o recurso e o botão de formatar como interno fica desativado.'
        '- Aparelhos Samsung Galaxy recentes costumam bloquear o recurso.'
        '- Voltar ao modo portátil funciona em qualquer versão a partir do Android 6.0.'
        ''
        '# Testado em'
        '- TCL TAB 10 5G (9183W, firmware T-Mobile), Android 12.'
        ''
        '# No computador'
        '- Windows 10 ou 11, com o Android SDK Platform-Tools (adb) instalado.'
    )))

    $tabs.TabPages.Add((New-TipsPage 'Cuidados e problemas' @(
        '# Antes de formatar'
        '- As duas opções de formatação APAGAM todo o conteúdo do cartão. Copie antes o que for importante.'
        '- Como armazenamento interno, o cartão fica criptografado e só funciona neste aparelho.'
        '- Prefira cartões A1 ou A2 (classe para apps). Cartões lentos deixam o aparelho lento.'
        '- Antes de voltar ao modo portátil ou remover o cartão, mova os apps de volta: Configurações > Apps > [app] > Armazenamento > Alterar.'
        '- A formatação pode levar alguns minutos. Não desconecte o cabo nem bloqueie o aparelho.'
        ''
        '# Se o aparelho não aparece'
        '- Confira se a Depuração USB está ligada e se a tela está desbloqueada.'
        '- Alguns cabos USB-C só carregam ou falham com o ADB. Troque o cabo.'
        '- Se o aviso de autorização não aparecer, use "Revogar autorizações de depuração USB", desligue e ligue a depuração e reconecte o cabo.'
        '- No Windows, se o Gerenciador de Dispositivos mostrar "Código 10" no aparelho, reconecte em outra porta ou instale o Google USB Driver (Android Studio > SDK Manager > SDK Tools).'
        ''
        '# Firmware de operadora'
        'Aparelhos vendidos por operadoras (ex.: T-Mobile) podem esconder opções do menu, como idiomas e o formato interno do cartão. A ferramenta usa os comandos do próprio Android, que continuam disponíveis.'
    )))

    $bottom = New-Object System.Windows.Forms.Panel
    $bottom.Dock = 'Bottom'; $bottom.Height = 48

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = 'Mostrar estas dicas ao abrir'
    $chk.AutoSize = $true; $chk.Location = '12,14'
    $chk.Checked = Get-ShowTips

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = 'Começar'
    $btnOk.Size = '110,30'; $btnOk.Anchor = 'Top,Right'
    $btnOk.Location = New-Object System.Drawing.Point(($bottom.Width - 122), 9)
    $btnOk.DialogResult = 'OK'
    $dlg.AcceptButton = $btnOk; $dlg.CancelButton = $btnOk

    $bottom.Controls.AddRange(@($chk, $btnOk))
    $dlg.Controls.Add($tabs)
    $dlg.Controls.Add($bottom)
    $bottom.Add_Resize({ $btnOk.Left = $bottom.ClientSize.Width - $btnOk.Width - 12 })
    $dlg.Add_Shown({ $btnOk.Left = $bottom.ClientSize.Width - $btnOk.Width - 12; $btnOk.Focus() })

    [void]$dlg.ShowDialog($form)
    Set-ShowTips $chk.Checked
}

$btnTips.Add_Click({ Show-Tips })
$btnDevices.Add_Click({ Refresh-Devices })
$btnList.Add_Click({ Refresh-Cards })
$cmbDevice.Add_SelectedIndexChanged({ $list.Items.Clear(); Update-ActionButtons })
$list.Add_SelectedIndexChanged({ Update-ActionButtons })
$btnInternal.Add_Click({ Invoke-Partition 'private' })
$btnPortable.Add_Click({ Invoke-Partition 'public' })

$script:SdkLevel = 0
$script:HasAdoptable = $false

$form.Add_Shown({
    if (Get-ShowTips) { Show-Tips }
    if ($script:Adb) {
        $lblAdb.Text = "adb: $script:Adb"
        Refresh-Devices
        if ($cmbDevice.SelectedItem -and $cmbDevice.SelectedItem.State -eq 'device') { Refresh-Cards }
    } else {
        $lblAdb.Text = 'adb.exe não encontrado'
        Write-Log 'adb.exe não encontrado no PATH nem no Android SDK. Instale o Android SDK Platform-Tools.'
        foreach ($c in @($btnDevices, $btnList)) { $c.Enabled = $false }
    }
    Update-ActionButtons
})

[void]$form.ShowDialog()
