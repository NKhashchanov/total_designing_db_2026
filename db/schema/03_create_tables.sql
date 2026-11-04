create table client (
    client_id uuid not null default exts.uuid_generate_v4(),
    login varchar(50) not null,
    password varchar(32) not null,
    phone_number varchar(20) not null
);
alter table client add constraint pk_client primary key (client_id);
alter table client add constraint uq_client_login unique (login);
alter table client add constraint uq_client_phone unique (phone_number);
alter table client add constraint chk_client_login_not_empty check (length(trim(login)) > 0);
alter table client add constraint chk_client_password_md5 check (length(password) = 32);
alter table client add constraint chk_client_phone_not_empty check (length(trim(phone_number)) > 0);

-----------
create table address (
    address_id uuid not null default exts.uuid_generate_v4(),
    street varchar(100) not null,
    house_number varchar(20) not null,
    apartment_office varchar(20)
);
alter table address add constraint pk_address primary key (address_id);
alter table address add constraint chk_address_street_not_empty check (length(trim(street)) > 0);
alter table address add constraint chk_address_house_not_empty check (length(trim(house_number)) > 0);

-----------
create table client_address (
    client_id uuid not null,
    address_id uuid not null
);
alter table client_address add constraint pk_client_address primary key (client_id, address_id);
alter table client_address add constraint fk_client_address_client 
		foreign key (client_id) references client (client_id) on delete cascade;
alter table client_address add constraint fk_client_address_address foreign key (address_id) references address (address_id);

-----------
create table restaurant (
    restaurant_id uuid not null default exts.uuid_generate_v4(),
    restaurant_name varchar(100) not null,
    address_id uuid not null,
    description text not null,
    work_start time not null,
    work_end time not null,
    company_details text not null,
    rating numeric(3, 2),
    status restaurant_status not null default 'активен'
);
alter table restaurant add constraint pk_restaurant primary key (restaurant_id);
alter table restaurant add constraint uq_restaurant_address unique (address_id);
alter table restaurant add constraint fk_restaurant_address foreign key (address_id) references address (address_id);
alter table restaurant add constraint chk_restaurant_name_not_empty check (length(trim(restaurant_name)) > 0);
alter table restaurant  add constraint chk_restaurant_desc_not_empty check (length(trim(description)) > 0);
alter table restaurant add constraint chk_restaurant_details_not_empty check (length(trim(company_details)) > 11);
alter table restaurant add constraint chk_restaurant_work_hours check (work_end > work_start);
alter table restaurant add constraint chk_restaurant_rating check (rating is null or (rating >= 0 and rating <= 5));

-----------
create table courier (
    courier_id uuid not null default exts.uuid_generate_v4(),
    fio varchar(100) not null,
    phone_number varchar(20) not null,
    status courier_status not null default 'свободен',
    hire_date date not null,
    dismissal_date date,
    coefficient numeric(3, 2) not null default 0.1
);
alter table courier add constraint pk_courier primary key (courier_id);
alter table courier add constraint uq_courier_phone unique (phone_number);
alter table courier add constraint chk_courier_fio_not_empty check (length(trim(fio)) > 0);
alter table courier add constraint chk_courier_phone_not_empty check (length(trim(phone_number)) >= 11);
alter table courier add constraint chk_courier_coefficient check (coefficient >= 0.1 and coefficient <= 0.5);
alter table courier add constraint chk_courier_dates check (dismissal_date is null or dismissal_date >= hire_date);
alter table courier add constraint chk_courier_dismissal_status check (status != 'уволен' or dismissal_date is not null);
-----------
create table courier_pay (
    year int not null,
    month int not null,
    courier_id uuid not null,
    amount numeric(12, 2) not null,
    coefficient_used numeric(3, 2) not null
);
alter table courier_pay add constraint pk_courier_pay primary key (year, month, courier_id);
alter table courier_pay add constraint fk_courier_pay_courier foreign key (courier_id) references courier (courier_id);
alter table courier_pay add constraint chk_courier_pay_month check (month >= 1 and month <= 12);
alter table courier_pay add constraint chk_courier_pay_amount check (amount >= 0);
alter table courier_pay add constraint chk_courier_pay_coef check (coefficient_used >= 0.1 and coefficient_used <= 0.5);

-----------
create table product_category (
    product_category_id uuid not null default exts.uuid_generate_v4(),
    product_category_name varchar(100) not null
);
alter table product_category add constraint pk_product_category primary key (product_category_id);
alter table product_category add constraint uq_product_category_name unique (product_category_name);
alter table product_category add constraint chk_category_name_not_empty check (length(trim(product_category_name)) > 0);

