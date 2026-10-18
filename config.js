// Conexión con la base de datos de la tienda (Supabase).
//
// Si estos dos valores quedan vacíos, la página funciona como demo con datos
// ficticios guardados solo en el navegador.
//
// Dónde encontrarlos: panel de Supabase > Project Settings > API.
// La "anon public key" está hecha para ir en la página: los permisos reales
// los ponen las reglas de la base de datos (supabase/schema.sql).
// NUNCA pongas aquí la "service_role key".
window.ALMACEN_CONFIG = {
  supabaseUrl: "https://wcmmnpcildbgnwetysil.supabase.co",
  supabaseAnonKey: "sb_publishable_YiwMyApLbbao1JVoBHSWHQ_7TliOnQK",
  // Las personas entran con un nombre de usuario; por dentro se guarda como
  // usuario@<este dominio>. No se envían correos a esa dirección.
  dominioUsuarios: "almacen.local"
};
