-- FOOD-101, FOOD-105. Межтабличная целостность и агрегаты.
set search_path to mineev_food, pg_catalog;

-- Фиксируем цену позиции и проверяем принадлежность блюда ресторану заказа.
create function check_order_position() returns trigger
language plpgsql set search_path to mineev_food, pg_catalog as $$
declare
    v_order_restaurant uuid;
    v_product_restaurant uuid;
    v_price numeric;
begin
    select restaurant_id into v_order_restaurant from "order"
    where order_id = new.order_id for no key update;
    select restaurant_id, price into v_product_restaurant, v_price from product
    where product_id = new.product_id for share;
    if v_order_restaurant is distinct from v_product_restaurant then
        raise exception 'Блюдо должно принадлежать ресторану заказа' using errcode = '23514';
    end if;
    if new.unit_price is null then
        new.unit_price := v_price;
    end if;
    return new;
end $$;
-- Проверяем позицию до ее записи.
create trigger order_position_check before insert or update on order_structure
for each row execute function check_order_position();

-- Запрещаем смену ресторана блюда, если оно уже входит в заказ.
create function guard_product_restaurant() returns trigger
language plpgsql set search_path to mineev_food, pg_catalog as $$
begin
    if new.restaurant_id is distinct from old.restaurant_id and exists (
        select 1 from order_structure os where os.product_id = old.product_id
    ) then
        raise exception 'Нельзя сменить ресторан у блюда из истории заказов' using errcode = '23514';
    end if;
    return new;
end $$;
-- Проверяем изменение ресторана до обновления блюда.
create trigger product_restaurant_guard before update of restaurant_id on product
for each row execute function guard_product_restaurant();

-- Отложенная проверка состава и суммы заказа на момент завершения транзакции.
create function validate_order(p_id uuid) returns void
language plpgsql set search_path to mineev_food, pg_catalog as $$
declare
    v_order "order"%rowtype;
    v_sum numeric;
    v_status order_pay_status;
begin
    select * into v_order from "order" where order_id = p_id;
    if not found then return; end if;
    select round(sum(quantity * unit_price), 2) into v_sum
    from order_structure where order_id = p_id;
    if v_sum is null or v_sum <> v_order.order_amount then
        raise exception 'Заказ % должен иметь позиции на сумму order_amount', p_id using errcode = '23514';
    end if;
    if exists (select 1 from order_structure os join product p using (product_id)
               where os.order_id = p_id and p.restaurant_id <> v_order.restaurant_id) then
        raise exception 'Позиции заказа % относятся к другому ресторану', p_id using errcode = '23514';
    end if;
    if exists (select 1 from payment p where p.order_id = p_id and p.amount <> v_order.total_amount) then
        raise exception 'Сумма платежа не совпадает с total_amount заказа %', p_id using errcode = '23514';
    end if;
    select case when count(*) filter (where status = 'успех') > 0 then 'оплачен'::order_pay_status
                when count(*) = 0 or count(*) filter (where status = 'в_обработке') > 0 then 'ожидает'::order_pay_status
                else 'ошибка'::order_pay_status end into v_status
    from payment where order_id = p_id;
    if v_order.pay_status <> v_status then
        raise exception 'Некорректный pay_status заказа %', p_id using errcode = '23514';
    end if;
    if exists (select 1 from review r where r.order_id = p_id and (
        (r.entity_type = 'заказ' and r.entity_id <> p_id)
        or (r.entity_type = 'ресторан' and r.entity_id <> v_order.restaurant_id)
        or (r.entity_type = 'блюдо' and not exists (
            select 1 from order_structure os where os.order_id = p_id and os.product_id = r.entity_id)))) then
        raise exception 'Изменение заказа % нарушает связь с отзывом', p_id using errcode = '23514';
    end if;
end $$;

-- Проверяем затронутые заказы, включая прежний заказ при переносе позиции.
create function check_order_final() returns trigger
language plpgsql set search_path to mineev_food, pg_catalog as $$
begin
    if tg_op <> 'DELETE' then perform validate_order(new.order_id); end if;
    if tg_op = 'DELETE' then
        perform validate_order(old.order_id);
    elsif tg_op = 'UPDATE' then
        if old.order_id <> new.order_id then perform validate_order(old.order_id); end if;
    end if;
    return null;
end $$;
-- Проверяем итоговое состояние при изменении заголовка заказа.
create constraint trigger order_final_check after insert or update on "order"
deferrable initially deferred for each row execute function check_order_final();
-- Проверяем состав заказа после добавления, изменения или удаления позиций.
create constraint trigger order_structure_final_check after insert or update or delete on order_structure
deferrable initially deferred for each row execute function check_order_final();

-- Блокируем строку заказа при изменении платежа; проверяем сумму до записи.
create function check_payment_amount() returns trigger
language plpgsql set search_path to mineev_food, pg_catalog as $$
declare v_total numeric;
begin
    select total_amount into v_total from "order" where order_id = new.order_id for no key update;
    if new.amount is distinct from v_total then
        raise exception 'Сумма платежа должна совпадать с total_amount заказа' using errcode = '23514';
    end if;
    return new;
end $$;
-- Проверяем сумму до добавления или изменения платежа.
create trigger payment_amount_check before insert or update on payment
for each row execute function check_payment_amount();

