#requires -Version 5.1
<#
  SD card via ADB — Windows GUI to list an Android device's SD card, format it
  as internal (adoptable) storage or return it to portable mode.

  The interface follows the Windows display language: Brazilian Portuguese for
  Portuguese systems, International English for every other language.

  Usage: open "Cartao SD ADB.bat" or run:
    powershell -NoProfile -ExecutionPolicy Bypass -STA -File sd_adb_tool.ps1
  -Lang pt|en forces a language. -NoGui only loads the functions (for tests).
#>
param([switch]$NoGui, [ValidateSet('', 'pt', 'en')][string]$Lang = '')

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# ---------------------------------------------------------------- Idioma / Language

if (-not $Lang) {
    $Lang = if ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'pt') { 'pt' } else { 'en' }
}
$script:Lang = $Lang

$script:Strings = @{
    pt = @{
        AdbMissing        = 'adb.exe não encontrado. Instale o Android SDK Platform-Tools.'
        AdbMissingShort   = 'adb.exe não encontrado'
        AdbMissingLog     = 'adb.exe não encontrado no PATH nem no Android SDK. Instale o Android SDK Platform-Tools.'
        Timeout           = 'Tempo esgotado ({0} s) em: adb {1}'
        ModeMixed         = 'Misto'
        ModeInternal      = 'Armazenamento interno'
        ModePortable      = 'Portátil'
        ModeNone          = 'Sem volume montado'
        UsageLine         = '{0}: {1} usados de {2}'
        WindowTitle       = 'Cartão SD via ADB'
        Device            = 'Aparelho:'
        RefreshDevices    = 'Atualizar aparelhos'
        ListCards         = 'Listar cartões'
        Tips              = 'Dicas'
        ColCard           = 'Cartão'
        ColSize           = 'Tamanho'
        ColMode           = 'Modo atual'
        ColVolumes        = 'Volumes'
        ColUsage          = 'Uso'
        BtnInternal       = 'Formatar como armazenamento interno'
        BtnPortable       = 'Voltar ao modo portátil'
        WarnErase         = 'As duas opções APAGAM todo o conteúdo do cartão.'
        Error             = 'Erro: {0}'
        NoDevices         = 'Nenhum aparelho encontrado. Confira o cabo, a Depuração USB e o aviso "Permitir depuração USB?".'
        DevicesFound      = '{0} aparelho(s) encontrado(s).'
        DeviceNotReady    = "{0} está '{1}'. Desbloqueie o aparelho e aceite o aviso de depuração."
        SelectDevice      = 'Selecione um aparelho primeiro.'
        DeviceState       = "O aparelho está '{0}' e ainda não aceita comandos."
        AndroidVersion    = 'Android {0} (API {1}).'
        TooOld            = 'Esta versão do Android não suporta usar o cartão como armazenamento interno (requer Android 6.0 ou mais novo). Veja "Dicas".'
        AdoptYes          = 'Suporte a armazenamento interno (adotável): sim'
        AdoptNo           = 'Suporte a armazenamento interno (adotável): não ({0}). O fabricante bloqueou o recurso; só o modo portátil está disponível.'
        NoCards           = 'Nenhum cartão encontrado. Confira se ele está inserido.'
        CardLine          = '{0}: {1}, modo {2}. {3}'
        ConfirmInternalT  = 'Formatar como armazenamento interno'
        ConfirmInternal   = "O cartão {0} ({1}) será APAGADO e formatado como armazenamento interno.`n`n- Ele ficará criptografado e só funcionará neste aparelho.`n- Apps movidos para ele param de funcionar se o cartão for removido ou falhar.`n`nContinuar?"
        ConfirmPortableT  = 'Voltar ao modo portátil'
        ConfirmPortable   = "O cartão {0} ({1}) será APAGADO e formatado como portátil (exFAT/FAT).`n`n- Apps e dados que estiverem nele serão perdidos e precisarão ser reinstalados.`n- Antes, mova os apps de volta para o armazenamento interno (Configurações > Apps > [app] > Armazenamento > Alterar).`n`nContinuar?"
        Cancelled         = 'Operação cancelada.'
        Formatting        = "Formatando {0} como '{1}'. Isso pode levar alguns minutos; não desconecte o cabo."
        Done              = 'Concluído.'
        ExitCode          = 'O comando terminou com código {0}.'
        TipsTitle         = 'Dicas antes de começar'
        ShowTipsOnStart   = 'Mostrar estas dicas ao abrir'
        Start             = 'Começar'
    }
    en = @{
        AdbMissing        = 'adb.exe not found. Install the Android SDK Platform-Tools.'
        AdbMissingShort   = 'adb.exe not found'
        AdbMissingLog     = 'adb.exe was not found in PATH or in the Android SDK. Install the Android SDK Platform-Tools.'
        Timeout           = 'Timed out ({0} s) running: adb {1}'
        ModeMixed         = 'Mixed'
        ModeInternal      = 'Internal storage'
        ModePortable      = 'Portable'
        ModeNone          = 'No volume mounted'
        UsageLine         = '{0}: {1} used of {2}'
        WindowTitle       = 'SD Card via ADB'
        Device            = 'Device:'
        RefreshDevices    = 'Refresh devices'
        ListCards         = 'List cards'
        Tips              = 'Tips'
        ColCard           = 'Card'
        ColSize           = 'Size'
        ColMode           = 'Current mode'
        ColVolumes        = 'Volumes'
        ColUsage          = 'Usage'
        BtnInternal       = 'Format as internal storage'
        BtnPortable       = 'Return to portable mode'
        WarnErase         = 'Both options ERASE everything on the card.'
        Error             = 'Error: {0}'
        NoDevices         = 'No device found. Check the cable, USB debugging and the "Allow USB debugging?" prompt.'
        DevicesFound      = '{0} device(s) found.'
        DeviceNotReady    = "{0} is '{1}'. Unlock the device and accept the debugging prompt."
        SelectDevice      = 'Select a device first.'
        DeviceState       = "The device is '{0}' and cannot take commands yet."
        AndroidVersion    = 'Android {0} (API {1}).'
        TooOld            = 'This Android version cannot use the card as internal storage (Android 6.0 or newer is required). See "Tips".'
        AdoptYes          = 'Internal (adoptable) storage support: yes'
        AdoptNo           = 'Internal (adoptable) storage support: no ({0}). The manufacturer blocked this feature; only portable mode is available.'
        NoCards           = 'No card found. Check that it is inserted.'
        CardLine          = '{0}: {1}, mode {2}. {3}'
        ConfirmInternalT  = 'Format as internal storage'
        ConfirmInternal   = "Card {0} ({1}) will be ERASED and formatted as internal storage.`n`n- It will be encrypted and will only work in this device.`n- Apps moved to it stop working if the card is removed or fails.`n`nContinue?"
        ConfirmPortableT  = 'Return to portable mode'
        ConfirmPortable   = "Card {0} ({1}) will be ERASED and formatted as portable (exFAT/FAT).`n`n- Apps and data on it will be lost and must be reinstalled.`n- First, move apps back to internal storage (Settings > Apps > [app] > Storage > Change).`n`nContinue?"
        Cancelled         = 'Operation cancelled.'
        Formatting        = "Formatting {0} as '{1}'. This may take a few minutes; do not unplug the cable."
        Done              = 'Done.'
        ExitCode          = 'The command finished with exit code {0}.'
        TipsTitle         = 'Tips before you start'
        ShowTipsOnStart   = 'Show these tips at startup'
        Start             = 'Start'
    }
}

