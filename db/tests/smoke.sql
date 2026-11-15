-- Проверки FOOD-101–109. Выполняются под inspector и откатываются в конце.
\set ON_ERROR_STOP on
\echo '=== A. Роль и схема ==='
set role inspector;
set search_path to mineev_food, pg_catalog, exts;
select current_user, current_database(), current_setting('TimeZone');
begin;
-- Проверяем состав схемы, типы идентификаторов и права роли.
do $$
begin
    if current_user <> 'inspector' then raise exception 'Тест должен работать под inspector'; end if;
    if (select count(*) from information_schema.tables where table_schema='mineev_food' and table_type='BASE TABLE') <> 12 then
        raise exception 'Ожидаются 12 таблиц';
    end if;
    if (select count(*) from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='mineev_food' and t.typtype='e') <> 8 then
        raise exception 'Ожидаются 8 enum';
    end if;
    if (select count(*) from pg_constraint where contype='f' and connamespace='mineev_food'::regnamespace) < 15 then
        raise exception 'Недостаточно внешних ключей';
    end if;
    if exists(select 1 from information_schema.columns where table_schema='mineev_food' and column_name like '%_id' and data_type <> 'uuid') then
        raise exception 'Найдены ID не типа uuid';
    end if;
    if not has_schema_privilege('inspector','mineev_food','USAGE') or not has_schema_privilege('inspector','mineev_food','CREATE') then
        raise exception 'Недостаточно прав на схему';
    end if;
    perform exts.uuid_generate_v4();
end $$;

\echo '=== C. Генератор и повторные вызовы ==='
call erase_test_data();
call erase_test_data();
call insert_test_data(1);
set constraints all immediate;
set constraints all deferred;
-- Проверяем минимальную порцию и отказ при недопустимом value.
do $$
begin
    if (select count(*) from client) <> 1 or (select count(*) from "order") <> 5
       or (select count(*) from courier_pay) <> 6 then raise exception 'Неверное распределение value=1'; end if;
    begin
        call insert_test_data(0);
        raise exception 'value=0 принят';
    exception when invalid_parameter_value then null;
    end;
end $$;
call erase_test_data();
call insert_test_data(10);
set constraints all immediate;
set constraints all deferred;
select 'client' as tbl, count(*) from client
union all select 'courier', count(*) from courier
union all select 'product_category', count(*) from product_category
union all select 'restaurant', count(*) from restaurant
union all select 'address', count(*) from address
union all select 'product', count(*) from product
union all select 'order', count(*) from "order"
union all select 'review', count(*) from review
union all select 'payment', count(*) from payment
union all select 'client_address', count(*) from client_address
union all select 'order_structure', count(*) from order_structure
union all select 'courier_pay', count(*) from courier_pay order by 1;
-- Проверяем число строк, даты, выплаты и рейтинги для value=10.
do $$
begin
    if (select count(*) from client) <> 10 or (select count(*) from courier) <> 10
       or (select count(*) from product_category) <> 10 or (select count(*) from restaurant) <> 10
       or (select count(*) from address) <> 50 or (select count(*) from product) <> 50
       or (select count(*) from "order") <> 50 or (select count(*) from review) <> 50
       or (select count(*) from payment) <> 50 or (select count(*) from courier_pay) <> 60
       or (select count(*) from client_address) <> 40 or (select count(*) from order_structure) <> 100 then
        raise exception 'Неверное распределение строк value=10';
    end if;
    if not exists(select 1 from courier where status <> 'уволен') then raise exception 'Нет активных курьеров'; end if;
    if exists(select 1 from client where password !~ '^[0-9a-f]{32}$' or btrim(login)='' or btrim(phone_number)='') then
        raise exception 'Неверные данные клиента';
    end if;
    if exists(select 1 from "order" where order_timestamp < localtimestamp - interval '180 days' or order_timestamp > localtimestamp) then
        raise exception 'Дата заказа вне диапазона';
    end if;
    if exists(select 1 from courier_pay cp where amount <> round(coefficient_used * coalesce((
        select sum(o.commission) from "order" o where o.courier_id=cp.courier_id and o.status='доставлен'
          and extract(year from o.order_timestamp)=cp.year and extract(month from o.order_timestamp)=cp.month),0),2)) then
        raise exception 'Некорректная история выплат';
    end if;
    if exists(select 1 from product p where p.rating is distinct from (select round(avg(r.rating),2) from review r where r.entity_type='блюдо' and r.entity_id=p.product_id)) then
        raise exception 'Некорректный рейтинг блюда';
    end if;
    if exists(select 1 from restaurant p where p.rating is distinct from (select round(avg(r.rating),2) from review r where r.entity_type='ресторан' and r.entity_id=p.restaurant_id)) then
        raise exception 'Некорректный рейтинг ресторана';
    end if;
