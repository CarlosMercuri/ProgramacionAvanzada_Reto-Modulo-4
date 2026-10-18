# Decisión técnica: política de sobrescritura y conservación de evidencias

**Proyecto:** Reto Integrador — Observabilidad Reproducible  
**Materia:** Programación Avanzada para Ciencia de Datos  
**Fecha de documentación:** 18 de octubre de 2026  
**Estado:** Decisión implementada y probada; comportamiento ante reejecuciones documentado como limitación operativa.

## 1. Contexto y alcance de la consigna

El notebook de la cátedra plantea que **cada corrida utilice un `run_id` diferente y conserve sus propios artefactos**. Los cuatro archivos generados por corrida son:

- `detalle.csv`: registros procesados y filtrados.
- `resumen.json`: parámetros e indicadores finales.
- `entorno.json`: información del entorno y huellas SHA-256 de entradas relevantes.
- `ejecucion.log`: eventos de carga, limpieza, filtrado y finalización.

El código de partida crea el directorio mediante:

```python
RUN_DIR.mkdir(parents=True, exist_ok=True)
```

La consigna enfatiza la conservación de evidencias, pero **no especifica de forma expresa** qué hacer ante la reutilización accidental de un `run_id`: sobrescribir archivos, agregar contenido (*append*) o rechazar la ejecución. Por ello, la política aquí descripta es una **decisión técnica adicional del proyecto**, no una obligación textual de la cátedra.

## 2. Alternativas consideradas

| Alternativa | Comportamiento si el `run_id` existe | Riesgo o limitación |
|---|---|---|
| Sobrescribir (`w`) | Reemplaza los archivos anteriores | Pérdida de evidencia histórica y de trazabilidad. |
| Agregar (`a`, *append*) | Concatena contenido con el existente | Puede duplicar filas en CSV y producir un JSON inválido al concatenar objetos; mezcla eventos de distintas corridas en un log. |
| Rechazar la reutilización | Interrumpe antes de escribir los artefactos | Impide repetir una ejecución con el mismo `run_id` sin gestionar previamente un nuevo identificador. |

**Decisión adoptada:** rechazar la reutilización de un directorio de corrida existente. No se adopta *append* como política general para estos cuatro artefactos.

## 3. Implementación

En la orquestación, antes de crear el logger y de escribir los archivos de salida, se utiliza:

```python
RUN_DIR = RESULTADOS_DIR / run_id

try:
    RUN_DIR.mkdir(parents=True, exist_ok=False)
except FileExistsError:
    raise FileExistsError(
        f"ERROR: El run_id '{run_id}' ya existe en {RUN_DIR}. "
        "Utilizá un run_id nuevo para conservar las evidencias anteriores."
    )
```

Esta decisión protege la **reutilización accidental del directorio de artefactos**. No constituye un sistema completo de almacenamiento inmutable: no bloquea otras modificaciones externas de archivos, ni impide que se sobrescriba el **notebook de salida de Papermill** si se reutiliza su ruta (`ejecutado_web.ipynb`, por ejemplo). Tampoco garantiza por sí sola una reserva atómica de nombres en escenarios con múltiples procesos concurrentes.

## 4. Evidencias obtenidas

### Prueba negativa: `run_id` existente

- Se intentó reutilizar `manual_web`.
- Se obtuvo el `FileExistsError` esperado **antes de inicializar el logger** de la corrida rechazada.
- Se compararon mediante SHA-256 los cuatro artefactos de `manual_web` antes y después del intento.
- **Resultado observado:** `detalle.csv`, `resumen.json`, `entorno.json` y `ejecucion.log` permanecieron intactos.

### Prueba positiva: `run_id` nuevo

- Se ejecutó `manual_web_revision_01`.
- La orquestación finalizó y generó sus cuatro artefactos.
- Se verificó que los archivos originales de `manual_web` continuaban intactos mediante sus hashes SHA-256 previamente registrados.
- **Resultado observado:** la protección no bloqueó una corrida nueva.

