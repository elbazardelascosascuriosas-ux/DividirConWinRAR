<#
.SYNOPSIS
    Dividir archivos grandes en partes usando WinRAR (GUI) con progreso simulado suave + tiempo restante estimado
.VERSION
    2.6 - Agregado -ep para archivos sin carpeta intermedia + limpieza de nombre base
#>

#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ==================== CONFIGURACIÓN ====================
$script:Config = @{
    DefaultDirectory       = "D:\juguetes"
    WinRARPaths            = @(
        "C:\Program Files\WinRAR\winrar.exe"
        "C:\Program Files (x86)\WinRAR\winrar.exe"
        "${env:ProgramFiles}\WinRAR\winrar.exe"
        "${env:ProgramFiles(x86)}\WinRAR\winrar.exe"
    )
    EncodingCodePage       = 850
    MinPartSizeMB          = 5
    DefaultPartSize        = "800m"
    WindowStyle            = "Hidden"
    
    # Ajustes para simulación de progreso - SSD rápido + CPU moderna (2025-2026)
    SimulatedBaseTimePerGB = 32           # segundos por GB ≈ muy buen SSD NVMe + compresión media-alta
    SimulatedMinTime       = 90           # tiempo mínimo simulado aunque el archivo sea pequeño
}

# ==================== FUNCIONES AUXILIARES ====================

function Write-Log {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('Info','Warning','Error','Success')] [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    if ($Level -eq 'Error')      { Write-Host $logEntry -ForegroundColor Red }
    elseif ($Level -eq 'Warning') { Write-Host $logEntry -ForegroundColor Yellow }
    elseif ($Level -eq 'Success') { Write-Host $logEntry -ForegroundColor Green }
    else                          { Write-Verbose $logEntry }
}

function Find-WinRAR {
    foreach ($path in $script:Config.WinRARPaths) {
        if (Test-Path $path -PathType Leaf) {
            Write-Log "WinRAR GUI encontrado: $path" -Level Success
            return $path
        }
    }
    Write-Log "No se encontró winrar.exe" -Level Error
    return $null
}

function Test-ValidPartSize {
    param([string]$Size)
    
    if ($Size -notmatch '^\d+[kKmMgGtT]$') { return $false }
    
    $number = [regex]::Match($Size, '^(\d+)').Groups[1].Value
    $unit   = $Size[-1].ToString().ToLower()
    
    $bytes = switch ($unit) {
        'k' { [int64]$number * 1KB }
        'm' { [int64]$number * 1MB }
        'g' { [int64]$number * 1GB }
        't' { [int64]$number * 1TB }
        default { 0 }
    }
    
    $minBytes = $script:Config.MinPartSizeMB * 1MB
    return $bytes -ge $minBytes
}

function Convert-SecondsToReadable {
    param([double]$Seconds)
    if ($Seconds -lt 0) { return "--:--" }
    $ts = [TimeSpan]::FromSeconds([math]::Max(0, [math]::Round($Seconds)))
    if ($ts.TotalHours -ge 1) {
        return $ts.ToString("hh\:mm\:ss")
    }
    return $ts.ToString("mm\:ss")
}

