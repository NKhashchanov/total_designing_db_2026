# Протокол для самопроверки

## Окружение

| Параметр | Значение |
|---|---|
| PostgreSQL version | 15.18 |
| Дата проверки | 15.11.2026 |
| Схема | `bokareva_food` |
| Роль-аудитор | `inspector` |

Все проверки — под `inspector`, если не указано иное.

---

## A. Подготовка

### A.1. Восстановление бэкапа

Ожидается: без ошибок.
Факт: восстанавливала в базу `foodexpress_bokareva`, где есть только схема `exts` с `uuid-ossp` (BR-13.3): `pg_restore -d foodexpress_bokareva --exit-on-error foodexpress_bokareva.backup` - ошибок нет. Потом `psql -U postgres -d foodexpress_bokareva -f db/schema/grants.sql` - ошибок нет. Весь протокол дальше выполняла, подключившись как `inspector` с паролем `NetoSQL2025` (`psql -h localhost -U inspector`).
Вердикт: OK

### A.2. Переключение на inspector

```sql
SET ROLE inspector;
SET search_path TO bokareva_food, exts;
SELECT current_user;
```

Ожидается: `inspector`.
Факт: `inspector`
Вердикт: OK

---

## B. FOOD-101: Структура схемы

### B.1. Схема существует

```sql
SELECT schema_name FROM information_schema.schemata
WHERE schema_name LIKE '%_food';
```

Ожидается: `bokareva_food`.
Факт: `bokareva_food`

### B.2. Схема `exts` с `uuid-ossp`

```sql
SELECT extname, extnamespace::regnamespace AS schema
FROM pg_extension WHERE extname = 'uuid-ossp';
```

Ожидается: `uuid-ossp`, схема `exts`.
Факт: `uuid-ossp | exts`

### B.3. Все 12 исходных таблиц + N после нормализации

```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'bokareva_food'
ORDER BY table_name;
```

Ожидается: `address`, `client`, `client_address`, `courier`, `courier_pay`, `order`, `order_structure`, `payment`, `product`, `product_category`, `restaurant`, `review` (12 + N штук).
Факт: 14 строк - 13 таблиц (12 из ERD + `legal_entity`, вынесена при нормализации) и представление `how_much_money`, оно тоже попадает в `information_schema.tables`.

### B.4. Все PK — `uuid`

```sql
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'bokareva_food'
  AND column_name LIKE '%_id'
  AND data_type != 'uuid';
```

Ожидается: пусто.
Факт: пусто.

### B.5. Enum-типы

```sql
SELECT t.typname, array_agg(e.enumlabel ORDER BY e.enumsortorder) AS values
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'bokareva_food'
GROUP BY t.typname
ORDER BY t.typname;
```

Ожидается: 8 типов со значениями из constraints.md.
Факт:
```
courier_status     | {свободен,занят,на_доставке,уволен}
order_pay_status   | {ожидает,оплачен,ошибка}
order_status       | {создан,готовится,в_доставке,доставлен,отменён}
payment_status     | {успех,ошибка,в_обработке}
payment_type       | {карта,наличные,безнал}
product_status     | {доступно,нет_в_наличии,архив}
restaurant_status  | {активен,неактивен}
review_entity_type | {блюдо,ресторан,заказ}
```

### B.6. FK-ограничения

```sql
SELECT conname, conrelid::regclass AS tbl, confrelid::regclass AS ref
FROM pg_constraint
WHERE contype = 'f'
  AND connamespace = 'bokareva_food'::regnamespace
ORDER BY tbl, conname;
```

Ожидается: не менее 15 FK, все из erd.md.
Факт: 19 FK - все связи из erd.md, три составных (`order_client_address_fk`, `payment_order_amount_fk`, `review_order_client_fk`) и `restaurant_legal_entity_fk`.

### B.7. Пароль — MD5

```sql
SELECT length(password) AS len, password
FROM client LIMIT 5;
```

