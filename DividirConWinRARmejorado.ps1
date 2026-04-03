# DividirConWinRAR.ps1 - Versión mejorada v3
# Progreso REAL via archivo temporal + UI clara + botones sin emoji + carpeta completa

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$originalEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(850)

# ============================================================
# FUNCIÓN: Buscar WinRAR
# ============================================================
function Get-WinRARPath {
    $rutasComunes = @(
        "C:\Program Files\WinRAR\rar.exe",
        "C:\Program Files (x86)\WinRAR\rar.exe"
    )
    foreach ($r in $rutasComunes) { if (Test-Path $r) { return $r } }
    $regPaths = @(
        "HKLM:\SOFTWARE\WinRAR",
        "HKLM:\SOFTWARE\WOW6432Node\WinRAR",
        "HKCU:\SOFTWARE\WinRAR"
    )
    foreach ($reg in $regPaths) {
        try {
            $val = (Get-ItemProperty -Path $reg -ErrorAction Stop).exe64
            if (-not $val) { $val = (Get-ItemProperty -Path $reg -ErrorAction Stop).exe32 }
            $candidate = Join-Path (Split-Path $val) "rar.exe"
            if (Test-Path $candidate) { return $candidate }
        } catch {}
    }
    $found = Get-Command "rar.exe" -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    return $null
}

# ============================================================
# FUNCIÓN: Descripción del código de salida de RAR
# ============================================================
function Get-RARExitDescription($code) {
    switch ($code) {
        0   { return "Exito" }
        1   { return "Advertencia (archivos bloqueados o en uso)" }
        2   { return "Error fatal" }
        3   { return "Error de CRC (datos corruptos)" }
        4   { return "Error de bloqueo (archivo ya en uso)" }
        5   { return "Error de escritura en disco" }
        6   { return "Error de apertura de archivo" }
        7   { return "Version de RAR incorrecta" }
        8   { return "Memoria insuficiente" }
        9   { return "Error al crear archivo" }
        10  { return "Sin archivos para comprimir" }
        255 { return "Cancelado por el usuario" }
        default { return "Error desconocido (codigo $code)" }
    }
}

# ============================================================
# FUNCIÓN: Verificar espacio libre
# ============================================================
function Test-DiskSpace($archivos, $directorio) {
    try {
        $totalBytes = ($archivos | ForEach-Object {
            if (Test-Path $_ -PathType Container) {
                (Get-ChildItem $_ -Recurse -File | Measure-Object -Property Length -Sum).Sum
            } else {
                (Get-Item $_).Length
            }
        } | Measure-Object -Sum).Sum
        $drive = Split-Path -Qualifier $directorio
        $freeSpace = (Get-PSDrive ($drive.TrimEnd(':'))).Free
        if ($freeSpace -lt $totalBytes) {
            $necesarioMB = [math]::Round($totalBytes / 1MB, 1)
            $libresMB    = [math]::Round($freeSpace  / 1MB, 1)
            [System.Windows.Forms.MessageBox]::Show(
                "Espacio insuficiente en disco.`n`nNecesario (aprox.): $necesarioMB MB`nDisponible: $libresMB MB",
                "Error de espacio", "OK", "Error")
            return $false
        }
    } catch { }
    return $true
}

# ============================================================
# 1. CONFIGURACIÓN
# ============================================================
$formConfig = New-Object System.Windows.Forms.Form
$formConfig.Text = "Configuracion de compresion"
$formConfig.Size = New-Object System.Drawing.Size(460, 280)
$formConfig.StartPosition = "CenterScreen"
$formConfig.FormBorderStyle = "FixedDialog"
$formConfig.MaximizeBox = $false
$formConfig.TopMost = $true
$formConfig.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$grpTamano = New-Object System.Windows.Forms.GroupBox
$grpTamano.Location = New-Object System.Drawing.Point(15, 10)
$grpTamano.Size = New-Object System.Drawing.Size(420, 90)
$grpTamano.Text = "Tamanio de cada parte"
$formConfig.Controls.Add($grpTamano)

