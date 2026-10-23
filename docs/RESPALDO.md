# Respaldo automático por Gmail

Todas las noches (alrededor de la 01:30, hora de Chile) llega un correo con el respaldo completo de la tienda adjunto: productos, ventas, compras, conteos, fiados, reservas, proveedores, ofertas y cierres de caja. Si algún día algo falla, ese archivo se carga en la app y los datos vuelven.

El envío lo hace GitHub (gratis) con un trabajo programado del repositorio. Se configura una sola vez, en unos 10 minutos.

## 1. Preparar el Gmail

Conviene usar un Gmail solo para esto (por ejemplo `emporio.respaldos@gmail.com`), aunque también sirve el de la dueña.

1. Entra a ese Gmail y abre [myaccount.google.com/security](https://myaccount.google.com/security).
2. Activa la **Verificación en 2 pasos** (Google lo pide para el paso siguiente).
3. Abre [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords), escribe un nombre como `Respaldo almacén` y toca **Crear**.
4. Google muestra una **contraseña de aplicación** de 16 letras. Cópiala: se usa en el paso 3. No es la contraseña normal del Gmail y solo sirve para enviar correos.

## 2. Crear la clave en la app

1. Entra a la app con la **cuenta maestra** (solo ella ve esta opción; la dueña no la ve).
2. Ve a **Más > Respaldo > Respaldo automático por correo** y toca **Crear clave**.
3. Copia la clave que aparece. Se muestra una sola vez; si se pierde, se crea otra con **Cambiar clave**.

## 3. Guardar los datos en GitHub

En el repositorio: **Settings > Secrets and variables > Actions > New repository secret**. Crea estos secretos (nombre exacto, en mayúsculas):

| Nombre | Valor |
| --- | --- |
| `RESPALDO_CLAVE` | La clave del paso 2 |
| `GMAIL_USUARIO` | El Gmail del paso 1, por ejemplo `emporio.respaldos@gmail.com` |
| `GMAIL_CLAVE_APP` | La contraseña de aplicación de 16 letras |
| `RESPALDO_PARA` | Opcional: otro correo que reciba los respaldos (por ejemplo, el de la dueña). Si no se crea, llegan al mismo Gmail |

Los secretos de GitHub no se ven en el código ni en la página, aunque el repositorio sea público.

## 4. Probar

1. En el repositorio, abre la pestaña **Actions** y elige **Respaldo diario**.
2. Toca **Run workflow** y espera un minuto.
3. Debe aparecer con un ✓ verde y llegar el correo "Respaldo Emporio del Valle AAAA-MM-DD".

Si sale una ✗ roja, abre el trabajo para ver el motivo. Los más comunes:
- *Faltan secretos del repositorio*: falta crear uno de la tabla o el nombre está mal escrito.
- *Clave de respaldo incorrecta*: se cambió la clave en la app; pon la nueva en `RESPALDO_CLAVE`.
- *Username and Password not accepted*: la contraseña de aplicación está mal o falta la verificación en 2 pasos.

Cuando el respaldo falla, GitHub le avisa por correo al dueño del repositorio.

## Recuperar los datos

En la app: **Más > Respaldo > Elegir archivo de respaldo**, y elige el archivo `.json` del correo. Antes de restaurar se muestra qué trae. Solo agrega lo que falta: no borra ni cambia lo que ya está.

## Bueno saber

- El respaldo diario también mantiene despierto el proyecto gratuito de Supabase, que se pausa si pasa una semana sin uso.
- GitHub apaga los trabajos programados de un repositorio público si pasan 60 días sin cambios en el repositorio. Antes avisa por correo; para reactivarlo, en **Actions > Respaldo diario** toca **Enable workflow**.
- La clave solo permite *leer* el respaldo. Con ella no se puede vender, borrar ni cambiar nada.
