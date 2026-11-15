-- FOOD-102. Каждая новая порция добавляется независимо, без удаления старых данных.
set search_path to mineev_food, pg_catalog;
create procedure insert_test_data(value integer)
language plpgsql set search_path to mineev_food, pg_catalog as $$
declare
    v_clients uuid[] := '{}'; v_couriers uuid[] := '{}'; v_categories uuid[] := '{}';
    v_restaurants uuid[] := '{}'; v_addresses uuid[] := '{}'; v_products uuid[] := '{}';
    v_prices numeric[] := '{}';
    v_client uuid; v_courier uuid; v_category uuid; v_restaurant uuid; v_address uuid;
    v_product uuid; v_order uuid; v_entity uuid;
    v_token text := exts.uuid_generate_v4()::text;
    v_phone text; v_status courier_status; v_order_status order_status;
    v_payment_status payment_status; v_review_type review_entity_type;
    v_price numeric; v_quantity numeric; v_sum numeric; v_commission numeric;
    v_order_time timestamp; v_delivery_time timestamp;
    v_now timestamp := localtimestamp;
    v_month date := date_trunc('month', localtimestamp)::date;
    v_earliest timestamp := greatest(v_now - interval '6 months', v_now - interval '180 days');
    v_start timestamp; v_stop timestamp;
    i integer; j integer; k integer; m integer; v_index integer;