end $$;
call insert_test_data(10);
-- Проверяем добавление второй порции без удаления первой.
do $$
begin
    if (select count(*) from client) <> 20 or (select count(*) from "order") <> 100
       or (select count(*) from courier_pay) <> 120 then raise exception 'Повторный запуск не добавил независимую порцию'; end if;
end $$;
set constraints all immediate;
set constraints all deferred;

\echo '=== D. Отрицательные проверки ==='
-- Проверяем отказ при нарушении ограничений целостности.
do $$
declare
    v_order "order"%rowtype;
    v_position order_structure%rowtype;
    v_product uuid;
    v_client uuid;
    v_address uuid;
    v_pay payment%rowtype;
begin
    select * into v_order from "order" where status='доставлен' limit 1;
    select * into v_position from order_structure where order_id=v_order.order_id limit 1;
    select product_id into v_product from product where restaurant_id<>v_order.restaurant_id limit 1;
    select client_id into v_client from client where client_id<>v_order.client_id limit 1;
    select a.address_id into v_address from address a where not exists(select 1 from client_address ca where ca.client_id=v_order.client_id and ca.address_id=a.address_id) limit 1;
    select * into v_pay from payment where order_id=v_order.order_id and status='успех';
    begin
        insert into client(login,password,phone_number) select login,password,'000000000000' from client limit 1;
        raise exception 'Дублирующий логин принят';
    exception when unique_violation then null; end;
    begin
        update "order" set address_id=v_address where order_id=v_order.order_id;
        raise exception 'Чужой адрес принят';
    exception when foreign_key_violation then null; end;
    begin
        insert into order_structure(order_id,product_id,quantity) values(v_order.order_id,v_product,1);
        raise exception 'Блюдо другого ресторана принято';
    exception when check_violation then null; end;
    begin
        insert into order_structure(order_id,product_id,quantity) values(v_position.order_id,v_position.product_id,1);
        raise exception 'Дубликат позиции принят';
    exception when unique_violation then null; end;
    begin
        update order_structure set quantity=0 where order_id=v_position.order_id and product_id=v_position.product_id;
        raise exception 'Нулевое количество принято';
    exception when check_violation then null; end;
    begin
        insert into payment(order_id,payment_type,amount,transaction_id,status)
        values(v_order.order_id,'карта',v_order.total_amount,exts.uuid_generate_v4(),'успех');
        raise exception 'Вторая успешная оплата принята';
    exception when unique_violation then null; end;
    begin
        update payment set amount=amount+1 where payment_id=v_pay.payment_id;
        raise exception 'Неверная сумма оплаты принята';
    exception when check_violation then null; end;
    begin
        insert into review(client_id,entity_type,entity_id,order_id,description,rating)
        values(v_client,'заказ',v_order.order_id,v_order.order_id,'Чужой отзыв',5);
        raise exception 'Чужой автор принят';
    exception when check_violation or foreign_key_violation then null; end;
    begin
        insert into review(client_id,entity_type,entity_id,order_id,description,rating)
        values(v_order.client_id,'блюдо',v_product,v_order.order_id,'Чужое блюдо',5);
        raise exception 'Отзыв на чужое блюдо принят';
    exception when check_violation then null; end;
    begin
        update "order" set pay_status='ошибка' where order_id=v_order.order_id;
        set constraints all immediate;
        raise exception 'Некорректный pay_status принят';
    exception when check_violation then null; end;
    begin
        delete from order_structure where order_id=v_order.order_id;
        set constraints all immediate;
        raise exception 'Пустой заказ принят';
    exception when check_violation then null; end;
    begin
        update order_structure set quantity=quantity+1 where order_id=v_position.order_id and product_id=v_position.product_id;
        set constraints all immediate;
        raise exception 'Несогласованная сумма заказа принята';
    exception when check_violation then null; end;
