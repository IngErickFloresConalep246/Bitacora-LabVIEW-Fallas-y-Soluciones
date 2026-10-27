# Solución: error 2705 al instalar LabVIEW (`ni-metauninstaller` / `MetaUninstaller.msi`)

> **English TL;DR** *(optional workaround based on my own machine — not an official NI fix; confirm the cause in your logs first)*: If the NI/LabVIEW installer fails with *"An error occurred while installing a package: ni-metauninstaller … The error code is 2705"*, and cleaning old NI software doesn't help, the cause may be that NI's `NIPaths` custom action can't resolve the Windows **Public Documents** folder (`SHGetFolderPath(CSIDL_COMMON_DOCUMENTS)` fails with `0x80070003`). This leaves the MSI `Directory` table with an orphan entry → error 2705. **Workaround:** pre-set `NIPUBDOCSDIR` and `NIPUBAPPDATADIR` under `HKLM\SOFTWARE\[WOW6432Node\]National Instruments\Common\Installer`, then run the installer again. See [Paso 4](#4-la-solución) or run [`fix-ni-2705.ps1`](fix-ni-2705.ps1).

Guía paso a paso basada en un caso real, resuelto analizando los logs de Windows Installer y el propio paquete de NI.

---

## Índice

1. [Síntoma](#1-síntoma)
2. [Lo que NO funcionó](#2-lo-que-no-funcionó)
3. [Diagnóstico: encontrar la causa real](#3-diagnóstico-encontrar-la-causa-real)
4. [La solución](#4-la-solución)
5. [Segundo problema: paquete dañado en el ISO](#5-segundo-problema-paquete-dañado-en-el-iso)
6. [Limpieza final](#6-limpieza-final)
7. [Extra: LabVIEW + Arduino](#7-extra-labview--arduino)

**Probado con:** LabVIEW 2026 Q3 (64-bit), `ni-metauninstaller 26.5.0.49246`, Windows 64-bit.

> ⚠️ **Esta es una solución opcional, basada en los problemas que encontré en mi equipo.** No es un procedimiento oficial de NI ni una solución definitiva: tu error 2705 podría tener otra causa. Antes de aplicar el [paso 4](#4-la-solución), revisa tus logs como se explica en el [paso 3](#3-diagnóstico-encontrar-la-causa-real) para confirmar que es el mismo caso. Todos los cambios de registro son reversibles.

---

## 1. Síntoma

Al instalar LabVIEW (con el instalador en línea **o** con el ISO offline), aparece:

```
We encountered a problem:
An error occurred while installing a package: ni-metauninstaller (26.5.0.49246-0+f94)

Additional error information:
• An error occurred while installing the MSI at 'MU\MetaUninstaller.msi'.
  The installer has encountered an unexpected error installing this package.
  This may indicate a problem with this package. The error code is 2705.
```

El botón **Try Again** no sirve: el error se repite siempre.

---

## 2. Lo que NO funcionó

Es la recomendación típica en foros. Vale la pena hacerla primero, pero en este caso **no era la causa**:

- Desinstalar todo lo de NI desde *Configuración → Aplicaciones*.
- Usar el *Program Install and Uninstall troubleshooter* de Microsoft.
- Quitar con `msiexec /x` los componentes de NI que quedaban registrados.
- Borrar `C:\Program Files\National Instruments`, `C:\Program Files (x86)\National Instruments` y `C:\ProgramData\National Instruments`.
- Borrar las claves `HKLM\SOFTWARE\National Instruments` (32 y 64 bits).
- Reparar Windows Installer (`sfc /scannow`, `msiexec /unregister` + `/regserver`).
- Resolver reinicios pendientes de Windows Update.
- Usar el ISO offline en lugar del instalador en línea.

Con el sistema **completamente limpio**, el error seguía apareciendo. Eso indicaba que el problema estaba en Windows, no en restos de NI.

<details>
<summary>Comando para ver si quedan componentes de NI registrados</summary>

```powershell
Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
  Where-Object { $_.Publisher -match "National Instruments|^NI$" -or $_.DisplayName -match "^NI " } |
  Select-Object DisplayName, PSChildName | Format-Table -AutoSize
```

Y para desinstalarlos todos (los que tienen código MSI `{...}`):

```powershell
$apps = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
  Where-Object { $_.Publisher -match "National Instruments|^NI$" -or $_.DisplayName -match "^NI " }
foreach ($a in $apps) {
  if ($a.PSChildName -match '^\{') {
    Write-Host "Quitando $($a.DisplayName)"
    Start-Process msiexec.exe -ArgumentList "/x $($a.PSChildName) /qn /norestart" -Wait
  }
}
```
</details>

---

## 3. Diagnóstico: encontrar la causa real

### 3.1 Activar el log detallado de Windows Installer

En **PowerShell como administrador**:

```powershell
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v Logging /t REG_SZ /d voicewarmupx /f
```

Ejecuta el instalador de LabVIEW hasta que falle. Se generan archivos `MSI*.LOG` en `%TEMP%`, uno por paquete.

### 3.2 Buscar el log que falló

```powershell
$log = Get-ChildItem $env:TEMP -Filter "MSI*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Select-String -Path $log.FullName -Pattern "2705|Return value 3" -Context 15,3
```

Si el más reciente no es el de `MetaUninstaller.msi`, busca entre los demás con `Select-String -Path "$env:TEMP\MSI*.LOG" -Pattern "2705"`.

Aparece esto:

```
Action start: CostInitialize.
Note: 1: 2705 2: Directory
DEBUG: Error 2705:  Invalid table: Directory; Could not be linked as tree.
Product: NI Uninstaller 26.5.0 -- ... The error code is 2705. The arguments are: Directory, ,
```

**Qué significa:** Windows Installer no puede armar el "árbol" de carpetas del paquete, porque alguna carpeta apunta a una carpeta padre que no existe en la tabla `Directory`.

### 3.3 Por qué falta esa carpeta

Al abrir `MetaUninstaller.msi` (con [Orca](https://learn.microsoft.com/windows/win32/msi/orca-exe) o `msitools`), se ve que su tabla `Directory` **no viene completa**. Varias carpetas (`NISHAREDDIR`, `NIMIFDIR`, `NILEGALDIR`, `NIPUBDOCSDIR`…) las agrega en tiempo de instalación una acción personalizada de NI llamada **NIPaths**.

Para cada carpeta, NIPaths:
1. Busca la ruta en el registro (`HKLM\SOFTWARE\National Instruments\Common\Installer`).
2. Si no la encuentra, la construye a partir de una carpeta especial de Windows.

`NIPUBDOCSDIR` se construye a partir de **Documentos públicos** (`CSIDL_COMMON_DOCUMENTS`, normalmente `C:\Users\Public\Documents`). En el log se ve:

```
NIPaths II: NIPUBDOCSDIR: Read failed. Property not set.
NIPaths II: NIPUBDOCSDIR: Created Directory Table entry [NICSIDLCOMMONDOCUMENTS]\NI|National Instruments
...
NIPaths II: ERROR! SHGetFolderPath(CSIDL_COMMON_DOCUMENTS) failed with error 2147942403
```

`2147942403` = `0x80070003` = **"No se encuentra la ruta"**.

Es decir, NIPaths crea la carpeta `NIPUBDOCSDIR` colgando de `NICSIDLCOMMONDOCUMENTS`. Pero como Windows no le devuelve "Documentos públicos", esa carpeta padre nunca se crea. Queda una carpeta huérfana y aparece el **error 2705**.

**Para confirmarlo en tu log:**
```powershell
Select-String -Path "$env:TEMP\MSI*.LOG" -Pattern "CSIDL_COMMON_DOCUMENTS"
```

> 💡 **Dato curioso:** en este caso la carpeta existía, el registro de *Shell Folders* era correcto, y `[Environment]::GetFolderPath("CommonDocuments")` respondía bien desde PowerShell. La falla solo ocurría **dentro del contexto de la instalación**. Los demás paquetes de NI se instalaban sin problema porque no usan esa carpeta. El MetaUninstaller sí la usa, y por eso fallaba siempre ese.

<details>
<summary>Comandos para revisar la carpeta "Documentos públicos"</summary>

```powershell
$env:PUBLIC
Test-Path "C:\Users\Public\Documents"
[Environment]::GetFolderPath("CommonDocuments")
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" /v "Common Documents"
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" | Select-Object Public, ProfilesDirectory, ProgramData
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions\{ED4824AF-DCE4-45A8-81E2-FC7965083634}" | Select-Object Name, ParentFolder, RelativePath
```

Valores normales: `C:\Users\Public`, `True`, `C:\Users\Public\Documents`, `%PUBLIC%\Documents`.

Si algo de esto está mal, conviene repararlo también:
```powershell
New-Item -ItemType Directory -Path "C:\Users\Public\Documents" -Force | Out-Null
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" /v "Common Documents" /t REG_EXPAND_SZ /d "%PUBLIC%\Documents" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" /v "Common Documents" /t REG_SZ /d "C:\Users\Public\Documents" /f
```
</details>

---

## 4. La solución

Como NIPaths **primero busca la ruta en el registro**, basta con dejársela escrita. Así nunca tiene que pedirle la carpeta a Windows, y `NIPUBDOCSDIR` se crea con una ruta fija en lugar de colgar de la carpeta que falla.

En **PowerShell como administrador**:

```powershell
New-Item -ItemType Directory -Path "C:\Users\Public\Documents\National Instruments" -Force | Out-Null
New-Item -ItemType Directory -Path "C:\ProgramData\National Instruments" -Force | Out-Null

foreach ($k in "HKLM:\SOFTWARE\National Instruments\Common\Installer",
               "HKLM:\SOFTWARE\WOW6432Node\National Instruments\Common\Installer") {
  if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
  Set-ItemProperty -Path $k -Name NIPUBDOCSDIR    -Value 'C:\Users\Public\Documents\National Instruments\'
  Set-ItemProperty -Path $k -Name NIPUBAPPDATADIR -Value 'C:\ProgramData\National Instruments\'
  Get-ItemProperty -Path $k | Select-Object NIPUBDOCSDIR, NIPUBAPPDATADIR | Format-List
}
```

> ⚠️ Usa `Set-ItemProperty`, como arriba, y **no** `reg add ... /d "...\"`. Con `reg add`, la diagonal `\` antes de la comilla final se "come" la comilla, y el valor queda con basura al final.

Después, **sin reiniciar**, ejecuta el instalador de LabVIEW como administrador. ✅

También puedes usar el script [`fix-ni-2705.ps1`](fix-ni-2705.ps1) de este repositorio:

```powershell
# Solo diagnostico (no cambia nada)
powershell -ExecutionPolicy Bypass -File .\fix-ni-2705.ps1

# Diagnostico + aplicar la solucion
powershell -ExecutionPolicy Bypass -File .\fix-ni-2705.ps1 -Apply
```

**No borres estos valores después.** Si en el futuro actualizas o reinstalas software de NI, son los que evitan que vuelva el error.

**Para revertir** (no se recomienda mientras uses software de NI):
```powershell
foreach ($k in "HKLM:\SOFTWARE\National Instruments\Common\Installer","HKLM:\SOFTWARE\WOW6432Node\National Instruments\Common\Installer") {
  Remove-ItemProperty -Path $k -Name NIPUBDOCSDIR, NIPUBAPPDATADIR -ErrorAction SilentlyContinue
}
```

---

## 5. Segundo problema: paquete dañado en el ISO

Una vez resuelto el 2705, la instalación desde el ISO falló con:

```
Could not retrieve the package 'ni-labview-2026-scripting-codegen'.
Package checksum validation failed ... The package may be corrupted.
```

Significa que el ISO se descargó o copió dañado. La solución fue usar el **instalador en línea** de LabVIEW, que ya funcionaba gracias a la solución anterior, y **seleccionar solo los componentes necesarios**. Así descarga mucho menos que el ISO completo (~34 GB).

Para trabajar con **Arduino/ESP32** basta con:
- ✅ LabVIEW (64-bit)
- ✅ JKI VI Package Manager
- ✅ NI-VISA
- ❌ NI-DAQmx: solo hace falta si tienes una tarjeta DAQ de NI (como myDAQ). Se puede instalar después.

---

## 6. Limpieza final

Desactiva el log detallado de Windows Installer (si no, sigue generando logs grandes):

```powershell
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v Logging /f
Remove-Item "$env:TEMP\MSI*.LOG" -Force -ErrorAction SilentlyContinue
```

Y vuelve a activar el antivirus y el firewall si los desactivaste. El firewall no tiene relación con este error.

---

## 7. Extra: LabVIEW + Arduino

1. Instala **LabVIEW Hobbyist Toolkit** (la versión actual de LINX), desde *NI Package Manager → Browse Products → "Hobbyist"*, o desde [ni.com](https://www.ni.com/en/support/downloads/tools-network/download.labview-hobbyist-toolkit.html). Usa la misma versión y los mismos bits que tu LabVIEW. El paquete viejo "Digilent LINX" de VIPM está descontinuado.
2. Instala el driver USB del Arduino: el del Arduino IDE para placas originales, o el driver **CH340** para clones.
3. En LabVIEW: **Tools → Hobbyist → LINX Firmware Wizard** → Arduino → tu modelo → *Serial/USB* → *Pre-Built Firmware* → puerto COM.
4. Prueba: **Help → Find Examples → "Blink"**. Elige el puerto COM y dale Run. Para detenerlo, usa el botón **Stop**, no el de abortar, para que se cierre el puerto.

Las funciones están en la paleta **Hobbyist**: `Open.vi`, `Close.vi`, `Peripherals → Analog/Digital/PWM`.

---

## Referencias

- [Labview Install error (2705) – NI Community](https://forums.ni.com/t5/LabVIEW/Labview-Install-error/m-p/4325397)
- [Error Windows 10 (ni-metauninstaller 2705) – NI Community](https://forums.ni.com/t5/LabVIEW/Error-Windows-10/m-p/4307801)
- [Windows Installer error codes – Microsoft](https://learn.microsoft.com/windows/win32/msi/windows-installer-error-messages)
- [LabVIEW Hobbyist Toolkit – NI](https://www.ni.com/en/support/downloads/tools-network/download.labview-hobbyist-toolkit.html)