-- Вычисляем итоговый статус оплаты по всем попыткам заказа.
create function refresh_pay_status(p_id uuid) returns void
language plpgsql set search_path to mineev_food, pg_catalog as $$
declare v_status order_pay_status;
begin
    perform 1 from "order" where order_id = p_id for no key update;
    if not found then return; end if;
    select case when count(*) filter (where status = 'успех') > 0 then 'оплачен'::order_pay_status
                when count(*) = 0 or count(*) filter (where status = 'в_обработке') > 0 then 'ожидает'::order_pay_status
                else 'ошибка'::order_pay_status end into v_status
    from payment where order_id = p_id;
    update "order" set pay_status = v_status where order_id = p_id and pay_status is distinct from v_status;
end $$;
-- Обновляем статус затронутых заказов после изменения платежа.
create function payment_change() returns trigger
language plpgsql set search_path to mineev_food, pg_catalog as $$
begin
    if tg_op <> 'DELETE' then perform refresh_pay_status(new.order_id); end if;
    if tg_op = 'DELETE' then
        perform refresh_pay_status(old.order_id);
    elsif tg_op = 'UPDATE' then
        if old.order_id <> new.order_id then perform refresh_pay_status(old.order_id); end if;
    end if;
    return null;
end $$;
-- Синхронизируем статус заказа при любом изменении платежей.
create trigger payment_status_change after insert or update or delete on payment
for each row execute function payment_change();

-- Проверяем автора отзыва и принадлежность объекта указанному заказу.
create function check_review_object() returns trigger
language plpgsql set search_path to mineev_food, pg_catalog as $$
declare v_order "order"%rowtype;
begin
    select * into v_order from "order" where order_id = new.order_id for no key update;
    if not found or v_order.client_id <> new.client_id then
        raise exception 'Отзыв должен принадлежать клиенту заказа' using errcode = '23514';
    end if;
    case new.entity_type
        when 'заказ' then
            if new.entity_id <> new.order_id then
                raise exception 'Отзыв должен относиться к указанному заказу' using errcode = '23514';
            end if;
        when 'ресторан' then
            if new.entity_id <> v_order.restaurant_id then
                raise exception 'Отзыв должен относиться к ресторану заказа' using errcode = '23514';
            end if;
        when 'блюдо' then
            if not exists (select 1 from order_structure where order_id = new.order_id and product_id = new.entity_id) then
                raise exception 'Отзыв должен относиться к блюду из заказа' using errcode = '23514';
            end if;
    end case;
    return new;
end $$;
-- Проверяем связи отзыва до его записи.
create trigger review_object_check before insert or update on review
for each row execute function check_review_object();

-- Защита агрегатов от прямой записи несогласованного рейтинга.
create function check_aggregate_rating() returns trigger
language plpgsql set search_path to mineev_food, pg_catalog as $$
declare v_expected numeric; v_id uuid; v_type review_entity_type;
begin
    if tg_table_name = 'product' then
        v_id := new.product_id; v_type := 'блюдо';
    else
        v_id := new.restaurant_id; v_type := 'ресторан';
    end if;
    select round(avg(rating), 2) into v_expected from review where entity_type = v_type and entity_id = v_id;
    if new.rating is distinct from v_expected then
        raise exception 'Рейтинг вычисляется по отзывам, ожидается %', v_expected using errcode = '23514';
    end if;
    return new;
end $$;
-- Запрещаем запись рейтинга блюда, не соответствующего отзывам.
create trigger product_rating_check before insert or update of rating on product
for each row execute function check_aggregate_rating();
-- Запрещаем запись рейтинга ресторана, не соответствующего отзывам.
create trigger restaurant_rating_check before insert or update of rating on restaurant
for each row execute function check_aggregate_rating();

-- Пересчитываем среднюю оценку блюда или ресторана по отзывам.
create function refresh_rating(p_type review_entity_type, p_id uuid) returns void
language plpgsql set search_path to mineev_food, pg_catalog as $$
declare v_rating numeric;
begin
    -- Блокируем строку объекта перед чтением среднего, чтобы избежать потерянного обновления.
    if p_type = 'блюдо' then
        perform 1 from product where product_id = p_id for no key update;
    elsif p_type = 'ресторан' then
        perform 1 from restaurant where restaurant_id = p_id for no key update;
    else return;
    end if;
    if not found then return; end if;
    select round(avg(rating), 2) into v_rating from review where entity_type = p_type and entity_id = p_id;
    if p_type = 'блюдо' then
        update product set rating = v_rating where product_id = p_id;
    else
        update restaurant set rating = v_rating where restaurant_id = p_id;
    end if;
end $$;
-- Пересчитываем рейтинги затронутых объектов, включая прежний объект отзыва.
create function rating_change() returns trigger
language plpgsql set search_path to mineev_food, pg_catalog as $$
begin
    if tg_op = 'DELETE' then
        perform refresh_rating(old.entity_type, old.entity_id);
    elsif tg_op = 'INSERT' then
        perform refresh_rating(new.entity_type, new.entity_id);
    else
        if (old.entity_type, old.entity_id) is distinct from (new.entity_type, new.entity_id) then
            perform refresh_rating(old.entity_type, old.entity_id);
        end if;
        perform refresh_rating(new.entity_type, new.entity_id);
    end if;
    return null;
end $$;
-- Обновляем рейтинг после добавления, изменения или удаления отзыва.
create trigger review_rating_change after insert or update or delete on review
for each row execute function rating_change();