function T([string]$key) {
    $s = $script:Strings[$script:Lang][$key]
    if ($args.Count) { $s = $s -f $args }
    return $s
}

# ---------------------------------------------------------------- ADB

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
    if (-not $script:Adb) { throw (T AdbMissing) }
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
            throw (T Timeout $TimeoutSec $psi.Arguments)
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
    $c = [System.Globalization.CultureInfo]::CurrentCulture
    if ($bytes -ge 1GB) { ($bytes / 1GB).ToString('N1', $c) + ' GB' }
    elseif ($bytes -ge 1MB) { ($bytes / 1MB).ToString('N0', $c) + ' MB' }
    else { ($bytes / 1KB).ToString('N0', $c) + ' KB' }
}

# Lê "dumpsys mount" e devolve um objeto por cartão (disco removível).
# Mode: internal | portable | mixed | none
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
        $mode = if ($types -contains 'PRIVATE' -and $types -contains 'PUBLIC') { 'mixed' }
                elseif ($types -contains 'PRIVATE') { 'internal' }
                elseif ($types -contains 'PUBLIC') { 'portable' }
                else { 'none' }

        $usage = @()
        foreach ($v in $d.Volumes) {
            if ($v.State -eq 'MOUNTED' -and $v.Path -and $v.Path -ne 'null') {
                $df = (Invoke-Adb @('-s', $Serial, 'shell', "df -k $($v.Path)")).Output -split "`r?`n" | Select-Object -Last 1
                $f = $df -split '\s+'
                if ($f.Count -ge 4 -and $f[1] -match '^\d+$') {
                    $usage += T UsageLine $v.Type.ToLower() (Format-Size ([double]$f[2] * 1KB)) (Format-Size ([double]$f[1] * 1KB))
                }
            }
        }

        $modeText = switch ($mode) { 'mixed' { T ModeMixed } 'internal' { T ModeInternal } 'portable' { T ModePortable } default { T ModeNone } }

        [pscustomobject]@{
            DiskId     = $d.Id
            Size       = $d.Size
            SizeText   = Format-Size $d.Size
            Adoptable  = $d.Flags -match 'ADOPTABLE'
            Mode       = $mode
            ModeText   = $modeText
            VolumeText = ($d.Volumes | ForEach-Object { "$($_.Id) ($($_.State.ToLower()))" }) -join ', '
            UsageText  = $usage -join '; '
        }
    }
}

