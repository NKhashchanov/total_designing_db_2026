-- FOOD-101. Физическая модель.
set search_path to mineev_food, pg_catalog;

-- Учетные данные и телефон клиента.
create table client (
    client_id uuid primary key default exts.uuid_generate_v4(),
    login varchar(100) not null unique,
    password varchar(32) not null,
    phone_number char(12) not null unique,
    constraint client_login_nonempty check (btrim(login) <> ''),
    constraint client_password_md5 check (password ~ '^[0-9a-fA-F]{32}$'),
    constraint client_phone_nonempty check (btrim(phone_number) <> '')
);

-- Адреса доставки и расположения ресторанов.
create table address (
    address_id uuid primary key default exts.uuid_generate_v4(),
    street varchar(150) not null,
    house_number varchar(20) not null,
    apartment_office varchar(20),
    constraint address_street_nonempty check (btrim(street) <> ''),
    constraint address_house_nonempty check (btrim(house_number) <> ''),
    constraint address_unit_nonempty check (apartment_office is null or btrim(apartment_office) <> ''),
    constraint address_physical_unique unique nulls not distinct (street, house_number, apartment_office)
);

-- Связь клиентов с доступными им адресами.
create table client_address (
    client_id uuid references client(client_id),
    address_id uuid references address(address_id),
    primary key (client_id, address_id)
);

-- Рестораны, реквизиты, режим работы и рейтинг.
create table restaurant (
    restaurant_id uuid primary key default exts.uuid_generate_v4(),
    restaurant_name varchar(255) not null,
    address_id uuid not null unique references address(address_id),
    description text not null,
    work_start time not null,
    work_end time not null,
    company_details text not null,
    rating numeric(3,2),
    status restaurant_status not null,
    constraint restaurant_name_nonempty check (btrim(restaurant_name) <> ''),
    constraint restaurant_description_nonempty check (btrim(description) <> ''),
    constraint restaurant_details_nonempty check (btrim(company_details) <> ''),
    constraint restaurant_work_time check (work_end > work_start),
    constraint restaurant_rating_range check (rating between 0 and 5)
);

-- Курьеры, даты работы и текущий коэффициент зарплаты.
create table courier (
    courier_id uuid primary key default exts.uuid_generate_v4(),
    fio varchar(255) not null,
    phone_number char(12) not null,
    status courier_status not null,
    hire_date date not null,
    dismissal_date date,
    coefficient numeric(2,1) not null default 0.1,
    constraint courier_fio_nonempty check (btrim(fio) <> ''),
    constraint courier_phone_nonempty check (btrim(phone_number) <> ''),
    constraint courier_dismissal_status check ((status = 'уволен') = (dismissal_date is not null)),
    constraint courier_dismissal_date check (dismissal_date >= hire_date),
    constraint courier_coefficient_range check (coefficient between 0.1 and 0.5)
);

-- История ежемесячных выплат и примененных коэффициентов.
create table courier_pay (
    year integer not null,
    month integer not null,
    courier_id uuid references courier(courier_id),
    amount numeric(14,2) not null,
    coefficient_used numeric(2,1) not null,
    primary key (year, month, courier_id),
    constraint courier_pay_year_range check (year between 1 and 9999),
    constraint courier_pay_month_range check (month between 1 and 12),
    constraint courier_pay_amount_nonnegative check (amount >= 0 and amount <> 'NaN'::numeric),
    constraint courier_pay_coefficient_range check (coefficient_used between 0.1 and 0.5)
);

-- Справочник категорий блюд.
create table product_category (
    product_category_id uuid primary key default exts.uuid_generate_v4(),
    product_category_name varchar(150) not null,
    constraint product_category_name_nonempty check (btrim(product_category_name) <> '')
);