end $$;
set constraints all immediate;
set constraints all deferred;

\echo '=== E. add_product, рейтинг, платежи ==='
-- Проверяем добавление блюда, изменение рейтингов и статусы платежей.
do $$
declare
    v_restaurant uuid; v_category uuid; v_product uuid;
    v_order "order"%rowtype; v_product2 uuid;
    v_review uuid; v_pay uuid; v_review2 uuid;
    v_ids uuid[] := '{}'; v_orders uuid[] := '{}';
    v_count bigint; i integer; v_new_order uuid;
begin
    select restaurant_id into v_restaurant from restaurant limit 1;
    select product_category_id into v_category from product_category limit 1;
    select count(*) into v_count from product;
    call add_product(p_restaurant_id=>v_restaurant, p_product_category_id=>v_category,
        p_name=>'Блюдо для теста рейтинга', p_price=>1000, p_rating=>4.5, p_status=>'доступно', p_description=>'Тест');
    select product_id into v_product from product where product_name='Блюдо для теста рейтинга' and restaurant_id=v_restaurant;
    if (select count(*) from product) <> v_count+1 or (select rating from product where product_id=v_product) is not null then
        raise exception 'Некорректное добавление блюда';
    end if;
    begin
        call add_product('00000000-0000-0000-0000-000000000000',v_category,'Неверное',100,null,'доступно','Тест');
        raise exception 'Несуществующий ресторан принят';
    exception when foreign_key_violation then null; end;
    begin
        call add_product(v_restaurant,v_category,'Неверное',-1,null,'доступно','Тест');
        raise exception 'Отрицательная цена принята';
    exception when check_violation then null; end;
    call add_product(v_restaurant,v_category,'Второе тестовое блюдо',1000,null,'доступно','Тест');
    select product_id into v_product2 from product where product_name='Второе тестовое блюдо' and restaurant_id=v_restaurant;
    select * into v_order from "order" limit 1;
    for i in 1..3 loop
        insert into "order"(courier_id,client_id,address_id,restaurant_id,order_amount,commission,total_amount,status,description)
        values(v_order.courier_id,v_order.client_id,v_order.address_id,v_restaurant,2000,200,2200,'создан','Тест рейтинга') returning order_id into v_new_order;
        v_orders:=array_append(v_orders,v_new_order);
        insert into order_structure(order_id,product_id,quantity) values(v_new_order,v_product,1),(v_new_order,v_product2,1);
        insert into review(client_id,order_id,entity_type,entity_id,description,rating)
        values(v_order.client_id,v_new_order,'блюдо',v_product,'Тест рейтинга',i+2) returning review_id into v_review;
        v_ids:=array_append(v_ids,v_review);
    end loop;
    if (select rating from product where product_id=v_product) is distinct from 4::numeric then raise exception 'AVG должен быть 4'; end if;
    delete from review where review_id=v_ids[1];
    if (select rating from product where product_id=v_product) is distinct from 4.5::numeric then raise exception 'AVG должен быть 4.5'; end if;
    update review set entity_id=v_product2 where review_id=v_ids[2];
    if (select rating from product where product_id=v_product) is distinct from 5::numeric
       or (select rating from product where product_id=v_product2) is distinct from 4::numeric then raise exception 'Перенос отзыва не пересчитал оба объекта'; end if;
    update review set entity_type='ресторан', entity_id=v_restaurant where review_id=v_ids[2];
    if (select rating from product where product_id=v_product2) is not null then raise exception 'Старый рейтинг не сброшен'; end if;
    update review set entity_type='заказ', entity_id=v_orders[2] where review_id=v_ids[2];
    delete from review where review_id=v_ids[3];
    if (select rating from product where product_id=v_product) is not null then raise exception 'Рейтинг без отзывов не NULL'; end if;
    -- Ошибка оплаты, затем новая попытка, затем успех, затем удаление успеха.
    insert into payment(order_id,payment_type,amount,transaction_id,status)
    values(v_orders[1],'карта',2200,exts.uuid_generate_v4(),'ошибка') returning payment_id into v_pay;
    if (select pay_status from "order" where order_id=v_orders[1]) <> 'ошибка' then raise exception 'Ожидалась ошибка'; end if;
    insert into payment(order_id,payment_type,amount,transaction_id,status)
    values(v_orders[1],'наличные',2200,exts.uuid_generate_v4(),'в_обработке') returning payment_id into v_review2;
    if (select pay_status from "order" where order_id=v_orders[1]) <> 'ожидает' then raise exception 'Ожидался статус ожидает'; end if;
    update payment set status='успех' where payment_id=v_review2;
    if (select pay_status from "order" where order_id=v_orders[1]) <> 'оплачен' then raise exception 'Ожидался статус оплачен'; end if;
    delete from payment where payment_id=v_review2;
    if (select pay_status from "order" where order_id=v_orders[1]) <> 'ошибка' then raise exception 'Ошибка после удаления успеха'; end if;
    delete from payment where payment_id=v_pay;
    if (select pay_status from "order" where order_id=v_orders[1]) <> 'ожидает' then raise exception 'Нет попыток — ожидает'; end if;
