# Обоснование ограничений FoodExpress

Рабочая схема `mineev_food`. Нумерация правил соответствует [бизнес-правилам](../docs/company-rules.md). Физическая модель: [типы](schema/01_types.sql), [таблицы](schema/02_tables.sql), [индексы](schema/03_constraints.sql), [триггеры](schema/04_triggers.sql).

## ENUM-типы

| Тип | Значения | BR |
|---|---|---|
| restaurant_status | активен, неактивен | BR-4.3 |
| product_status | доступно, нет_в_наличии, архив | BR-5.5 |
| courier_status | свободен, занят, на_доставке, уволен | BR-6.2 |
| order_status | создан, готовится, в_доставке, доставлен, отменён | BR-7.7 |
| order_pay_status | ожидает, оплачен, ошибка | BR-7.9 |
| payment_status | успех, ошибка, в_обработке | BR-8.2 |
| payment_type | карта, наличные, безнал | BR-8.2 |
| review_entity_type | блюдо, ресторан, заказ | BR-9.1 |

Ровно восемь типов. Значения не изменены (BR-11.5).

## Особенности ссылочной целостности

### 1. Платежные операции

Помимо `payment_id` и `order_id` таблица содержит `payment_type`, `amount`, `transaction_id`, `transaction_timestamp`, `status`: это сведения о конкретной попытке платежа по BR-8.2. `transaction_id` выбран UUID, уникален и не имеет DEFAULT: провайдер должен передать его сам. Для генератора тестовый провайдер имитируется через `exts.uuid_generate_v4()`. Тип оплаты в `payment`, а не в заказе (BR-8.6): при повторной попытке способ оплаты может измениться. Данных карт нет (BR-1.7, BR-8.5).

### 2. Принадлежность адреса клиенту

`foreign key (client_id, address_id) references client_address(client_id, address_id)` на `order` обеспечивает BR-7.4. Два отдельных FK на клиента и адрес не гарантируют принадлежность адреса клиенту. Пара в таблице связи уникальна по PK. Удалить эту привязку, пока заказ на нее ссылается, нельзя: история заказов сохраняется (BR-3.5).

### 3. Один ресторан в заказе

`order_position_check` (BEFORE INSERT/UPDATE) проверяет совпадение ресторана блюда и ресторана заказа (BR-7.3). `restaurant_id` не дублируется в `order_structure`: это исключает зависимость от части составного ключа. Для обратных изменений `product_restaurant_guard` запрещает смену ресторана у уже заказанного блюда, а отложенная проверка заказа повторно сверяет ресторан со всеми позициями при изменении самого заказа. FK обеспечивает существование объектов. Для заказа проверяется итоговая сумма позиций и наличие хотя бы одной позиции (BR-7.10, BR-7.14); проверки отложены, поскольку при вставке заголовка его позиции еще не существуют.

### 4. Полиморфный review

Сохранены `entity_id`, `entity_type` и `order_id` из ERD. Обычный FK на entity_id не подходит, потому что целевая таблица определяется типом. `review_object_check` проверяет: для блюда — наличие позиции с данным product_id в указанном заказе; для ресторана — совпадение с restaurant_id заказа; для заказа — совпадение с order_id. Автор должен быть владельцем заказа (BR-9.2); дополнительно используется составной FK `(order_id, client_id)`. Уникальность `(order_id, entity_type, entity_id)` ограничивает отзывы на один объект в рамках заказа (BR-9.5). Отложенная проверка заказа предотвращает удаление позиции, на которую есть отзыв, или смену ресторана, нарушающую отзыв. Триггер `review_rating_change` обновляет агрегаты при INSERT/UPDATE/DELETE (BR-9.6, BR-9.7).

## CHECK-ограничения

Все имена приведены в `02_tables.sql`. `btrim(...) <> ''` запрещает пустые и состоящие только из пробелов обязательные строки. Для nullable-строк пустое значение представляется NULL, а не пустой строкой. `NaN` дополнительно исключен из неотрицательных чисел, поскольку специальное значение PostgreSQL numeric иначе могло бы пройти сравнение `>= 0`.