Ожидается: `len = 32`, hex-строка.
Факт: `len = 32`, например `dd16f2fb356bced6e16de5aed3d519f6`. Строк не из 32 hex-символов - 0.

---

## C. FOOD-102: `insert_test_data(value)`

### C.1. Чистая схема

```sql
CALL erase_test_data();
```

Ожидается: без ошибок.
Факт: без ошибок.

### C.2. Первый запуск

```sql
CALL insert_test_data(10);
```

Ожидается: без ошибок.
Факт: без ошибок.

### C.3. Распределение строк (BR-11.7)

```sql
SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "order"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
ORDER BY tbl;
```

Ожидается: 10, 10, 10, 10, 50, 50, 50, 50, 50.
Факт: client, courier, product_category, restaurant — по 10; address, product, order, review, payment — по 50. Дополнительно: legal_entity 10, client_address 40, courier_pay 60.

### C.4. Адреса ресторанов vs клиентов (BR-11.7)

```sql
SELECT 'restaurant addresses' AS cat, count(*) FROM restaurant WHERE address_id IS NOT NULL
UNION ALL
SELECT 'total addresses', count(*) FROM address;
```

Ожидается: 10 ресторанных адресов, 50 всего → 40 клиентских.
Факт: 10 и 50.

### C.5. Нет пустых строк (BR-11.3)

```sql
SELECT count(*) FROM client WHERE login = '' OR password = '' OR phone_number = '';
-- и аналогично для других varchar-полей с NOT NULL
```

Ожидается: 0.
Факт: 0. По остальным текстовым полям (ФИО курьера, названия ресторана/блюда/категории, описания, текст отзыва) пустых строк тоже 0.

### C.6. Нет NULL там, где запрещено (BR-11.3)

```sql
SELECT count(*) FROM "order" WHERE client_id IS NULL OR restaurant_id IS NULL
  OR courier_id IS NULL OR address_id IS NULL OR total_amount IS NULL;
-- и аналогично для других NOT NULL полей
```

Ожидается: 0.
Факт: 0.

### C.7. Минимум один активный курьер (BR-6.6)

```sql
SELECT count(*) FROM courier WHERE status != 'уволен';
```

Ожидается: `>= 1`.
Факт: 7.

### C.8. `courier_pay` консистентен с правилами (BR-10.2)

```sql
SELECT cp.year, cp.month, cp.courier_id, cp.amount, cp.coefficient_used,
       round(coalesce((
           SELECT sum(o.commission)
           FROM "order" o
           WHERE o.courier_id = cp.courier_id
             AND o.status = 'доставлен'
             AND extract(year  from o.order_timestamp) = cp.year
             AND extract(month from o.order_timestamp) = cp.month
       ), 0) * cp.coefficient_used, 2) AS expected_amount
FROM courier_pay cp
LIMIT 20;
```

Ожидается: `amount = expected_amount` в каждой строке.
Факт: всё сходится, проверяла все 60 строк а не только 20 - расхождений 0.

### C.9. Повторный вызов не ломает

```sql
DO $$
BEGIN
    FOR i IN 1..10 LOOP
        CALL insert_test_data(10);
    END LOOP;
END $$;
```

Ожидается: без ошибок, данные добавляются или заменяются (по решению студента, задокументированному в constraints.md).
Факт: без ошибок, данные добавляются — заказов стало 550.

---

## D. Проверки бизнес-правил на сгенерированных данных

Проверки выполнены после C.9.

### D.1. Все FK валидны (нет orphans)