-----------
create table product (
    product_id uuid not null default exts.uuid_generate_v4(),
    product_name varchar(100) not null,
    product_category_id uuid not null,
    price numeric(10, 2) not null,
    restaurant_id uuid not null,
    photo_url text,
    rating numeric(3, 2),
    status product_status not null default 'доступно',
    description text not null
);
alter table product add constraint pk_product primary key (product_id);
alter table product add constraint fk_product_category 
		foreign key (product_category_id) references product_category (product_category_id) on delete restrict;
alter table product add constraint fk_product_restaurant foreign key (restaurant_id) references restaurant (restaurant_id);
alter table product add constraint chk_product_name_not_empty check (length(trim(product_name)) > 0);
alter table product add constraint chk_product_desc_not_empty check (length(trim(description)) > 0);
alter table product add constraint chk_product_price check (price >= 0);
alter table product add constraint chk_product_rating check (rating is null or (rating >= 0 and rating <= 5));

-----------
create table "order" (
    order_id uuid not null default exts.uuid_generate_v4(),
    courier_id uuid not null,
    client_id uuid not null,
    address_id uuid not null,
    restaurant_id uuid not null,
    order_timestamp timestamp not null default localtimestamp,
    delivery_timestamp timestamp,
    order_amount numeric(10, 2) not null,
    commission numeric(10, 2) generated always as (round(order_amount * 0.10, 2)) stored,
    total_amount numeric(10, 2) generated always as (order_amount + round(order_amount * 0.10, 2)) stored,
    status order_status not null default 'создан',
    pay_status order_pay_status not null default 'ожидает',
    description text
);
alter table "order" add constraint pk_order primary key (order_id);
alter table "order" add constraint fk_order_courier foreign key (courier_id) references courier (courier_id);
alter table "order" add constraint fk_order_client foreign key (client_id) references client (client_id);
alter table "order" add constraint fk_order_address  foreign key (address_id) references address (address_id);
alter table "order" add constraint fk_order_restaurant foreign key (restaurant_id) references restaurant (restaurant_id);
alter table "order" add constraint fk_order_client_address foreign key (client_id, address_id) references client_address (client_id, address_id);
alter table "order" add constraint chk_order_min_total check (total_amount >= 1000);
alter table "order" add constraint chk_order_delivery_time check (delivery_timestamp is null or delivery_timestamp >= order_timestamp);

-----------
create table order_structure (
    order_id uuid not null,
    product_id uuid not null,
    quantity numeric(8, 3) not null
);
alter table order_structure add constraint pk_order_structure primary key (order_id, product_id);
alter table order_structure  add constraint fk_order_structure_order 
		foreign key (order_id) references "order" (order_id) on delete cascade;
alter table order_structure add constraint fk_order_structure_product foreign key (product_id) references product (product_id);
alter table order_structure add constraint chk_order_structure_quantity check (quantity > 0);

-----------
create table payment (
    payment_id uuid not null default exts.uuid_generate_v4(),
    order_id uuid not null,
    payment_type payment_type not null,
    amount numeric(10, 2) not null,
    transaction_id varchar(100),
    payment_timestamp timestamp not null default localtimestamp,
    status payment_status not null default 'в_обработке'
);
alter table payment add constraint pk_payment primary key (payment_id);
alter table payment add constraint uq_payment_transaction unique (transaction_id);
alter table payment add constraint fk_payment_order foreign key (order_id) references "order" (order_id);
alter table payment add constraint chk_payment_amount_non_negative check (amount >= 0);
create unique index uq_payment_one_success_per_order on payment (order_id) where status = 'успех';

-----------
create table review (
    review_id uuid not null default exts.uuid_generate_v4(),
    client_id uuid not null,
    order_id uuid not null,
    review_timestamp timestamp not null default localtimestamp,
    entity_id uuid not null,
    entity_type review_entity_type not null,
    description text,
    photo_url text,
    rating numeric(2, 1) not null
);
alter table review add constraint pk_review primary key (review_id);
alter table review  add constraint uq_review_order_entity unique (order_id, entity_type, entity_id);
alter table review add constraint fk_review_client 
		foreign key (client_id) references client (client_id) on delete cascade;
alter table review add constraint fk_review_order 
		foreign key (order_id)  references "order" (order_id) on delete cascade;
alter table review add constraint chk_review_rating_range check (rating >= 1 and rating <= 5);
alter table review add constraint chk_review_desc_not_empty check (length(trim(description)) > 0);