if ($NoGui) { return }

# ---------------------------------------------------------------- Interface

$form = New-Object System.Windows.Forms.Form
$form.Text = T WindowTitle
$form.Size = New-Object System.Drawing.Size(900, 620)
$form.MinimumSize = New-Object System.Drawing.Size(760, 520)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)

$lblDevice = New-Object System.Windows.Forms.Label
$lblDevice.Text = T Device
$lblDevice.Location = '12,16'; $lblDevice.AutoSize = $true

$cmbDevice = New-Object System.Windows.Forms.ComboBox
$cmbDevice.DropDownStyle = 'DropDownList'
$cmbDevice.Location = '85,12'; $cmbDevice.Width = 420

$btnDevices = New-Object System.Windows.Forms.Button
$btnDevices.Text = T RefreshDevices
$btnDevices.Location = '515,11'; $btnDevices.Size = '150,28'

$btnList = New-Object System.Windows.Forms.Button
$btnList.Text = T ListCards
$btnList.Location = '675,11'; $btnList.Size = '120,28'

$btnTips = New-Object System.Windows.Forms.Button
$btnTips.Text = T Tips
$btnTips.Location = '802,11'; $btnTips.Size = '70,28'
$btnTips.Anchor = 'Top,Right'

$lblAdb = New-Object System.Windows.Forms.Label
$lblAdb.Location = '12,46'; $lblAdb.AutoSize = $true
$lblAdb.ForeColor = [System.Drawing.Color]::DimGray

$list = New-Object System.Windows.Forms.ListView
$list.View = 'Details'; $list.FullRowSelect = $true; $list.MultiSelect = $false; $list.HideSelection = $false
$list.Location = '12,72'; $list.Size = '860,150'
$list.Anchor = 'Top,Left,Right'
[void]$list.Columns.Add((T ColCard), 110)
[void]$list.Columns.Add((T ColSize), 80)
[void]$list.Columns.Add((T ColMode), 160)
[void]$list.Columns.Add((T ColVolumes), 270)
[void]$list.Columns.Add((T ColUsage), 230)

$btnInternal = New-Object System.Windows.Forms.Button
$btnInternal.Text = T BtnInternal
$btnInternal.Location = '12,232'; $btnInternal.Size = '280,32'

$btnPortable = New-Object System.Windows.Forms.Button
$btnPortable.Text = T BtnPortable
$btnPortable.Location = '302,232'; $btnPortable.Size = '200,32'

$lblWarn = New-Object System.Windows.Forms.Label
$lblWarn.Text = T WarnErase
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
    $btnInternal.Enabled = $ok -and $sel.Adoptable -and $script:HasAdoptable -and $sel.Mode -ne 'internal'
    $btnPortable.Enabled = $ok -and $sel.Mode -ne 'portable'
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
    } catch { Write-Log (T Error $_.Exception.Message); return }
    foreach ($d in $devs) {
        $label = if ($d.Model) { "$($d.Model)  ($($d.Serial))  - $($d.State)" } else { "$($d.Serial)  - $($d.State)" }
        $d | Add-Member -NotePropertyName Label -NotePropertyValue $label
        [void]$cmbDevice.Items.Add($d)
    }
    if ($devs.Count -eq 0) {
        Write-Log (T NoDevices)
    } else {
        $ready = $devs | Where-Object State -eq 'device' | Select-Object -First 1
        $cmbDevice.SelectedItem = if ($ready) { $ready } else { $devs[0] }
        Write-Log (T DevicesFound $devs.Count)
        foreach ($d in $devs | Where-Object State -ne 'device') {
            Write-Log (T DeviceNotReady $d.Serial $d.State)
        }
    }
}