```sql
SELECT 'order_structure → order' AS fk, count(*) AS orphans
FROM order_structure os
LEFT JOIN "order" o ON os.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'order_structure → product', count(*)
FROM order_structure os
LEFT JOIN product p ON os.product_id = p.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'payment → order', count(*)
FROM payment pmt
LEFT JOIN "order" o ON pmt.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'review → order', count(*)
FROM review r
LEFT JOIN "order" o ON r.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'courier_pay → courier', count(*)
FROM courier_pay cp
LEFT JOIN courier c ON cp.courier_id = c.courier_id
WHERE c.courier_id IS NULL
UNION ALL
SELECT 'client_address → client', count(*)
FROM client_address ca
LEFT JOIN client c ON ca.client_id = c.client_id
WHERE c.client_id IS NULL
UNION ALL
SELECT 'client_address → address', count(*)
FROM client_address ca
LEFT JOIN address a ON ca.address_id = a.address_id
WHERE a.address_id IS NULL;
```

Ожидается: все 0.
Факт: все 0.

### D.2. Минимальная сумма заказа (BR-1.8)

```sql
SELECT count(*) FROM "order" WHERE total_amount < 1000;
```

Ожидается: 0.
Факт: 0.

### D.3. Комиссия = 10% (BR-1.4)

```sql
SELECT count(*) FROM "order" WHERE round(order_amount * 0.10, 2) != commission;
```

Ожидается: 0.
Факт: 0.

### D.4. `total_amount = order_amount + commission`

```sql
SELECT count(*) FROM "order"
WHERE round(order_amount + commission, 2) != total_amount;
```

Ожидается: 0.
Факт: 0.

### D.5. Дата доставки не раньше создания (BR-7.13)

```sql
SELECT count(*) FROM "order"
WHERE delivery_timestamp IS NOT NULL AND delivery_timestamp < order_timestamp;
```

Ожидается: 0.
Факт: 0.

### D.6. Адрес доставки принадлежит клиенту (BR-7.4)

```sql
SELECT count(*) FROM "order" o
LEFT JOIN client_address ca
  ON ca.client_id = o.client_id AND ca.address_id = o.address_id
WHERE ca.client_id IS NULL;
```

Ожидается: 0.
Факт: 0.

### D.7. Все блюда в заказе из одного ресторана (BR-7.3)

```sql
SELECT count(DISTINCT os.order_id)
FROM order_structure os
JOIN "order" o ON os.order_id = o.order_id
JOIN product p ON os.product_id = p.product_id
WHERE p.restaurant_id != o.restaurant_id;
```

Ожидается: 0.
Факт: 0.

### D.8. Ровно одна успешная оплата на заказ (BR-8.1)

```sql
SELECT order_id, count(*) AS cnt
FROM payment
WHERE status = 'успех'
GROUP BY order_id
HAVING count(*) != 1;
```

Ожидается: пусто.
Факт: пусто.

### D.9. Сумма оплаты = `total_amount` заказа (BR-8.4)

```sql
SELECT count(*) FROM payment p
JOIN "order" o ON p.order_id = o.order_id
WHERE p.amount != o.total_amount;
```

Ожидается: 0.
Факт: 0.

### D.10. Нет дубликатов в `client_address` (BR-2.5)

```sql
SELECT client_id, address_id, count(*)
FROM client_address
GROUP BY client_id, address_id
HAVING count(*) > 1;
```

Ожидается: пусто.
Факт: пусто.

### D.11. Нет дубликатов в `order_structure` (BR-7.16)

```sql
SELECT order_id, product_id, count(*)
FROM order_structure
GROUP BY order_id, product_id
HAVING count(*) > 1;
```

Ожидается: пусто.
Факт: пусто.

### D.12. `work_end > work_start` (BR-4.4)

```sql
SELECT count(*) FROM restaurant WHERE work_end <= work_start;
```

Ожидается: 0.
Факт: 0.

### D.13. `dismissal_date >= hire_date` (BR-6.3)

```sql
SELECT count(*) FROM courier
WHERE dismissal_date IS NOT NULL AND dismissal_date < hire_date;
```

Ожидается: 0.
Факт: 0.

### D.14. Рейтинг блюд/ресторанов соответствует отзывам (BR-9.6)

