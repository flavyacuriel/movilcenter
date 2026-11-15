-- =====================================================================
--  Actualización 28 · Comprobante solo en Binance y categoría "Consolas"
--  1. Pago móvil y transferencia: basta con la referencia (la captura es
--     opcional). Binance sigue pidiendo la captura del pago.
--  2. La categoría "Accesorios" pasa a llamarse "Consolas".
--  Ejecutar DESPUÉS de 27. Se puede ejecutar más de una vez.
-- =====================================================================

-- 1. Binance siempre con captura (la página ya lo pide; esto lo asegura)
create or replace function public._binance_con_comprobante() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.metodo = 'usdt' and nullif(trim(coalesce(new.comprobante_path, '')), '') is null then
    raise exception 'Para pagos por Binance adjunta la captura del pago.';
  end if;
  return new;
end $$;
drop trigger if exists binance_con_comprobante on public.pagos;
create trigger binance_con_comprobante before insert on public.pagos
  for each row execute function public._binance_con_comprobante();
revoke execute on function public._binance_con_comprobante() from public, anon, authenticated;

-- 2. Categoría Consolas
update public.productos set categoria = 'Consolas', forma = 'console' where categoria = 'Accesorios';

create or replace function public.guardar_producto(p jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare v_id int := nullif(p->>'id', '')::int; t int; v_cat text := p->>'categoria';
begin
  if v_id is not null then select tienda_id into t from productos where id = v_id;
  else t := coalesce(mi_tienda_admin(), nullif(p->>'tienda_id', '')::int); end if;
  if t is null then raise exception 'Elige la tienda del producto.'; end if;
  perform _requiere_admin_de(t);
  if length(trim(coalesce(p->>'nombre', ''))) < 2 then raise exception 'Escribe el nombre del producto.'; end if;
  if v_cat not in ('Teléfonos','Tablets','Smartwatch','Audio','Consolas') then raise exception 'Elige la categoría.'; end if;
  if coalesce((p->>'precio')::numeric, -1) < 0 then raise exception 'Escribe un precio válido.'; end if;
  if v_id is null then
    insert into productos(tienda_id, marca, nombre, categoria, forma, precio, stock, colores, capacidades, specs, descripcion, imagen_url, financiable, activo, orden)
    values (t, left(trim(coalesce(p->>'marca', '')), 40), left(trim(p->>'nombre'), 80), v_cat,
            case v_cat when 'Tablets' then 'tablet' when 'Smartwatch' then 'watch' when 'Audio' then 'buds' when 'Consolas' then 'console' else 'phone' end,
            (p->>'precio')::numeric, greatest(0, coalesce((p->>'stock')::int, 0)),
            coalesce(p->'colores', '[{"n":"Único","hex":"#777777"}]'), nullif(p->'capacidades', '[]'::jsonb), coalesce(p->'specs', '{}'),
            left(coalesce(p->>'descripcion', ''), 600), nullif(trim(coalesce(p->>'imagen_url', '')), ''),
            coalesce((p->>'financiable')::boolean, true), coalesce((p->>'activo')::boolean, true), coalesce((p->>'orden')::int, 100))
    returning id into v_id;
    perform _log(format('Producto creado: %s', trim(p->>'nombre')));
  else
    update productos set marca = left(trim(coalesce(p->>'marca', marca)), 40), nombre = left(trim(p->>'nombre'), 80), categoria = v_cat,
           precio = (p->>'precio')::numeric, colores = coalesce(p->'colores', colores), capacidades = case when p ? 'capacidades' then nullif(p->'capacidades', '[]'::jsonb) else capacidades end,
           specs = coalesce(p->'specs', specs), descripcion = left(coalesce(p->>'descripcion', descripcion), 600),
           imagen_url = case when p ? 'imagen_url' then nullif(trim(p->>'imagen_url'), '') else imagen_url end,
           financiable = coalesce((p->>'financiable')::boolean, financiable), activo = coalesce((p->>'activo')::boolean, activo),
           orden = coalesce((p->>'orden')::int, orden)
     where id = v_id;
    perform _log(format('Producto editado: %s', trim(p->>'nombre')));
  end if;
  return v_id;
end $$;
revoke execute on function public.guardar_producto(jsonb) from public, anon;
grant execute on function public.guardar_producto(jsonb) to authenticated;
