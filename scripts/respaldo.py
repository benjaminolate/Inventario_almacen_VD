"""Respaldo automático de la tienda: pide los datos a Supabase y los manda por Gmail.

Lo corre GitHub Actions todos los días (.github/workflows/respaldo.yml). Usa solo la
biblioteca estándar de Python. Variables de entorno (secretos del repositorio):
  RESPALDO_CLAVE      clave creada en la app (Más > Respaldo > Respaldo automático)
  GMAIL_USUARIO       correo Gmail que envía, ej: emporio.respaldos@gmail.com
  GMAIL_CLAVE_APP     "contraseña de aplicación" de ese Gmail (16 letras)
  RESPALDO_PARA       (opcional) a quién llega; si falta, al mismo GMAIL_USUARIO
La URL y la clave pública de Supabase se leen de config.js.
"""
import datetime, json, os, re, smtplib, ssl, sys, urllib.request
from email.message import EmailMessage
from zoneinfo import ZoneInfo

cfg = open(os.path.join(os.path.dirname(__file__), "..", "config.js"), encoding="utf-8").read()
url = re.search(r'supabaseUrl:\s*"([^"]+)"', cfg).group(1).rstrip("/")
key = re.search(r'supabaseAnonKey:\s*"([^"]+)"', cfg).group(1)
clave, usuario, app = (os.environ.get(k, "").strip() for k in ("RESPALDO_CLAVE", "GMAIL_USUARIO", "GMAIL_CLAVE_APP"))
para = os.environ.get("RESPALDO_PARA", "").strip() or usuario
faltan = [k for k, v in (("RESPALDO_CLAVE", clave), ("GMAIL_USUARIO", usuario), ("GMAIL_CLAVE_APP", app)) if not v]
if faltan:
    sys.exit("Faltan secretos del repositorio: " + ", ".join(faltan))

req = urllib.request.Request(f"{url}/rest/v1/rpc/respaldo_automatico", data=json.dumps({"clave": clave}).encode(),
                             headers={"apikey": key, "Content-Type": "application/json"}, method="POST")
try:
    with urllib.request.urlopen(req, timeout=120) as r:
        datos = json.load(r)
except urllib.error.HTTPError as e:
    sys.exit(f"Supabase respondió {e.code}: {e.read().decode()[:300]}")

t = datos["tablas"]
hoy = datetime.datetime.now(ZoneInfo("America/Santiago")).strftime("%Y-%m-%d")
ventas = sum(1 for m in t["movimientos"] if m.get("tipo") == "venta")
resumen = f"{len(t['productos'])} productos, {len(t['movimientos'])} movimientos (de ellos, {ventas} de venta) y {len(t['clientes'])} clientes con fiado."

msg = EmailMessage()
msg["Subject"] = f"Respaldo {datos.get('tienda', 'Almacén')} {hoy}"
msg["From"], msg["To"] = usuario, para
msg.set_content(f"""Respaldo automático del {hoy}.

{resumen}

Para recuperar los datos: en la app, Más > Respaldo > Elegir archivo de respaldo, y elige el archivo adjunto.
Guarda este correo; no hace falta hacer nada más.
""")
msg.add_attachment(json.dumps(datos, ensure_ascii=False, indent=1).encode(), maintype="application", subtype="json",
                   filename=f"respaldo-almacen-{hoy}.json")
with smtplib.SMTP_SSL("smtp.gmail.com", 465, context=ssl.create_default_context()) as s:
    s.login(usuario, app.replace(" ", ""))
    s.send_message(msg)
print("Respaldo enviado a", para, "·", resumen)
