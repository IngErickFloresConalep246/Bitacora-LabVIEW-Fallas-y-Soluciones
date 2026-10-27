<#
.SYNOPSIS
  Diagnostica y corrige el error 2705 de ni-metauninstaller (MetaUninstaller.msi)
  al instalar LabVIEW / software de NI.

.DESCRIPTION
  La accion personalizada NIPaths de NI necesita la carpeta "Documentos publicos"
  (CSIDL_COMMON_DOCUMENTS). Si Windows no se la entrega durante la instalacion,
  la tabla Directory del MSI queda incompleta y aparece el error 2705.

  Este script pre-escribe en el registro las rutas que NIPaths busca primero
  (NIPUBDOCSDIR y NIPUBAPPDATADIR), para que no dependa de esa consulta.

  Sin parametros: solo diagnostica, no cambia nada.
  Con -Apply:     aplica la solucion (requiere PowerShell como administrador).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\fix-ni-2705.ps1
  powershell -ExecutionPolicy Bypass -File .\fix-ni-2705.ps1 -Apply
#>
param([switch]$Apply)

$ErrorActionPreference = 'Stop'

$PubDocs    = 'C:\Users\Public\Documents\National Instruments\'
$PubAppData = 'C:\ProgramData\National Instruments\'
$Keys = @(
  'HKLM:\SOFTWARE\National Instruments\Common\Installer',
  'HKLM:\SOFTWARE\WOW6432Node\National Instruments\Common\Installer'
)

function Write-Check($label, $ok, $detail) {
  $mark  = if ($ok) { '[OK]  ' } else { '[!!]  ' }
  $color = if ($ok) { 'Green' } else { 'Yellow' }
  Write-Host ($mark + $label + $(if ($detail) { " -> $detail" })) -ForegroundColor $color
}

Write-Host "`n=== Diagnostico: carpeta 'Documentos publicos' ===" -ForegroundColor Cyan
$common = [Environment]::GetFolderPath('CommonDocuments')
Write-Check 'Variable PUBLIC'                 ([bool]$env:PUBLIC) $env:PUBLIC
Write-Check 'C:\Users\Public\Documents existe' (Test-Path 'C:\Users\Public\Documents')
Write-Check 'GetFolderPath(CommonDocuments)'  ([bool]$common) $common

Write-Host "`n=== Diagnostico: logs de Windows Installer en %TEMP% ===" -ForegroundColor Cyan
$hits = Get-ChildItem $env:TEMP -Filter 'MSI*.LOG' -ErrorAction SilentlyContinue |
        Select-String -Pattern 'CSIDL_COMMON_DOCUMENTS\) failed' -List -ErrorAction SilentlyContinue
if ($hits) {
  Write-Check 'Se encontro la falla de NIPaths (CSIDL_COMMON_DOCUMENTS)' $false
  $hits | ForEach-Object { Write-Host "      $($_.Path)" }
  Write-Host '      Esto confirma la causa del error 2705.' -ForegroundColor Yellow
} else {
  Write-Host '      No se encontraron logs con la falla (puede que el log detallado no este activo).'
}

Write-Host "`n=== Diagnostico: valores de registro de NI ===" -ForegroundColor Cyan
foreach ($k in $Keys) {
  $p = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
  Write-Check "$k\NIPUBDOCSDIR"    ($p.NIPUBDOCSDIR    -eq $PubDocs)    $p.NIPUBDOCSDIR
  Write-Check "$k\NIPUBAPPDATADIR" ($p.NIPUBAPPDATADIR -eq $PubAppData) $p.NIPUBAPPDATADIR
}

if (-not $Apply) {
  Write-Host "`nSolo diagnostico. Para aplicar la solucion ejecuta de nuevo con -Apply (como administrador).`n" -ForegroundColor Cyan
  return
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host "`nERROR: abre PowerShell como administrador para usar -Apply.`n" -ForegroundColor Red
  exit 1
}

Write-Host "`n=== Aplicando solucion ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $PubDocs    -Force | Out-Null
New-Item -ItemType Directory -Path $PubAppData -Force | Out-Null
foreach ($k in $Keys) {
  if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
  Set-ItemProperty -Path $k -Name NIPUBDOCSDIR    -Value $PubDocs
  Set-ItemProperty -Path $k -Name NIPUBAPPDATADIR -Value $PubAppData
  $p = Get-ItemProperty -Path $k
  Write-Check "$k\NIPUBDOCSDIR"    ($p.NIPUBDOCSDIR    -eq $PubDocs)    $p.NIPUBDOCSDIR
  Write-Check "$k\NIPUBAPPDATADIR" ($p.NIPUBAPPDATADIR -eq $PubAppData) $p.NIPUBAPPDATADIR
}

Write-Host "`nListo. Ahora ejecuta el instalador de LabVIEW como administrador (sin reiniciar).`n" -ForegroundColor Green