$lblTamano = New-Object System.Windows.Forms.Label
$lblTamano.Location = New-Object System.Drawing.Point(10, 22)
$lblTamano.Size = New-Object System.Drawing.Size(400, 20)
$lblTamano.Text = "Ejemplos: 100m, 500m, 800m, 1g, 4g, 2048k  (defecto: 800m)"
$grpTamano.Controls.Add($lblTamano)

$txtTamano = New-Object System.Windows.Forms.TextBox
$txtTamano.Location = New-Object System.Drawing.Point(10, 48)
$txtTamano.Size = New-Object System.Drawing.Size(400, 28)
$txtTamano.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$txtTamano.Text = "800m"
$grpTamano.Controls.Add($txtTamano)

$grpCompresion = New-Object System.Windows.Forms.GroupBox
$grpCompresion.Location = New-Object System.Drawing.Point(15, 110)
$grpCompresion.Size = New-Object System.Drawing.Size(420, 75)
$grpCompresion.Text = "Nivel de compresion"
$formConfig.Controls.Add($grpCompresion)

$cboNivel = New-Object System.Windows.Forms.ComboBox
$cboNivel.Location = New-Object System.Drawing.Point(10, 30)
$cboNivel.Size = New-Object System.Drawing.Size(400, 28)
$cboNivel.DropDownStyle = "DropDownList"
$cboNivel.Items.AddRange(@(
    "0 - Sin compresion (Store) - ideal para video",
    "1 - Compresion rapida",
    "5 - Normal"
))
$cboNivel.SelectedIndex = 0
$grpCompresion.Controls.Add($cboNivel)

$btnOk = New-Object System.Windows.Forms.Button
$btnOk.Location = New-Object System.Drawing.Point(235, 215)
$btnOk.Size = New-Object System.Drawing.Size(90, 32)
$btnOk.Text = "Aceptar"
$btnOk.DialogResult = "OK"
$formConfig.AcceptButton = $btnOk
$formConfig.Controls.Add($btnOk)

$btnCancelarConfig = New-Object System.Windows.Forms.Button
$btnCancelarConfig.Location = New-Object System.Drawing.Point(340, 215)
$btnCancelarConfig.Size = New-Object System.Drawing.Size(90, 32)
$btnCancelarConfig.Text = "Cancelar"
$btnCancelarConfig.DialogResult = "Cancel"
$formConfig.CancelButton = $btnCancelarConfig
$formConfig.Controls.Add($btnCancelarConfig)

if ($formConfig.ShowDialog() -ne "OK") { exit }

$nivelCompresion = $cboNivel.SelectedItem.ToString().Substring(0, 1)
$tamanoParte = $txtTamano.Text.Trim()
if ($tamanoParte -match '^\d+$') { $tamanoParte += "m" }
if ($tamanoParte -notmatch '^\d+[kKmMgGbB]$') {
    [System.Windows.Forms.MessageBox]::Show("Formato invalido. Usa: 100m, 500m, 1g, 4g", "Error", "OK", "Error")
    exit
}
# ============================================================
# 2. SELECCIÓN DE ARCHIVOS
# ============================================================
$openFile = New-Object System.Windows.Forms.OpenFileDialog
$openFile.InitialDirectory = "D:\juguetes"
$openFile.Filter = "Todos los archivos (*.*)|*.*"
$openFile.Title = "Selecciona uno o varios archivos (Ctrl o Shift para varios)"
$openFile.Multiselect = $true
if ($openFile.ShowDialog() -ne "OK") { exit }
$archivos = $openFile.FileNames
if ($archivos.Count -eq 0) { exit }

# ============================================================
# 3. DETECTAR WinRAR
# ============================================================
$rarPath = Get-WinRARPath
if (-not $rarPath) {
    [System.Windows.Forms.MessageBox]::Show(
        "WinRAR no encontrado.`nInstala desde: www.win-rar.com", "Error", "OK", "Error")
    exit
}