```sql
-- product.rating = AVG(review.rating) по отзывам на блюдо
SELECT p.product_id, p.rating,
       (SELECT round(avg(r.rating), 2) FROM review r
        WHERE r.entity_type = 'блюдо' AND r.entity_id = p.product_id) AS expected
FROM product p
WHERE p.rating IS NOT NULL
LIMIT 20;
```

Ожидается: `rating = expected`.
Факт: совпадает во всех строках (проверяла все 116 блюд с рейтингом, без LIMIT). Для ресторанов аналогичный запрос тоже без расхождений.

---

## E. Функции и процедуры

### E.1. `add_product` — успешный вызов

Запрос из шаблона:

```sql
SELECT count(*) AS before FROM product;

CALL add_product(
    p_restaurant_id => (SELECT restaurant_id FROM restaurant LIMIT 1),
    p_product_category_id => (SELECT product_category_id FROM product_category LIMIT 1),
    p_name => 'Тестовое блюдо',
    p_price => 250,
    p_rating => 4.5,
    p_status => 'доступно',
    p_description => 'Описание'
    -- + photo_url если есть
);

SELECT count(*) AS after FROM product;
```

В таком виде не выполняется: `ERROR: cannot use subquery in CALL argument`. Это ограничение PostgreSQL - в аргументах `CALL` подзапрос нельзя, а `add_product` по AC FOOD-104 именно процедура. Поэтому id ресторана и категории беру заранее через `\gset` (команда psql: сохраняет результат запроса в переменные) и подставляю.

Рабочий вариант (psql):

```sql
SELECT count(*) AS before FROM product;

SELECT restaurant_id AS rid FROM restaurant LIMIT 1 \gset
SELECT product_category_id AS cid FROM product_category LIMIT 1 \gset

CALL add_product(
    p_restaurant_id => :'rid',
    p_product_category_id => :'cid',
    p_name => 'Тестовое блюдо',
    p_price => 250,
    p_rating => 4.5,
    p_status => 'доступно',
    p_description => 'Описание'
);

SELECT count(*) AS after FROM product;
```

Ожидается: `after = before + 1`.
Факт: `before = 550`, `after = 551`.

### E.2. `add_product` — падает на несуществующий ресторан

Запрос из шаблона:

```sql
CALL add_product(
    p_restaurant_id => '00000000-0000-0000-0000-000000000000',
    -- остальные аргументы
);
```

В шаблоне вместо остальных аргументов комментарий, в таком виде это синтаксическая ошибка. Рабочий вариант - категория настоящая (`:'cid'` из E.1), ресторана с таким id нет. Описание передаю, потому что оно обязательно (`product.description NOT NULL`, BR-5.2), иначе вызов упадёт раньше, чем дойдёт до проверки ресторана:

```sql
CALL add_product(
    p_restaurant_id => '00000000-0000-0000-0000-000000000000',
    p_product_category_id => :'cid',
    p_name => 'Тестовое блюдо',
    p_price => 250,
    p_description => 'Описание'
);
```

Ожидается: ошибка с внятным сообщением.
Факт:
```
ERROR:  insert or update on table "product" violates foreign key constraint "product_restaurant_fk"
DETAIL:  Key (restaurant_id)=(00000000-0000-0000-0000-000000000000) is not present in table "restaurant".
```
Ошибку даёт сам FK `product_restaurant_fk`, своих проверок в процедуре нет. Из названия ограничения и DETAIL видно, что нарушено и какое значение не найдено. Аналогично для категории - `product_category_fk`, для отрицательной цены - `product_price_chk`.

### E.3. `rating_change` — пересчитывает рейтинг

Запрос из шаблона:

