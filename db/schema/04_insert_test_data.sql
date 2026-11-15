-- FOOD-102 insert_test_data(value)
-- можно вызывать сколько угодно раз подряд, каждый вызов добавляет новую порцию данных

SET search_path TO bokareva_food, exts;

CREATE OR REPLACE PROCEDURE bokareva_food.insert_test_data(value int)
LANGUAGE plpgsql
SET search_path = bokareva_food, exts
AS $$
DECLARE
    c_alphabet constant text := 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя';
    c_pool_len constant int  := 10000;
    v_pool     text;

    v_window_start date := date_trunc('month', current_date - interval '5 months')::date;

    v_category_ids   uuid[]      := '{}';
    v_courier_ids    uuid[]      := '{}';
    v_courier_hire   date[]      := '{}';
    v_courier_fire   date[]      := '{}';
    v_address_ids    uuid[]      := '{}';
    v_restaurant_ids uuid[]      := '{}';
    v_active_rests   int[]       := '{}';   -- номера активных ресторанов, заказы только в них
    v_client_ids     uuid[]      := '{}';
    v_product_ids    uuid[]      := '{}';
    v_product_prices numeric[]   := '{}';
    v_product_avail  boolean[]   := '{}';
    v_order_ids      uuid[]      := '{}';
    v_order_clients  uuid[]      := '{}';
    v_order_done_ts  timestamp[] := '{}';

    -- всё, на что можно оставить отзыв (BR-9.2, BR-9.5): номер заказа, тип, id объекта.
    -- каждая тройка встречается один раз, поэтому дублей отзывов не бывает
    v_t_order    int[]                := '{}';
    v_t_type     review_entity_type[] := '{}';
    v_t_entity   uuid[]               := '{}';
    v_t_shuffled int[];

    v_id        uuid;
    v_total     numeric;
    v_str       text;
    v_str2      text;
    v_str3      text;
    v_is_org    boolean;
    v_status    courier_status;
    v_rstatus   restaurant_status;
    v_prstatus  product_status;
    v_ostatus   order_status;
    v_pstatus   payment_status;
    v_paystatus order_pay_status;
    v_hire      date;
    v_fire      date;
    v_ws        time;
    v_lo        timestamp;
    v_hi        timestamp;
    v_ts        timestamp;
    v_dts       timestamp;
    v_c int; v_r int; v_k int; v_n int; v_off int;
    v_avail     int[];
    v_items     int[];
    v_qty       numeric[];
    v_amount    numeric;
    v_month     date;
    v_cnt       bigint[];
    v_comm      numeric[];
    v_coef      numeric[];
    i int; j int; k int;
