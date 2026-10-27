# Error 2705 en la instalación de NI LabVIEW (`ni-metauninstaller`)

**Diagnóstico y resolución documentados de un caso real**

[← Volver al índice de errores de LabVIEW](../README.md)

> 📘 **Acerca de este repositorio.** Este es un repositorio público con fines educativos. En él documento fallas de software que se han presentado en mi equipo o en los equipos de mis alumnos, junto con el procedimiento que seguimos para resolverlas, con la intención de que sirva como material de consulta para la comunidad estudiantil. Si a alguien fuera de la comunidad educativa le resulta útil, es bienvenido a usarlo. No tiene fines de lucro.

| | |
|---|---|
| **Software afectado** | NI LabVIEW 2026 Q3 (64-bit) · paquete `ni-metauninstaller 26.5.0.49246` |
| **Sistema** | Windows 64-bit |
| **Error presentado** | La instalación se detiene con el código de error **2705** |
| **Causa identificada** | La acción personalizada *NIPaths* no logra resolver la carpeta *Documentos públicos* de Windows |
| **Tipo de solución** | Solución alterna: dos valores en el registro de Windows |

> ⚠️ **Aviso.** Esta es una solución opcional, basada en los problemas que encontré en mi equipo. No es un procedimiento oficial de NI ni una solución definitiva: tu error 2705 podría tener otra causa. Antes de aplicar la solución de la [sección 6](#6-solución-aplicada), sigue el diagnóstico de la [sección 4](#4-procedimiento-de-diagnóstico) para confirmar que se trata del mismo caso. Todos los cambios de registro son reversibles.

---

## Contenido

1. [Descripción del problema](#1-descripción-del-problema)
2. [Conceptos previos](#2-conceptos-previos)
3. [Primeros intentos: descartar restos de instalaciones anteriores](#3-primeros-intentos-descartar-restos-de-instalaciones-anteriores)
4. [Procedimiento de diagnóstico](#4-procedimiento-de-diagnóstico)
5. [Análisis de causa raíz](#5-análisis-de-causa-raíz)
6. [Solución aplicada](#6-solución-aplicada)
7. [Problema adicional: paquete dañado en el ISO](#7-problema-adicional-paquete-dañado-en-el-iso)
8. [Limpieza y verificación final](#8-limpieza-y-verificación-final)
9. [Recomendaciones para casos similares](#9-recomendaciones-para-casos-similares)
10. [Anexo: script de diagnóstico y corrección](#anexo-script-de-diagnóstico-y-corrección)
11. [Referencias](#referencias)
12. [Summary in English](#summary-in-english)
13. [Aviso legal](#aviso-legal)

---

## 1. Descripción del problema

Al instalar LabVIEW, el instalador de NI comienza descargando e instalando una serie de componentes base. Uno de los primeros es `ni-metauninstaller`, el desinstalador común que NI usa para administrar todos sus productos. En este punto la instalación se detenía con el siguiente mensaje:

```
We encountered a problem:
An error occurred while installing a package: ni-metauninstaller (26.5.0.49246-0+f94)

Additional error information:
• An error occurred while installing the MSI at 'MU\MetaUninstaller.msi'.
  The installer has encountered an unexpected error installing this package.
  This may indicate a problem with this package. The error code is 2705.
```

El botón *Try Again* reproducía el error de forma idéntica. La falla ocurría tanto con el instalador en línea como con la imagen ISO offline, lo que ya sugería que el problema no estaba en la descarga, sino en el equipo.

---

## 2. Conceptos previos

Para entender el diagnóstico conviene conocer algunas piezas de cómo se instala software en Windows.

**Windows Installer y los paquetes MSI.** Muchos programas de Windows se instalan mediante archivos `.msi`. Un MSI no es un ejecutable: es una pequeña **base de datos** con tablas que describen qué archivos copiar, a qué carpetas, qué claves de registro crear, etc. El servicio **Windows Installer** (`msiexec.exe`) lee esas tablas y ejecuta la instalación paso a paso. Cada paso se llama **acción** (por ejemplo `CostInitialize`, `InstallFiles`).

**La tabla `Directory`.** Es la tabla del MSI que define las carpetas de destino. Cada fila tiene una carpeta y su **carpeta padre**, de modo que en conjunto forman un **árbol** que parte de la raíz (`TARGETDIR`). Por ejemplo:

```
TARGETDIR
 └─ ProgramFilesFolder
     └─ National Instruments
         └─ Shared
             └─ NIUninstaller
```

Si alguna carpeta apunta a un padre que no existe en la tabla, el árbol no se puede construir.

**Acciones personalizadas (*custom actions*).** Además de las acciones estándar, un fabricante puede incluir su propio código (normalmente una DLL) dentro del MSI. NI utiliza una llamada **NIPaths**, que calcula las rutas de instalación de sus productos y **agrega filas a la tabla `Directory` en tiempo de instalación**.

**Carpetas especiales de Windows.** Windows identifica ciertas carpetas del sistema (Archivos de programa, `ProgramData`, *Documentos públicos*…) mediante identificadores, en lugar de rutas fijas. Los programas las consultan con funciones como `SHGetFolderPath`. *Documentos públicos* se identifica como `CSIDL_COMMON_DOCUMENTS` y normalmente corresponde a `C:\Users\Public\Documents`.

**Códigos de error.** El **2705** es un error interno de Windows Installer que significa: *"Tabla inválida: Directory; no se pudo enlazar como árbol"*. Es decir, el árbol de carpetas descrito arriba quedó incompleto.

---

## 3. Primeros intentos: descartar restos de instalaciones anteriores

La explicación más frecuente de este error en los foros de NI es que una instalación anterior dejó restos que confunden al instalador nuevo. Por eso el primer paso fue dejar el equipo completamente limpio de software de NI. Aunque en este caso **no resultó ser la causa**, es un procedimiento recomendable, porque descarta la explicación más común antes de profundizar.

### 3.1 Identificar componentes de NI registrados

Muchos componentes de NI no aparecen en *Configuración → Aplicaciones*, pero sí están registrados en Windows. Para listarlos, en **PowerShell como administrador**:

```powershell
Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
  Where-Object { $_.Publisher -match "National Instruments|^NI$" -or $_.DisplayName -match "^NI " } |
  Select-Object DisplayName, PSChildName | Format-Table -AutoSize
```

La columna `PSChildName` muestra el **código de producto** de cada componente (un identificador entre llaves `{...}`).

### 3.2 Desinstalarlos

El siguiente comando recorre esa lista y desinstala en modo silencioso cada componente que tenga código de producto:

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

Si **NI Package Manager** sigue apareciendo, se desinstala desde *Configuración → Aplicaciones*, porque no usa el mismo tipo de instalador.

### 3.3 Eliminar carpetas y claves de registro residuales

```powershell
Remove-Item "C:\Program Files\National Instruments","C:\Program Files (x86)\National Instruments","C:\ProgramData\National Instruments" -Recurse -Force -ErrorAction SilentlyContinue
reg delete "HKLM\SOFTWARE\National Instruments" /f
reg delete "HKLM\SOFTWARE\WOW6432Node\National Instruments" /f
```

> Antes de borrar las claves de registro puedes respaldarlas con `reg export "HKLM\SOFTWARE\National Instruments" "%USERPROFILE%\Desktop\NI_respaldo.reg"`.

### 3.4 Otras verificaciones realizadas

- Ejecutar el *Program Install and Uninstall troubleshooter* de Microsoft para quitar registros dañados.
- Reparar Windows Installer: `sfc /scannow`, `msiexec /unregister` y `msiexec /regserver`.
- Confirmar que no hubiera reinicios pendientes de Windows Update.
- Verificar que las rutas del sistema (`ProgramFilesDir`, `CommonFilesDir`) fueran correctas.

### 3.5 Resultado

Con el equipo totalmente limpio, ya sin componentes registrados, carpetas ni claves de NI, el error **seguía apareciendo**. Esto descartaba la hipótesis de los restos de instalación y obligaba a buscar la causa en otra parte. Para eso es necesario leer qué hace exactamente el instalador en el momento de la falla.

---

## 4. Procedimiento de diagnóstico

### 4.1 Activar el registro detallado de Windows Installer

Por defecto, Windows Installer no deja un registro completo de lo que hace. Se puede activar mediante una política del sistema. En **PowerShell como administrador**:

```powershell
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v Logging /t REG_SZ /d voicewarmupx /f
```

Cada letra de `voicewarmupx` activa un tipo de información (*verbose*, errores, propiedades, etc.). A partir de este momento, cada paquete MSI que se instale genera un archivo `MSIxxxxx.LOG` en la carpeta temporal del usuario (`%TEMP%`).

### 4.2 Reproducir el error

Se ejecuta de nuevo el instalador de LabVIEW hasta que aparezca el error 2705. Como el instalador de NI instala varios paquetes MSI seguidos, se generan **varios logs**: uno por paquete.

### 4.3 Localizar el log del paquete que falló

Para encontrar cuál de todos contiene el error:

```powershell
Select-String -Path "$env:TEMP\MSI*.LOG" -Pattern "2705" -List | Select-Object Path
```

Y para ver el contexto de la falla dentro de ese archivo:

```powershell
Select-String -Path "<ruta del log>" -Pattern "2705|Return value 3" -Context 15,3
```

> En los logs de Windows Installer, `Return value 1` significa que una acción terminó bien y `Return value 3` que **falló**. Buscar `Return value 3` es la forma más rápida de encontrar dónde se rompió una instalación.

### 4.4 Lo que muestra el log

```
Action start: CostInitialize.
PROPERTY CHANGE: Adding ROOTDRIVE property.
Note: 1: 2705 2: Directory
DEBUG: Error 2705:  Invalid table: Directory; Could not be linked as tree.
Product: NI Uninstaller 26.5.0 -- ... The error code is 2705. The arguments are: Directory, ,
Action ended: CostInitialize. Return value 3.
```

La acción que falla es `CostInitialize`, que es justamente la que construye el árbol de carpetas para calcular el espacio necesario. En ese momento todavía no se ha copiado ningún archivo: **la falla ocurre al interpretar la tabla `Directory`**, no al escribir en disco. Por eso tampoco tenían relación el espacio libre, el antivirus ni el firewall.

Un dato adicional: en los logs del mismo intento, **todos los demás paquetes de NI se instalaban correctamente** y solo fallaba `MetaUninstaller.msi`. La pregunta era entonces qué tiene ese paquete de diferente.

---

## 5. Análisis de causa raíz

### 5.1 Inspección del paquete

El archivo del paquete (`.nipkg`) se encuentra dentro de la carpeta `pool` del ISO. Es un archivo comprimido que contiene `MetaUninstaller.msi`. Al abrir el MSI con un editor de tablas ([Orca](https://learn.microsoft.com/windows/win32/msi/orca-exe) en Windows o `msitools` en Linux), la tabla `Directory` muestra filas como estas:

| Directory | Directory_Parent |
|---|---|
| `TARGETDIR` | — |
| `ProgramFilesFolder` | `TARGETDIR` |
| `CommonAppDataFolder` | `TARGETDIR` |
| `AutoPlaySuppress…` | **`NIMIFDIR`** |
| `NIProductNoticesDir` | **`NILEGALDIR`** |
| `NIPackageManagerDir…` | **`NISHAREDDIR`** |

Las carpetas padre marcadas en negritas **no existen en la tabla**. Esto no es un defecto del paquete: es intencional. Esas filas las agrega **NIPaths** durante la instalación, antes de que se ejecute `CostInitialize`.

### 5.2 Cómo calcula NIPaths cada carpeta

NIPaths tiene sus propias tablas internas. Para cada carpeta que necesita sigue esta lógica:

1. **Busca la ruta en el registro**, en `HKLM\SOFTWARE\National Instruments\Common\Installer`.
2. Si no la encuentra, **la construye a partir de una carpeta padre**, que puede ser otra carpeta de NI o una carpeta especial de Windows.

Una de las carpetas que requiere `MetaUninstaller.msi` es `NIPUBDOCSDIR`, cuya carpeta padre es *Documentos públicos* (`NICSIDLCOMMONDOCUMENTS` → `CSIDL_COMMON_DOCUMENTS`).

### 5.3 La evidencia en el log

NIPaths escribe su propio diagnóstico dentro del log de Windows Installer, con el prefijo `NIPaths II:`:

```
NIPaths II: Processing NIPUBDOCSDIR (Dir type): Directory for global user-editable config files
NIPaths II: Trying NIPathsRegLocator NIPUBDOCSDIRRegLoc option 1
NIPaths II: Locator failed with option 1
NIPaths II: NIPUBDOCSDIR: Read failed. Property not set.
NIPaths II: NIPUBDOCSDIR: Created Directory Table entry [NICSIDLCOMMONDOCUMENTS]\NI|National Instruments
...
NIPaths II: ERROR! SHGetFolderPath(CSIDL_COMMON_DOCUMENTS) failed with error 2147942403
```

Línea por línea:

1. NIPaths busca `NIPUBDOCSDIR` en el registro y **no la encuentra**. Es normal en un equipo limpio.
2. Entonces crea la fila de `NIPUBDOCSDIR` colgando de `NICSIDLCOMMONDOCUMENTS` (*Documentos públicos*).
3. Al intentar resolver *Documentos públicos*, la función `SHGetFolderPath` de Windows **falla**.

El código `2147942403` en hexadecimal es `0x80070003`, que corresponde al error de Windows `ERROR_PATH_NOT_FOUND`: **"No se encuentra la ruta especificada"**.

### 5.4 Conclusión

La cadena completa de la falla es:

```
SHGetFolderPath(Documentos públicos) falla
        ↓
NIPaths no crea la fila NICSIDLCOMMONDOCUMENTS
        ↓
NIPUBDOCSDIR queda apuntando a un padre inexistente
        ↓
CostInitialize no puede construir el árbol de la tabla Directory
        ↓
Error 2705
```

Esto explica también por qué solo fallaba `MetaUninstaller.msi`: los demás paquetes no requieren `NIPUBDOCSDIR`, así que la falla de `SHGetFolderPath` no les afecta.

### 5.5 Un detalle relevante

Al revisar la carpeta *Documentos públicos* desde PowerShell, todo estaba correcto:

```powershell
$env:PUBLIC                                    # C:\Users\Public
Test-Path "C:\Users\Public\Documents"          # True
[Environment]::GetFolderPath("CommonDocuments") # C:\Users\Public\Documents
```

Las claves `User Shell Folders`, `ProfileList` y `FolderDescriptions` también tenían sus valores de fábrica. Es decir, **desde la sesión del usuario Windows sí encontraba la carpeta; la falla solo ocurría dentro del contexto de la instalación.** No fue posible determinar el motivo exacto dentro de Windows, por lo que la solución que sigue **evita** la consulta en lugar de corregir su origen. Por eso se considera una solución alterna y no una corrección definitiva.

<details>
<summary>Comandos para verificar la configuración de "Documentos públicos"</summary>

```powershell
$env:PUBLIC
Test-Path "C:\Users\Public\Documents"
[Environment]::GetFolderPath("CommonDocuments")
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" /v "Common Documents"
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" | Select-Object Public, ProfilesDirectory, ProgramData
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions\{ED4824AF-DCE4-45A8-81E2-FC7965083634}" | Select-Object Name, ParentFolder, RelativePath
```

Valores esperados: `C:\Users\Public`, `True`, `C:\Users\Public\Documents` y `%PUBLIC%\Documents`.

Si en tu equipo alguno es incorrecto, conviene restaurarlo antes de aplicar la sección 6:

```powershell
New-Item -ItemType Directory -Path "C:\Users\Public\Documents" -Force | Out-Null
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" /v "Common Documents" /t REG_EXPAND_SZ /d "%PUBLIC%\Documents" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" /v "Common Documents" /t REG_SZ /d "C:\Users\Public\Documents" /f
```
</details>

---

## 6. Solución aplicada

### 6.1 Principio

Según la sección 5.2, NIPaths **primero busca la ruta en el registro** y solo recurre a *Documentos públicos* si no la encuentra. Por lo tanto, si la ruta ya está escrita en el registro, NIPaths la usa directamente, crea `NIPUBDOCSDIR` sin depender de la carpeta problemática y el árbol de carpetas queda completo.

Se escriben dos valores, ambos con las rutas estándar que NI usaría normalmente:

| Valor | Ruta |
|---|---|
| `NIPUBDOCSDIR` | `C:\Users\Public\Documents\National Instruments\` |
| `NIPUBAPPDATADIR` | `C:\ProgramData\National Instruments\` |

Se escriben en las dos vistas del registro, la de 64 bits y la de 32 bits (`WOW6432Node`), porque los componentes de NI pueden leer cualquiera de las dos.

### 6.2 Procedimiento

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

La salida debe mostrar dos veces los valores de la tabla anterior, sin caracteres extra al final.

> **Nota técnica.** Se usa `Set-ItemProperty` en lugar de `reg add` a propósito. Con `reg add ... /d "C:\ruta\"`, la diagonal inversa antes de la comilla de cierre se interpreta como un carácter de escape: la comilla deja de cerrar el texto y el resto de la línea (incluido `/f`) termina dentro del valor.

Después de aplicar estos valores, **sin reiniciar**, se ejecuta de nuevo el instalador de LabVIEW como administrador. En este caso, el paquete `ni-metauninstaller` se instaló correctamente y el instalador continuó con el resto de los componentes.

### 6.3 Mantenimiento y reversión

Estos valores **deben conservarse** mientras se use software de NI: cualquier actualización o reinstalación futura volvería a pasar por NIPaths.

Si en algún momento se desea revertir el cambio:

```powershell
foreach ($k in "HKLM:\SOFTWARE\National Instruments\Common\Installer","HKLM:\SOFTWARE\WOW6432Node\National Instruments\Common\Installer") {
  Remove-ItemProperty -Path $k -Name NIPUBDOCSDIR, NIPUBAPPDATADIR -ErrorAction SilentlyContinue
}
```

---

## 7. Problema adicional: paquete dañado en el ISO

Una vez superado el error 2705, la instalación desde la imagen ISO se detuvo con un error distinto:

```
Could not retrieve the package 'ni-labview-2026-scripting-codegen'.
Package checksum validation failed ... Expected SHA256 checksum '68d4…' is different
from actual checksum '8d0e…'. The package may be corrupted.
```

**Interpretación.** Cada paquete de NI incluye una **suma de verificación SHA-256**: una huella digital calculada a partir de su contenido. Si un solo byte del archivo cambia, la huella cambia por completo. El instalador recalcula la huella del archivo y la compara con la esperada; al no coincidir, concluye que el archivo está dañado. Esto suele ocurrir cuando la descarga del ISO se interrumpe o cuando hay errores de lectura o copia en un disco externo.

**Solución.** Con el error 2705 ya resuelto, se usó el **instalador en línea** de LabVIEW, seleccionando solo los componentes necesarios. A diferencia del ISO (aproximadamente 34 GB), el instalador en línea descarga únicamente lo seleccionado, lo que además resolvía la falta de espacio en el disco.

Componentes seleccionados en este caso:

| Componente | ¿Instalar? | Motivo |
|---|---|---|
| LabVIEW (64-bit) | ✅ | Entorno de programación |
| JKI VI Package Manager | ✅ | Administrador de complementos de LabVIEW |
| NI-VISA | ✅ | Comunicación por puerto serial/USB |
| NI-DAQmx | Opcional | Solo para tarjetas de adquisición de NI (por ejemplo, myDAQ). Se puede instalar después |
| Demás controladores y módulos | ❌ | No se necesitaban y ocupan bastante espacio |

---

## 8. Limpieza y verificación final

El registro detallado de Windows Installer debe desactivarse al terminar, porque genera archivos grandes en cada instalación futura:

```powershell
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v Logging /f
Remove-Item "$env:TEMP\MSI*.LOG" -Force -ErrorAction SilentlyContinue
```

Si durante las pruebas se desactivaron el antivirus o el firewall, deben volver a activarse. Ninguno de los dos tenía relación con este error.

**Verificación final:** LabVIEW abre correctamente, y en *NI Package Manager → Installed* aparecen los componentes seleccionados.

---

## 9. Recomendaciones para casos similares

Más allá de la solución puntual, de este caso se desprenden algunas recomendaciones que aplican a muchas otras fallas de instalación:

1. **Descartar primero la causa más común.** La limpieza de restos de NI no resolvió el problema, pero eliminó la explicación más probable y redujo el campo de búsqueda.
2. **No adivinar: obtener evidencia.** El mensaje de error en pantalla ("problem with this package") era engañoso. El log detallado mostró exactamente qué acción fallaba y por qué.
3. **Comparar lo que funciona con lo que no.** Que todos los paquetes se instalaran excepto uno indicaba que la causa estaba en algo exclusivo de ese paquete.
4. **Ir a la fuente.** Inspeccionar las tablas del MSI permitió entender la lógica de NIPaths y, a partir de ella, identificar en qué punto se podía intervenir: la ruta en el registro.
5. **Hacer el cambio mínimo y que se pueda revertir.** La solución consiste en dos valores de registro con las rutas estándar, sin modificar el paquete ni el sistema más allá de lo necesario.
6. **Documentar.** Este documento existe para que el siguiente caso tome minutos y no días.

---

## Anexo: script de diagnóstico y corrección

El archivo [`fix-ni-2705.ps1`](fix-ni-2705.ps1) automatiza las secciones 4, 5 y 6.

**Sin parámetros solo diagnostica y no modifica nada.** Revisa:
- que la carpeta *Documentos públicos* exista y Windows la reporte correctamente;
- si hay logs en `%TEMP%` con la falla de NIPaths (`CSIDL_COMMON_DOCUMENTS ... failed`), lo que confirma que se trata de este caso;
- si los valores `NIPUBDOCSDIR` y `NIPUBAPPDATADIR` ya están configurados.

**Con `-Apply` aplica la solución de la sección 6** y verifica el resultado. Requiere PowerShell como administrador.

```powershell
# 1. Diagnóstico (no cambia nada)
powershell -ExecutionPolicy Bypass -File .\fix-ni-2705.ps1

# 2. Si el diagnóstico confirma el caso, aplicar la solución
powershell -ExecutionPolicy Bypass -File .\fix-ni-2705.ps1 -Apply
```

`-ExecutionPolicy Bypass` permite ejecutar el script solo en esa ocasión, sin cambiar la configuración de seguridad de PowerShell en el equipo.

---

## Referencias

- [Labview Install error (2705) — NI Community](https://forums.ni.com/t5/LabVIEW/Labview-Install-error/m-p/4325397)
- [Error Windows 10 (ni-metauninstaller 2705) — NI Community](https://forums.ni.com/t5/LabVIEW/Error-Windows-10/m-p/4307801)
- [Windows Installer error messages — Microsoft Learn](https://learn.microsoft.com/windows/win32/msi/windows-installer-error-messages)
- [Directory table — Microsoft Learn](https://learn.microsoft.com/windows/win32/msi/directory-table)

---

## Summary in English

*Optional workaround based on my own machine — not an official NI fix. Confirm the cause in your logs first.*

**Symptom:** the NI/LabVIEW installer fails on `ni-metauninstaller` (`MU\MetaUninstaller.msi`) with error **2705** ("Invalid table: Directory; Could not be linked as tree"), even on a fully cleaned system.

**Root cause in this case:** `MetaUninstaller.msi` relies on NI's `NIPaths` custom action to add several rows to the MSI `Directory` table at install time. For `NIPUBDOCSDIR`, NIPaths first looks in the registry and, if not found, parents it to Public Documents. In this machine, `SHGetFolderPath(CSIDL_COMMON_DOCUMENTS)` failed inside the install context with `0x80070003` (path not found), leaving `NIPUBDOCSDIR` orphaned → `CostInitialize` fails with 2705. Look for this line in the verbose MSI log:

```
NIPaths II: ERROR! SHGetFolderPath(CSIDL_COMMON_DOCUMENTS) failed with error 2147942403
```

**Workaround:** pre-set `NIPUBDOCSDIR` and `NIPUBAPPDATADIR` under both `HKLM\SOFTWARE\National Instruments\Common\Installer` and `HKLM\SOFTWARE\WOW6432Node\National Instruments\Common\Installer` (see [section 6](#6-solución-aplicada) or run [`fix-ni-2705.ps1`](fix-ni-2705.ps1) `-Apply`), then rerun the installer.

---

## Aviso legal

NI, National Instruments y LabVIEW son marcas registradas de National Instruments Corporation. Windows es marca registrada de Microsoft Corporation. Este repositorio no está afiliado, patrocinado ni respaldado por dichas empresas, no cuenta con derechos sobre su software y no lo distribuye.

El contenido tiene fines exclusivamente educativos y no persigue fines de lucro. Se proporciona "tal cual", sin garantía de ningún tipo; quien aplique los procedimientos aquí descritos lo hace bajo su propia responsabilidad.

---

[← Volver al índice de errores de LabVIEW](../README.md)
