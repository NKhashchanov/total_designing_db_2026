-- Контролируемые данные для проверки пропущенного месяца, пустого ресторана и статистики.
\set ON_ERROR_STOP on
set role inspector;
set search_path to mineev_food, pg_catalog, exts;
begin;
call erase_test_data();
call insert_test_data(1);
set constraints all immediate;
set constraints all deferred;

-- Создаем контролируемые заказы и проверяем статистику и пропущенный месяц.
do $$
declare
    v_order "order"%rowtype;
    v_old_order uuid;
    v_address uuid;
    v_restaurant uuid;
    v_gap text:=to_char(current_date-interval '1 month','YYYY-MM');
    v_stats record;
    v_product uuid;
    v_best_name varchar;
    v_login varchar;
    v_old_time timestamp:=date_trunc('month',localtimestamp)-interval '2 months'+interval '1 day';
begin
    select * into v_order from "order" where status='доставлен';
    -- В генераторе value=1 единственная доставка относится к текущему месяцу.
    insert into "order"(courier_id,client_id,address_id,restaurant_id,order_timestamp,delivery_timestamp,
                        order_amount,commission,total_amount,status,description)
    values(v_order.courier_id,v_order.client_id,v_order.address_id,v_order.restaurant_id,v_old_time,v_old_time,
           v_order.order_amount,v_order.commission,v_order.total_amount,'доставлен','Контрольный заказ прошлого месяца')
    returning order_id into v_old_order;
    insert into order_structure(order_id,product_id,quantity,unit_price)
    select v_old_order,product_id,quantity,unit_price from order_structure where order_id=v_order.order_id;
    insert into address(street,house_number) values('Контрольная улица','1') returning address_id into v_address;
    insert into restaurant(restaurant_name,address_id,description,work_start,work_end,company_details,status)
    values('Контрольный пустой ресторан',v_address,'Тест',time '09:00',time '22:00','Тест','активен') returning restaurant_id into v_restaurant;
    select * into v_stats from get_statistic() where restaurant_name='Контрольный пустой ресторан';
    if not found or v_stats.total_amount<>0 or v_stats.avg_amount is not null
       or v_stats.best_product_name is not null or v_stats.best_user is not null then
        raise exception 'Неверная статистика пустого ресторана';
    end if;
    select * into v_stats from get_statistic() where restaurant_name=(select restaurant_name from restaurant where restaurant_id=v_order.restaurant_id);
    select product_id into v_product from order_structure where order_id=v_order.order_id order by quantity desc limit 1;
    select product_name into v_best_name from product where product_id=v_product;
    select login into v_login from client where client_id=v_order.client_id;
    if v_stats.total_amount is distinct from v_order.total_amount*2 or v_stats.avg_amount is distinct from v_order.total_amount
       or v_stats.best_product_name is distinct from v_best_name or v_stats.best_user is distinct from v_login then
        raise exception 'Неверная агрегация заказов, количеств или клиентов';
    end if;
    -- Ровно три месяца: первый с заказом, средний без доставок, текущий с заказом.
    if (select count(*) from how_much_money)<>3 or not exists (
        select 1 from how_much_money where year_month=v_gap and sum_no_commission=0 and sum_with_commission=0
        and commission=0 and courier_pay=0 and net_profit=0 and prev_commission=v_order.commission
        and commission_diff=-v_order.commission) then
        raise exception 'Рекурсивный отчет не заполнил пропущенный месяц';
    end if;
end $$;
set constraints all immediate;
select * from get_statistic() order by restaurant_name;
select * from how_much_money order by year_month;
rollback;
reset role;
\echo 'EDGE_CASES_OK: пустой ресторан, агрегация и пропущенный месяц проверены.'