# ============================================================
# 4. VERIFICAR ESPACIO
# ============================================================
$directorioSalida = Split-Path $archivos[0]
if (-not (Test-DiskSpace $archivos $directorioSalida)) { exit }

# ============================================================
# 5. VENTANA DE PROGRESO
# ============================================================
$cancelado = $false

$formProgreso = New-Object System.Windows.Forms.Form
$formProgreso.Text = "WinRAR - Dividiendo archivos"
$formProgreso.Size = New-Object System.Drawing.Size(680, 400)
$formProgreso.StartPosition = "CenterScreen"
$formProgreso.FormBorderStyle = "FixedDialog"
$formProgreso.ControlBox = $false
$formProgreso.TopMost = $true
$formProgreso.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# Etiqueta global
$lblGlobal = New-Object System.Windows.Forms.Label
$lblGlobal.Location = New-Object System.Drawing.Point(20, 15)
$lblGlobal.Size = New-Object System.Drawing.Size(640, 24)
$lblGlobal.Text = "Procesando 1 de $($archivos.Count)..."
$lblGlobal.TextAlign = "MiddleCenter"
$lblGlobal.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$formProgreso.Controls.Add($lblGlobal)

# Barra global
$progressGlobal = New-Object System.Windows.Forms.ProgressBar
$progressGlobal.Location = New-Object System.Drawing.Point(20, 45)
$progressGlobal.Size = New-Object System.Drawing.Size(640, 18)
$progressGlobal.Minimum = 0
$progressGlobal.Maximum = $archivos.Count
$progressGlobal.Value = 0
$formProgreso.Controls.Add($progressGlobal)

# Etiqueta archivo actual
$lblArchivo = New-Object System.Windows.Forms.Label
$lblArchivo.Location = New-Object System.Drawing.Point(20, 72)
$lblArchivo.Size = New-Object System.Drawing.Size(640, 20)
$lblArchivo.Text = ""
$lblArchivo.TextAlign = "MiddleLeft"
$formProgreso.Controls.Add($lblArchivo)

# Barra archivo actual
$progressArchivo = New-Object System.Windows.Forms.ProgressBar
$progressArchivo.Location = New-Object System.Drawing.Point(20, 97)
$progressArchivo.Size = New-Object System.Drawing.Size(640, 28)
$progressArchivo.Minimum = 0
$progressArchivo.Maximum = 100
$progressArchivo.Value = 0
$formProgreso.Controls.Add($progressArchivo)

# Porcentaje
$lblPorcentaje = New-Object System.Windows.Forms.Label
$lblPorcentaje.Location = New-Object System.Drawing.Point(20, 132)
$lblPorcentaje.Size = New-Object System.Drawing.Size(640, 40)
$lblPorcentaje.Text = "0%"
$lblPorcentaje.TextAlign = "MiddleCenter"
$lblPorcentaje.Font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
$formProgreso.Controls.Add($lblPorcentaje)

# Stats (velocidad / ETA)
$lblStats = New-Object System.Windows.Forms.Label
$lblStats.Location = New-Object System.Drawing.Point(20, 178)
$lblStats.Size = New-Object System.Drawing.Size(640, 20)
$lblStats.Text = ""
$lblStats.TextAlign = "MiddleCenter"
$lblStats.ForeColor = [System.Drawing.Color]::DimGray
$formProgreso.Controls.Add($lblStats)

# Log
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(20, 205)
$txtLog.Size = New-Object System.Drawing.Size(640, 100)
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 8)
$txtLog.Text = "Log de operaciones:`r`n"
$formProgreso.Controls.Add($txtLog)

# Botón cancelar — centrado y visible
$btnCancelarProceso = New-Object System.Windows.Forms.Button
$btnCancelarProceso.Location = New-Object System.Drawing.Point(270, 318)
$btnCancelarProceso.Size = New-Object System.Drawing.Size(140, 36)
$btnCancelarProceso.Text = "Cancelar"
$btnCancelarProceso.BackColor = [System.Drawing.Color]::FromArgb(200, 50, 50)
$btnCancelarProceso.ForeColor = [System.Drawing.Color]::White
$btnCancelarProceso.FlatStyle = "Flat"
$btnCancelarProceso.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$formProgreso.Controls.Add($btnCancelarProceso)