| Таблица | Имя ограничения | Условие | BR и обоснование |
|---|---|---|---|
| client | client_login_nonempty | btrim(login) <> '' | BR-2.1, BR-11.3 — логин обязателен |
| client | client_password_md5 | password ~ '^[0-9a-fA-F]{32}$' | BR-2.3 — ровно MD5 в hex |
| client | client_phone_nonempty | btrim(phone_number) <> '' | BR-2.1, BR-11.3 — телефон обязателен |
| address | address_street_nonempty | btrim(street) <> '' | BR-3.1, BR-11.3 — улица обязательна |
| address | address_house_nonempty | btrim(house_number) <> '' | BR-3.1, BR-11.3 — номер дома обязателен |
| address | address_unit_nonempty | apartment_office is null or btrim(apartment_office) <> '' | BR-3.2, BR-11.3 — квартира/офис необязательны, но не пустая строка |
| restaurant | restaurant_name_nonempty | btrim(restaurant_name) <> '' | BR-4.1, BR-11.3 — название обязательно |
| restaurant | restaurant_description_nonempty | btrim(description) <> '' | BR-4.1, BR-11.3 — описание обязательно |
| restaurant | restaurant_details_nonempty | btrim(company_details) <> '' | BR-4.1, BR-4.5, BR-11.3 — реквизиты обязательны |
| restaurant | restaurant_work_time | work_end > work_start | BR-4.4 — закрытие позже открытия |
| restaurant | restaurant_rating_range | rating between 0 and 5 | BR-4.2 — диапазон рейтинга; NULL допускается по BR-9.7 |
| courier | courier_fio_nonempty | btrim(fio) <> '' | BR-6.1, BR-11.3 — ФИО обязательно |
| courier | courier_phone_nonempty | btrim(phone_number) <> '' | BR-6.1, BR-11.3 — телефон обязателен |
| courier | courier_dismissal_status | (status = 'уволен') = (dismissal_date is not null) | BR-6.3, BR-11.3 — уволенный имеет дату, работающий не имеет |
| courier | courier_dismissal_date | dismissal_date >= hire_date | BR-6.3 — увольнение не раньше найма |
| courier | courier_coefficient_range | coefficient between 0.1 and 0.5 | BR-6.4 — допустимый коэффициент |
| courier_pay | courier_pay_year_range | year between 1 and 9999 | BR-10.1, BR-10.3, BR-11.6 — календарный год, совместимый с YYYY-MM |
| courier_pay | courier_pay_month_range | month between 1 and 12 | BR-10.1, BR-10.3 — календарный месяц |
| courier_pay | courier_pay_amount_nonnegative | amount >= 0 and amount <> NaN | BR-10.4 — зарплата неотрицательна |
| courier_pay | courier_pay_coefficient_range | coefficient_used between 0.1 and 0.5 | BR-6.4, BR-10.2 — использованный коэффициент в диапазоне |
| product_category | product_category_name_nonempty | btrim(product_category_name) <> '' | BR-5.7, BR-11.3 — название категории обязательно |
| product | product_name_nonempty | btrim(product_name) <> '' | BR-5.2, BR-11.3 — название обязательно |
| product | product_description_nonempty | btrim(description) <> '' | BR-5.2, BR-11.3 — описание обязательно |
| product | product_photo_nonempty | photo_url is null or btrim(photo_url) <> '' | BR-5.6 — фотография необязательна; нет пустой ссылки |
| product | product_price_nonnegative | price >= 0 and price <> NaN | BR-5.3 — цена неотрицательна |
| product | product_rating_range | rating between 0 and 5 | BR-5.4 — допустимый диапазон, NULL по BR-9.7 |
| order | order_description_nonempty | btrim(description) <> '' | BR-11.3, ERD — описание предусмотрено контрактом и не указано как nullable |
| order | order_amount_nonnegative | order_amount >= 0 and order_amount <> NaN | BR-5.3, BR-7.10 — стоимость блюд неотрицательна |
| order | order_commission_check | commission = round(order_amount * 0.10, 2) | BR-1.4, BR-7.10 — комиссия 10%, округление до копеек |
| order | order_total_check | total_amount = order_amount + commission | BR-1.5, BR-7.10 — полная стоимость |
| order | order_minimum_amount | total_amount >= 1000 | BR-1.8, BR-7.11 — минимальная сумма |
| order | order_delivery_time | delivery_timestamp >= order_timestamp | BR-7.13 — хронология; NULL допускается до завершения |
| order | order_delivered_time | status <> 'доставлен' or delivery_timestamp is not null | BR-7.12 — доставленный заказ имеет время завершения |
| order_structure | order_structure_quantity_positive | quantity > 0 and quantity <> NaN | BR-7.15 — положительное, допускается дробное |
| order_structure | order_structure_price_nonnegative | unit_price >= 0 and unit_price <> NaN | BR-5.3, BR-7.10 — историческая цена позиции неотрицательна |
| payment | payment_amount_nonnegative | amount >= 0 and amount <> NaN | BR-8.4, BR-7.11 — денежная сумма согласуется с заказом |
| review | review_description_nonempty | btrim(description) <> '' | BR-9.3, BR-11.3 — текст обязателен |
| review | review_photo_nonempty | photo_url is null or btrim(photo_url) <> '' | BR-9.3 — фото необязательно, нет пустой ссылки |
| review | review_rating_range | rating between 1 and 5 | BR-9.4 — оценка от 1 до 5 |