function Show-SizeInputForm {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $form = New-Object System.Windows.Forms.Form -Property @{
        Text            = "Tamaño de cada parte"
        Size            = New-Object System.Drawing.Size(460,240)
        StartPosition   = "CenterScreen"
        FormBorderStyle = "FixedDialog"
        MaximizeBox     = $false
        MinimizeBox     = $false
        TopMost         = $true
    }
    
    $label = New-Object System.Windows.Forms.Label -Property @{
        Location = New-Object System.Drawing.Point(20,20)
        Size     = New-Object System.Drawing.Size(410,70)
        Text     = "Tamaño de cada volumen (ejemplos válidos):`n800m   1500m   2g   4g   7500m`n`nMínimo recomendado: $($script:Config.MinPartSizeMB) MB"
    }
    
    $tb = New-Object System.Windows.Forms.TextBox -Property @{
        Location = New-Object System.Drawing.Point(20,100)
        Size     = New-Object System.Drawing.Size(410,28)
        Font     = New-Object System.Drawing.Font("Consolas",12)
        Text     = $script:Config.DefaultPartSize
    }
    
    $ok = New-Object System.Windows.Forms.Button -Property @{
        Location = New-Object System.Drawing.Point(240,150)
        Size     = New-Object System.Drawing.Size(100,38)
        Text     = "Aceptar"
        DialogResult = "OK"
    }
    
    $cancel = New-Object System.Windows.Forms.Button -Property @{
        Location = New-Object System.Drawing.Point(130,150)
        Size     = New-Object System.Drawing.Size(100,38)
        Text     = "Cancelar"
        DialogResult = "Cancel"
    }
    
    $form.Controls.AddRange(@($label,$tb,$ok,$cancel))
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel
    
    if ($form.ShowDialog() -eq "OK") {
        $size = $tb.Text.Trim().ToLower()
        if (Test-ValidPartSize $size) {
            Write-Log "Tamaño seleccionado: $size" -Level Info
            return $size
        }
        else {
            [System.Windows.Forms.MessageBox]::Show(
                "Formato inválido o tamaño demasiado pequeño.`nEjemplos: 800m, 1500m, 2g, 4g, 7500m`nMínimo: $($script:Config.MinPartSizeMB)MB",
                "Tamaño incorrecto",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            return $null
        }
    }
    return $null
}

function Select-Files {
    $initDir = if (Test-Path $script:Config.DefaultDirectory) { 
        $script:Config.DefaultDirectory 
    } else { 
        [Environment]::GetFolderPath("MyDocuments") 
    }
    
    $ofd = New-Object System.Windows.Forms.OpenFileDialog -Property @{
        InitialDirectory = $initDir
        Multiselect      = $true
        Title            = "Selecciona archivo(s) a dividir"
        Filter           = "Archivos grandes (*.mkv;*.mp4;*.iso;*.zip;*.rar;*.7z;*)|*.mkv;*.mp4;*.iso;*.zip;*.rar;*.7z;*.*|Todos los archivos (*.*)|*.*"
    }
    
    if ($ofd.ShowDialog() -eq "OK") {
        return $ofd.FileNames
    }
    return $null
}

function Test-ShouldOverwrite {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) { return $true }
    
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Ya existe:`n$Path`n`n¿Deseas sobreescribirlo?",
        "Archivo ya existe",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )
    
    return $result -eq "Yes"
}

# ==================== FUNCIÓN PRINCIPAL DE DIVISIÓN ====================

function Split-FileWithWinRARGUI {
    param(
        [Parameter(Mandatory)] [string]$WinRarExe,
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [string]$PartSize,
        [Parameter(Mandatory)] [hashtable]$UI,
        [Parameter(Mandatory)] [int]$Index,
        [Parameter(Mandatory)] [int]$Total
    )
    
    $fileName   = [IO.Path]::GetFileName($FilePath)
    $dir        = [IO.Path]::GetDirectoryName($FilePath)
    $baseName   = [IO.Path]::GetFileNameWithoutExtension($FilePath)
    
    # Limpieza opcional del nombre base (recomendado para nombres largos o con caracteres raros)
    $cleanBase  = $baseName -replace '[^ \w\.-]', '_' -replace '\s+', ' ' -replace '^\s+|\s+$', ''
    $outputBase = Join-Path $dir $cleanBase
    
    # Si prefieres el nombre original sin limpiar, comenta las 3 líneas anteriores y usa:
    # $outputBase = Join-Path $dir $baseName
    
    if (-not (Test-ShouldOverwrite "$outputBase.part1.rar")) {
        Write-Log "Omitido por usuario: $fileName" -Level Warning
        return @{ Success = $false; Skipped = $true; Message = "Omitido por usuario" }
    }
    
    $args = @(
        "a"
        "-v$PartSize"
        "-m5"
        "-s"           # Archivo sólido (importante para compresión eficiente)
        "-ma5"         # Formato RAR5
        "-ep"          # <--- CLAVE: excluye rutas de carpeta, guarda solo el nombre del archivo
        "-dh"
        "-t"
        "--"           # Separa switches de paths
        "`"$outputBase`""  # Base sin .rar
        "`"$FilePath`""    # Archivo a comprimir
    ) -join " "
    
    $psi = New-Object System.Diagnostics.ProcessStartInfo -Property @{
        FileName               = $WinRarExe
        Arguments              = $args
        WorkingDirectory       = $dir
        UseShellExecute        = $true
        RedirectStandardOutput = $false
        RedirectStandardError  = $false
        CreateNoWindow         = $true
        WindowStyle            = $script:Config.WindowStyle
    }
    
    Write-Log "Iniciando WinRAR: $args" -Level Info
    
    $process = [System.Diagnostics.Process]::Start($psi)
    
    # Estimación realista según tamaño del archivo
    $fileSizeGB = [math]::Round((Get-Item $FilePath).Length / 1GB, 2)
    $estimatedTotalSeconds = [math]::Max(
        $script:Config.SimulatedMinTime,
        [math]::Round($fileSizeGB * $script:Config.SimulatedBaseTimePerGB)
    )
    
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $simulatedPercent = 0
    
    while (-not $process.HasExited) {
        $elapsed = $sw.Elapsed.TotalSeconds
        
        # Progreso base
        $progressFactor = [Math]::Min(1.0, $elapsed / $estimatedTotalSeconds)
        $simulatedPercent = [Math]::Min(99, [math]::Round($progressFactor * 100))
        
        # Últimos porcentajes más lentos (sensación realista)
        if ($simulatedPercent -gt 92) {
            $simulatedPercent = [Math]::Min(99, $simulatedPercent + (Get-Random -Minimum 0.12 -Maximum 0.55))
        }
        
        # Tiempo restante
        if ($progressFactor -gt 0.03 -and $progressFactor -lt 0.97) {
            $remainingSeconds = ($estimatedTotalSeconds * (1 - $progressFactor)) / [Math]::Max(0.15, $progressFactor)
            $remainingStr = Convert-SecondsToReadable $remainingSeconds
        } else {
            $remainingStr = "--:--"
        }
        
        $status = "WinRAR en proceso: $simulatedPercent%  |  Tiempo restante estimado: $remainingStr  |  Transcurrido: $($sw.Elapsed.ToString('mm\:ss'))"
        
        Update-Progress $UI $Index $Total $fileName $simulatedPercent $status
        
        Start-Sleep -Milliseconds 800
    }
    
    $process.WaitForExit()
    $sw.Stop()
    
    $exitCode = $process.ExitCode
    
    Update-Progress $UI $Index $Total $fileName 100 "Finalizado ($($sw.Elapsed.ToString('mm\:ss')))"
    
    if ($exitCode -eq 0) {
        Write-Log "ÉXITO: $fileName → $outputBase.part*.rar ($($sw.Elapsed.ToString('mm\:ss')))" -Level Success
        return @{ Success = $true; Duration = $sw.Elapsed }
    }
    else {
        Write-Log "FALLO (código $exitCode): $fileName" -Level Error
        return @{ Success = $false; ExitCode = $exitCode; Duration = $sw.Elapsed }
    }
}

function Update-Progress {
    param($UI, $index, $total, $file, $percent, $status)
    
    $UI.LabelGlobal.Text      = if ($total -eq 1) { "Procesando archivo..." } else { "Archivo $($index+1) de $total" }
    $UI.ProgressGlobal.Value  = if ($total -eq 1) { 0 } else { $index }
    $UI.LabelArchivo.Text     = $file
    $UI.ProgressArchivo.Value = $percent
    $UI.LabelPorcentaje.Text  = "$percent%"
    $UI.LabelTiempo.Text      = $status
    
    [System.Windows.Forms.Application]::DoEvents()
}

function New-ProgressForm {
    param([int]$TotalFiles)
    
    $f = New-Object System.Windows.Forms.Form -Property @{
        Text            = "Procesando con WinRAR"
        Size            = New-Object System.Drawing.Size(720,300)
        StartPosition   = "CenterScreen"
        FormBorderStyle = "FixedDialog"
        ControlBox      = $false
        TopMost         = $true
    }
    
    $globalLabel = New-Object System.Windows.Forms.Label -Property @{ Location = "20,20"; Size = "680,30"; TextAlign = "MiddleCenter"; Font = "Segoe UI,11,style=Bold" }
    $globalProg  = New-Object System.Windows.Forms.ProgressBar -Property @{ Location = "20,55"; Size = "680,30"; Maximum = [Math]::Max(1, $TotalFiles) }
    $fileLabel   = New-Object System.Windows.Forms.Label -Property @{ Location = "20,95"; Size = "680,30"; TextAlign = "MiddleCenter" }
    $fileProg    = New-Object System.Windows.Forms.ProgressBar -Property @{ Location = "20,130"; Size = "680,40"; Maximum = 100 }
    $pctLabel    = New-Object System.Windows.Forms.Label -Property @{ Location = "20,185"; Size = "680,40"; TextAlign = "MiddleCenter"; Font = "Segoe UI,16,style=Bold"; ForeColor = "DarkGreen" }
    $timeLabel   = New-Object System.Windows.Forms.Label -Property @{ Location = "20,235"; Size = "680,25"; TextAlign = "MiddleCenter"; ForeColor = "Gray" }
    
    $f.Controls.AddRange(@($globalLabel,$globalProg,$fileLabel,$fileProg,$pctLabel,$timeLabel))
    
    if ($TotalFiles -eq 1) {
        $globalProg.Visible = $false
        $globalLabel.Visible = $false
        $fileLabel.Location = New-Object System.Drawing.Point(20,40)
        $fileProg.Location  = New-Object System.Drawing.Point(20,75)
        $pctLabel.Location  = New-Object System.Drawing.Point(20,130)
        $timeLabel.Location = New-Object System.Drawing.Point(20,180)
    }
    
    return @{
        Form           = $f
        LabelGlobal    = $globalLabel
        ProgressGlobal = $globalProg
        LabelArchivo   = $fileLabel
        ProgressArchivo= $fileProg
        LabelPorcentaje= $pctLabel
        LabelTiempo    = $timeLabel
    }
}

# ==================== FLUJO PRINCIPAL ====================

try {
    Add-Type -AssemblyName System.Windows.Forms,System.Drawing
    
    $winrar = Find-WinRAR
    if (!$winrar) {
        [System.Windows.Forms.MessageBox]::Show(
            "No se encontró winrar.exe",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        exit
    }
    
    $partSize = Show-SizeInputForm
    if (!$partSize) { exit }
    
    $selected = Select-Files
    $files = @($selected)
    
    if ($files.Count -eq 0) {
        Write-Log "Selección cancelada o vacía" -Level Info
        [System.Windows.Forms.MessageBox]::Show("No se seleccionaron archivos.", "Cancelado", "OK", "Information")
        exit
    }

    $ui = New-ProgressForm -TotalFiles $files.Count
    $ui.Form.Show()
    $ui.Form.Activate()
    [System.Windows.Forms.Application]::DoEvents()

    $stats = @{ Success=0; Failed=0; Skipped=0; Errors=@() }
    $totalTime = [TimeSpan]::Zero
    
    for ($i = 0; $i -lt $files.Count; $i++) {
        $result = Split-FileWithWinRARGUI -WinRarExe $winrar -FilePath $files[$i] -PartSize $partSize -UI $ui -Index $i -Total $files.Count
        
        $totalTime += $result.Duration
        
        if ($result.Success) {
            $stats.Success++
        }
        elseif ($result.Skipped) {
            $stats.Skipped++
        }
        else {
            $stats.Failed++
            $stats.Errors += "• $($files[$i] | Split-Path -Leaf) → error $($result.ExitCode)"
        }
    }
    
    $ui.LabelGlobal.Text = "¡Proceso finalizado!"
    $ui.ProgressGlobal.Value = $files.Count
    $ui.ProgressArchivo.Value = 100
    $ui.LabelPorcentaje.Text = "100%"
    $ui.LabelTiempo.Text = "Tiempo total: $($totalTime.ToString('hh\:mm\:ss'))"
    Start-Sleep -Milliseconds 1800
    $ui.Form.Close()
    
    $msg = @"
Proceso completado

Archivos: $($files.Count)
Éxitos:   $($stats.Success)
Omitidos: $($stats.Skipped)
Fallidos: $($stats.Failed)
Tiempo:   $($totalTime.ToString('hh\:mm\:ss'))

$($stats.Errors -join "`n")
"@
    
    $icon = if ($stats.Failed -gt 0) { [System.Windows.Forms.MessageBoxIcon]::Warning } else { [System.Windows.Forms.MessageBoxIcon]::Information }
    [System.Windows.Forms.MessageBox]::Show($msg,"Resultado",[System.Windows.Forms.MessageBoxButtons]::OK,$icon)
}
catch {
    Write-Log "ERROR CRÍTICO: $_" -Level Error
    [System.Windows.Forms.MessageBox]::Show("Error inesperado:`n$_","Error fatal","OK","Error")
}
finally {
    Write-Log "=== FIN ===" -Level Info
}