$procesoActual = $null
$btnCancelarProceso.Add_Click({
    $script:cancelado = $true
    if ($null -ne $script:procesoActual -and -not $script:procesoActual.HasExited) {
        try { $script:procesoActual.Kill() } catch {}
    }
    $btnCancelarProceso.Enabled = $false
    $btnCancelarProceso.Text = "Cancelando..."
})

$formProgreso.Show()
[System.Windows.Forms.Application]::DoEvents()

# ============================================================
# FUNCIÓN: Log
# ============================================================
function Add-Log($msg) {
    $hora = Get-Date -Format "HH:mm:ss"
    $txtLog.AppendText("[$hora] $msg`r`n")
    $txtLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

# ============================================================
# 6. PROCESAR ARCHIVOS
# ============================================================
$exitosos      = 0
$fallidos      = 0
$detallesError = ""
$tiempoTotal   = [System.Diagnostics.Stopwatch]::StartNew()

for ($i = 0; $i -lt $archivos.Count -and -not $cancelado; $i++) {

    $entradaActual  = $archivos[$i]
    $nombreMostrado = [IO.Path]::GetFileName($entradaActual)
    $dirSalida      = Split-Path $entradaActual
    $nombreBase     = [IO.Path]::GetFileNameWithoutExtension($nombreMostrado)
    $salidaRar      = Join-Path $dirSalida "$nombreBase.rar"

    # Reset UI
    $progressArchivo.Value = 0
    $lblPorcentaje.Text    = "0%"
    $lblArchivo.Text       = "Archivo: $nombreMostrado"
    $lblGlobal.Text        = "Procesando $($i + 1) de $($archivos.Count)  -  $nombreMostrado"
    $progressGlobal.Value  = $i
    $lblStats.Text         = ""
    [System.Windows.Forms.Application]::DoEvents()

    Add-Log "Iniciando: $nombreMostrado"

    # ── Construir argumentos ──────────────────────────────────
    # ESTRATEGIA DE PROGRESO: tamaño de archivos .rar generados vs tamaño original.
    # No depende de stdout de WinRAR (que no emite nada útil cuando está redirigido).

    $flags = "a -v$tamanoParte -ep -m$nivelCompresion -s"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName        = $rarPath
    $psi.Arguments       = "$flags `"$salidaRar`" `"$entradaActual`""
    $psi.WindowStyle     = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow  = $true
    $psi.UseShellExecute = $false

    $script:procesoActual = [System.Diagnostics.Process]::Start($psi)
    $tiempoArchivo = [System.Diagnostics.Stopwatch]::StartNew()

    # Tamaño original del archivo fuente
    $tamanoOriginalBytes = try { (Get-Item $entradaActual -ErrorAction Stop).Length } catch { 0 }
    $tamanoMB = [math]::Round($tamanoOriginalBytes / 1MB, 1)

    # Patrón de partes: nombre.rar, nombre.r00, nombre.r01, ...
    $patronPartes = Join-Path $dirSalida ($nombreBase + "*.r*")
    $patronRar    = Join-Path $dirSalida ($nombreBase + ".rar")

    $ultimoPct = 0
    while (-not $script:procesoActual.HasExited -and -not $cancelado) {
        Start-Sleep -Milliseconds 400
        [System.Windows.Forms.Application]::DoEvents()

        # Sumar bytes escritos en todas las partes ya creadas
        $bytesEscritos = 0
        try {
            $partesActuales = @(Get-Item $patronRar -ErrorAction SilentlyContinue) +
                              @(Get-Item $patronPartes -ErrorAction SilentlyContinue)
            foreach ($parte in $partesActuales) {
                try { $bytesEscritos += $parte.Length } catch {}
            }
        } catch {}

        if ($tamanoOriginalBytes -gt 0 -and $bytesEscritos -gt 0) {
            # Los .rar comprimidos son menores que el original; capamos al 99% mientras corre
            $pct = [math]::Min(99, [math]::Round($bytesEscritos * 100 / $tamanoOriginalBytes))
            if ($pct -gt $ultimoPct) {
                $ultimoPct = $pct
                $progressArchivo.Value = $pct
                $lblPorcentaje.Text    = "$pct%"

                $elapsed = $tiempoArchivo.Elapsed.TotalSeconds
                if ($elapsed -gt 1) {
                    $velocidad = [math]::Round(($bytesEscritos / 1MB) / $elapsed, 1)
                    $restante  = if ($pct -gt 0) {
                        [math]::Max(0, [math]::Round(($elapsed / $pct) * (100 - $pct)))
                    } else { 0 }
                    $etaTexto = if ($restante -ge 60) {
                        "$([math]::Floor($restante/60))m $($restante % 60)s restantes"
                    } else { "${restante}s restantes" }
                    $lblStats.Text = "Velocidad: ${velocidad} MB/s   -   ETA: $etaTexto"
                }
                [System.Windows.Forms.Application]::DoEvents()
            }
        }
    }

    if (-not $cancelado) {
        $progressArchivo.Value = 100
        $lblPorcentaje.Text    = "100%"
        $lblStats.Text         = "Completado en $([math]::Round($tiempoArchivo.Elapsed.TotalSeconds, 1))s"
        [System.Windows.Forms.Application]::DoEvents()
    }

    $script:procesoActual.WaitForExit()
    $exitCode = $script:procesoActual.ExitCode

    if ($cancelado) {
        Add-Log "CANCELADO por el usuario."
        break
    }

    if ($exitCode -eq 0) {
        $exitosos++
        Add-Log "OK: $nombreMostrado"
    } else {
        $fallidos++
        $desc = Get-RARExitDescription $exitCode
        $detallesError += "`n* $nombreMostrado => $desc (codigo $exitCode)"
        Add-Log "ERROR: $nombreMostrado - $desc (codigo $exitCode)"
    }
}

# Finalizar UI
$tiempoTotal.Stop()
$progressGlobal.Value = if ($cancelado) { $progressGlobal.Value } else { $archivos.Count }
$lblGlobal.Text = if ($cancelado) { "Operacion cancelada" } else { "Completado!" }
$lblStats.Text  = "Tiempo total: $([math]::Round($tiempoTotal.Elapsed.TotalSeconds, 1))s"
Start-Sleep -Milliseconds 900
$formProgreso.Close()

[Console]::OutputEncoding = $originalEncoding

# ============================================================
# 7. RESULTADO FINAL
# ============================================================
$procesados = if ($cancelado) { $exitosos + $fallidos } else { $archivos.Count }
$tiempoStr  = "$([math]::Floor($tiempoTotal.Elapsed.TotalMinutes))m $($tiempoTotal.Elapsed.Seconds)s"

$mensaje  = "Resultado de la operacion`n"
$mensaje += "─────────────────────────────────`n"
$mensaje += "Archivos procesados : $procesados de $($archivos.Count)`n"
$mensaje += "Exitosos            : $exitosos`n"
$mensaje += "Fallidos            : $fallidos`n"
if ($cancelado) { $mensaje += "Estado              : CANCELADO`n" }
$mensaje += "Tiempo total        : $tiempoStr`n"
$mensaje += "Tamanio de parte    : $tamanoParte`n"
$mensaje += "Nivel de compresion : $nivelCompresion`n"

if ($fallidos -gt 0) {
    $mensaje += "`nErrores encontrados:`n$detallesError"
    $icono = "Error"
} elseif ($cancelado) {
    $icono = "Warning"
} else {
    $icono = "Information"
}

[System.Windows.Forms.MessageBox]::Show($mensaje, "Resultado final", "OK", $icono)
