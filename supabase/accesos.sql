-- Control de acceso de Tumbao (movil/lib/acceso.dart).
--
-- Proyecto de Supabase: rqudigxjjjtscuvmpjrv. Esto ya esta aplicado; el archivo
-- queda para poder rehacerlo. NO lleva claves: la clave que usa la app es la
-- publica («publishable»), y no tiene permiso sobre ninguna tabla.
--
-- Como se maneja (Table Editor de Supabase, sin codigo):
--   dar acceso ........ agregar una fila en `accesos` con el `nombre`; el
--                       `codigo` (XXXX-XXXX-XXXX) se genera solo
--   quitar acceso ..... `activo` en false
--   cambio de telefono  dejar `dispositivo` en blanco
--   quien lo usa ...... columnas `dispositivo` y `ultimo_uso`
--
-- La segunda parte (latido, historial y resumen_accesos) esta en accesos_v2.sql, que
-- tambien reemplaza validar_acceso por una con la version de la app.
--
-- Con los plazos de la app: pasados 7 dias sin validar no se busca ni se baja,
-- pasados 30 no abre. Quitar un codigo surte efecto cuando el telefono tiene red.

-- Codigos de acceso de Tumbao: quien puede usar la app y desde que telefono.
-- Se maneja desde el Table Editor de Supabase; la app solo llama a validar_acceso.

create or replace function public.generar_codigo() returns text
language sql volatile
as $$
  select upper(substr(h, 1, 4) || '-' || substr(h, 5, 4) || '-' || substr(h, 9, 4))
  from (select replace(gen_random_uuid()::text, '-', '') as h) t
$$;

create table if not exists public.accesos (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  codigo text not null unique default public.generar_codigo(),
  activo boolean not null default true,
  dispositivo text,
  creado timestamptz not null default now(),
  ultimo_uso timestamptz
);
comment on table public.accesos is 'Codigos de acceso de Tumbao. activo=false bloquea; dispositivo=null deja usarlo en otro telefono.';

-- Con RLS y sin politicas, nadie lee ni escribe la tabla por la API publica:
-- solo la funcion de abajo (security definer) y el panel de Supabase.
alter table public.accesos enable row level security;

create table if not exists public.intentos_acceso (
  ip text not null,
  cuando timestamptz not null default now()
);
create index if not exists intentos_acceso_ip_cuando on public.intentos_acceso (ip, cuando);
alter table public.intentos_acceso enable row level security;

create or replace function public.validar_acceso(p_codigo text, p_dispositivo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  a public.accesos;
  v_ip text;
  limpio text;
  fallos int;
begin
  v_ip := coalesce(
    nullif(split_part(coalesce((current_setting('request.headers', true)::json)->>'x-forwarded-for', ''), ',', 1), ''),
    '?'
  );
  select count(*) into fallos
    from public.intentos_acceso
    where intentos_acceso.ip = v_ip and cuando > now() - interval '10 minutes';
  if fallos >= 20 then
    return jsonb_build_object('estado', 'espera');
  end if;

  limpio := upper(regexp_replace(coalesce(p_codigo, ''), '[^A-Za-z0-9]', '', 'g'));
  if length(coalesce(p_dispositivo, '')) < 8 or length(p_dispositivo) > 200 then
    return jsonb_build_object('estado', 'no_existe');
  end if;

  select * into a from public.accesos where replace(codigo, '-', '') = limpio for update;
  if not found then
    insert into public.intentos_acceso (ip) values (v_ip);
    delete from public.intentos_acceso where cuando < now() - interval '1 day';
    return jsonb_build_object('estado', 'no_existe');
  end if;

  if not a.activo then
    return jsonb_build_object('estado', 'desactivado');
  end if;

  if a.dispositivo is null then
    update public.accesos set dispositivo = p_dispositivo where id = a.id;
  elsif a.dispositivo <> p_dispositivo then
    return jsonb_build_object('estado', 'otro_telefono');
  end if;

  update public.accesos set ultimo_uso = now() where id = a.id;
  return jsonb_build_object('estado', 'ok', 'nombre', a.nombre);
end;
$$;

revoke all on function public.validar_acceso(text, text) from public;
grant execute on function public.validar_acceso(text, text) to anon, authenticated;
revoke all on function public.generar_codigo() from public;

-- Defensa doble: la clave publica no tiene ningun permiso sobre las tablas.
revoke all on public.accesos from anon, authenticated;
revoke all on public.intentos_acceso from anon, authenticated;
