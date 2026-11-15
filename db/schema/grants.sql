-- FOOD-109: роль доступа к объектам FoodExpress.
do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'inspector') then
        create role inspector login password 'NetoSQL2025';
    else
        alter role inspector login password 'NetoSQL2025';
    end if;
end $$;
-- Выдаем права на рабочую схему и ее объекты.
grant all privileges on schema mineev_food to inspector;
grant usage on schema exts, information_schema, pg_catalog to inspector;
grant all privileges on all tables in schema mineev_food to inspector;
grant execute on all routines in schema mineev_food to inspector;
grant execute on function exts.uuid_generate_v4() to inspector;
-- Разрешаем использование перечислений в запросах и процедурах.
grant usage on type mineev_food.restaurant_status, mineev_food.product_status,
    mineev_food.courier_status, mineev_food.order_status, mineev_food.order_pay_status,
    mineev_food.payment_status, mineev_food.payment_type, mineev_food.review_entity_type to inspector;
-- Настраиваем права на будущие объекты, создаваемые владельцем.
alter default privileges in schema mineev_food grant all on tables to inspector;
alter default privileges in schema mineev_food grant execute on routines to inspector;