function Refresh-Cards {
    $list.Items.Clear()
    Update-ActionButtons
    $serial = Get-SelectedSerial
    if (-not $serial) { Write-Log (T SelectDevice); return }
    if ($cmbDevice.SelectedItem.State -ne 'device') { Write-Log (T DeviceState $cmbDevice.SelectedItem.State); return }
    Set-Busy $true
    try {
        $ver = (Invoke-Adb @('-s', $serial, 'shell', 'getprop ro.build.version.release; getprop ro.build.version.sdk')).Output -split "`r?`n"
        $script:SdkLevel = [int]($ver[1] -replace '\D', '')
        Write-Log (T AndroidVersion $ver[0] $script:SdkLevel)
        if ($script:SdkLevel -lt 23) {
            Write-Log (T TooOld)
            return
        }
        $adopt = Invoke-Adb @('-s', $serial, 'shell', 'sm has-adoptable')
        $script:HasAdoptable = $adopt.Output -eq 'true'
        $cards = @(Get-SdCards -Serial $serial)
        Write-Log $(if ($script:HasAdoptable) { T AdoptYes } else { T AdoptNo $adopt.Output })
        if ($cards.Count -eq 0) { Write-Log (T NoCards) }
        foreach ($c in $cards) {
            $item = New-Object System.Windows.Forms.ListViewItem($c.DiskId)
            [void]$item.SubItems.Add($c.SizeText)
            [void]$item.SubItems.Add($c.ModeText)
            [void]$item.SubItems.Add($c.VolumeText)
            [void]$item.SubItems.Add($c.UsageText)
            $item.Tag = $c
            [void]$list.Items.Add($item)
            Write-Log (T CardLine $c.DiskId $c.SizeText $c.ModeText $c.UsageText)
        }
        if ($list.Items.Count -eq 1) { $list.Items[0].Selected = $true }
    } catch {
        Write-Log (T Error $_.Exception.Message)
    } finally {
        Set-Busy $false
    }
}

function Invoke-Partition([string]$target) {
    $serial = Get-SelectedSerial
    $card = $list.SelectedItems[0].Tag
    if ($target -eq 'private') {
        $title = T ConfirmInternalT
        $msg = T ConfirmInternal $card.DiskId $card.SizeText
    } else {
        $title = T ConfirmPortableT
        $msg = T ConfirmPortable $card.DiskId $card.SizeText
    }
    $answer = [System.Windows.Forms.MessageBox]::Show($form, $msg, $title, 'YesNo', 'Warning', 'Button2')
    if ($answer -ne 'Yes') { Write-Log (T Cancelled); return }

    Set-Busy $true
    try {
        Write-Log (T Formatting $card.DiskId $target)
        $r = Invoke-Adb @('-s', $serial, 'shell', "sm partition $($card.DiskId) $target") -TimeoutSec 1800
        Write-Result $r
        if ($r.ExitCode -eq 0 -and -not $r.Error) { Write-Log (T Done) }
        else { Write-Log (T ExitCode $r.ExitCode) }
    } catch {
        Write-Log (T Error $_.Exception.Message)
    } finally {
        Set-Busy $false
    }
    Refresh-Cards
}

# ---------------------------------------------------------------- Tela de dicas / Tips screen

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

