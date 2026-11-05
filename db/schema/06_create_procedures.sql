create or replace procedure add_product(
  p_restaurant_id uuid,
  p_product_category_id uuid,
  p_name varchar,
  p_price numeric,
  p_description text,
  p_status product_status default 'доступно',
  p_photo_url text default null
)
as $$
begin
  if not exists (select 1 from restaurant where restaurant_id = p_restaurant_id) then
    raise exception 'ресторан с id % не существует', p_restaurant_id;
  end if;

  if not exists (select 1 from product_category where product_category_id = p_product_category_id) then
    raise exception 'категория с id % не существует', p_product_category_id;
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'название блюда не может быть пустым';
  end if;

  if p_price is null or p_price < 0 then
    raise exception 'цена блюда не может быть отрицательной';
  end if;

  if p_description is null or length(trim(p_description)) = 0 then
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
    p_name,
    p_product_category_id,
    p_price,
    p_restaurant_id,
    p_photo_url,
    p_rating,
    coalesce(p_status, 'доступно'),
    p_description
  );
end;
$$ language plpgsql;