## PK и UNIQUE

| Таблица | Ключ / ограничение | BR и обоснование |
|---|---|---|
| client | PK client_id | BR-11.1 — UUID записи |
| address | PK address_id | BR-11.1 — UUID адреса |
| restaurant | PK restaurant_id | BR-11.1 — UUID ресторана |
| courier | PK courier_id | BR-11.1 — UUID курьера |
| product_category | PK product_category_id | BR-5.7, BR-11.1 — UUID категории |
| product | PK product_id | BR-11.1 — UUID блюда |
| order | PK order_id | BR-11.1 — UUID заказа |
| payment | PK payment_id | BR-11.1 — UUID попытки оплаты |
| review | PK review_id | BR-11.1 — UUID отзыва |
| client_address | PK (client_id, address_id) | BR-2.5 — уникальная привязка |
| order_structure | PK (order_id, product_id) | BR-7.16 — одна строка блюда на заказ |
| courier_pay | PK (year, month, courier_id) | BR-10.3 — одна выплата на курьера и месяц |
| client | UNIQUE (login) | BR-2.2 — логин уникален |
| client | UNIQUE (phone_number) | BR-2.2 — телефон уникален |
| address | UNIQUE NULLS NOT DISTINCT (street, house_number, apartment_office) | BR-3.3, BR-3.4 — один физический адрес должен иметь один ID; иначе два ресторана обошли бы UNIQUE address_id через две одинаковые строки. NULL трактуется как отсутствие квартиры, а не произвольное значение |
| restaurant | UNIQUE (address_id) | BR-3.3 — один физический адрес не может принадлежать двум ресторанам |
| order | order_client_pair_unique UNIQUE (order_id, client_id) | BR-9.2 — технический ключ для составного FK автора отзыва; пара уже логически уникальна благодаря PK order_id |
| payment | UNIQUE (transaction_id) | BR-8.3 — внешний ID транзакции уникален |
| payment | payment_one_success UNIQUE INDEX (order_id) WHERE status = 'успех' | BR-8.1 — не более одной успешной попытки на заказ |
| review | review_object_unique UNIQUE (order_id, entity_type, entity_id) | BR-9.5 — не более одного отзыва на объект в заказе |

Имена ресторанов, блюд, категорий и телефоны курьеров не имеют ограничения уникальности. Адресная уникальность сравнивает сохраненные компоненты буквально; стандартизация написания улицы относится к вводу данных.

