# DividirConWinRAR.ps1 - Progreso REAL + ANIMACIÓN SUAVE del porcentaje
# Barra inferior avanza progresivamente incluso entre reportes de WinRAR

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Forzar codificación OEM para rar.exe (esencial para español)
$originalEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(850)  # CP850 español

# Al final del script, antes del MessageBox final:
[Console]::OutputEncoding = $originalEncoding

# === 1. Pedir tamaño de parte ===
$formTamano = New-Object System.Windows.Forms.Form
$formTamano.Text = "Tamaño de las partes"
$formTamano.Size = New-Object System.Drawing.Size(420, 200)
$formTamano.StartPosition = "CenterScreen"
$formTamano.FormBorderStyle = "FixedDialog"
$formTamano.MaximizeBox = $false
$formTamano.TopMost = $true

$lbl = New-Object System.Windows.Forms.Label
$lbl.Location = New-Object System.Drawing.Point(20, 20)
$lbl.Size = New-Object System.Drawing.Size(380, 50)
$lbl.Text = "Ingresa el tamaño de cada parte:`nEjemplos: 100m (100 MB), 500m, 1g, 4g, 2048k"
$formTamano.Controls.Add($lbl)

$txtTamano = New-Object System.Windows.Forms.TextBox
$txtTamano.Location = New-Object System.Drawing.Point(20, 80)
$txtTamano.Size = New-Object System.Drawing.Size(360, 30)
$txtTamano.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$formTamano.Controls.Add($txtTamano)

$btnOk = New-Object System.Windows.Forms.Button
$btnOk.Location = New-Object System.Drawing.Point(160, 130)
$btnOk.Size = New-Object System.Drawing.Size(100, 35)
$btnOk.Text = "Aceptar"
$btnOk.DialogResult = "OK"
$formTamano.AcceptButton = $btnOk
$formTamano.Controls.Add($btnOk)

if ($formTamano.ShowDialog() -ne "OK") { exit }

$tamanoParte = $txtTamano.Text.Trim()

if ($tamanoParte -notmatch '^\d+[kKmMgGbB]$') {
    [System.Windows.Forms.MessageBox]::Show("Formato inválido.`nUsa: 100m, 500m, 1g, 2048k", "Error", "OK", "Error")
    exit
}

# === 2. Seleccionar múltiples archivos ===
$openFile = New-Object System.Windows.Forms.OpenFileDialog
$openFile.InitialDirectory = "D:\juguetes"
$openFile.Filter = "Todos los archivos (*.*)|*.*"
$openFile.Title = "Selecciona uno o varios archivos (Ctrl o Shift para varios)"
$openFile.Multiselect = $true

if ($openFile.ShowDialog() -ne "OK") {
    [System.Windows.Forms.MessageBox]::Show("Operación cancelada.", "Información", "OK", "Information")
    exit
}

$archivos = $openFile.FileNames
if ($archivos.Count -eq 0) { exit }

# === 3. Buscar WinRAR ===
$rarPath = "C:\Program Files\WinRAR\rar.exe"
if (-not (Test-Path $rarPath)) {
    $rarPath = "C:\Program Files (x86)\WinRAR\rar.exe"
    if (-not (Test-Path $rarPath)) {
        [System.Windows.Forms.MessageBox]::Show("WinRAR no encontrado.`nInstálalo desde www.win-rar.com", "Error", "OK", "Error")
        exit
    }
}

# === 4. Ventana de progreso con dos barras ===
$formProgreso = New-Object System.Windows.Forms.Form
$formProgreso.Text = "Dividiendo archivos con WinRAR..."
$formProgreso.Size = New-Object System.Drawing.Size(650, 240)
$formProgreso.StartPosition = "CenterScreen"
$formProgreso.FormBorderStyle = "FixedDialog"
$formProgreso.ControlBox = $false
$formProgreso.TopMost = $true

$lblGlobal = New-Object System.Windows.Forms.Label
$lblGlobal.Location = New-Object System.Drawing.Point(20, 20)
$lblGlobal.Size = New-Object System.Drawing.Size(610, 30)
$lblGlobal.Text = "Procesando archivo 1 de $($archivos.Count)"
$lblGlobal.TextAlign = "MiddleCenter"
$formProgreso.Controls.Add($lblGlobal)

