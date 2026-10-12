# Inventario Almacén

Sistema de inventario para celular pensado para almacenes de barrio: permite vender, recibir mercadería y contar el stock por sectores escaneando códigos de barras con la cámara, todo desde el navegador y sin instalar nada.

**Demo en vivo:** https://benjaminolate.github.io/Inventario_almacen_VD/

> La demo usa **datos ficticios de ejemplo** (productos, precios, ventas y clientes inventados). El botón **"Reiniciar demo"**, en la pantalla de inicio, vuelve a cargarlos.

---

## Capturas de pantalla

<!-- Reemplaza cada marcador por la imagen correspondiente, guardada en docs/capturas/ -->

| Inicio | Vender | Contar por sector |
|---|---|---|
| ![Panel de inicio](docs/capturas/inicio.png) | ![Vender](docs/capturas/vender.png) | ![Contar por sector](docs/capturas/contar.png) |

| Escaneo de códigos | Fiados | Historial |
|---|---|---|
| ![Escaneo de códigos de barras](docs/capturas/escaneo.png) | ![Fiados](docs/capturas/fiados.png) | ![Historial](docs/capturas/historial.png) |

---

## El problema que resuelve

Muchos negocios de barrio llevan el stock "de memoria" y **no pueden cerrar un día completo para contar todo** el inventario. Sin un conteo inicial, ningún sistema de inventario sirve.

La solución es que **cada producto se calcula desde su propio último conteo**:

```
Stock = último conteo + compras − ventas desde ese conteo
```

Así se puede contar un sector por día (por ejemplo, Bebidas el lunes y Lácteos el martes) sin detener la venta y sin que nada quede desfasado: las ventas se registran desde el primer día y, para cada producto, solo se descuentan las que ocurrieron después de su conteo.

## Funcionalidades

**Inventario**
- **Ventas:** búsqueda por nombre o escaneo, carrito con cantidades y total, confirmación de la venta.
- **Recepción de mercadería:** registro de lo que llega del proveedor, con cantidad y costo unitario por producto y total de la factura.
- **Conteo por sectores:** se cuenta un sector a la vez; una cantidad se puede marcar como aproximada o un producto como "No lo tenemos". Al terminar muestra las diferencias entre lo que esperaba el sistema y lo contado.
- **Productos:** catálogo precargado con 54 productos típicos de almacén en 9 sectores, con filtro, búsqueda, edición (nombre, precio, costo, stock mínimo, código de barras), últimos movimientos y alta de productos nuevos.
- **Historial** de ventas, compras y conteos, con filtro por tipo.
- **Panel de inicio:** porcentaje del inventario contado, ventas del día, avance del conteo por sector, productos bajo el stock mínimo y lo más vendido en los últimos 7 días.

**Escaneo de códigos de barras con la cámara**
- Lectura en vivo con la cámara trasera del celular (EAN-13, EAN-8, UPC-A, UPC-E, Code 128 y Code 39), con vibración al leer.
- Usa la API nativa **`BarcodeDetector`** cuando el navegador la ofrece y **ZXing** como respaldo cuando no.
- Alternativas: sacar una foto al código, elegir una foto guardada o escribir el número a mano.
- Si un código no existe, se puede asociar a un producto del catálogo o crear uno nuevo; desde ahí se reconoce solo.

**Fiados**
- Cuaderno de cuentas por cliente: anotar fiados, registrar pagos y ver saldo y movimientos.
- Total por cobrar entre todos los clientes.
- **Recordatorio por WhatsApp** con el mensaje de la deuda ya redactado. Los fiados no afectan el stock.

**Aviso del pan**
- Botón **"Avisar que llegó el pan"** que abre WhatsApp con el mensaje listo para enviarlo al grupo de clientes. El mensaje se puede editar o copiar y queda guardado.

**Otros**
- Diseño pensado para celular, con modo oscuro automático.
- Datos ficticios de ejemplo y botón **"Reiniciar demo"**.

## Tecnologías

| Área | Qué se usa |
|---|---|
| Lenguaje | JavaScript (vanilla, sin framework), HTML y CSS |
| Arquitectura | Aplicación de una sola página (`index.html`) con vistas renderizadas desde JavaScript |
| Datos | `localStorage` del navegador (sin servidor ni base de datos) |
| Códigos de barras | `BarcodeDetector` (nativo) y [ZXing](https://github.com/zxing-js/library) `@zxing/library` 0.21.3 como respaldo |
| Cámara | `getUserMedia` (escaneo en vivo) y captura por foto |
| Mensajería | Enlaces de WhatsApp con el mensaje ya escrito |
| Tipografías | Google Fonts (Bricolage Grotesque y Figtree) |
| Publicación | GitHub Pages |

## Cómo usarlo

**En línea:** abre la [demo en vivo](https://benjaminolate.github.io/Inventario_almacen_VD/) en el celular o en el computador. Para escanear, da permiso a la cámara.

**Localmente:**

```bash
git clone https://github.com/benjaminolate/Inventario_almacen_VD.git
cd Inventario_almacen_VD
python3 -m http.server 8000
# luego abre http://localhost:8000 en el navegador
```

También se puede abrir `index.html` directamente, pero el escaneo en vivo con la cámara solo funciona en HTTPS o en `localhost`.

**Requisitos:** un navegador moderno y conexión a internet (para cargar ZXing y las tipografías).

## Estructura del proyecto

```
Inventario_almacen_VD/
├── index.html        # Toda la aplicación: estilos, vistas y lógica
├── docs/
│   └── capturas/     # Imágenes usadas en este README
├── README.md
├── LICENSE
└── .gitignore
```

Dentro de `index.html` el código se organiza en bloques:

| Bloque | Qué hace |
|---|---|
| Datos y catálogo | Sectores, catálogo precargado y generación de los datos de ejemplo |
| Almacenamiento | `load()` / `save()` sobre `localStorage` |
| Cálculo de stock | `stockOf()`: último conteo + compras − ventas posteriores |
| Escáner | Lectura en vivo, por foto y asociación de códigos nuevos |
| Vistas | Inicio, Vender, Recibir, Contar, Productos, Historial, Fiados y Más |
| WhatsApp | Enlaces para recordatorios de fiados y aviso del pan |

## Estado actual

**Demo funcional.** Todo lo descrito en Funcionalidades funciona en un solo dispositivo, con los datos guardados en el `localStorage` del navegador.

Todavía **no tiene**:
- Base de datos compartida: los datos no se sincronizan entre celulares y se pierden si se borran los datos del navegador.
- Usuarios ni inicio de sesión.

Incluye además una **vista previa de reservas de pan** (marcada como "próxima etapa"): muestra la lista de reservas del día, permite marcarlas como entregadas y simular una reserva.

## Próximos pasos

- Base de datos compartida para usar el sistema desde varios celulares a la vez.
- Usuarios e inicio de sesión para el personal del almacén.
- Reservas de pan reales: el cliente reserva desde un link y la reserva llega al celular de la tienda.

## Autor

**Benjamín Olate Chirino**
GitHub: [@benjaminolate](https://github.com/benjaminolate) · LinkedIn: <!-- agrega aquí el link a tu perfil -->

## Licencia

Distribuido bajo la licencia MIT. Ver [LICENSE](LICENSE).
