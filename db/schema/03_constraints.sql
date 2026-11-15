-- FOOD-101. Индексы для внешних ключей и агрегатов.
set search_path to mineev_food, pg_catalog;
-- Разрешаем только одну успешную оплату каждого заказа.
create unique index payment_one_success on payment(order_id) where status = 'успех';
-- Индексы для поиска связанных записей по внешним ключам.
create index client_address_address_idx on client_address(address_id);
create index courier_pay_courier_idx on courier_pay(courier_id);
create index product_restaurant_idx on product(restaurant_id);
create index product_category_idx on product(product_category_id);
create index order_client_address_idx on "order"(client_id, address_id);
create index order_address_idx on "order"(address_id);
create index order_restaurant_idx on "order"(restaurant_id);
-- Поиск заказов курьера за расчетный период.
create index order_courier_month_idx on "order"(courier_id, order_timestamp);
-- Поиск позиций блюда и попыток оплаты заказа.
create index order_structure_product_idx on order_structure(product_id);
create index payment_order_idx on payment(order_id);
-- Поиск отзывов клиента и пересчет рейтинга объекта.
create index review_client_idx on review(client_id);
create index review_object_idx on review(entity_type, entity_id);