```sql
-- Выбрать заказ, блюдо и клиента
SELECT p.product_id, p.rating FROM product p WHERE p.rating IS NOT NULL LIMIT 1;

-- Вставить отзыв на это блюдо
INSERT INTO review (review_id, client_id, review_timestamp, entity_id, entity_type, order_id, description, rating)
VALUES (
    exts.uuid_generate_v4(),
    (SELECT client_id FROM client LIMIT 1),
    localtimestamp,
    <product_id>,
    'блюдо',
    (SELECT order_id FROM "order" LIMIT 1),
    'Тестовый отзыв',
    5
);

SELECT rating FROM product WHERE product_id = <product_id>;
```

Здесь клиент, заказ и блюдо берутся `LIMIT 1` из разных таблиц и между собой не связаны. Кроме того, `<product_id>` - заглушка, её надо заменить настоящим id. Но и с настоящим id схема такой отзыв не пропустит: это отзыв на то, чего клиент не заказывал (BR-9.2). Какая проверка сработает, зависит от данных: составной FK `review_order_client_fk` (заказ не этого клиента), триггер `review_entity_check` (блюда нет в заказе) или UNIQUE `review_one_per_entity_uq` (отзыв на это блюдо в этом заказе уже есть, BR-9.5). Когда проверяла, подставив id блюда, получила `duplicate key value violates unique constraint "review_one_per_entity_uq"`; клиент при этом тоже был не тот, что в заказе. Поэтому клиента, заказ и блюдо беру из одного доставленного заказа, где на это блюдо ещё нет отзыва. Блюдо с рейтингом ниже 4 - чтобы отзыв с оценкой 5 точно изменил рейтинг.

Рабочий вариант (psql):

```sql
SELECT os.order_id AS e3_order, o.client_id AS e3_client, os.product_id AS e3_product
FROM order_structure os
JOIN "order" o  USING (order_id)
JOIN product p  USING (product_id)
WHERE p.rating < 4
  AND o.status = 'доставлен'
  AND NOT EXISTS (SELECT 1 FROM review r
                  WHERE r.order_id = os.order_id
                    AND r.entity_type = 'блюдо'
                    AND r.entity_id = os.product_id)
LIMIT 1 \gset

SELECT rating FROM product WHERE product_id = :'e3_product';

INSERT INTO review (client_id, entity_id, entity_type, order_id, description, rating)
VALUES (:'e3_client', :'e3_product', 'блюдо', :'e3_order', 'Тестовый отзыв', 5)
RETURNING review_id AS e3_review \gset

SELECT rating FROM product WHERE product_id = :'e3_product';
```

Ожидается: `rating` пересчитан.
Факт: у блюда был 1 отзыв и `rating = 3.00`; после отзыва с оценкой 5 - `4.00` (= среднее по 2 отзывам).

### E.4. `rating_change` — удаление отзыва

Запрос из шаблона:

```sql
-- Удалить отзыв из E.3
DELETE FROM review WHERE review_id = <review_id>;

SELECT rating FROM product WHERE product_id = <product_id>;
```

Рабочий вариант - id отзыва и блюда из переменных E.3. Дополнительно в транзакции удаляю все отзывы на блюдо, чтобы проверить `rating IS NULL`, и откатываю:

```sql
DELETE FROM review WHERE review_id = :'e3_review';
SELECT rating FROM product WHERE product_id = :'e3_product';

BEGIN;
DELETE FROM review WHERE entity_type = 'блюдо' AND entity_id = :'e3_product';
SELECT rating FROM product WHERE product_id = :'e3_product';
ROLLBACK;
```

Ожидается: если других отзывов нет — `rating IS NULL`; иначе — пересчитан.
Факт: `3.00` - пересчитан обратно по оставшемуся отзыву. После удаления всех отзывов на это блюдо - `rating IS NULL` (транзакцию откатила).

### E.5. `get_statistic()`

```sql
SELECT * FROM get_statistic();
```

Ожидается:
- Колонки: `restaurant_name`, `best_product_name`, `total_amount`, `avg_amount`, `best_user`.
- По одной строке на ресторан.
- `best_user` = `client.login` (не NULL при наличии заказов).

