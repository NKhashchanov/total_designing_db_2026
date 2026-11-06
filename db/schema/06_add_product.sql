create or replace procedure add_product(
  p_restaurant_id$u uuid,
  p_product_category_id$u uuid,
  p_name$c varchar,
  p_price$n numeric,
  p_description$c text,
  p_status$c product_status default 'доступно',
  p_photo_url$c text default null
)
as $$
begin
  if not exists (select 1 from restaurant where restaurant_id = p_restaurant_id$u) then
    raise exception 'ресторан с id % не существует', p_restaurant_id$u;
  end if;

  if not exists (select 1 from product_category where product_category_id = p_product_category_id$u) then
    raise exception 'категория с id % не существует', p_product_category_id$u;
  end if;

  if p_name$c is null or length(trim(p_name$c)) = 0 then
    raise exception 'название блюда не может быть пустым';
  end if;

  if p_price$n is null or p_price$n < 0 then
    raise exception 'цена блюда не может быть отрицательной';
  end if;

  if p_description$c is null or length(trim(p_description$c)) = 0 then
    raise exception 'описание блюда не может быть пустым';
  end if;

  insert into product (
    product_id,
    product_name,
    product_category_id,
    price,
    restaurant_id,
    photo_url,
    rating,
    status,
    description
  ) values (
    exts.uuid_generate_v4(),
    p_name$c,
    p_product_category_id$u,
    p_price$n,
    p_restaurant_id$u,
    p_photo_url$c,
    null,
    coalesce(p_status$c, 'доступно'),
    p_description$c
  );
end;
$$ language plpgsql;