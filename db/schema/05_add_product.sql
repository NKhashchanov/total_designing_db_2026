-- FOOD-104: добавление блюда в меню ресторана.
set search_path to mineev_food, pg_catalog;
create procedure add_product(
    p_restaurant_id uuid,
    p_product_category_id uuid,
    p_name varchar,
    p_price numeric,
    p_rating numeric,
    p_status product_status,
    p_description text,
    p_photo_url text default null
)
language plpgsql set search_path to mineev_food, pg_catalog as $$
begin
    if not exists (select 1 from restaurant where restaurant_id = p_restaurant_id) then
        raise exception 'Ресторан % не существует', p_restaurant_id using errcode = '23503';
    end if;
    if not exists (select 1 from product_category where product_category_id = p_product_category_id) then
        raise exception 'Категория % не существует', p_product_category_id using errcode = '23503';
    end if;
    if p_price is null or p_price < 0 or p_price = 'NaN'::numeric then
        raise exception 'Цена должна быть неотрицательным числом' using errcode = '23514';
    end if;
    if p_rating is not null and not (p_rating between 0 and 5) then
        raise exception 'Рейтинг должен быть от 0 до 5' using errcode = '23514';
    end if;
    -- Начальный рейтинг не сохраняется: без отзывов он равен NULL (BR-9.7).
    if p_rating is not null then
        raise notice 'Начальный рейтинг % не сохраняется: у нового блюда нет отзывов', p_rating;
    end if;
    insert into product(product_name, product_category_id, price, restaurant_id, photo_url, rating, status, description)
    values (p_name, p_product_category_id, p_price, p_restaurant_id, p_photo_url, null, p_status, p_description);
end $$;
