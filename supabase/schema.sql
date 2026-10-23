-- =====================================================================
-- Inventario Almacén: base de datos en Supabase (Postgres)
--
-- Cómo usarlo: en el panel de Supabase, abre "SQL Editor", pega todo este
-- archivo y presiona "Run". Se puede volver a ejecutar sin perder datos.
--
-- Modelo:
--   stock = último conteo + compras − ventas desde ese conteo (por producto)
--   Todas las horas las pone el servidor, así varios celulares con la hora
--   distinta no desordenan el cálculo.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Usuarios de la tienda
-- ---------------------------------------------------------------------
create table if not exists public.perfiles (
  id      uuid primary key references auth.users(id) on delete cascade,
  usuario text not null,
  nombre  text not null,
  rol     text not null default 'vendedor' check (rol in ('admin','vendedor')),
  activo  boolean not null default false,
  creado  timestamptz not null default now()
);

-- Es miembro activo de la tienda
create or replace function public.es_miembro() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and activo);
$$;

create or replace function public.es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and activo and rol = 'admin');
$$;

-- Para la pantalla de inicio de sesión: si todavía no hay administradora,
-- se ofrece crear la primera cuenta.
create or replace function public.hay_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where rol = 'admin' and activo);
$$;

-- Registro cerrado: solo se crean cuentas que la administradora agregó desde
-- Equipo (queda una invitación por una hora). Así nadie de afuera llena la
-- lista de usuarios aunque llame directo a la API de registro.
create table if not exists public.invitaciones (
  usuario text primary key,
  creado  timestamptz not null default now(),
  por     uuid references auth.users(id) on delete cascade default auth.uid()
);
alter table public.invitaciones enable row level security;   -- sin políticas: solo por las funciones

create or replace function public.invitar(p_usuario text) returns void
language plpgsql security definer set search_path = public as $$
declare u text := regexp_replace(lower(trim(coalesce(p_usuario, ''))), '\s+', '.', 'g');
begin
  if not es_admin() then raise exception 'Solo la administradora puede agregar personas'; end if;
  if u !~ '^[a-z0-9._-]{2,40}$' then raise exception 'El usuario solo puede tener letras sin tilde, números, punto o guion'; end if;
  delete from invitaciones where creado < now() - interval '1 hour';
  insert into invitaciones (usuario) values (u) on conflict (usuario) do update set creado = now(), por = auth.uid();
end $$;

-- Cada cuenta nueva crea su perfil. La primera queda como administradora;
-- las demás necesitan invitación y quedan inactivas hasta que la administradora las activa.
create or replace function public.nuevo_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
declare primera boolean; invitado text;
begin
  perform pg_advisory_xact_lock(4242);
  primera := not exists (select 1 from perfiles where rol = 'admin');
  if not primera then
    delete from invitaciones where usuario = lower(split_part(new.email, '@', 1)) and creado > now() - interval '1 hour'
      returning usuario into invitado;
    if invitado is null then raise exception 'Registro cerrado: solo la administradora puede agregar personas'; end if;
  end if;
  insert into perfiles (id, usuario, nombre, rol, activo, maestra)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'usuario',''), split_part(new.email,'@',1)),
    coalesce(nullif(new.raw_user_meta_data->>'nombre',''), split_part(new.email,'@',1)),
    case when primera then 'admin' else 'vendedor' end,
    primera,
    primera and not exists (select 1 from perfiles where maestra)
  );
  return new;
end $$;

drop trigger if exists al_crear_usuario on auth.users;
create trigger al_crear_usuario after insert on auth.users
  for each row execute function public.nuevo_perfil();

-- Que nadie se quede sin administradora por error
create or replace function public.cuidar_admins() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from perfiles where rol = 'admin' and activo) then
    raise exception 'Debe quedar al menos una administradora activa';
  end if;
  return null;
end $$;

drop trigger if exists al_cambiar_perfil on public.perfiles;
create constraint trigger al_cambiar_perfil after update or delete on public.perfiles
  deferrable initially deferred for each row execute function public.cuidar_admins();

-- Cuenta maestra: la primera cuenta (o, en tiendas que ya existían, la
-- administradora más antigua). Siempre es administradora activa y solo
-- su dueño la puede cambiar.
alter table public.perfiles add column if not exists maestra boolean not null default false;
create unique index if not exists perfiles_una_maestra on public.perfiles ((true)) where maestra;

create or replace function public.cuidar_maestra() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- auth.uid() es null en el SQL Editor: ahí sí se puede cambiar todo
  if auth.uid() is null then return coalesce(new, old); end if;
  if tg_op = 'DELETE' then
    if old.maestra then raise exception 'La cuenta maestra no se puede borrar'; end if;
    return old;
  end if;
  if new.maestra is distinct from old.maestra then raise exception 'La cuenta maestra no se puede traspasar desde la app'; end if;
  if old.maestra then
    if auth.uid() <> old.id then raise exception 'La cuenta maestra solo la puede cambiar su dueño'; end if;
    if new.rol <> 'admin' or not new.activo then raise exception 'La cuenta maestra siempre es administradora y con acceso'; end if;
  end if;
  return new;
end $$;

drop trigger if exists al_cambiar_maestra on public.perfiles;
create trigger al_cambiar_maestra before update or delete on public.perfiles
  for each row execute function public.cuidar_maestra();

do $$ begin
  if not exists (select 1 from perfiles where maestra) then
    update perfiles set maestra = true
     where id = (select id from perfiles where rol = 'admin' and activo order by creado limit 1);
  end if;
