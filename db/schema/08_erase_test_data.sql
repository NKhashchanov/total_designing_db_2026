-- FOOD-103. Порядок удаления обратен зависимостям FK.
set search_path to mineev_food, pg_catalog;
create procedure erase_test_data()
language plpgsql set search_path to mineev_food, pg_catalog as $$
begin
    delete from review;
    delete from payment;
    delete from order_structure;
    delete from "order";
    delete from courier_pay;
    delete from product;
    delete from restaurant;
    delete from client_address;
    delete from product_category;
    delete from courier;
    delete from client;
    delete from address;
end $$;