## FK-ограничения

Все FK по умолчанию NO ACTION. Никакого автоматического каскадного удаления истории. Для связей обязательность обеспечена NOT NULL либо составным PK.

| Таблица | Столбцы | → Таблица | BR и обоснование |
|---|---|---|---|
| client_address | client_id | client(client_id) | BR-2.4 — существует клиент привязки |
| client_address | address_id | address(address_id) | BR-2.4 — существует адрес привязки |
| restaurant | address_id | address(address_id) | BR-3.3 — один существующий адрес |
| courier_pay | courier_id | courier(courier_id) | BR-10.1, BR-10.2 — выплата конкретному курьеру |
| product | product_category_id | product_category(product_category_id) | BR-5.1 — одна существующая категория |
| product | restaurant_id | restaurant(restaurant_id) | BR-5.1 — один существующий ресторан |
| order | courier_id | courier(courier_id) | BR-7.5 — курьер заказа |
| order | client_id | client(client_id) | BR-7.1, BR-7.2 — клиент заказа |
| order | address_id | address(address_id) | BR-7.4 — адрес доставки |
| order | restaurant_id | restaurant(restaurant_id) | BR-7.2 — ресторан заказа |
| order | client_id, address_id | client_address(client_id, address_id) | BR-7.4 — адрес принадлежит клиенту |
| order_structure | order_id | order(order_id) | BR-7.14 — позиция существующего заказа |
| order_structure | product_id | product(product_id) | BR-7.14 — позиция существующего блюда |
| payment | order_id | order(order_id) | BR-8.1, BR-8.2 — попытка оплаты заказа |
| review | client_id | client(client_id) | BR-9.2 — существующий автор |
| review | order_id | order(order_id) | BR-9.2 — заказ-основание |
| review | order_id, client_id | order(order_id, client_id) | BR-9.2 — отзыв автора, который оформил заказ |

Всего 17 FK: все 15 из концептуальной ERD и два составных. Отдельные FK на order.client_id, order.address_id и review.client_id сохранены по контракту ERD, хотя часть их гарантий следует из составных FK. `entity_id` не имеет прямого FK; обоснование в разделе «Полиморфный review».

## NOT NULL

Первичные ключи и обязательные внешние ключи описаны в соответствующих разделах. Все поля, не перечисленные в разделе NULL, обязательны согласно BR-11.3; состав полей согласован с ERD.

| Таблица | Столбцы | BR и обоснование |
|---|---|---|
| client | login, password, phone_number | BR-2.1–BR-2.3 — данные регистрации |
| restaurant | status, work_start, work_end | BR-4.3, BR-4.4 — статус и время работы обязательны |
| courier | status, hire_date, coefficient | BR-6.1–BR-6.5 — состояние сотрудника и действующий коэффициент |
| courier_pay | amount, coefficient_used | BR-10.2 — сумма и использованный коэффициент |
| order | order_timestamp, status, pay_status, order_amount, commission, total_amount | BR-7.1, BR-7.6–BR-7.12 — момент заказа, состояния и суммы |
| order_structure | quantity, unit_price | BR-7.10, BR-7.15 — количество и цена для расчета суммы |
| payment | payment_type, amount, transaction_id, transaction_timestamp, status | BR-8.2, BR-8.3 — атрибуты каждой попытки |
| review | entity_id, entity_type, rating, review_timestamp | BR-9.1–BR-9.4 — объект и оценка отзыва |

## NULL (осознанно разрешено)

| Таблица | Столбец | BR и объяснение |
|---|---|---|
| address | apartment_office | BR-3.2 — частный дом или отдельный вход |
| courier | dismissal_date | BR-6.3, BR-11.3 — у работающего отсутствует |
| order | delivery_timestamp | BR-7.12 — до доставки может отсутствовать |
| product | photo_url | BR-5.6 — фото необязательно |
| review | photo_url | BR-9.3 — фото необязательно |
| restaurant, product | rating | BR-9.7 — нет отзывов, среднее неизвестно |