end $$;

-- La administradora cambia el usuario o la contraseña de otra persona
-- (o los suyos). La cuenta maestra solo la cambia su dueño.
create or replace function public.cambiar_acceso(persona uuid, usuario_nuevo text default null, clave_nueva text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare p perfiles; correo text; u text;
begin
  if not es_admin() then raise exception 'Solo la administradora puede cambiar usuarios y contraseñas'; end if;
  select * into p from perfiles where id = persona;
  if not found then raise exception 'Esa persona no existe'; end if;
  if p.maestra and persona <> auth.uid() then raise exception 'La cuenta maestra solo la puede cambiar su dueño'; end if;

  if nullif(trim(coalesce(clave_nueva, '')), '') is not null then
    if char_length(clave_nueva) < 6 then raise exception 'La contraseña debe tener al menos 6 caracteres'; end if;
    update auth.users set encrypted_password = crypt(clave_nueva, gen_salt('bf')), updated_at = now() where id = persona;
  end if;

  u := regexp_replace(lower(trim(coalesce(usuario_nuevo, ''))), '\s+', '.', 'g');
  if u <> '' and u <> p.usuario then
    if u !~ '^[a-z0-9._-]{2,40}$' then raise exception 'El usuario solo puede tener letras sin tilde, números, punto o guion'; end if;
    select split_part(email, '@', 2) into correo from auth.users where id = persona;
    correo := u || '@' || coalesce(nullif(correo, ''), 'almacen.local');
    if exists (select 1 from auth.users where lower(email) = correo and id <> persona) then raise exception 'Ese usuario ya existe'; end if;
    update auth.users set email = correo, updated_at = now(),
      raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('usuario', u)
     where id = persona;
    if to_regclass('auth.identities') is not null then
      execute 'update auth.identities set identity_data = identity_data || jsonb_build_object(''email'', $1::text), updated_at = now() where user_id = $2 and provider = ''email'''
        using correo, persona;
    end if;
    update perfiles set usuario = u where id = persona;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Proveedores
-- ---------------------------------------------------------------------
create table if not exists public.proveedores (
  id       uuid primary key default gen_random_uuid(),
  nombre   text not null check (char_length(nombre) between 1 and 80),
  telefono text not null default '',
  nota     text not null default '',     -- ej: "pasa los martes"
  creado   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Catálogo
-- ---------------------------------------------------------------------
create table if not exists public.productos (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null check (char_length(nombre) between 1 and 120),
  sector      text not null,
  precio      integer not null default 0 check (precio >= 0),
  costo       integer not null default 0 check (costo >= 0),
  minimo      integer not null default 3 check (minimo >= 0),
  codigo      text unique,
  tiene       boolean not null default true,       -- false = "No lo tenemos"
  conteo_cant integer check (conteo_cant >= 0),
  conteo_at   timestamptz,
  aproximado  boolean not null default false,
  creado      timestamptz not null default now(),
  actualizado timestamptz not null default now()
);

create table if not exists public.movimientos (
  id          uuid primary key default gen_random_uuid(),
  producto_id uuid not null references public.productos(id),
  tipo        text not null check (tipo in ('venta','compra','conteo')),
  cantidad    integer not null check (cantidad >= 0),
  precio      integer,           -- venta: precio unitario cobrado
  costo       integer,           -- compra: costo unitario
  proveedor   text,              -- compra
  esperado    integer,           -- conteo: lo que decía el sistema
  grupo       uuid,              -- misma venta o misma recepción
  usuario_id  uuid references auth.users(id) default auth.uid(),
  at          timestamptz not null default now()
);
-- Columnas agregadas después de la primera versión (se suman sin perder datos)
drop view if exists public.productos_stock;   -- se vuelve a crear más abajo
-- Venta a granel: las cantidades aceptan decimales (1,250 kg de pan)
alter table public.movimientos alter column cantidad    type numeric(12,3);
alter table public.movimientos alter column esperado    type numeric(12,3);
alter table public.productos   alter column conteo_cant type numeric(12,3);
alter table public.productos   add column if not exists unidad text not null default 'un' check (unidad in ('un','kg'));  -- kg = a granel, precio por kilo
alter table public.productos   add column if not exists atajo boolean not null default false;  -- botón rápido en Vender
alter table public.productos   add column if not exists por_caja integer check (por_caja is null or por_caja between 2 and 1000);  -- unidades que trae la caja del proveedor
alter table public.productos   add column if not exists proveedor_id uuid references public.proveedores(id) on delete set null;
alter table public.movimientos add column if not exists descuento integer not null default 0;   -- venta: descuento por ofertas
alter table public.movimientos add column if not exists medio text check (medio in ('efectivo','debito','transferencia'));  -- venta
alter table public.movimientos add column if not exists vence date;                              -- compra: fecha de vencimiento
alter table public.movimientos add column if not exists vence_revisado boolean not null default false;
create index if not exists movimientos_producto_at on public.movimientos (producto_id, at);
create index if not exists movimientos_vence on public.movimientos (vence) where vence is not null;
create index if not exists movimientos_at on public.movimientos (at desc);
create index if not exists movimientos_grupo on public.movimientos (grupo);

-- Stock calculado: último conteo + compras − ventas posteriores al conteo
create view public.productos_stock with (security_invoker = true) as
select p.*,
  case when p.conteo_at is null then null else p.conteo_cant + coalesce((
    select sum(case m.tipo when 'compra' then m.cantidad when 'venta' then -m.cantidad else 0 end)
    from movimientos m where m.producto_id = p.id and m.at > p.conteo_at), 0) end as stock,
  case when p.conteo_at is null then coalesce((
    select sum(m.cantidad) from movimientos m where m.producto_id = p.id and m.tipo = 'venta'), 0)
  else 0 end as ventas_sin_contar
from public.productos p;

-- Venta: [{"producto_id": "...", "cantidad": 3, "precio": 590, "descuento": 270}, ...]
-- medio: efectivo, debito o transferencia
drop function if exists public.registrar_venta(jsonb);
-- grupo_id y hora los manda el celular cuando la venta se guardó sin internet:
-- si la misma venta llega dos veces se guarda una sola, y queda con la hora real
-- en que se hizo (como mucho 3 días atrás, nunca en el futuro).
drop function if exists public.registrar_venta(jsonb, text);
create or replace function public.registrar_venta(items jsonb, medio text default 'efectivo', grupo_id uuid default null, hora timestamptz default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare g uuid := coalesce(registrar_venta.grupo_id, gen_random_uuid());
        t timestamptz := least(now(), greatest(coalesce(registrar_venta.hora, now()), now() - interval '3 days'));
begin
  if not es_miembro() then raise exception 'Sin permiso'; end if;
  if jsonb_typeof(items) <> 'array' or jsonb_array_length(items) = 0 then raise exception 'Venta vacía'; end if;
  if registrar_venta.medio not in ('efectivo','debito','transferencia') then raise exception 'Medio de pago no válido'; end if;
  if registrar_venta.grupo_id is not null then
    perform pg_advisory_xact_lock(hashtext(g::text));
    if exists (select 1 from movimientos where grupo = g) then return g; end if;
  end if;
  insert into movimientos (producto_id, tipo, cantidad, precio, descuento, medio, grupo, usuario_id, at)
  select (i->>'producto_id')::uuid, 'venta', round((i->>'cantidad')::numeric, 3),
         coalesce((i->>'precio')::int, p.precio), greatest(0, coalesce((i->>'descuento')::int, 0)),
         registrar_venta.medio, g, auth.uid(), t
  from jsonb_array_elements(items) i join productos p on p.id = (i->>'producto_id')::uuid
  where (i->>'cantidad')::numeric > 0;
  return g;
end $$;

-- Recepción de mercadería: actualiza el costo, marca el producto como disponible y,
-- si viene un proveedor de la lista, lo deja como proveedor del producto.
-- items: [{"producto_id": "...", "cantidad": 24, "costo": 1300, "vence": "2026-11-02", "por_caja": 12}, ...]
-- (cantidad y costo siempre por unidad; por_caja es opcional y queda guardado en el producto)
drop function if exists public.registrar_compra(text, jsonb);
create or replace function public.registrar_compra(proveedor text, items jsonb, proveedor_id uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare g uuid := gen_random_uuid();
begin
  if not es_miembro() then raise exception 'Sin permiso'; end if;
  insert into movimientos (producto_id, tipo, cantidad, costo, proveedor, vence, grupo, usuario_id)
  select (i->>'producto_id')::uuid, 'compra', round((i->>'cantidad')::numeric, 3), (i->>'costo')::int,
         nullif(trim(registrar_compra.proveedor), ''), nullif(i->>'vence','')::date, g, auth.uid()
  from jsonb_array_elements(items) i where (i->>'cantidad')::numeric > 0;
  update productos p set costo = coalesce((i->>'costo')::int, p.costo), tiene = true, actualizado = now(),
    por_caja = coalesce(nullif((i->>'por_caja')::int, 0), p.por_caja),
    proveedor_id = coalesce(registrar_compra.proveedor_id, p.proveedor_id)
  from jsonb_array_elements(items) i
  where p.id = (i->>'producto_id')::uuid and (i->>'cantidad')::numeric > 0;
  return g;
end $$;

-- Marca un vencimiento como ya revisado (vendido, rebajado o retirado)
create or replace function public.revisar_vencimiento(p_id uuid, p_revisado boolean default true) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not es_miembro() then raise exception 'Sin permiso'; end if;
  update movimientos set vence_revisado = p_revisado where id = p_id and tipo = 'compra';
end $$;

-- Conteo de un sector:
-- [{"producto_id": "...", "cantidad": 12, "aproximado": false, "tiene": true}, ...]
-- "cantidad" puede venir vacía si solo se cambia "tiene". Devuelve las diferencias.
drop function if exists public.registrar_conteo(jsonb);
create or replace function public.registrar_conteo(items jsonb)
returns table (producto_id uuid, esperado numeric, contado numeric)
language plpgsql security definer set search_path = public as $$
declare i jsonb; pid uuid; q numeric; esp numeric; g uuid := gen_random_uuid();
begin
  if not es_miembro() then raise exception 'Sin permiso'; end if;
  for i in select * from jsonb_array_elements(items) loop
    pid := (i->>'producto_id')::uuid;
    if i ? 'tiene' and jsonb_typeof(i->'tiene') = 'boolean' then
      update productos set tiene = (i->>'tiene')::boolean, actualizado = now() where id = pid;
      if not (i->>'tiene')::boolean then continue; end if;
    end if;
    if coalesce(i->>'cantidad','') = '' then continue; end if;
    q := greatest(0, round((i->>'cantidad')::numeric, 3));
    select s.stock into esp from productos_stock s where s.id = pid;
    update productos set conteo_cant = q, conteo_at = now(),
      aproximado = coalesce((i->>'aproximado')::boolean, false), actualizado = now()
    where id = pid;
    insert into movimientos (producto_id, tipo, cantidad, esperado, grupo, usuario_id)
    values (pid, 'conteo', q, esp, g, auth.uid());
    producto_id := pid; esperado := esp; contado := q;
    return next;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Ofertas y packs: "3 galletas por $1.500"
-- ---------------------------------------------------------------------
create table if not exists public.ofertas (
  id          uuid primary key default gen_random_uuid(),
  producto_id uuid not null references public.productos(id) on delete cascade,
  cantidad    integer not null check (cantidad between 2 and 100),
  precio      integer not null check (precio > 0),     -- precio del pack completo
  activa      boolean not null default true,
  creado      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Fiados (no afectan el inventario)
-- ---------------------------------------------------------------------
create table if not exists public.clientes (
  id       uuid primary key default gen_random_uuid(),
  nombre   text not null check (char_length(nombre) between 1 and 80),
  telefono text not null default '',
  creado   timestamptz not null default now()
);

create table if not exists public.fiados (
  id         uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.clientes(id) on delete cascade,
  tipo       text not null check (tipo in ('fiado','abono')),
  monto      integer not null check (monto > 0),
  nota       text not null default '',
  usuario_id uuid references auth.users(id) default auth.uid(),
  at         timestamptz not null default now()
);
create index if not exists fiados_cliente on public.fiados (cliente_id, at);
alter table public.fiados add column if not exists medio text check (medio in ('efectivo','debito','transferencia'));  -- abono

-- ---------------------------------------------------------------------
-- Cierre de caja: compara lo vendido desde el cierre anterior con lo que hay en la caja
-- ---------------------------------------------------------------------
create table if not exists public.cierres (
  id         uuid primary key default gen_random_uuid(),
  desde      timestamptz not null,
  hasta      timestamptz not null,
  fondo      integer not null default 0,          -- efectivo con que se abrió la caja
  esperado   jsonb not null,                      -- {"efectivo": 0, "debito": 0, "transferencia": 0}
  contado    jsonb not null,
  ventas     integer not null default 0,          -- cantidad de ventas
  nota       text not null default '',
  usuario_id uuid references auth.users(id) default auth.uid(),
  at         timestamptz not null default now()
);

-- Lo que debería haber en la caja desde el último cierre (o desde el inicio del día)
create or replace function public.resumen_caja() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d timestamptz; v jsonb; a jsonb; n int;
begin
  if not es_miembro() then raise exception 'Sin permiso'; end if;
  d := coalesce((select max(hasta) from cierres),
                (hoy_chile()::timestamp at time zone 'America/Santiago'));
  select coalesce(jsonb_object_agg(medio, total), '{}'::jsonb) into v from (
    select coalesce(medio,'efectivo') medio, sum(round(cantidad * precio) - descuento)::int total
    from movimientos where tipo = 'venta' and at > d group by 1) x;
  select coalesce(jsonb_object_agg(medio, total), '{}'::jsonb) into a from (
    select coalesce(medio,'efectivo') medio, sum(monto)::int total
    from fiados where tipo = 'abono' and at > d group by 1) x;
  select count(distinct coalesce(grupo, id)) into n from movimientos where tipo = 'venta' and at > d;
  return jsonb_build_object('desde', d, 'ventas', v, 'abonos', a, 'num_ventas', n);
end $$;

create or replace function public.registrar_cierre(p_fondo integer, p_contado jsonb, p_nota text default '') returns uuid
language plpgsql security definer set search_path = public as $$
declare r jsonb := resumen_caja(); m text; e jsonb := '{}'::jsonb; id uuid;
begin
  foreach m in array array['efectivo','debito','transferencia'] loop
    e := e || jsonb_build_object(m, coalesce((r->'ventas'->>m)::int, 0) + coalesce((r->'abonos'->>m)::int, 0)
                                   + case when m = 'efectivo' then coalesce(p_fondo, 0) else 0 end);
  end loop;
  insert into cierres (desde, hasta, fondo, esperado, contado, ventas, nota, usuario_id)
  values ((r->>'desde')::timestamptz, now(), coalesce(p_fondo, 0), e, p_contado, (r->>'num_ventas')::int,
          left(coalesce(p_nota, ''), 300), auth.uid())
  returning cierres.id into id;
  return id;
end $$;

-- ---------------------------------------------------------------------
-- Pan y reservas
-- ---------------------------------------------------------------------
create table if not exists public.ajustes (
  clave text primary key,
  valor jsonb not null
);

create table if not exists public.panes (
  id     serial primary key,
  nombre text not null unique,
  activo boolean not null default true,
  orden  integer not null default 0
);

-- Fecha de hoy en Chile
create or replace function public.hoy_chile() returns date
language sql stable as $$ select (now() at time zone 'America/Santiago')::date $$;

create table if not exists public.reservas (
  id        uuid primary key default gen_random_uuid(),
  codigo    text not null,
  nombre    text not null check (char_length(nombre) between 1 and 60),
  telefono  text not null default '' check (char_length(telefono) <= 20),
  items     jsonb not null,                     -- {"Marraquetas": 10, "Hallullas": 4}
  detalle   text not null,                      -- "10 marraquetas, 4 hallullas"
  nota      text not null default '' check (char_length(nota) <= 200),
  dia       date not null default public.hoy_chile(),   -- día en que se retira
  estado    text not null default 'pendiente' check (estado in ('pendiente','entregada','cancelada')),
  creado    timestamptz not null default now(),
  entregado_at  timestamptz,
  entregado_por uuid references auth.users(id)
);
create index if not exists reservas_dia on public.reservas (dia, creado);

-- Datos que ve el cliente en la página de reservas (sin iniciar sesión)
create or replace function public.info_reservas() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'tienda',      coalesce((select valor #>> '{}' from ajustes where clave = 'tienda_nombre'), 'Almacén'),
    'abiertas',    coalesce((select (valor #>> '{}')::boolean from ajustes where clave = 'reservas_abiertas'), true),
    'hora_limite', coalesce((select (valor #>> '{}')::int from ajustes where clave = 'reservas_hora_limite'), 19),
    'hora_chile',  extract(hour from now() at time zone 'America/Santiago')::int,
    'hoy',         hoy_chile(),
    'panes',       coalesce((select jsonb_agg(nombre order by orden, id) from panes where activo), '[]'::jsonb)
  );
$$;

-- El cliente crea su reserva. p_para: 'hoy' o 'manana'
-- Huella de la conexión de quien llama (IP mezclada con un secreto y el día, sin guardar la IP)
alter table public.reservas add column if not exists origen text;
create table if not exists public.secretos (clave text primary key, valor text not null);
alter table public.secretos enable row level security;   -- sin políticas: nadie lo lee desde la app
insert into public.secretos values ('huella', encode(gen_random_bytes(32), 'hex')) on conflict do nothing;
create or replace function public.origen_peticion() returns text
language plpgsql stable security definer set search_path = public, extensions as $$
declare h json; ip text;
begin
  begin h := current_setting('request.headers', true)::json; exception when others then return null; end;
  ip := coalesce(h->>'cf-connecting-ip', nullif(trim(split_part(h->>'x-forwarded-for', ',', 1)), ''), h->>'x-real-ip');
  if ip is null then return null; end if;
  return encode(digest(ip || hoy_chile()::text || (select valor from secretos where clave = 'huella'), 'sha256'), 'hex');
end $$;

create or replace function public.crear_reserva(p_nombre text, p_telefono text, p_items jsonb, p_para text, p_nota text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  info jsonb := info_reservas();
  d date; k text; v jsonb; n int; total int := 0; det text := ''; limpio jsonb := '{}'::jsonb;
  r reservas; o text := origen_peticion();
begin
  p_nombre := trim(coalesce(p_nombre,'')); p_telefono := regexp_replace(coalesce(p_telefono,''), '[^0-9+]', '', 'g');
  if not (info->>'abiertas')::boolean then raise exception 'Las reservas están cerradas por ahora'; end if;
  if char_length(p_nombre) < 2 or char_length(p_nombre) > 60 then raise exception 'Escribe tu nombre'; end if;
  if char_length(p_telefono) > 20 then raise exception 'Teléfono no válido'; end if;
  if p_para = 'hoy' then
    if (info->>'hora_chile')::int >= (info->>'hora_limite')::int then raise exception 'Ya no se reciben reservas para hoy, elige mañana'; end if;
    d := hoy_chile();
  elsif p_para = 'manana' then d := hoy_chile() + 1;
  else raise exception 'Día no válido'; end if;
  if jsonb_typeof(p_items) <> 'object' then raise exception 'Elige qué pan quieres'; end if;
  if exists (select 1 from jsonb_object_keys(p_items) x where not (info->'panes') ? x) then
    raise exception 'Ese pan no está disponible';
  end if;
  -- Se recorre en el orden de la lista de panes para que el detalle salga ordenado
  for k in select jsonb_array_elements_text(info->'panes') loop
    v := p_items->k;
    if v is null then continue; end if;
    if jsonb_typeof(v) <> 'number' then raise exception 'Cantidad no válida'; end if;
    n := (v #>> '{}')::numeric::int;
    if n < 0 or n > 100 then raise exception 'Cantidad no válida'; end if;
    if n = 0 then continue; end if;
    total := total + n; limpio := limpio || jsonb_build_object(k, n);
    det := det || case when det = '' then '' else ', ' end || n || ' ' || lower(k);
  end loop;
  if total = 0 then raise exception 'Elige qué pan quieres'; end if;
  if total > 200 then raise exception 'Para pedidos grandes, habla directo con el almacén'; end if;
  -- Freno contra abuso: no más de 40 reservas en 10 minutos en total
  if (select count(*) from reservas where creado > now() - interval '10 minutes') >= 40 then
    raise exception 'Hay muchas reservas en este momento, intenta en unos minutos';
  end if;
  -- y por conexión (se guarda solo una huella de la IP, no la IP) y por celular
  if o is not null and (select count(*) from reservas where origen = o and creado > now() - interval '1 hour') >= 5 then
    raise exception 'Ya hiciste varias reservas seguidas. Si necesitas más pan, habla directo con el almacén';
  end if;
  if p_telefono <> '' and (select count(*) from reservas where telefono = p_telefono and dia = d and estado = 'pendiente') >= 3 then
    raise exception 'Ese celular ya tiene varias reservas para ese día. Si necesitas más pan, habla directo con el almacén';
  end if;
  insert into reservas (codigo, nombre, telefono, items, detalle, nota, dia, origen)
  values (upper(substr(encode(gen_random_bytes(3),'hex'),1,4)), p_nombre, p_telefono, limpio, det,
          left(trim(coalesce(p_nota,'')), 200), d, o)
  returning * into r;
  return jsonb_build_object('id', r.id, 'codigo', r.codigo, 'dia', r.dia, 'detalle', r.detalle);
end $$;

-- El cliente revisa o cancela su reserva con el id que le quedó guardado
create or replace function public.estado_reserva(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', id, 'codigo', codigo, 'nombre', nombre, 'detalle', detalle, 'dia', dia, 'estado', estado)
  from reservas where id = p_id;
$$;

create or replace function public.cancelar_reserva(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  update reservas set estado = 'cancelada' where id = p_id and estado = 'pendiente';
  return estado_reserva(p_id);
end $$;

-- ---------------------------------------------------------------------
-- Permisos (Row Level Security)
-- Solo los miembros activos ven y cambian datos. Los clientes de la página
-- de reservas solo pueden usar las funciones de reservas de arriba.
-- ---------------------------------------------------------------------
alter table public.perfiles    enable row level security;
alter table public.productos   enable row level security;
alter table public.movimientos enable row level security;
alter table public.clientes    enable row level security;
alter table public.fiados      enable row level security;
alter table public.ajustes     enable row level security;
alter table public.panes       enable row level security;
alter table public.reservas    enable row level security;
alter table public.proveedores enable row level security;
alter table public.ofertas     enable row level security;
alter table public.cierres     enable row level security;

do $$
declare t text;
begin
  -- Borra las políticas anteriores para poder volver a ejecutar el archivo
  for t in select format('drop policy %I on %I.%I', policyname, schemaname, tablename)
           from pg_policies where schemaname = 'public' loop
    execute t;
  end loop;
end $$;

create policy "ver mi perfil o el equipo" on public.perfiles for select to authenticated
  using (id = auth.uid() or es_miembro());
create policy "admin cambia perfiles" on public.perfiles for update to authenticated
  using (es_admin()) with check (es_admin());

create policy "miembros ven productos"     on public.productos for select to authenticated using (es_miembro());
create policy "miembros agregan productos" on public.productos for insert to authenticated with check (es_miembro());
create policy "miembros editan productos"  on public.productos for update to authenticated using (es_miembro()) with check (es_miembro());

-- Los movimientos solo se crean con las funciones registrar_*; nadie los edita ni borra
create policy "miembros ven movimientos" on public.movimientos for select to authenticated using (es_miembro());

create policy "miembros ven clientes"     on public.clientes for select to authenticated using (es_miembro());
create policy "miembros agregan clientes" on public.clientes for insert to authenticated with check (es_miembro());
create policy "miembros editan clientes"  on public.clientes for update to authenticated using (es_miembro()) with check (es_miembro());
create policy "admin borra clientes"      on public.clientes for delete to authenticated using (es_admin());

create policy "miembros ven fiados"    on public.fiados for select to authenticated using (es_miembro());
create policy "miembros anotan fiados" on public.fiados for insert to authenticated
  with check (es_miembro() and usuario_id = auth.uid());
create policy "admin borra fiados"     on public.fiados for delete to authenticated using (es_admin());

create policy "miembros ven ajustes"    on public.ajustes for select to authenticated using (es_miembro());
create policy "miembros cambian ajustes" on public.ajustes for all to authenticated using (es_miembro()) with check (es_miembro());

create policy "miembros ven panes"  on public.panes for select to authenticated using (es_miembro());
create policy "admin cambia panes"  on public.panes for all to authenticated using (es_admin()) with check (es_admin());

create policy "miembros ven reservas"     on public.reservas for select to authenticated using (es_miembro());
create policy "miembros cambian reservas" on public.reservas for update to authenticated using (es_miembro()) with check (es_miembro());

create policy "miembros ven proveedores"     on public.proveedores for select to authenticated using (es_miembro());
create policy "miembros agregan proveedores" on public.proveedores for insert to authenticated with check (es_miembro());
create policy "miembros editan proveedores"  on public.proveedores for update to authenticated using (es_miembro()) with check (es_miembro());
create policy "admin borra proveedores"      on public.proveedores for delete to authenticated using (es_admin());

create policy "miembros ven ofertas"     on public.ofertas for select to authenticated using (es_miembro());
create policy "miembros agregan ofertas" on public.ofertas for insert to authenticated with check (es_miembro());
create policy "miembros editan ofertas"  on public.ofertas for update to authenticated using (es_miembro()) with check (es_miembro());
create policy "miembros borran ofertas"  on public.ofertas for delete to authenticated using (es_miembro());

-- Los cierres solo se crean con registrar_cierre y no se editan
create policy "miembros ven cierres" on public.cierres for select to authenticated using (es_miembro());

-- ---------------------------------------------------------------------
-- Página pública de la tienda (tienda.html): nombre, foto, descripción y links
-- que la administradora edita en la app. Se guarda en ajustes.pagina.
-- ---------------------------------------------------------------------
create or replace function public.info_tienda() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'tienda',   coalesce((select valor #>> '{}' from ajustes where clave = 'tienda_nombre'), 'Almacén'),
    'pagina',   coalesce((select valor from ajustes where clave = 'pagina'), '{}'::jsonb),
    'reservas', coalesce((select (valor #>> '{}')::boolean from ajustes where clave = 'reservas_abiertas'), true)
                and coalesce((select (valor ->> 'pan')::boolean from ajustes where clave = 'extensiones'), true));
$$;

-- ---------------------------------------------------------------------
-- Restaurar un respaldo descargado desde la app (solo administradora).
-- Agrega lo que falta y no borra ni cambia lo que ya existe. Las cuentas no
-- se restauran: lo hecho por personas que ya no existen queda sin autor.
-- Los productos del catálogo inicial que nunca se usaron y que se llaman igual
-- que uno del respaldo se reemplazan por el del respaldo (caso: proyecto nuevo).
-- ---------------------------------------------------------------------
create or replace function public.restaurar_respaldo(datos jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  t text; arr jsonb; cols text; sel text; n int; res jsonb := '{}'::jsonb;
  orden text[] := array['proveedores','productos','clientes','fiados','ofertas','panes','ajustes','movimientos','cierres','reservas'];
begin
  if not es_admin() then raise exception 'Solo la administradora puede restaurar un respaldo'; end if;
  datos := coalesce(datos->'tablas', datos);
  if jsonb_typeof(datos->'productos') is distinct from 'array' then raise exception 'El archivo no parece un respaldo de la tienda'; end if;
  delete from productos p
  where not exists (select 1 from jsonb_array_elements(datos->'productos') e where (e->>'id')::uuid = p.id)
    and exists (select 1 from jsonb_array_elements(datos->'productos') e where e->>'nombre' = p.nombre)
    and not exists (select 1 from movimientos m where m.producto_id = p.id)
    and not exists (select 1 from ofertas o where o.producto_id = p.id);
  foreach t in array orden loop
    arr := datos->t;
    if jsonb_typeof(arr) is distinct from 'array' or jsonb_array_length(arr) = 0 then continue; end if;
    -- Columnas que trae el respaldo y que existen en la tabla (los respaldos antiguos traen menos)
    select string_agg(quote_ident(c.column_name), ', ' order by c.ordinal_position),
           string_agg(case when c.column_name in ('usuario_id','entregado_por')
                        then format('(select u.id from auth.users u where u.id = r.%I)', c.column_name)
                        else 'r.' || quote_ident(c.column_name) end, ', ' order by c.ordinal_position)
      into cols, sel
    from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = t and arr->0 ? c.column_name;
    if cols is null then continue; end if;
    execute format('insert into public.%I (%s) select %s from jsonb_populate_recordset(null::public.%I, $1) r on conflict do nothing', t, cols, sel, t)
      using arr;
    get diagnostics n = row_count;
    res := res || jsonb_build_object(t, n);
  end loop;
  perform setval(pg_get_serial_sequence('public.panes', 'id'), greatest((select max(id) from panes), 1));
  return res;
end $$;

-- Las funciones internas no se exponen a visitantes sin sesión
revoke execute on function public.nuevo_perfil() from public, anon, authenticated;
revoke execute on function public.cuidar_admins() from public, anon, authenticated;
revoke execute on function public.registrar_venta(jsonb, text, uuid, timestamptz) from public, anon;
revoke execute on function public.registrar_compra(text, jsonb, uuid) from public, anon;
revoke execute on function public.registrar_conteo(jsonb) from public, anon;
revoke execute on function public.revisar_vencimiento(uuid, boolean) from public, anon;
revoke execute on function public.resumen_caja() from public, anon;
revoke execute on function public.registrar_cierre(integer, jsonb, text) from public, anon;
revoke execute on function public.restaurar_respaldo(jsonb) from public, anon;
grant execute on function public.restaurar_respaldo(jsonb) to authenticated;
revoke execute on function public.cambiar_acceso(uuid, text, text) from public, anon;
revoke execute on function public.invitar(text), public.origen_peticion() from public, anon;
grant execute on function public.invitar(text) to authenticated;
grant execute on function public.cambiar_acceso(uuid, text, text) to authenticated;
grant execute on function public.registrar_venta(jsonb, text, uuid, timestamptz), public.registrar_compra(text, jsonb, uuid),
  public.registrar_conteo(jsonb), public.revisar_vencimiento(uuid, boolean), public.resumen_caja(),
  public.registrar_cierre(integer, jsonb, text) to authenticated;
grant execute on function public.hay_admin(), public.info_reservas(), public.info_tienda(), public.hoy_chile(),
  public.crear_reserva(text, text, jsonb, text, text), public.estado_reserva(uuid),
  public.cancelar_reserva(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------
-- Cambios en vivo (Realtime): los celulares de la tienda se actualizan solos
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  foreach t in array array['productos','movimientos','clientes','fiados','reservas','ajustes','perfiles','panes','proveedores','ofertas','cierres'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Datos iniciales (solo si las tablas están vacías)
-- ---------------------------------------------------------------------
insert into public.ajustes (clave, valor) values
  ('tienda_nombre', '"Almacén"'),
  ('mensaje_pan', '"🍞 ¡Llegó el pan calentito! Marraquetas y hallullas recién salidas. Los esperamos en el almacén."'),
  ('reservas_abiertas', 'true'),
  ('reservas_hora_limite', '19')
on conflict (clave) do nothing;

insert into public.panes (nombre, orden)
select x.nombre, x.orden from (values ('Marraqueta',1),('Hallulla',2),('Pan amasado',3),('Dobladitas',4),('Pan integral',5)) x(nombre, orden)
where not exists (select 1 from public.panes);

-- Catálogo típico de almacén (precios de referencia; se ajustan en la app)
insert into public.productos (nombre, sector, precio, costo, minimo)
select x.* from (values
 ('Coca-Cola 1,5 L','Bebidas',1990,1300,6),('Coca-Cola 3 L','Bebidas',2990,2050,6),('Coca-Cola Zero 1,5 L','Bebidas',1990,1300,3),
 ('Sprite 1,5 L','Bebidas',1790,1150,3),('Fanta 1,5 L','Bebidas',1790,1150,3),('Pepsi 1,5 L','Bebidas',1690,1080,3),
 ('Bilz 1,5 L','Bebidas',1590,1000,3),('Pap 1,5 L','Bebidas',1590,1000,3),('Agua mineral sin gas 1,6 L','Bebidas',990,560,6),
 ('Agua mineral con gas 1,6 L','Bebidas',990,560,3),
 ('Jugo en caja naranja 1 L','Jugos',1290,820,6),('Jugo en caja durazno 1 L','Jugos',1290,820,3),('Jugo en caja piña 1 L','Jugos',1290,820,3),
 ('Néctar individual 200 ml','Jugos',450,260,6),('Jugo en polvo sobre','Jugos',150,80,6),
 ('Leche entera 1 L','Lácteos',1150,820,6),('Leche descremada 1 L','Lácteos',1150,820,3),('Yogur batido 125 g','Lácteos',350,210,6),
 ('Mantequilla 250 g','Lácteos',2490,1750,3),('Queso laminado 250 g','Lácteos',2990,2100,3),
 ('Arroz grado 2, 1 kg','Abarrotes',1490,980,6),('Fideos espirales 400 g','Abarrotes',790,480,6),('Fideos spaghetti 400 g','Abarrotes',790,480,6),
 ('Azúcar 1 kg','Abarrotes',1190,820,6),('Harina 1 kg','Abarrotes',1090,720,3),('Sal 1 kg','Abarrotes',490,280,3),
 ('Aceite maravilla 1 L','Abarrotes',2690,1890,6),('Té 20 bolsitas','Abarrotes',990,610,3),('Café instantáneo 170 g','Abarrotes',4990,3500,3),
 ('Pan de molde','Abarrotes',2190,1500,6),
 ('Lentejas 1 kg','Legumbres',1990,1350,3),('Porotos 1 kg','Legumbres',2490,1700,3),('Garbanzos 1 kg','Legumbres',2290,1550,3),
 ('Arvejas partidas 500 g','Legumbres',1190,780,3),
 ('Galletas de agua','Galletas',690,420,6),('Galletas de soda','Galletas',690,420,6),('Galletas rellenas chocolate','Galletas',590,350,6),
 ('Galletas rellenas vainilla','Galletas',590,350,6),('Galletas de vino','Galletas',890,560,3),
 ('Atún lomitos en lata','Conservas',2290,1550,3),('Jurel en lata','Conservas',1990,1300,3),('Choclo en lata','Conservas',1190,760,3),
 ('Salsa de tomate 200 g','Conservas',590,350,6),('Duraznos en almíbar','Conservas',1890,1250,3),
 ('Papas fritas 110 g','Snacks',1490,950,6),('Ramitas 90 g','Snacks',1090,690,3),('Maní salado 100 g','Snacks',990,620,3),
 ('Chocolate 100 g','Snacks',1390,900,6),('Chicle','Snacks',200,110,6),
 ('Papel higiénico 4 rollos','Aseo',2490,1700,3),('Lavaloza 500 ml','Aseo',1490,950,3),('Cloro 1 L','Aseo',990,600,3),
 ('Detergente en polvo 1 kg','Aseo',3490,2400,3),('Jabón de tocador','Aseo',450,270,3)
) x(nombre, sector, precio, costo, minimo)
where not exists (select 1 from public.productos);

-- Pan por unidad (con botón rápido en Vender) y verduras a granel (precio por kilo).
-- Se agregan una vez, también en tiendas que ya tenían el catálogo anterior.
insert into public.productos (nombre, sector, precio, costo, minimo, unidad, atajo)
select x.* from (values
 ('Marraqueta','Pan',250,160,10,'un',true),('Hallulla','Pan',250,160,10,'un',true),('Pan amasado','Pan',400,260,10,'un',true),
 ('Dobladitas','Pan',250,160,10,'un',false),('Pan integral','Pan',300,200,10,'un',false),
 ('Tomate','Verduras',1490,900,2,'kg',false),('Papa','Verduras',990,550,3,'kg',false),('Cebolla','Verduras',990,550,2,'kg',false),
 ('Zanahoria','Verduras',990,550,1,'kg',false),('Palta','Verduras',4990,3500,1,'kg',false),('Limón','Verduras',1990,1200,1,'kg',false),
 ('Plátano','Verduras',1290,800,2,'kg',false),('Lechuga','Verduras',990,600,3,'un',false)
) x(nombre, sector, precio, costo, minimo, unidad, atajo)
where not exists (select 1 from public.productos where sector in ('Pan','Verduras'));

-- El pan se vende por unidad (la primera versión lo tenía por kilo). Se hace una sola vez,
-- para no deshacer cambios que la tienda haga después. Los nombres de las reservas
-- quedan iguales a los productos para que "Tipos de pan" maneje ambos.
do $$
begin
  if not exists (select 1 from public.ajustes where clave = 'pan_por_unidad') then
    update public.productos set unidad = 'un', minimo = 10, conteo_cant = null, conteo_at = null,
      precio = case nombre when 'Pan amasado' then 400 when 'Pan integral' then 300 else 250 end,
      costo  = case nombre when 'Pan amasado' then 260 when 'Pan integral' then 200 else 160 end
    where sector = 'Pan' and unidad = 'kg';
    update public.panes set nombre = 'Marraqueta' where nombre = 'Marraquetas' and not exists (select 1 from public.panes where nombre = 'Marraqueta');
    update public.panes set nombre = 'Hallulla'   where nombre = 'Hallullas'   and not exists (select 1 from public.panes where nombre = 'Hallulla');
    insert into public.ajustes (clave, valor) values ('pan_por_unidad', 'true');
  end if;
end $$;
