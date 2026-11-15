-- FOOD-101. Фиксированные статусы.
set search_path to mineev_food, pg_catalog;
-- Доступность ресторана для работы.
create type restaurant_status as enum ('активен', 'неактивен');
-- Доступность блюда в меню.
create type product_status as enum ('доступно', 'нет_в_наличии', 'архив');
-- Текущее состояние курьера.
create type courier_status as enum ('свободен', 'занят', 'на_доставке', 'уволен');
-- Этап обработки и доставки заказа.
create type order_status as enum ('создан', 'готовится', 'в_доставке', 'доставлен', 'отменён');
-- Итоговое состояние оплаты заказа.
create type order_pay_status as enum ('ожидает', 'оплачен', 'ошибка');
-- Результат отдельной попытки оплаты.
create type payment_status as enum ('успех', 'ошибка', 'в_обработке');
-- Способ оплаты.
create type payment_type as enum ('карта', 'наличные', 'безнал');
-- Тип объекта, на который оставлен отзыв.
create type review_entity_type as enum ('блюдо', 'ресторан', 'заказ');
