# Conectar la tienda a Supabase (modo multiusuario)

Con estos pasos, el sistema deja de guardar los datos en un solo celular y pasa a usar una base de datos en internet. Así:

- Varias personas atienden al mismo tiempo, desde celulares o computadores, y todos ven el mismo stock.
- Cada persona entra con su usuario y contraseña, y el historial muestra quién hizo cada venta, compra o conteo.
- Los clientes reservan pan desde un link (`reservar.html`) y la reserva aparece al instante en la tienda.
- Los datos no se pierden si se borra el navegador o se pierde un celular.

Se usa el plan gratuito de Supabase. Toma unos 15 minutos.

## 1. Crear el proyecto

1. Entra a [supabase.com](https://supabase.com) y crea una cuenta (se puede entrar con GitHub).
2. Presiona **New project**.
3. Ponle un nombre (por ejemplo `almacen`), inventa una contraseña para la base de datos (guárdala, aunque la app no la usa) y elige la región **South America (São Paulo)**, que es la más cercana a Chile.
4. Espera a que termine de crearse (un par de minutos).

## 2. Crear las tablas

1. En el menú de la izquierda, abre **SQL Editor**.
2. Presiona **New query**, pega todo el contenido de [`supabase/schema.sql`](../supabase/schema.sql) y presiona **Run**.
3. Debe decir *Success*. Ese archivo crea las tablas, los permisos, las funciones de reservas y el catálogo inicial de productos. Se puede volver a ejecutar sin perder datos.

**Al actualizar la app:** cuando una versión nueva trae funciones que guardan datos nuevos (por ejemplo proveedores, ofertas, cierres de caja o venta a granel), hay que volver a ejecutar el `schema.sql` completo de esa versión en el **SQL Editor**, idealmente antes de publicar la página nueva. Agrega solo lo que falta: no borra ventas, productos ni cuentas.

## 3. Permitir entrar con usuario (sin correo)

Las personas de la tienda entran con un nombre de usuario, no con su correo. Para eso Supabase no debe pedir confirmar el correo:

1. Abre **Authentication** y luego **Sign In / Providers** (en algunas versiones del panel está en **Providers > Email**).
2. Desactiva **Confirm email** y guarda.

## 4. Copiar las claves a `config.js`

1. Abre **Project Settings** y luego **API Keys** (o **API**, según la versión del panel). Copia la **Project URL**, que está en **Data API** o en la misma página.
2. Copia la clave pública: **Publishable key** (empieza con `sb_publishable_`) o, en proyectos más antiguos, la **anon public key**.
3. Pégalas en [`config.js`](../config.js):

```js
window.ALMACEN_CONFIG = {
  supabaseUrl: "https://xxxxxxxx.supabase.co",
  supabaseAnonKey: "sb_publishable_xxxxxxxx",
  dominioUsuarios: "almacen.local"
};
```

La clave pública está hecha para ir en la página: lo que cada persona puede ver o cambiar lo deciden las reglas de la base de datos. **Nunca pongas la `service_role` key ni la `secret` key** en `config.js` ni en el repositorio.

4. Sube el cambio a GitHub. GitHub Pages publica la nueva versión en uno o dos minutos.

## 5. Primer uso

La misma página sirve de demo pública y de sistema de la tienda. La dirección normal (`https://benjaminolate.github.io/Inventario_almacen_VD/`) sigue mostrando la demo, por ejemplo para quien llega desde un CV. **La tienda se abre agregando `?tienda` al final:** `https://benjaminolate.github.io/Inventario_almacen_VD/?tienda`. Cada celular o computador lo recuerda después de abrir ese link una vez, así que conviene guardarlo en la pantalla de inicio.

1. Abre la página de la tienda (con `?tienda`), apenas esté publicada: el primero que crea una cuenta queda como **cuenta maestra**. Como todavía no hay cuentas, aparece **Configurar la tienda**: ahí se crea (nombre, usuario y contraseña). Hazlo apenas publiques la página, para que nadie más la cree antes.
   - La cuenta maestra es administradora para siempre: nadie más puede cambiarle el usuario, la contraseña ni los permisos, ni quitarle el acceso. Sirve de llave de repuesto si alguien pierde su contraseña.
2. En **Más > Equipo y cuenta**, se agregan las demás personas con **+ Agregar** y se les entrega su usuario y contraseña. Tocando a una persona se le cambia el nombre, el usuario, la contraseña, los permisos o el acceso.
3. Antes de empezar, conviene revisar en **Productos** los nombres y precios del catálogo inicial, y en **Más > Equipo y cuenta** el nombre de la tienda que ven los clientes.
4. El conteo parte desde cero: se cuenta un sector a la vez, igual que en la demo.

## Reservas de pan

- El link para clientes está en **Más > Reservas de pan** (botones *Enviar por WhatsApp* y *Copiar link*). También se puede agregar al mensaje de **Avisar que llegó el pan**.
- Los clientes eligen el pan, si es para hoy o mañana, y dejan su nombre y, si quieren, su celular. Reciben un código de 4 letras para decir al retirar.
- En la tienda se ve cuánto pan apartar, se marca cada reserva como entregada y, si el cliente dejó su celular, se le avisa por WhatsApp.
- Se puede cerrar las reservas en cualquier momento y elegir hasta qué hora se aceptan reservas para el mismo día.

## Página de la tienda

- Es `tienda.html`, una página para clientes con la foto del almacén, descripción, dirección, horario y botones a la reseña de Google, el grupo de WhatsApp, cómo llegar, redes sociales y la reserva de pan.
- Se edita en **Más > Página de la tienda**: **+ Agregar link**, elegir el tipo y pegar el link (cada tipo explica dónde conseguirlo). El orden se cambia con las flechas.
- Ahí mismo está el **código QR** para imprimir y pegar en el mostrador, y los botones para enviar o copiar el link.
- Cualquier persona puede verla sin cuenta; solo la administradora la cambia.

## Quién puede hacer qué

| | Administradora | Vendedor/a |
|---|---|---|
| Vender, recibir mercadería, contar | Sí | Sí |
| Editar productos y precios | Sí | Sí |
| Anotar fiados y pagos | Sí | Sí |
| Atender y cerrar reservas | Sí | Sí |
| Agregar personas, quitar acceso, cambiar permisos | Sí | No |
| Cambiar usuario o contraseña de otra persona | Sí (menos la cuenta maestra) | No |
| Nombre de la tienda, página de la tienda | Sí | No |
| Restaurar un respaldo | Sí | No |
| Proveedores, ofertas, cierre de caja | Sí | Sí |
| Encender o apagar extensiones | Sí | No |

Las ventas, compras y conteos quedan registrados con la hora del servidor y la persona que los hizo, y no se pueden editar ni borrar desde la app.

## Cosas a saber

- **Contraseña olvidada:** la administradora le pone una nueva en **Más > Equipo y cuenta**, tocando a la persona. Si la que olvidó la contraseña es la única administradora, se entra con la cuenta maestra. Cada persona puede cambiar la suya en **Más > Equipo y cuenta**. Si se pierde la contraseña de la cuenta maestra, se cambia en el panel de Supabase (**Authentication > Users**).
- **Plan gratuito:** Supabase pausa los proyectos gratuitos que pasan una semana sin uso. Una tienda que lo usa todos los días no se pausa; si se pausa, se reactiva desde el panel.
- **Respaldo:** el plan gratuito no guarda copias descargables. La administradora puede descargar una copia de todo en **Más > Respaldo > Descargar respaldo** (un archivo con la fecha en el nombre); conviene hacerlo una vez por semana y guardarlo en el computador o en Google Drive. En la misma pantalla, **Elegir archivo de respaldo** lo vuelve a cargar: muestra qué trae y solo agrega lo que falta, sin borrar ni cambiar nada de lo que ya está. Sirve, por ejemplo, para pasar todo a un proyecto de Supabase nuevo (las cuentas de usuario no viajan en el respaldo; se vuelven a crear en Equipo). También se pueden exportar tablas sueltas en **Table Editor** (*Export to CSV*).
- **Instalar la app:** en **Más > Instalar la app** están los pasos para cada celular. Queda con su ícono y abre más rápido; igual necesita internet para vender.
- **Conexión:** arriba a la derecha se ve si hay conexión (*En línea*), si se está reconectando o si no hay internet, y cuántas cosas faltan por enviar.
- **Sin internet:** las **ventas** y los **fiados o pagos** de clientes ya anotados se guardan en el celular y se envían solos cuando vuelve la conexión, con la hora en que se hicieron (aparecen como *Por enviar* en el Historial y en Fiados). El stock que se ve ya les descuenta lo vendido. Si el celular se reinicia sin internet, la app abre con los últimos datos guardados. Recibir mercadería, contar, crear clientes y cambiar productos necesitan internet. Conviene no cerrar sesión con ventas por enviar.
- **Demo:** la dirección normal muestra la demo con datos ficticios, y en un celular de la tienda se puede abrir con `?demo` o con el botón *Ver demo con datos ficticios* de la pantalla de inicio de sesión. La demo nunca toca la base de datos.
