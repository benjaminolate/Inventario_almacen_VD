# Inventario Almacén

Sistema de inventario para celular pensado para almacenes de barrio: permite vender, recibir mercadería y contar el stock por sectores escaneando códigos de barras con la cámara, todo desde el navegador y sin instalar nada. Funciona como demo en un solo dispositivo o, conectado a Supabase, con varias personas atendiendo a la vez y reservas de pan para los clientes.

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
- **Ventas:** búsqueda por nombre o escaneo, carrito con cantidades y total, medio de pago (efectivo, débito o transferencia) y cálculo del vuelto. Botones rápidos para lo que más se vende (por ejemplo, el pan, que se vende por unidad).
- **Tipos de pan:** cada pan con su precio por unidad, botón rápido en Vender y opción de reservarlo.
- **Venta a granel:** verduras con precio por kilo; se venden por peso (lo que marca la balanza) o por monto ("$1.000 de pan").
- **Ofertas y packs:** por ejemplo "3 galletas por $1.500"; el descuento se aplica solo en el carrito al juntar las unidades, y avisa cuando falta poco para completar el pack.
- **Recepción de mercadería:** registro de lo que llega del proveedor, con cantidad, costo unitario, fecha de vencimiento opcional y total de la factura.
- **Lista de compras:** se arma sola con los productos bajo el stock mínimo, separada por proveedor, con cantidades sugeridas, pedido por WhatsApp y un botón para recibir ese pedido.
- **Proveedores:** contacto, notas y productos de cada uno.
- **Vencimientos:** aviso de lo que vence esta semana o ya venció, para venderlo antes o rebajarlo con una oferta.
- **Cierre de caja:** compara lo registrado desde el último cierre con lo contado en caja, separado en efectivo (con el sencillo inicial), débito y transferencia, y guarda el historial de cierres.
- **Conteo por sectores:** se cuenta un sector a la vez; una cantidad se puede marcar como aproximada o un producto como "No lo tenemos". Al terminar muestra las diferencias entre lo que esperaba el sistema y lo contado.
- **Productos:** catálogo precargado con 67 productos típicos de almacén en 11 sectores (incluidos pan por unidad y verduras a granel), con filtro, búsqueda, edición (nombre, precio, costo, stock mínimo, código de barras), últimos movimientos y alta de productos nuevos.
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

**Aviso y reservas de pan**
- Botón **"Avisar que llegó el pan"** que abre WhatsApp con el mensaje listo para enviarlo al grupo de clientes. El mensaje se puede editar o copiar y queda guardado.
- **Reservas de pan** desde una página pública (`reservar.html`): el cliente elige el pan, si es para hoy o mañana, y recibe un código. En la tienda aparece al instante, con el total de pan a apartar, y se marca como entregada o se avisa por WhatsApp que está lista.

**Multiusuario (con Supabase)**
- Inicio de sesión con usuario y contraseña; roles de administradora y vendedor/a.
- Todos los celulares y computadores ven el mismo stock y se actualizan en vivo.
- El historial registra quién hizo cada movimiento, con la hora del servidor.

**Otros**
- Diseño pensado para celular. **Más** separa Logística, Ayudas y Configuración, y cada pantalla tiene botón **Regresar** (también funciona el botón atrás del celular).
- **Apariencia** por aparato: tema claro, oscuro o automático, 5 fuentes y colores personalizados.
- **Extensiones:** fiados, pan, proveedores, vencimientos, ofertas y cierre de caja se pueden apagar en **Más > Extensiones** si la tienda no los usa.
- Datos ficticios de ejemplo y botón **"Reiniciar demo"**.

## Tecnologías

| Área | Qué se usa |
|---|---|
| Lenguaje | JavaScript (vanilla, sin framework), HTML y CSS |
| Arquitectura | Aplicación de una sola página (`index.html`) con vistas renderizadas desde JavaScript |
| Datos | Demo: `localStorage` del navegador. Tienda: [Supabase](https://supabase.com) (Postgres, Auth y Realtime) con reglas de acceso por fila (RLS) |
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

**Con base de datos (varios usuarios):** sigue la guía [docs/SUPABASE.md](docs/SUPABASE.md). Se crea un proyecto gratuito en Supabase, se ejecuta `supabase/schema.sql` y se pegan la URL y la clave pública en `config.js`. Sin esos datos, la página funciona como demo.

**Requisitos:** un navegador moderno y conexión a internet (para cargar ZXing y las tipografías).

## Estructura del proyecto

```
Inventario_almacen_VD/
├── index.html        # Toda la aplicación: estilos, vistas y lógica
├── reservar.html     # Página pública para que los clientes reserven pan
├── config.js         # URL y clave pública de Supabase (vacío = modo demo)
├── supabase/
│   └── schema.sql    # Tablas, permisos (RLS), funciones y catálogo inicial
├── docs/
│   ├── SUPABASE.md   # Guía para conectar la base de datos
│   └── capturas/     # Imágenes usadas en este README
├── README.md
├── LICENSE
└── .gitignore
```

Dentro de `index.html` el código se organiza en bloques:

| Bloque | Qué hace |
|---|---|
| Datos y catálogo | Sectores, catálogo precargado y generación de los datos de ejemplo |
| Almacenamiento demo | `load()` / `save()` sobre `localStorage` |
| Base de datos | Carga desde Supabase, cambios en vivo y `act`: cada acción se guarda en modo demo o en el servidor |
| Cálculo de stock | `stockOf()`: último conteo + compras − ventas posteriores (en la tienda lo calcula la vista `productos_stock`) |
| Escáner | Lectura en vivo, por foto y asociación de códigos nuevos |
| Vistas | Inicio, Vender, Recibir, Contar, Productos, Historial, Fiados, Reservas, Equipo y Más |
| Inicio de sesión | Pantalla de entrada, creación de la primera cuenta y modo demo |
| WhatsApp | Enlaces para recordatorios de fiados y aviso del pan |

## Estado actual

- **Demo:** funciona en un solo dispositivo, con datos ficticios en el `localStorage` del navegador. Las reservas de pan son una vista previa.
- **Tienda:** con `config.js` completo y abriendo la página con `?tienda`, usa la base de datos compartida, con usuarios, cambios en vivo y reservas reales. La dirección normal sigue mostrando la demo.

## Próximos pasos

- Instalar la app en el celular y que siga funcionando si se corta internet.
- Reportes de ventas y ganancia por día, semana y mes.
- Anular una venta mal registrada (hoy los movimientos no se editan).

## Autor

**Benjamín Olate Chirino**
GitHub: [@benjaminolate](https://github.com/benjaminolate) · LinkedIn: <!-- agrega aquí el link a tu perfil -->

## Licencia

Distribuido bajo la licencia MIT. Ver [LICENSE](LICENSE).
