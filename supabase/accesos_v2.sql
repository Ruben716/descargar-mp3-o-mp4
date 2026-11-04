-- Segunda parte del control de acceso (ver accesos.sql): el latido que evita que
-- Supabase pause el proyecto y el historial de uso de cada codigo.
-- Tampoco lleva claves. Ya esta aplicado en el proyecto rqudigxjjjtscuvmpjrv.

-- Que las tablas nuevas nazcan sin permisos para la clave publica.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated, public;

-- El latido: un proyecto gratis se pausa tras una semana sin actividad. Un flujo
-- de GitHub (mantener-supabase.yml) llama a latido() cada dia y esto escribe
-- de verdad en la base, para que cuente como actividad.
create table if not exists public.latido_servicio (
  id int primary key default 1 check (id = 1),
  ultimo timestamptz not null default now(),
  veces bigint not null default 0
);
insert into public.latido_servicio (id) values (1) on conflict do nothing;
alter table public.latido_servicio enable row level security;
revoke all on public.latido_servicio from anon, authenticated;

create or replace function public.latido() returns jsonb
language plpgsql security definer set search_path = public
as $$
begin
  update public.latido_servicio set ultimo = now(), veces = veces + 1 where id = 1;
  return jsonb_build_object('ok', true, 'cuando', now());
end;
$$;
revoke all on function public.latido() from public;
grant execute on function public.latido() to anon, authenticated;

-- El historial: cada validacion de un codigo que existe. Se guardan 90 dias.
create table if not exists public.uso_codigos (
  id bigint generated always as identity primary key,
  acceso_id uuid not null references public.accesos (id) on delete cascade,
  cuando timestamptz not null default now(),
  resultado text not null,
  version_app text,
  ip text
);
create index if not exists uso_codigos_acceso_cuando on public.uso_codigos (acceso_id, cuando desc);
alter table public.uso_codigos enable row level security;
revoke all on public.uso_codigos from anon, authenticated;

-- La funcion nueva recibe tambien la version de la app (opcional: las apps
-- anteriores siguen llamando con dos datos).
drop function if exists public.validar_acceso(text, text);

create or replace function public.validar_acceso(p_codigo text, p_dispositivo text, p_version text default null)
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
  v_version text;
  v_resultado text;
begin
  v_ip := coalesce(
    nullif(split_part(coalesce((current_setting('request.headers', true)::json)->>'x-forwarded-for', ''), ',', 1), ''),
    '?'
  );
  v_version := left(nullif(trim(coalesce(p_version, '')), ''), 30);

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
    v_resultado := 'desactivado';
  elsif a.dispositivo is null then
    update public.accesos set dispositivo = p_dispositivo where id = a.id;
    v_resultado := 'ok';
  elsif a.dispositivo <> p_dispositivo then
    v_resultado := 'otro_telefono';
  else
    v_resultado := 'ok';
  end if;

  insert into public.uso_codigos (acceso_id, resultado, version_app, ip)
    values (a.id, v_resultado, v_version, v_ip);
  delete from public.uso_codigos where cuando < now() - interval '90 days';

  if v_resultado = 'ok' then
    update public.accesos set ultimo_uso = now() where id = a.id;
    return jsonb_build_object('estado', 'ok', 'nombre', a.nombre);
  end if;
  return jsonb_build_object('estado', v_resultado);
end;
$$;

revoke all on function public.validar_acceso(text, text, text) from public;
grant execute on function public.validar_acceso(text, text, text) to anon, authenticated;

-- Para mirar desde el Table Editor: como se usa cada codigo. «redes_7d» son las
-- IP distintas de los ultimos 7 dias: con datos moviles cambia sola, asi que es
-- una pista y no una prueba; muchas (mas de 6) suelen ser un codigo compartido.
create or replace view public.resumen_accesos as
select
  a.nombre,
  a.codigo,
  a.activo,
  a.dispositivo is not null as con_telefono,
  a.ultimo_uso,
  (select count(*) from public.uso_codigos u where u.acceso_id = a.id and u.cuando > now() - interval '7 days') as usos_7d,
  (select count(distinct u.ip) from public.uso_codigos u where u.acceso_id = a.id and u.cuando > now() - interval '7 days') as redes_7d,
  (select count(*) from public.uso_codigos u
     where u.acceso_id = a.id and u.cuando > now() - interval '7 days' and u.resultado = 'otro_telefono') as rechazos_otro_telefono_7d,
  (select u.version_app from public.uso_codigos u where u.acceso_id = a.id order by u.cuando desc limit 1) as version_app
from public.accesos a
order by a.ultimo_uso desc nulls last;
revoke all on public.resumen_accesos from anon, authenticated;