begin
    if value is null or value < 1 then
        raise exception 'value должно быть положительным целым числом' using errcode = '22023';
    end if;
    -- Параллельные генераторы не конкурируют за уникальные телефоны.
    lock table client in share row exclusive mode;
    -- Создаем клиентов, курьеров, категории, рестораны и адреса новой порции.
    -- Сохраняем идентификаторы для дальнейшего связывания записей.
    for i in 1..value loop
        loop
            v_phone := '+7' || lpad(floor(random()*10000000000)::bigint::text, 10, '0');
            exit when not exists (select 1 from client where phone_number = v_phone);
        end loop;
        insert into client(login, password, phone_number)
        values ('client_' || v_token || '_' || i, md5(random()::text), v_phone)
        returning client_id into v_client;
        v_clients := array_append(v_clients, v_client);

        v_status := (enum_range(null::courier_status))[case when i = 1 then 1 else 1 + (i - 1) % 4 end];
        insert into courier(fio, phone_number, status, hire_date, dismissal_date, coefficient)
        values ((array['Иванов Иван Иванович','Петров Петр Сергеевич','Сидоров Алексей Андреевич','Смирнова Анна Олеговна'])[1+(i-1)%4],
                '+7' || lpad(floor(random()*10000000000)::bigint::text, 10, '0'),
                v_status, v_earliest::date, case when v_status = 'уволен' then current_date end, 0.1)
        returning courier_id into v_courier;
        v_couriers := array_append(v_couriers, v_courier);

        insert into product_category(product_category_name)
        values ((array['Пицца','Салаты','Горячие блюда','Десерты','Напитки'])[1+(i-1)%5] || ' ' || left(v_token, 8) || '-' || i)
        returning product_category_id into v_category;
        v_categories := array_append(v_categories, v_category);

        insert into address(street, house_number, apartment_office)
        values ('Ресторанная ' || v_token, i::text, null) returning address_id into v_address;
        insert into restaurant(restaurant_name, address_id, description, work_start, work_end, company_details, status)
        values ('Ресторан ' || left(v_token, 8) || '-' || i, v_address, 'Тестовый ресторан', time '09:00', time '23:00',
                'Тестовые реквизиты ' || i, (enum_range(null::restaurant_status))[1+(i-1)%2])
        returning restaurant_id into v_restaurant;
        v_restaurants := array_append(v_restaurants, v_restaurant);

        for j in 1..4 loop
            insert into address(street, house_number, apartment_office)
            values ('Жилая ' || v_token, i::text, j::text) returning address_id into v_address;
            v_addresses := array_append(v_addresses, v_address);
            insert into client_address values (v_client, v_address);
        end loop;
    end loop;

    -- У каждого ресторана пять блюд; категория берется из этой же порции.
    for i in 1..value loop
        for j in 1..5 loop
            v_price := 500 + floor(random()*401)::int;
            insert into product(product_name, product_category_id, price, restaurant_id, status, description)
            values ((array['Пицца','Салат','Паста','Суп','Десерт'])[j] || ' ' || i,
                    v_categories[1+(i+j-2)%value], v_price, v_restaurants[i],
                    (enum_range(null::product_status))[case when j <= 3 then 1 else j-2 end], 'Тестовое блюдо')
            returning product_id into v_product;
            v_products := array_append(v_products, v_product);
            v_prices := array_append(v_prices, v_price);
        end loop;
    end loop;

    -- Пять заказов на ресторан. В каждом две позиции; все связи берутся из массивов.
    for i in 1..value loop
        for j in 1..5 loop
            k := (i-1)*5 + j;
            -- Выбираем клиента, его адрес и блюда нужного ресторана.
            v_client := v_clients[1+(i+j-2)%value];
            v_courier := v_couriers[1+(i+j-2)%value];
            v_restaurant := v_restaurants[i];
            v_address := v_addresses[((1+(i+j-2)%value)-1)*4 + 1+(j-1)%4];
            v_product := v_products[(i-1)*5+1+(j-1)%3];
            v_index := (i-1)*5+1+j%3;
            v_quantity := case when j%2 = 0 then 1.5 else 2 end;
            v_sum := round(v_prices[(i-1)*5+1+(j-1)%3]*v_quantity + v_prices[v_index], 2);
            v_commission := round(v_sum*0.10, 2);
            v_order_status := (enum_range(null::order_status))[j];
            -- Один доставленный заказ на ресторан. Для первого ресторана — текущий месяц;
            -- прочие месяцы распределяются циклически, сохраняя диапазон последних 180 дней.
            m := case when j = 4 and i = 1 then 0 else (i+j-2)%6 end;
            v_start := greatest(v_earliest, v_month - m*interval '1 month');
            v_stop := least(v_now, v_month + (1-m)*interval '1 month');
            v_order_time := v_start + (v_stop-v_start)*(0.15+random()*0.55);
            v_delivery_time := case when v_order_status = 'доставлен'
                               then least(v_order_time + interval '40 minutes', v_stop) end;
            -- Записываем заказ и его позиции с согласованными суммами.
            insert into "order"(courier_id, client_id, address_id, restaurant_id, order_timestamp, delivery_timestamp,
                                order_amount, commission, total_amount, status, description)
            values (v_courier, v_client, v_address, v_restaurant, v_order_time, v_delivery_time,
                    v_sum, v_commission, v_sum+v_commission, v_order_status, 'Тестовый заказ ' || k)
            returning order_id into v_order;
            insert into order_structure(order_id, product_id, quantity, unit_price)
            values (v_order, v_product, v_quantity, v_prices[(i-1)*5+1+(j-1)%3]),
                   (v_order, v_products[v_index], 1, v_prices[v_index]);

            -- Формируем попытку оплаты с учетом этапа обработки заказа.
            v_payment_status := (enum_range(null::payment_status))[case when j in (2,3,4) then 1 when j=5 then 2 else 3 end];
            insert into payment(order_id, payment_type, amount, transaction_id, transaction_timestamp, status)
            values (v_order, (enum_range(null::payment_type))[1+(j-1)%3], v_sum+v_commission,
                    exts.uuid_generate_v4(), v_order_time, v_payment_status);

            -- Создаем отзыв на объект, связанный с этим заказом.
            v_review_type := (enum_range(null::review_entity_type))[1+(j-1)%3];
            v_entity := case v_review_type when 'блюдо' then v_product when 'ресторан' then v_restaurant else v_order end;
            insert into review(client_id, review_timestamp, entity_id, entity_type, order_id, description, rating)
            values (v_client, coalesce(v_delivery_time,v_order_time), v_entity, v_review_type, v_order, 'Тестовый отзыв', 1+floor(random()*5)::int);
        end loop;
    end loop;

    -- Шесть завершенных календарных месяцев, в хронологическом порядке.
    -- Даже месяц без доставок имеет строку с нулевой выплатой.
    for m in reverse 6..1 loop
        call calculate_courier_month((v_month-m*interval '1 month')::date, v_couriers);
    end loop;
end $$;
