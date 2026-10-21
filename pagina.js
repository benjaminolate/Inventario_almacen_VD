// Tipos de links de la página pública de la tienda (tienda.html).
// Lo usan la página pública para mostrarlos y la app para editarlos.
(function(){
"use strict";
const svg = d => `<svg viewBox="0 0 24 24" aria-hidden="true">${d}</svg>`;
const ICONS = {
  pan: svg('<path d="M4 11a8 5 0 0 1 16 0v1.5a1.5 1.5 0 0 1-1.5 1.5H5.5A1.5 1.5 0 0 1 4 12.5z"/><path d="M9 8.5l-1 3M13 8l-.5 3.5M16.5 9l.5 2.5"/>'),
  resena: svg('<path d="M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z"/>'),
  grupo: svg('<circle cx="9" cy="8" r="3.2"/><path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6"/><path d="M16 4.6a3.2 3.2 0 0 1 0 6.3M18 14.4c1.8.9 3 3 3 5.6"/>'),
  whatsapp: svg('<path d="M4 20l1.3-4A8 8 0 1 1 8 18.7z"/><path d="M9 9.5c.3 2.3 2.2 4.2 4.5 4.5l1-1.3 2 .8-.4 1.8c-3.9.3-8.2-4-7.9-7.9l1.8-.4.8 2z"/>'),
  maps: svg('<path d="M12 21s-6.5-6-6.5-11a6.5 6.5 0 0 1 13 0c0 5-6.5 11-6.5 11z"/><circle cx="12" cy="10" r="2.3"/>'),
  telefono: svg('<path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z"/>'),
  instagram: svg('<rect x="3.5" y="3.5" width="17" height="17" rx="5"/><circle cx="12" cy="12" r="4"/><circle cx="17.3" cy="6.7" r=".8"/>'),
  facebook: svg('<path d="M14 21v-7.5h2.6l.4-3H14V8.6c0-.9.3-1.5 1.6-1.5H17V4.4c-.3 0-1.2-.1-2.3-.1-2.3 0-3.7 1.4-3.7 3.9v2.3H8.4v3H11V21"/>'),
  tiktok: svg('<path d="M14 3v11.5a3.5 3.5 0 1 1-3.5-3.5"/><path d="M14 3c.4 2.6 2.2 4.4 5 4.6"/>'),
  otro: svg('<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>')
};
// [tipo, título por defecto, qué se pide, ejemplo, ayuda]
const TIPOS = [
  ["resena","Déjanos tu reseña en Google","Link para reseñar","https://g.page/r/.../review","En Google Maps, abre el perfil del almacén (como dueña) y toca \"Pedir reseñas\": ahí está el link para compartir. También sirve el link del lugar en Maps."],
  ["grupo","Únete a nuestro grupo de WhatsApp","Link de invitación al grupo","https://chat.whatsapp.com/...","En el grupo de WhatsApp: toca el nombre del grupo > Invitar al grupo > Copiar enlace."],
  ["whatsapp","Escríbenos por WhatsApp","Número de celular","9 1234 5678",""],
  ["maps","Cómo llegar","Link de Google Maps","https://maps.app.goo.gl/...","En Google Maps, busca el almacén > Compartir > Copiar enlace."],
  ["telefono","Llámanos","Número de teléfono","9 1234 5678",""],
  ["instagram","Instagram","Link del perfil","https://instagram.com/...",""],
  ["facebook","Facebook","Link de la página","https://facebook.com/...",""],
  ["tiktok","TikTok","Link del perfil","https://tiktok.com/@...",""],
  ["otro","Otro link","Link","https://...",""]
];
const tipo = k => TIPOS.find(t => t[0] === k) || TIPOS[TIPOS.length - 1];
// Celular chileno a formato internacional: 9 1234 5678 -> 56912345678
function phoneIntl(p){ let d = String(p || "").replace(/\D/g, ""); if (d.length === 9 && d[0] === "9") d = "56" + d; else if (d.length === 8) d = "569" + d; return d; }
// Solo se aceptan links web y de teléfono; lo demás se convierte en https://
function href(l){
  const v = String(l.valor || "").trim(); if (!v) return "";
  if (l.tipo === "whatsapp") return "https://wa.me/" + phoneIntl(v);
  if (l.tipo === "telefono") return "tel:+" + phoneIntl(v);
  if (/^https?:\/\//i.test(v)) return v;
  return "https://" + v.replace(/^[a-z]+:\/*/i, "");
}
window.PAGINA = { ICONS, TIPOS, tipo, href };
})();