Факт: колонки совпадают; 110 строк на 110 ресторанов; `total_amount < avg_amount` - 0 строк; у ресторанов с заказами `best_product_name` и `best_user` заполнены везде; все `best_user` - логины из `client`.

### E.6. `courier_salary()`

```sql
-- До
SELECT courier_id, coefficient FROM courier ORDER BY courier_id;

CALL courier_salary();

-- После
SELECT courier_id, coefficient FROM courier ORDER BY courier_id;
SELECT year, month, courier_id, amount, coefficient_used
FROM courier_pay
ORDER BY year DESC, month DESC, courier_id
LIMIT 20;
```

Ожидается:
- `courier.coefficient` пересчитан для работающих (по BR-10.2).
- У уволенных — не изменился.
- `courier_pay` содержит запись за текущий месяц.

Факт: у всех 83 работающих курьеров новый коэффициент соответствует BR-10.2 по числу доставок за месяц, у 27 уволенных не изменился; за 2026-11 есть по одной записи на каждого из 110 курьеров, `coefficient_used` у всех = коэффициенту до вызова.

### E.7. `courier_salary()` — повторный вызов

```sql
CALL courier_salary();
SELECT count(*) FROM courier_pay
WHERE year = extract(year from current_date)
  AND month = extract(month from current_date);
```

Ожидается: количество не изменилось (idempotency / обновление).
Факт: 110 до и после.

---

## F. Представление `how_much_money`

### F.1. Колонки

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'bokareva_food'
  AND table_name = 'how_much_money'
ORDER BY ordinal_position;
```

Ожидается: `year_month` (text), `sum_no_commission`, `sum_with_commission`, `commission`, `prev_commission`, `commission_diff`, `courier_pay`, `net_profit` (numeric).
Факт: совпадает.

### F.2. Месяцы покрыты

```sql
SELECT * FROM how_much_money ORDER BY year_month;
```

Ожидается: месяцы от первого доставленного заказа до последнего (не пропущено ни одного).
Факт: 6 месяцев подряд, с 2026-06 по 2026-11.

### F.3. Месяцы без заказов присутствуют (BR-11.9)

```sql
SELECT year_month FROM how_much_money
WHERE sum_no_commission = 0 OR sum_no_commission IS NULL;
```

Ожидается: если в какие-то месяцы заказов не было — они есть в результате.
Факт: пусто, в сгенерированных данных заказы есть в каждом месяце. Чтобы проверить, удалила в транзакции все заказы за август (вместе с их отзывами и оплатами) и откатила - август остался в отчёте с нулями.

### F.4. Корректность сумм

```sql
SELECT year_month,
       sum_no_commission,
       sum_with_commission,
       commission,
       prev_commission,
       commission_diff,
       courier_pay,
       net_profit
FROM how_much_money
ORDER BY year_month
LIMIT 10;
```

Ожидается:
- `commission = sum_with_commission - sum_no_commission`.
- `commission_diff = commission - prev_commission` (NULL для первого месяца).
- `net_profit = commission - courier_pay`.

Факт: все три равенства выполняются; у первого месяца `prev_commission` и `commission_diff` — NULL.

---

## G. Права `inspector`

### G.1. Права на схему

```sql
SELECT
    nspname AS schema_name,
    has_schema_privilege('inspector', nspname, 'USAGE')  AS usage,
    has_schema_privilege('inspector', nspname, 'CREATE') AS create