end $$;
set constraints all immediate;
set constraints all deferred;

\echo '=== E. Статистика и зарплата ==='
select * from get_statistic() order by restaurant_name;
-- Проверяем статистику, расчет зарплаты и повторный вызов процедуры.
do $$
declare
    v_courier uuid; v_before numeric; v_expected numeric;
    v_order "order"%rowtype; v_count bigint;
    v_dismissed uuid; v_dismissed_rate numeric;
    v_i integer; v_id uuid; v_month date:=date_trunc('month',localtimestamp)::date;
    v_year integer:=extract(year from current_date); v_mon integer:=extract(month from current_date);
begin
    if (select count(*) from get_statistic()) <> (select count(*) from restaurant) then raise exception 'Неверное число строк статистики'; end if;
    if exists(select 1 from get_statistic() s join restaurant r on r.restaurant_name=s.restaurant_name
              where s.total_amount is distinct from coalesce((select sum(o.total_amount) from "order" o where o.restaurant_id=r.restaurant_id and o.status='доставлен'),0)) then
        raise exception 'Сумма статистики не совпадает с заказами';
    end if;
    if next_coefficient(0)<>0.1 or next_coefficient(150)<>0.1 or next_coefficient(151)<>0.2
       or next_coefficient(250)<>0.2 or next_coefficient(251)<>0.3 or next_coefficient(500)<>0.3 or next_coefficient(501)<>0.5 then
        raise exception 'Неверные границы коэффициента';
    end if;
    -- 151 доставка за текущий месяц: проверяем переход коэффициента с 0.1 на 0.2.
    insert into courier(fio,phone_number,status,hire_date) values('Тест зарплаты','+70000000001','свободен',current_date) returning courier_id into v_courier;
    select * into v_order from "order" where status='доставлен' limit 1;
    for v_i in 1..151 loop
        insert into "order"(courier_id,client_id,address_id,restaurant_id,order_timestamp,delivery_timestamp,
                            order_amount,commission,total_amount,status,description)
        values(v_courier,v_order.client_id,v_order.address_id,v_order.restaurant_id,localtimestamp,localtimestamp,
               v_order.order_amount,v_order.commission,v_order.total_amount,'доставлен','Тест 151 доставки') returning order_id into v_id;
        insert into order_structure(order_id,product_id,quantity,unit_price)
        select v_id,product_id,quantity,unit_price from order_structure where order_id=v_order.order_id;
    end loop;
    select courier_id,coefficient into v_dismissed,v_dismissed_rate from courier where status='уволен' limit 1;
    call courier_salary();
    v_expected:=round(151*v_order.commission*0.1,2);
    select amount into v_before from courier_pay where courier_id=v_courier and year=v_year and month=v_mon;
    if v_before is distinct from v_expected or (select coefficient from courier where courier_id=v_courier) <> 0.2 then
        raise exception 'Неверный расчет 151 доставки';
    end if;
    if (select coefficient from courier where courier_id=v_dismissed) is distinct from v_dismissed_rate then raise exception 'Изменился коэффициент уволенного'; end if;
    select count(*) into v_count from courier_pay where year=v_year and month=v_mon;
    call courier_salary();
    if (select count(*) from courier_pay where year=v_year and month=v_mon) <> v_count
       or (select amount from courier_pay where courier_id=v_courier and year=v_year and month=v_mon) is distinct from v_before
       or (select coefficient_used from courier_pay where courier_id=v_courier and year=v_year and month=v_mon) <> 0.1 then
        raise exception 'Повторная зарплата некорректна';
    end if;
