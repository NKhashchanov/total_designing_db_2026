-- FOOD-102 C.9, FOOD-106 H.1–H.3. Отдельный нагрузочный сценарий.
\set ON_ERROR_STOP on
set role inspector;
set search_path to mineev_food, pg_catalog, exts;
begin;
call erase_test_data();
call insert_test_data(100);
-- Проверяем повторную генерацию и итоговый объем данных.
do $$
begin
    for i in 1..10 loop
        call insert_test_data(10);
    end loop;
    if (select count(*) from client)<>200 or (select count(*) from "order")<>1000 then
        raise exception 'Нагрузочная повторная генерация не соответствует количеству';
    end if;
end $$;
set constraints all immediate;
\echo '=== H.1. Два коррелированных подзапроса ==='
explain analyze
select c.courier_id,
       (select count(*) from "order" o where o.courier_id=c.courier_id and o.status='доставлен') as cnt,
       (select coalesce(sum(o.commission),0) from "order" o where o.courier_id=c.courier_id and o.status='доставлен') as commission_sum
from courier c;
\echo '=== H.2. Агрегация одним JOIN ==='
explain analyze
select c.courier_id,count(o.order_id) as cnt,coalesce(sum(o.commission),0) as commission_sum
from courier c left join "order" o on o.courier_id=c.courier_id and o.status='доставлен'
group by c.courier_id;
\echo '=== H.3. Вызов get_statistic ==='
explain analyze select * from get_statistic();
-- Функция VOLATILE (random для ничьих) и SET search_path могут скрывать внутренний план
-- за Function Scan. Ниже тот же запрос напрямую для анализа физических операторов.
explain analyze
with delivered as materialized (
    select o.order_id,o.restaurant_id,o.client_id,o.total_amount from "order" o where o.status='доставлен'
), money as (
    select d.restaurant_id,sum(d.total_amount) as total,avg(d.total_amount) as average from delivered d group by d.restaurant_id
), product_counts as (
    select d.restaurant_id,os.product_id,sum(os.quantity) as qty from delivered d join order_structure os using(order_id)
    group by d.restaurant_id,os.product_id
), best_product as (
    select distinct on(pc.restaurant_id) pc.restaurant_id,pc.product_id from product_counts pc order by pc.restaurant_id,pc.qty desc,random()
), client_counts as (
    select d.restaurant_id,d.client_id,count(*) as cnt from delivered d group by d.restaurant_id,d.client_id
), best_client as (
    select distinct on(cc.restaurant_id) cc.restaurant_id,cc.client_id from client_counts cc order by cc.restaurant_id,cc.cnt desc,random()
)
select r.restaurant_name,p.product_name,coalesce(m.total,0),m.average,c.login from restaurant r
left join money m using(restaurant_id) left join best_product bp using(restaurant_id)
left join product p on p.product_id=bp.product_id left join best_client bc on bc.restaurant_id=r.restaurant_id
left join client c on c.client_id=bc.client_id;
rollback;
reset role;
\echo 'PERFORMANCE_OK: повторная генерация завершена, планы выведены.'