BEGIN
    -- пул случайных букв, из него режутся все строковые значения
    SELECT string_agg(substr(c_alphabet, 1 + floor(random() * length(c_alphabet))::int, 1), '')
    INTO v_pool
    FROM generate_series(1, c_pool_len);


    -- категории, varchar(50), уникальное название
    FOR i IN 1 .. value LOOP
        LOOP
            v_str := substr(v_pool, 1 + floor(random() * (c_pool_len - 50))::int, 1 + floor(random() * 50)::int);
            EXIT WHEN NOT EXISTS (SELECT 1 FROM product_category WHERE product_category_name = v_str);
        END LOOP;

        INSERT INTO product_category (product_category_id, product_category_name)
        VALUES (exts.uuid_generate_v4(), v_str)
        RETURNING product_category_id INTO v_id;
        v_category_ids := v_category_ids || v_id;
    END LOOP;


    -- курьеры. первый всегда работает - нужен хотя бы один активный (BR-6.6)
    FOR i IN 1 .. value LOOP
        v_status := CASE WHEN i = 1 THEN 'свободен'::courier_status
                         ELSE (enum_range(NULL::courier_status))
                              [1 + floor(random() * cardinality(enum_range(NULL::courier_status)))::int]
                    END;
        -- наняли не позже вчера: заказы курьера генерируются с 08:00 дня найма до (сейчас - 2 часа),
        -- при найме сегодня этот интервал может оказаться пустым и заказ попал бы раньше найма
        v_hire := v_window_start + floor(random() * ((current_date - 1) - v_window_start + 1))::int;
        -- уволить можно только после найма (courier_dismissal_after_hire_chk)
        v_fire := CASE WHEN v_status = 'уволен'
                       THEN v_hire + floor(random() * (current_date - v_hire + 1))::int
                  END;

        INSERT INTO courier (courier_id, last_name, first_name, patronymic, phone_number,
                             status, hire_date, dismissal_date, coefficient)
        VALUES (exts.uuid_generate_v4(),
                substr(v_pool, 1 + floor(random() * (c_pool_len - 50))::int, 1 + floor(random() * 50)::int),
                substr(v_pool, 1 + floor(random() * (c_pool_len - 50))::int, 1 + floor(random() * 50)::int),
                CASE WHEN random() < 0.1 THEN NULL      -- отчества может не быть
                     ELSE substr(v_pool, 1 + floor(random() * (c_pool_len - 50))::int, 1 + floor(random() * 50)::int)
                END,
                '+7' || lpad(floor(random() * 1e10)::bigint::text, 10, '0'),
                v_status, v_hire, v_fire,
                0.1)                                    -- стартовый, BR-6.5; итоговый поставлю в конце
        RETURNING courier_id INTO v_id;

        v_courier_ids  := v_courier_ids  || v_id;
        v_courier_hire := v_courier_hire || v_hire;
        v_courier_fire := v_courier_fire || v_fire;
    END LOOP;


    -- адреса: первые value - под рестораны, остальные value*4 - под клиентов (BR-11.7).
    -- один физический адрес - одна строка (address_physical_uq)
    FOR i IN 1 .. value * 5 LOOP
        LOOP
            v_str  := substr(v_pool, 1 + floor(random() * (c_pool_len - 100))::int, 1 + floor(random() * 100)::int);
            v_str2 := substr(v_pool, 1 + floor(random() * (c_pool_len - 10))::int,  1 + floor(random() * 10)::int);
            v_str3 := CASE WHEN random() < 0.4 THEN NULL   -- частный дом, BR-3.2
                           ELSE substr(v_pool, 1 + floor(random() * (c_pool_len - 10))::int, 1 + floor(random() * 10)::int)
                      END;
            EXIT WHEN NOT EXISTS (SELECT 1 FROM address
                                  WHERE street = v_str AND house_number = v_str2
                                    AND COALESCE(apartment_office, '') = COALESCE(v_str3, ''));
        END LOOP;

        INSERT INTO address (address_id, street, house_number, apartment_office)
        VALUES (exts.uuid_generate_v4(), v_str, v_str2, v_str3)
        RETURNING address_id INTO v_id;
        v_address_ids := v_address_ids || v_id;
    END LOOP;


    -- рестораны и их юрлица
    FOR i IN 1 .. value LOOP
        -- юрлицо: организация (ИНН 10 + ОГРН 13) или ИП (ИНН 12 + ОГРНИП 15), ИНН и ОГРН уникальны
        v_is_org := random() < 0.7;
        LOOP
            v_str  := CASE WHEN v_is_org THEN lpad(floor(random() * 1e10)::bigint::text, 10, '0')
                                         ELSE lpad(floor(random() * 1e12)::bigint::text, 12, '0') END;
            v_str2 := CASE WHEN v_is_org THEN lpad(floor(random() * 1e13)::bigint::text, 13, '0')
                                         ELSE lpad(floor(random() * 1e15)::bigint::text, 15, '0') END;
            EXIT WHEN NOT EXISTS (SELECT 1 FROM legal_entity WHERE inn = v_str OR ogrn = v_str2);
        END LOOP;

        INSERT INTO legal_entity (legal_entity_id, inn, ogrn, bank_account)
        VALUES (exts.uuid_generate_v4(), v_str, v_str2,
                lpad(floor(random() * 1e10)::bigint::text, 10, '0')
                    || lpad(floor(random() * 1e10)::bigint::text, 10, '0'))
        RETURNING legal_entity_id INTO v_id;

        -- открытие с 00:00 до 11:59, работает от 1 до 12 часов -> закрытие всегда позже открытия
        -- и не переходит через полночь (restaurant_work_hours_chk)
        v_ws := time '00:00' + floor(random() * 720) * interval '1 minute';
        -- первый ресторан всегда активный, иначе может оказаться, что заказывать негде
        v_rstatus := CASE WHEN i = 1 THEN 'активен'::restaurant_status
                          ELSE (enum_range(NULL::restaurant_status))
                               [1 + floor(random() * cardinality(enum_range(NULL::restaurant_status)))::int]
                     END;

        INSERT INTO restaurant (restaurant_id, restaurant_name, address_id, legal_entity_id,
                                description, work_start, work_end, rating, status)
        VALUES (exts.uuid_generate_v4(),
                substr(v_pool, 1 + floor(random() * (c_pool_len - 100))::int, 1 + floor(random() * 100)::int),
                v_address_ids[i],
                v_id,
                CASE WHEN random() < 0.3 THEN NULL      -- описания может не быть
                     ELSE substr(v_pool, 1 + floor(random() * (c_pool_len - 255))::int, 1 + floor(random() * 255)::int)
                END,
                v_ws,
                v_ws + (60 + floor(random() * 661)) * interval '1 minute',
                NULL,                                   -- рейтинг посчитаю в конце по отзывам
                v_rstatus)
        RETURNING restaurant_id INTO v_id;

        v_restaurant_ids := v_restaurant_ids || v_id;
        IF v_rstatus = 'активен' THEN
            v_active_rests := v_active_rests || i;
        END IF;
    END LOOP;


    -- клиенты: логин varchar(50) и телефон уникальны (BR-2.2), пароль - md5 (BR-2.3)
    FOR i IN 1 .. value LOOP
        LOOP
            v_str  := substr(v_pool, 1 + floor(random() * (c_pool_len - 50))::int, 1 + floor(random() * 50)::int);
            v_str2 := '+7' || lpad(floor(random() * 1e10)::bigint::text, 10, '0');
            EXIT WHEN NOT EXISTS (SELECT 1 FROM client WHERE login = v_str OR phone_number = v_str2);
        END LOOP;

        INSERT INTO client (client_id, login, password, phone_number)
        VALUES (exts.uuid_generate_v4(), v_str, md5(random()::text), v_str2)
        RETURNING client_id INTO v_id;
        v_client_ids := v_client_ids || v_id;
    END LOOP;


    FOR k IN 1 .. value * 4 LOOP
        INSERT INTO client_address (client_id, address_id)
        VALUES (v_client_ids[1 + (k - 1) % value], v_address_ids[value + k]);
    END LOOP;


    -- первое блюдо у каждого ресторана всегда доступно, иначе может оказаться нечего заказать
    FOR i IN 1 .. value * 5 LOOP
        v_amount   := round((50 + random() * 4950)::numeric);
        v_prstatus := CASE WHEN i <= value THEN 'доступно'::product_status
                           ELSE (enum_range(NULL::product_status))
                                [1 + floor(random() * cardinality(enum_range(NULL::product_status)))::int]
                      END;

        INSERT INTO product (product_id, product_name, product_category_id, price,
                             restaurant_id, photo_url, rating, status, description)
        VALUES (exts.uuid_generate_v4(),
                substr(v_pool, 1 + floor(random() * (c_pool_len - 100))::int, 1 + floor(random() * 100)::int),
                v_category_ids[1 + floor(random() * value)::int],
                v_amount,
                v_restaurant_ids[1 + (i - 1) % value],
                CASE WHEN random() < 0.3 THEN NULL      -- фото необязательно, BR-5.6
                     ELSE substr(v_pool, 1 + floor(random() * (c_pool_len - 255))::int, 1 + floor(random() * 255)::int)
                END,
                NULL,                                   -- рейтинг посчитаю в конце по отзывам
                v_prstatus,
                -- описание блюда обязательно (BR-5.2)
                substr(v_pool, 1 + floor(random() * (c_pool_len - 255))::int, 1 + floor(random() * 255)::int))
        RETURNING product_id INTO v_id;

        v_product_ids    := v_product_ids    || v_id;
        v_product_prices := v_product_prices || v_amount;
        v_product_avail  := v_product_avail  || (v_prstatus = 'доступно');
    END LOOP;


    -- заказы, их состав и оплата
    FOR i IN 1 .. value * 5 LOOP
        v_c := 1 + floor(random() * value)::int;
        v_r := v_active_rests[1 + floor(random() * cardinality(v_active_rests))::int];
        v_k := 1 + floor(random() * value)::int;

        -- время заказа - пока курьер работал, и не позже чем 2 часа назад
        v_lo := v_courier_hire[v_k] + time '08:00';
        v_hi := least(localtimestamp - interval '2 hours',
                      coalesce(v_courier_fire[v_k] + time '22:00', 'infinity'::timestamp));
        v_ts := date_trunc('second', v_lo + random() * (v_hi - v_lo));

        -- каждый нечётный заказ доставлен: отзывы пишутся только на доставленные,
        -- так целей для value*5 отзывов всегда хватает.
        -- у уволенного курьера заказ может быть только завершён: доставлен или отменён
        IF i % 2 = 1 THEN
            v_ostatus := 'доставлен';
        ELSIF v_courier_fire[v_k] IS NOT NULL THEN
            v_ostatus := CASE WHEN random() < 0.85 THEN 'доставлен'::order_status ELSE 'отменён'::order_status END;
        ELSE
            v_ostatus := (enum_range(NULL::order_status))
                [1 + floor(random() * cardinality(enum_range(NULL::order_status)))::int];
        END IF;

        -- доставка через 20..90 минут после заказа (BR-7.12, BR-7.13)
        v_dts := CASE WHEN v_ostatus = 'доставлен'
                      THEN v_ts + (20 + floor(random() * 71)) * interval '1 minute'
                 END;

        -- состав: только доступные блюда этого ресторана (BR-7.3), без повторов (BR-7.16).
        -- беру v_n подряд идущих из списка доступных, начиная со случайного места
        v_avail := '{}';
        FOR j IN 0 .. 4 LOOP
            IF v_product_avail[v_r + value * j] THEN
                v_avail := v_avail || (v_r + value * j);
            END IF;
        END LOOP;

        v_n      := 1 + floor(random() * cardinality(v_avail))::int;
        v_off    := floor(random() * cardinality(v_avail))::int;
        v_items  := '{}';
        v_qty    := '{}';
        v_amount := 0;
        FOR j IN 0 .. v_n - 1 LOOP
            k        := v_avail[1 + (v_off + j) % cardinality(v_avail)];
            v_items  := v_items || k;
            v_qty    := v_qty || CASE WHEN random() < 0.1 THEN 0.5 ELSE 1 + floor(random() * 3) END;
            v_amount := v_amount + v_product_prices[k] * v_qty[j + 1];
        END LOOP;

        -- минимальная сумма заказа 1000 ₽ (BR-1.8): добираю количеством первого блюда
        WHILE v_amount < 1000 LOOP
            v_qty[1] := v_qty[1] + 1;
            v_amount := v_amount + v_product_prices[v_items[1]];
        END LOOP;

        -- заказ готовят, везут или уже доставили - значит он оплачен
        v_pstatus := CASE WHEN v_ostatus IN ('доставлен', 'в_доставке', 'готовится') THEN 'успех'::payment_status
                          ELSE (enum_range(NULL::payment_status))
                               [1 + floor(random() * cardinality(enum_range(NULL::payment_status)))::int]
                     END;
        -- статус оплаты заказа по его единственной попытке (BR-8.7)
        v_paystatus := CASE v_pstatus WHEN 'успех'  THEN 'оплачен'::order_pay_status
                                      WHEN 'ошибка' THEN 'ошибка'::order_pay_status
                                      ELSE 'ожидает'::order_pay_status END;

        INSERT INTO "order" (order_id, courier_id, client_id, address_id, restaurant_id,
                             order_timestamp, delivery_timestamp, order_amount,
                             status, pay_status, description)
        VALUES (exts.uuid_generate_v4(),
                v_courier_ids[v_k],
                v_client_ids[v_c],
                -- один из 4 адресов этого клиента (BR-7.4)
                v_address_ids[value + v_c + value * floor(random() * 4)::int],
                v_restaurant_ids[v_r],
                v_ts, v_dts, v_amount,
                v_ostatus, v_paystatus,
                CASE WHEN random() < 0.5 THEN NULL      -- комментарий необязателен
                     ELSE substr(v_pool, 1 + floor(random() * (c_pool_len - 255))::int, 1 + floor(random() * 255)::int)
                END)
        RETURNING order_id, total_amount INTO v_id, v_total;

        FOR j IN 1 .. v_n LOOP
            INSERT INTO order_structure (order_id, product_id, quantity)
            VALUES (v_id, v_product_ids[v_items[j]], v_qty[j]);
        END LOOP;

        -- одна попытка оплаты на заказ (BR-11.7: payment = value*5), сумма = итог заказа (BR-8.4),
        -- id транзакции varchar(64) уникален (BR-8.3)
        LOOP
            v_str := substr(v_pool, 1 + floor(random() * (c_pool_len - 64))::int, 1 + floor(random() * 64)::int);
            EXIT WHEN NOT EXISTS (SELECT 1 FROM payment WHERE transaction_ref = v_str);
        END LOOP;

        INSERT INTO payment (payment_id, order_id, payment_type, amount,
                             transaction_ref, payment_timestamp, status)
        VALUES (exts.uuid_generate_v4(), v_id,
                (enum_range(NULL::payment_type))
                    [1 + floor(random() * cardinality(enum_range(NULL::payment_type)))::int],
                v_total,
                v_str,
                v_ts + floor(random() * 10) * interval '1 minute',
                v_pstatus);

        v_order_ids     := v_order_ids     || v_id;
        v_order_clients := v_order_clients || v_client_ids[v_c];
        v_order_done_ts := v_order_done_ts || coalesce(v_dts, v_ts);

        -- на доставленный заказ можно оставить отзыв на сам заказ, его ресторан и каждое блюдо
        IF v_ostatus = 'доставлен' THEN
            v_t_order  := v_t_order  || i || i;
            v_t_type   := v_t_type   || 'заказ'::review_entity_type || 'ресторан'::review_entity_type;
            v_t_entity := v_t_entity || v_id || v_restaurant_ids[v_r];
            FOR j IN 1 .. v_n LOOP
                v_t_order  := v_t_order  || i;
                v_t_type   := v_t_type   || 'блюдо'::review_entity_type;
                v_t_entity := v_t_entity || v_product_ids[v_items[j]];
            END LOOP;
        END IF;
    END LOOP;


    -- отзывы: перемешиваю номера возможных целей и беру первые value*5 (samples, п.7c).
    -- каждая цель встречается в списке один раз, поэтому BR-9.5 соблюдается без повторных попыток
    SELECT array_agg(t ORDER BY random())
    INTO v_t_shuffled
    FROM generate_series(1, cardinality(v_t_order)) AS t;

    FOR i IN 1 .. value * 5 LOOP
        k   := v_t_shuffled[i];
        v_c := v_t_order[k];        -- номер заказа

        INSERT INTO review (review_id, client_id, review_timestamp, entity_id, entity_type,
                            order_id, description, photo_url, rating)
        VALUES (exts.uuid_generate_v4(),
                v_order_clients[v_c],
                -- через 1-72 часа после доставки, но не в будущем
                least(localtimestamp, v_order_done_ts[v_c] + (1 + floor(random() * 72)) * interval '1 hour'),
                v_t_entity[k], v_t_type[k], v_order_ids[v_c],
                substr(v_pool, 1 + floor(random() * (c_pool_len - 255))::int, 1 + floor(random() * 255)::int),
                CASE WHEN random() < 0.5 THEN NULL      -- фото необязательно, BR-9.3
                     ELSE substr(v_pool, 1 + floor(random() * (c_pool_len - 255))::int, 1 + floor(random() * 255)::int)
                END,
                1 + floor(random() * 5)::int);          -- 1..5, BR-9.4
    END LOOP;


    -- рейтинги блюд и ресторанов этого вызова - среднее по их отзывам (BR-9.6).
    -- у кого отзывов нет, остаётся NULL (BR-9.7)
    UPDATE product p
    SET rating = s.avg_rating
    FROM (SELECT r.entity_id, round(avg(r.rating), 2) AS avg_rating
          FROM review r
          WHERE r.entity_type = 'блюдо' AND r.entity_id = ANY (v_product_ids)
          GROUP BY r.entity_id) s
    WHERE p.product_id = s.entity_id;

    UPDATE restaurant rs
    SET rating = s.avg_rating
    FROM (SELECT r.entity_id, round(avg(r.rating), 2) AS avg_rating
          FROM review r
          WHERE r.entity_type = 'ресторан' AND r.entity_id = ANY (v_restaurant_ids)
          GROUP BY r.entity_id) s
    WHERE rs.restaurant_id = s.entity_id;


    -- courier_pay за 6 месяцев по правилам BR-10.2:
    -- платим по коэффициенту текущего месяца, по числу доставок считаем коэффициент на следующий
    v_coef := array_fill(0.1::numeric, ARRAY[value]);    -- в первый месяц у всех стартовый 0.1

    FOR j IN 0 .. 5 LOOP
        v_month := (v_window_start + make_interval(months => j))::date;

        -- доставки и комиссии каждого курьера за месяц (BR-10.5: только доставленные)
        SELECT array_agg(t.cnt ORDER BY t.ord), array_agg(t.comm ORDER BY t.ord)
        INTO v_cnt, v_comm
        FROM (SELECT c.ord,
                     count(o.order_id)              AS cnt,
                     coalesce(sum(o.commission), 0) AS comm
              FROM unnest(v_courier_ids) WITH ORDINALITY AS c(courier_id, ord)
              LEFT JOIN "order" o
                     ON o.courier_id = c.courier_id
                    AND o.status = 'доставлен'
                    AND o.order_timestamp >= v_month
                    AND o.order_timestamp <  v_month + interval '1 month'
              GROUP BY c.ord) t;

        FOR k IN 1 .. value LOOP
            INSERT INTO courier_pay (year, month, courier_id, amount, coefficient_used)
            VALUES (extract(year  FROM v_month)::int,
                    extract(month FROM v_month)::int,
                    v_courier_ids[k],
                    round(v_coef[k] * v_comm[k], 2),
                    v_coef[k]);

            -- уволенному до конца месяца новый коэффициент не ставим (BR-10.6)
            IF v_courier_fire[k] IS NULL
               OR v_courier_fire[k] >= (v_month + interval '1 month')::date THEN
                v_coef[k] := CASE WHEN v_cnt[k] <= 150 THEN 0.1
                                  WHEN v_cnt[k] <= 250 THEN 0.2
                                  WHEN v_cnt[k] <= 500 THEN 0.3
                                  ELSE 0.5 END;
            END IF;
        END LOOP;
    END LOOP;

    -- в courier.coefficient - коэффициент на следующий месяц
    UPDATE courier c
    SET coefficient = x.coef
    FROM unnest(v_courier_ids, v_coef) AS x(courier_id, coef)
    WHERE c.courier_id = x.courier_id;
END;
$$;
