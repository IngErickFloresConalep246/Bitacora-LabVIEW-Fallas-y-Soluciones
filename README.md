# Errores de instalación y configuración de NI LabVIEW

> 📘 **Acerca de este repositorio.** Este es un repositorio público con fines educativos. En él documento fallas de software que se han presentado en mi equipo o en los equipos de mis alumnos, junto con el procedimiento que seguimos para resolverlas, con la intención de que sirva como material de consulta para la comunidad estudiantil. Si a alguien fuera de la comunidad educativa le resulta útil, es bienvenido a usarlo. No tiene fines de lucro.

> ⚠️ **Aviso.** Las soluciones aquí documentadas son opcionales y se basan en los problemas que se presentaron en equipos específicos. No son procedimientos oficiales de NI ni soluciones definitivas. Antes de aplicar cualquiera, sigue el diagnóstico de cada caso para confirmar que tu error tiene la misma causa.

---

## Errores documentados

| Código | Error presentado | Componente | Versión | Documento |
|---|---|---|---|---|
| **2705** | La instalación se detiene en `ni-metauninstaller` (*Invalid table: Directory; Could not be linked as tree*) | `MetaUninstaller.msi` | LabVIEW 2026 Q3 | [Ver solución](error-2705-metauninstaller/README.md) |

---

## Organización del repositorio

Cada error tiene su propia carpeta con:

- **`README.md`**: descripción del problema, diagnóstico, análisis de la causa y solución aplicada.
- **Scripts de apoyo** (cuando aplica): herramientas para diagnosticar o corregir el problema de forma automática.

```
LabVIEW-Errores/
├── README.md                         ← este índice
└── error-2705-metauninstaller/
    ├── README.md
    └── fix-ni-2705.ps1
```

---

## Cómo usar esta guía

1. Busca en la tabla el **código de error** o el mensaje que te aparece.
2. Lee la sección de **diagnóstico** del documento correspondiente y confirma que tu caso coincide.
3. Solo entonces aplica la **solución**.
4. Si tu error no aparece aquí o la solución no funcionó, guarda el mensaje completo, capturas de pantalla y, si es posible, los logs de instalación. Con esa información se puede documentar un caso nuevo.