FROM pg_namespace
WHERE nspname = 'bokareva_food';
```

Ожидается: `bokareva_food`, `true`, `true` (полный доступ).
Факт: `bokareva_food | t | t`

### G.2. Права на таблицы

```sql
SELECT table_name, string_agg(privilege_type, ', ') AS privs
FROM information_schema.role_table_grants
WHERE grantee = 'inspector' AND table_schema = 'bokareva_food'
GROUP BY table_name;
```

Ожидается: у каждой таблицы `SELECT, INSERT, UPDATE, DELETE` (или `ALL`).
Факт: у всех 13 таблиц и у представления — полный набор прав: `DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE` (`ALL`).

### G.3. `information_schema` читается под `inspector`

```sql
SET ROLE inspector;
SELECT count(*) FROM information_schema.tables
WHERE table_schema = 'bokareva_food';
RESET ROLE;
```

Ожидается: 12 + N (количество таблиц).
Факт: 14 (13 таблиц + представление).

### G.4. `pg_catalog` читается под `inspector`

```sql
SET ROLE inspector;
SELECT count(*) FROM pg_catalog.pg_tables
WHERE schemaname = 'bokareva_food';
RESET ROLE;
```

Ожидается: 12 + N.
Факт: 13.

### G.5. Все процедуры/функции работают под `inspector`

```sql
SET ROLE inspector;
SET search_path TO bokareva_food, exts;

CALL erase_test_data();
CALL insert_test_data(10);
CALL courier_salary();
SELECT * FROM get_statistic();
SELECT * FROM how_much_money LIMIT 5;

RESET ROLE;
```

Ожидается: без `permission denied`.
Факт: всё выполнилось без ошибок.

---

## H. Оптимизация `get_statistic` (BR-11.8)

### H.1. `EXPLAIN ANALYZE` — паттерн «избыточные подзапросы»

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       (SELECT count(*) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен') AS cnt,
       (SELECT coalesce(sum(commission), 0) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен') AS commission_sum
FROM courier c;
```

Ожидается: два SubPlan, каждый — скан `"order"`. Время растёт линейно от числа курьеров.
Факт: время 1.037 мс, план: Seq Scan on courier + два SubPlan, каждый читает `"order"` 10 раз (loops=10 - после G.5 в базе 10 курьеров).

### H.2. `EXPLAIN ANALYZE` — паттерн «один JOIN»

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       count(o.order_id) AS cnt,
       coalesce(sum(o.commission), 0) AS commission_sum
FROM courier c
LEFT JOIN "order" o ON o.courier_id = c.courier_id AND o.status = 'доставлен'
GROUP BY c.courier_id;
```

Ожидается: один `Hash Right Join` / `Hash Left Join`, один скан `"order"`. Время меньше, чем в H.1.
Факт: время 0.165 мс, план: HashAggregate → Hash Left Join, `"order"` читается один раз.

### H.3. Применить к `get_statistic`

```sql
EXPLAIN ANALYZE SELECT * FROM get_statistic();
```

Ожидается: без `LATERAL`, без множественных подзапросов к одной таблице, без оконных функций там, где хватает агрегата.
Факт: `LATERAL`, SubPlan и WindowAgg нет, `DISTINCT ON` тоже; `"order"` читается один раз в CTE `delivered`, остальные таблицы — тоже по одному разу. Время 2.1 мс.
На саму функцию explain показывает только `Function Scan`, внутрь не заглядывает - поэтому план смотрела по запросу из тела функции.

---

## I. Очистка и повторная генерация

### I.1. `erase_test_data` очищает всё

```sql
CALL erase_test_data();

SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'legal_entity', count(*) FROM legal_entity
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "order"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
UNION ALL SELECT 'order_structure', count(*) FROM order_structure
UNION ALL SELECT 'client_address', count(*) FROM client_address
UNION ALL SELECT 'courier_pay', count(*) FROM courier_pay;
```

Ожидается: все 0.
Факт: все 0.

### I.2. Повторный `erase_test_data` не падает

```sql
CALL erase_test_data();
```

Ожидается: без ошибок.
Факт: без ошибок.

### I.3. После очистки `insert_test_data` снова работает

```sql
CALL insert_test_data(10);
SELECT count(*) FROM "order";
```

Ожидается: 50.
Факт: 50.