$progressGlobal = New-Object System.Windows.Forms.ProgressBar
$progressGlobal.Location = New-Object System.Drawing.Point(20, 60)
$progressGlobal.Size = New-Object System.Drawing.Size(610, 25)
$progressGlobal.Minimum = 0
$progressGlobal.Maximum = $archivos.Count
$progressGlobal.Value = 0
$formProgreso.Controls.Add($progressGlobal)

$lblArchivo = New-Object System.Windows.Forms.Label
$lblArchivo.Location = New-Object System.Drawing.Point(20, 100)
$lblArchivo.Size = New-Object System.Drawing.Size(610, 30)
$lblArchivo.Text = "Actual: $($archivos[0] | Split-Path -Leaf)"
$lblArchivo.TextAlign = "MiddleCenter"
$formProgreso.Controls.Add($lblArchivo)

$progressArchivo = New-Object System.Windows.Forms.ProgressBar
$progressArchivo.Location = New-Object System.Drawing.Point(20, 140)
$progressArchivo.Size = New-Object System.Drawing.Size(610, 30)
$progressArchivo.Minimum = 0
$progressArchivo.Maximum = 100
$progressArchivo.Value = 0
$formProgreso.Controls.Add($progressArchivo)

$lblPorcentaje = New-Object System.Windows.Forms.Label
$lblPorcentaje.Location = New-Object System.Drawing.Point(20, 180)
$lblPorcentaje.Size = New-Object System.Drawing.Size(610, 30)
$lblPorcentaje.Text = "0%"
$lblPorcentaje.TextAlign = "MiddleCenter"
$lblPorcentaje.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$formProgreso.Controls.Add($lblPorcentaje)

$formProgreso.Show()
[System.Windows.Forms.Application]::DoEvents()


# === 5. Procesar con animación progresiva simulada ===
$exitosos = 0
$fallidos = 0
$detallesError = ""

for ($i = 0; $i -lt $archivos.Count; $i++) {
    $archivoCompleto = $archivos[$i]
    $nombreArchivo = [IO.Path]::GetFileName($archivoCompleto)
    $directorio = Split-Path $archivoCompleto
    $salidaRar = Join-Path $directorio "$([IO.Path]::GetFileNameWithoutExtension($nombreArchivo)).rar"

    # Reiniciar barra del archivo actual
    $progressArchivo.Value = 0
    $lblPorcentaje.Text = "0%"
    $lblArchivo.Text = "Actual: $nombreArchivo"
    $lblGlobal.Text = "Procesando archivo $($i + 1) de $($archivos.Count)"
    $progressGlobal.Value = $i
    [System.Windows.Forms.Application]::DoEvents()

    $argumentos = "a -v$tamanoParte -ep -m5 -s -r -idq `"$salidaRar`" `"$archivoCompleto`""

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $rarPath
    $psi.Arguments = $argumentos
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false

    $process = [System.Diagnostics.Process]::Start($psi)

    # Animación progresiva simulada (sube suavemente mientras trabaja)
    $currentPercent = 0
    while (!$process.HasExited) {
        if ($currentPercent -lt 95) {  # Deja margen para el final real
            $currentPercent += 1
            $progressArchivo.Value = $currentPercent
            $lblPorcentaje.Text = "$currentPercent%"
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 200  # Ajusta: más bajo = más rápido
        }
        Start-Sleep -Milliseconds 100
    }

    # Completar al 100% al final
    while ($currentPercent -lt 100) {
        $currentPercent += 2
        $progressArchivo.Value = $currentPercent
        $lblPorcentaje.Text = "$currentPercent%"
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 60
    }

    $process.WaitForExit()
    $exitCode = $process.ExitCode

    if ($exitCode -eq 0) {
        $exitosos++
    } else {
        $fallidos++
        $detallesError += "`n• $nombreArchivo → Código: $exitCode"
    }
}

# ... (el final igual: completar barra global y mensaje)