## DEFAULT и вычисляемые значения

| Таблица | Поле | Решение |
|---|---|---|
| Все сущности с собственным UUID PK | *_id | DEFAULT exts.uuid_generate_v4(), BR-11.1 |
| courier | coefficient | DEFAULT 0.1, BR-6.5 |
| order | order_timestamp | DEFAULT localtimestamp, BR-7.1, BR-11.2 |
| order | pay_status | DEFAULT 'ожидает', BR-7.9, BR-8.7 (нет попыток) |
| payment, review | transaction_timestamp, review_timestamp | DEFAULT localtimestamp, BR-8.2, BR-9.3 |
| order_structure | unit_price | BEFORE INSERT подставляет цену блюда, если поле не передано; можно передать историческую цену явно. BR-7.10 |
| order | commission, total_amount | Обычные numeric с CHECK, а не GENERATED: совместимы с явной вставкой значений, предусмотренной контрактом операции. BR-1.4, BR-7.10 |
| restaurant, product | rating | NULL по умолчанию, вычисляется рейтингом отзывов, BR-9.6, BR-9.7 |

## Межтабличные правила и триггеры

| Механизм | BR | Гарантия |
|---|---|---|
| order_position_check | BR-7.3, BR-7.10 | Блюдо относится к ресторану заказа; сохраняется цена позиции |
| product_restaurant_guard | BR-7.3 | Нельзя сменой ресторана блюда нарушить историю |
| order_final_check, order_structure_final_check | BR-7.3, BR-7.10, BR-7.14, BR-8.4, BR-8.7, BR-9.2 | При COMMIT у заказа есть позиции, их сумма согласована, ресторан и отзывы валидны, сумма попыток и агрегированный статус согласованы |
| payment_amount_check | BR-8.4 | Сумма каждой попытки равна полной сумме заказа |
| payment_status_change | BR-8.7 | Пересчет pay_status при вставке, изменении и удалении платежей; для переноса попытки обновляются оба заказа |
| review_object_check | BR-9.1, BR-9.2 | Отзыв на фактически заказанный объект своего заказа |
| review_rating_change | BR-9.6, BR-9.7 | Пересчет среднего старого и нового объектов, NULL без отзывов, заказ не имеет агрегата |
| product_rating_check, restaurant_rating_check | BR-9.6, BR-9.7 | Прямая запись рейтинга не может отличаться от среднего по отзывам |

Триггеры строковые. Отложенная проверка заказа читает финальное состояние (если заказ удален, проверять уже нечего). Заголовок и позиции создаются в одной транзакции. При смене суммы сначала меняется заказ, затем все попытки оплаты в той же транзакции. При удалении всех данных сначала удаляются отзывы и платежи, затем позиции и заказы. Индексы на FK, order_timestamp, review(entity_type, entity_id) помогают проверкам и агрегатам. Уникальный частичный индекс предотвращает одновременное создание двух успешных платежей. Платежи и обновление рейтинга блокируют соответствующие родительские строки для согласованного пересчета; при конкурирующих транзакциях с конфликтующим порядком блокировок PostgreSQL может потребовать повтор транзакции.

## Связь с логической моделью

Функциональные зависимости и исключения из строгой 3НФ описаны в [логической модели](docs/logical_model.md#функциональные-зависимости-и-нормализация).

## Уточнения контрактов

- BR-11.7 использует clients, ERD — client. Используется client. `"order"` в двойных кавычках по BR-13.1, в соответствии с именем сущности.

- BR-8.1 формулирует «ровно одна успешная», но BR-8.7 допускает неоплаченные заказы. Инвариант: не более одной успешной попытки; для оплаченного заказа — ровно одна, для ожидающего/ошибки — ноль. При отсутствии попыток статус «ожидает».

- Бизнес-правило BR-6.6 (активный курьер) обеспечивается генератором, а не ограничением всей таблицы, поэтому очистка допустима. Ограничение связи заказа с адресом и сохранение истории не позволяют произвольно удалять ранее использованный адрес или клиента.