end $$;
set constraints all immediate;
set constraints all deferred;

\echo '=== F. Финансовое представление ==='
select * from how_much_money order by year_month;
-- Проверяем формулы финансового отчета и непрерывность месяцев.
do $$
begin
    if exists(select 1 from how_much_money where commission <> sum_with_commission-sum_no_commission
       or net_profit <> commission-courier_pay or commission_diff is distinct from commission-prev_commission) then raise exception 'Неверные суммы отчета'; end if;
    if (select prev_commission from how_much_money order by year_month limit 1) is not null then raise exception 'Первый предыдущий месяц должен быть NULL'; end if;
    if (select count(*) from how_much_money) <> (select count(*) from generate_series(
       date_trunc('month',(select min(order_timestamp) from "order" where status='доставлен')),
       date_trunc('month',(select max(order_timestamp) from "order" where status='доставлен')), interval '1 month')) then
        raise exception 'Пропущены месяцы отчета';
    end if;
end $$;

\echo '=== I. Очистка и повторная генерация ==='
call erase_test_data();
set constraints all immediate;
set constraints all deferred;
-- Проверяем отсутствие данных после очистки.
do $$
begin
    if exists(select 1 from client union all select 1 from address union all select 1 from client_address
              union all select 1 from restaurant union all select 1 from courier union all select 1 from courier_pay
              union all select 1 from product_category union all select 1 from product union all select 1 from "order"
              union all select 1 from order_structure union all select 1 from payment union all select 1 from review) then
        raise exception 'После erase остались строки';
    end if;
    if exists(select 1 from how_much_money) then raise exception 'Отчет пустой базы должен быть пуст'; end if;
end $$;
call erase_test_data();
call insert_test_data(10);
set constraints all immediate;
-- Проверяем повторное заполнение очищенной базы.
do $$
begin
    if (select count(*) from "order") <> 50 then raise exception 'Повторная генерация после очистки не удалась'; end if;
end $$;
rollback;
reset role;
\echo 'SMOKE_OK: проверки завершены; тестовые изменения откатились.'