### Papermill y reproducción en un entorno limpio

Se completaron las dos corridas solicitadas usando identificadores únicos:

| Corrida | Canal y período | Registros finales | Venta total |
|---|---|---:|---:|
| `web_bimestre` | Web; 2026-01-01 a 2026-02-28 | 13 | 382500.0 |
| `tienda_bimestre` | Tienda; 2026-03-01 a 2026-04-30 | 14 | 470000.0 |

Ambas finalizaron mediante Papermill y fueron reproducidas en un entorno virtual nuevo denominado `TestReto`. Las comparaciones posteriores confirmaron coincidencia de los hashes de entrada y `requirements.txt`, de las versiones principales registradas, de los parámetros y de los indicadores finales.

También se realizó **Restart Kernel & Run All** una vez en `TestReto`, con el identificador predeterminado `manual_web` todavía disponible: el notebook ejecutó sus 24 celdas de código sin excepciones sin capturar y finalizó satisfactoriamente.

Estas evidencias validan los escenarios probados; no demuestran que todas las dependencias transitivas o todos los archivos generados sean idénticos byte a byte.

## 5. Limitación conocida: `Restart Kernel & Run All`

La política `exist_ok=False` tiene una consecuencia deliberada:

> **Si el directorio correspondiente al `run_id` ya existe, una nueva ejecución falla con `FileExistsError`, aunque se haya reiniciado el kernel.**

Por lo tanto:

1. Una **primera ejecución desde un directorio de salida limpio** puede completar `Restart Kernel & Run All` correctamente, como ocurrió en `TestReto`.
2. Una **segunda ejecución con el mismo `run_id`** es rechazada intencionalmente; esto es distinto de un error de lógica de cálculo.
3. En Papermill, además de usar un nuevo `run_id`, es recomendable indicar **un nombre de notebook de salida diferente** para evitar reemplazar evidencias anteriores, ya que la protección de `RUN_DIR` no cubre ese archivo.

Esta restricción debe comunicarse en la entrega: el notebook es ejecutable desde un entorno limpio, pero **no es reejecutable indefinidamente con el mismo identificador sin intervención**. Si se requiere que `Run All` pueda repetirse sin ajustes, habrá que definir y probar una política alternativa; no está resuelta por la implementación actual.

## 6. Procedimiento operativo recomendado

- Conservar los artefactos existentes; **no borrarlos ni renombrarlos automáticamente** para sortear la protección.
- Para una nueva corrida, elegir un `run_id` único y verificar que su directorio todavía no exista.
- Para Papermill, elegir también una ruta nueva para el notebook ejecutado.
- Mantener registrados el `run_id`, los parámetros, los artefactos y los hashes de entrada.
- Ante una corrida fallida que ya creó su directorio, **inspeccionar ese directorio antes de decidir cómo recuperar o repetir**: la política actual también rechaza identificadores de ejecuciones incompletas.
- No atribuir a la consigna una obligación de sobrescribir, hacer *append* o rechazar identificadores; registrar esta elección como un control adicional.

## 7. Decisión final y trabajo futuro

**Se mantiene la protección mediante `exist_ok=False`**, porque las pruebas realizadas muestran que previene la reutilización accidental del directorio y preserva los cuatro artefactos existentes en el escenario probado.

**Pendiente de definición operativa:** si la cátedra o un entorno productivo exige repetir automáticamente una corrida con el mismo identificador, deberán acordarse las reglas de reejecución, versionado o generación de identificadores, además de cubrir explícitamente los notebooks generados por Papermill. Cualquier cambio deberá validarse con pruebas positivas, negativas y de regresión.

---

**Nota de alcance:** este documento es una evidencia complementaria de diseño y auditoría. No reemplaza el notebook, los archivos de la corrida ni los entregables establecidos por la cátedra.