# Cada aba: título e linhas. '#' = título, '-' = tópico, '' = linha em branco, resto = parágrafo.
$script:TipPages = @{
    pt = @(
        @{ Title = 'Preparar o aparelho'; Lines = @(
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
        ) }
        @{ Title = 'Versões do Android'; Lines = @(
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
        ) }
        @{ Title = 'Cuidados e problemas'; Lines = @(
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
        ) }
    )
    en = @(
        @{ Title = 'Prepare the device'; Lines = @(
            '# 1. Turn on Developer options'
            'On the device, open Settings > About tablet (or About phone) and tap "Build number" 7 times. You may be asked for your lock screen PIN.'
            '- Samsung: About phone > Software information > Build number.'
            '- Xiaomi/Redmi: About phone > MIUI / HyperOS version.'
            '- Motorola, TCL and stock Android: About phone > Build number.'
            ''
            '# 2. Turn on USB debugging'
            'Settings > System > Developer options > USB debugging. On some devices the menu is directly under Settings.'
            ''
            '# 3. Connect and authorise this computer'
            '- Use a data cable plugged directly into a PC port (no hub).'
            '- Unlock the screen and accept the "Allow USB debugging?" prompt, ticking "Always allow from this computer".'
            '- Click "Refresh devices". The state "device" means ready; "unauthorized" means the prompt has not been accepted; "offline" means the cable must be reconnected.'
            ''
            '# 4. When you are done'
            'While USB debugging is on, any authorised computer has broad access to the device. After making changes, turn USB debugging off and, if you like, use "Revoke USB debugging authorisations". The card keeps working normally afterwards.'
        ) }
        @{ Title = 'Android versions'; Lines = @(
            '# Using the card as internal storage'
            'This feature (called "adoptable storage") was introduced in Android 6.0. When you click "List cards", the tool shows the device version and whether it supports the feature.'
            ''
            '- Android 5.1 or earlier: not supported. The card only works as portable storage.'
            '- Android 6.0 to 8.1: supported. Usually shown in the card menu as "Format as internal".'
            '- Android 9 to 15: supported by the system, but many manufacturers and carriers hide the option from the menu. In those cases, formatting with this tool usually works.'
            '- Versions newer than Android 15: not verified with this tool.'
            ''
            '# When it does not work'
            '- If "Internal storage support" shows "no", the manufacturer blocked the feature and the format-as-internal button is disabled.'
            '- Recent Samsung Galaxy devices usually block the feature.'
            '- Returning to portable mode works on any version from Android 6.0.'
            ''
            '# Tested on'
            '- TCL TAB 10 5G (9183W, T-Mobile firmware), Android 12.'
            ''
            '# On the computer'
            '- Windows 10 or 11, with the Android SDK Platform-Tools (adb) installed.'
        ) }
        @{ Title = 'Precautions and issues'; Lines = @(
            '# Before formatting'
            '- Both formatting options ERASE everything on the card. Copy anything important first.'
            '- As internal storage, the card is encrypted and only works in this device.'
            '- Prefer A1 or A2 cards (app performance class). Slow cards make the device slow.'
            '- Before returning to portable mode or removing the card, move apps back: Settings > Apps > [app] > Storage > Change.'
            '- Formatting can take a few minutes. Do not unplug the cable or lock the device.'
            ''
            '# If the device does not show up'
            '- Check that USB debugging is on and the screen is unlocked.'
            '- Some USB-C cables only charge or fail with ADB. Try another cable.'
            '- If the authorisation prompt does not appear, use "Revoke USB debugging authorisations", turn debugging off and on, and reconnect the cable.'
            '- On Windows, if Device Manager shows "Code 10" for the device, reconnect it to another port or install the Google USB Driver (Android Studio > SDK Manager > SDK Tools).'
            ''
            '# Carrier firmware'
            'Devices sold by carriers (e.g. T-Mobile) may hide menu options such as languages and the internal card format. The tool uses Android''s own commands, which remain available.'
        ) }
    )
}

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
    $dlg.Text = T TipsTitle
    $dlg.Size = New-Object System.Drawing.Size(700, 600)
    $dlg.MinimumSize = New-Object System.Drawing.Size(560, 460)
    $dlg.StartPosition = 'CenterParent'
    $dlg.Font = $form.Font
    $dlg.MinimizeBox = $false; $dlg.ShowInTaskbar = $false

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = 'Fill'
    foreach ($p in $script:TipPages[$script:Lang]) { $tabs.TabPages.Add((New-TipsPage $p.Title $p.Lines)) }

    $bottom = New-Object System.Windows.Forms.Panel
    $bottom.Dock = 'Bottom'; $bottom.Height = 48

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = T ShowTipsOnStart
    $chk.AutoSize = $true; $chk.Location = '12,14'
    $chk.Checked = Get-ShowTips

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = T Start
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
        $lblAdb.Text = T AdbMissingShort
        Write-Log (T AdbMissingLog)
        foreach ($c in @($btnDevices, $btnList)) { $c.Enabled = $false }
    }
    Update-ActionButtons
})

[void]$form.ShowDialog()
