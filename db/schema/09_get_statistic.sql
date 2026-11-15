-- FOOD-106. Отдельная агрегация заказов, блюд и клиентов.
set search_path to mineev_food, pg_catalog;
create function get_statistic()
returns table(restaurant_name varchar, best_product_name varchar, total_amount numeric,
              avg_amount numeric, best_user varchar)
language sql volatile
set search_path to mineev_food, pg_catalog as $$
    -- Один раз выбираем доставленные заказы для всех агрегатов.
    with delivered as materialized (
        select o.order_id, o.restaurant_id, o.client_id, o.total_amount
        from "order" o where o.status = 'доставлен'
    -- Суммы и средний чек считаем без соединения с позициями.
    ), money as (
        select d.restaurant_id, sum(d.total_amount) as total, avg(d.total_amount) as average
        from delivered d group by d.restaurant_id
    -- Популярность блюда определяем по суммарному количеству.
    ), product_counts as (
        select d.restaurant_id, os.product_id, sum(os.quantity) as qty
        from delivered d join order_structure os using(order_id)
        group by d.restaurant_id, os.product_id
    -- При равных результатах выбираем одно блюдо случайно.
    ), best_product as (
        select distinct on (pc.restaurant_id) pc.restaurant_id, pc.product_id
        from product_counts pc order by pc.restaurant_id, pc.qty desc, random()
    -- Активность клиента определяем по числу заказов.
    ), client_counts as (
        select d.restaurant_id, d.client_id, count(*) as cnt
        from delivered d group by d.restaurant_id, d.client_id
    -- При равных результатах выбираем одного клиента случайно.
    ), best_client as (
        select distinct on (cc.restaurant_id) cc.restaurant_id, cc.client_id
        from client_counts cc order by cc.restaurant_id, cc.cnt desc, random()
    )
    -- Сохраняем в результате рестораны без доставленных заказов.
    select r.restaurant_name, p.product_name, coalesce(m.total,0), m.average, c.login
    from restaurant r
    left join money m using(restaurant_id)
    left join best_product bp using(restaurant_id)
    left join product p on p.product_id = bp.product_id
    left join best_client bc on bc.restaurant_id = r.restaurant_id
    left join client c on c.client_id = bc.client_id;
$$;