-- Меню ресторанов с ценами, статусами и рейтингами.
create table product (
    product_id uuid primary key default exts.uuid_generate_v4(),
    product_name varchar(255) not null,
    product_category_id uuid not null references product_category(product_category_id),
    price numeric(14,2) not null,
    restaurant_id uuid not null references restaurant(restaurant_id),
    photo_url text,
    rating numeric(3,2),
    status product_status not null,
    description text not null,
    constraint product_name_nonempty check (btrim(product_name) <> ''),
    constraint product_description_nonempty check (btrim(description) <> ''),
    constraint product_photo_nonempty check (photo_url is null or btrim(photo_url) <> ''),
    constraint product_price_nonnegative check (price >= 0 and price <> 'NaN'::numeric),
    constraint product_rating_range check (rating between 0 and 5)
);

-- Заказы клиентов, суммы, доставка и состояние оплаты.
create table "order" (
    order_id uuid primary key default exts.uuid_generate_v4(),
    courier_id uuid not null references courier(courier_id),
    client_id uuid not null references client(client_id),
    address_id uuid not null references address(address_id),
    restaurant_id uuid not null references restaurant(restaurant_id),
    order_timestamp timestamp not null default localtimestamp,
    delivery_timestamp timestamp,
    order_amount numeric(14,2) not null,
    commission numeric(14,2) not null,
    total_amount numeric(14,2) not null,
    status order_status not null,
    pay_status order_pay_status not null default 'ожидает',
    description text not null,
    constraint order_client_address_fk foreign key (client_id, address_id)
        references client_address(client_id, address_id),
    constraint order_client_pair_unique unique (order_id, client_id),
    constraint order_description_nonempty check (btrim(description) <> ''),
    constraint order_amount_nonnegative check (order_amount >= 0 and order_amount <> 'NaN'::numeric),
    constraint order_commission_check check (commission = round(order_amount * 0.10, 2)),
    constraint order_total_check check (total_amount = order_amount + commission),
    constraint order_minimum_amount check (total_amount >= 1000),
    constraint order_delivery_time check (delivery_timestamp >= order_timestamp),
    constraint order_delivered_time check (status <> 'доставлен' or delivery_timestamp is not null)
);

-- Позиции заказа с количеством и ценой на момент покупки.
create table order_structure (
    order_id uuid references "order"(order_id),
    product_id uuid references product(product_id),
    quantity numeric(12,3) not null,
    -- Цена фиксируется на момент покупки, а не читается из текущего меню.
    unit_price numeric(14,2) not null,
    primary key (order_id, product_id),
    constraint order_structure_quantity_positive check (quantity > 0 and quantity <> 'NaN'::numeric),
    constraint order_structure_price_nonnegative check (unit_price >= 0 and unit_price <> 'NaN'::numeric)
);

-- Попытки оплаты заказа и финансовые транзакции.
create table payment (
    payment_id uuid primary key default exts.uuid_generate_v4(),
    order_id uuid not null references "order"(order_id),
    payment_type payment_type not null,
    amount numeric(14,2) not null,
    -- Внешний идентификатор транзакции; тестовый провайдер выдает UUID.
    transaction_id uuid not null unique,
    transaction_timestamp timestamp not null default localtimestamp,
    status payment_status not null,
    constraint payment_amount_nonnegative check (amount >= 0 and amount <> 'NaN'::numeric)
);

-- Отзывы клиентов на блюда, рестораны и заказы.
create table review (
    review_id uuid primary key default exts.uuid_generate_v4(),
    client_id uuid not null references client(client_id),
    review_timestamp timestamp not null default localtimestamp,
    entity_id uuid not null,
    entity_type review_entity_type not null,
    order_id uuid not null references "order"(order_id),
    description text not null,
    photo_url text,
    rating numeric(3,2) not null,
    constraint review_author_order_fk foreign key (order_id, client_id)
        references "order"(order_id, client_id),
    constraint review_object_unique unique (order_id, entity_type, entity_id),
    constraint review_description_nonempty check (btrim(description) <> ''),
    constraint review_photo_nonempty check (photo_url is null or btrim(photo_url) <> ''),
    constraint review_rating_range check (rating between 1 and 5)
);
