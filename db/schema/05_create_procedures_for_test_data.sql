-- сиквенсы для уникальности данных
create sequence if not exists seq_client_num start with 1;
create sequence if not exists seq_client_phone start with 1000000;
create sequence if not exists seq_courier_num start with 1;
create sequence if not exists seq_courier_phone start with 2000000;
create sequence if not exists seq_category_num start with 1;
create sequence if not exists seq_restaurant_num start with 1;
create sequence if not exists seq_product_num start with 1;

create or replace procedure erase_test_data()
as $$
begin
  truncate table
    review,
    payment,
    order_structure,
    "order",
    courier_pay,
    client_address,
    product,
    product_category,
    restaurant,
    courier,
    client,
    address
  cascade;
  alter sequence seq_client_num restart;
  alter sequence seq_client_phone restart;
  alter sequence seq_courier_num restart;
  alter sequence seq_courier_phone restart;
  alter sequence seq_category_num restart;
  alter sequence seq_restaurant_num restart;
  alter sequence seq_product_num restart;
end;
$$ language plpgsql;

create or replace procedure insert_test_data(value int)
as $$
declare
  val$i int := value;
  i$i int;
  j$i int;
  m$i int;

  addr_id$u uuid;
  client_id$u uuid;
  courier_id$u uuid;
  cat_id$u uuid;
  rest_id$u uuid;
  order_id$u uuid;
  prod_id$u uuid;

  clients$u uuid[] := array[]::uuid[];
  couriers$u uuid[] := array[]::uuid[];
  categories$u uuid[] := array[]::uuid[];
  restaurants$u uuid[] := array[]::uuid[];
  rest_addrs$u uuid[] := array[]::uuid[];
  client_addrs$u uuid[] := array[]::uuid[];

  prod_ids$u uuid[];
  prod_prices$n numeric[];

  order_ts$t timestamp;
  delivery_ts$t timestamp;
  order_status$c order_status;
  order_amt$n numeric(10, 2);
  tot_amt$n numeric(10, 2);

  cur_client$u uuid;
  cur_addr$u uuid;
  cur_rest$u uuid;
  cur_courier$u uuid;

  dish1$u uuid;
  dish2$u uuid;
  qty1$n numeric(8, 3);
  qty2$n numeric(8, 3);

  comm_sum$n numeric(12, 2);
  deliv_cnt$i int;
  curr_coef$n numeric(3, 1);
  next_coef$n numeric(3, 1);
  pay_amt$n numeric(12, 2);

  m_date$d date;
  m_year$i int;
  m_month$i int;

  enums_courier_status$c courier_status[] := enum_range(null::courier_status);
  enums_product_status$c product_status[] := enum_range(null::product_status);
  enums_restaurant_status$c restaurant_status[] := enum_range(null::restaurant_status);
  enums_order_status$c order_status[] := enum_range(null::order_status);
  enums_order_pay_status$c order_pay_status[] := enum_range(null::order_pay_status);
  enums_payment_status$c payment_status[] := enum_range(null::payment_status);
  enums_payment_type$c payment_type[] := enum_range(null::payment_type);
  enums_review_type$c review_entity_type[] := enum_range(null::review_entity_type);
begin
  if val$i is null or val$i <= 0 then
    return;
  end if;

  -- 1. адреса
  -- для ресторанов
  for i$i in 1..val$i loop
    addr_id$u := exts.uuid_generate_v4();
    insert into address (address_id, street, house_number, apartment_office)
    values (
      addr_id$u,
      'Ленина ул.',
      (i$i + 100)::text,
      null
    );
    rest_addrs$u := array_append(rest_addrs$u, addr_id$u);
  end loop;

  -- для клиентов х4
  for i$i in 1..(val$i * 4) loop
    addr_id$u := exts.uuid_generate_v4();
    insert into address (address_id, street, house_number, apartment_office)
    values (
      addr_id$u,
      'Мира ул.',
      i$i::text,
      'кв. ' || (i$i % 100 + 1)::text
    );
    client_addrs$u := array_append(client_addrs$u, addr_id$u);
  end loop;

  -- 2. клиенты
  for i$i in 1..val$i loop
    client_id$u := exts.uuid_generate_v4();
    insert into client (client_id, login, password, phone_number)
    values (
      client_id$u,
      'user_' || nextval('seq_client_num')::text,
      md5(random()::text),
      '+79' || lpad(nextval('seq_client_phone')::text, 9, '0')
    );
    clients$u := array_append(clients$u, client_id$u);

    -- связываем с 4 клиентскими адресами (BR-2.4, BR-2.5)
    for j$i in 1..4 loop
      insert into client_address (client_id, address_id)
      values (client_id$u, client_addrs$u[(i$i - 1) * 4 + j$i]);
    end loop;
  end loop;

  -- 3. курьеры
  for i$i in 1..val$i loop
    courier_id$u := exts.uuid_generate_v4();
    if i$i = 1 then
      -- минимум один активный курьер
      insert into courier (courier_id, fio, phone_number, status, hire_date, dismissal_date, coefficient)
      values (
        courier_id$u,
        'курьер активный ' || nextval('seq_courier_num')::text,
        '+78' || lpad(nextval('seq_courier_phone')::text, 9, '0'),
        enums_courier_status$c[1],
        current_date - interval '8 months',
        null,
        0.1
      );
    elsif i$i = val$i and val$i > 1 then
      -- один уволенный курьер
      insert into courier (courier_id, fio, phone_number, status, hire_date, dismissal_date, coefficient)
      values (
        courier_id$u,
        'курьер уволенный ' || nextval('seq_courier_num')::text,
        '+78' || lpad(nextval('seq_courier_phone')::text, 9, '0'),
        enums_courier_status$c[4],
        current_date - interval '8 months',
        current_date - interval '1 month',
        0.1
      );
    else
      insert into courier (courier_id, fio, phone_number, status, hire_date, dismissal_date, coefficient)
      values (
        courier_id$u,
        'курьер ' || nextval('seq_courier_num')::text,
        '+78' || lpad(nextval('seq_courier_phone')::text, 9, '0'),
        enums_courier_status$c[1],
        current_date - interval '8 months',
        null,
        0.1
      );
    end if;
    couriers$u := array_append(couriers$u, courier_id$u);
  end loop;

  -- 4. категории продуктов
  for i$i in 1..val$i loop
    cat_id$u := exts.uuid_generate_v4();
    insert into product_category (product_category_id, product_category_name)
    values (
      cat_id$u,
      'категория ' || nextval('seq_category_num')::text
    );
    categories$u := array_append(categories$u, cat_id$u);
  end loop;

  -- 5. рестораны
  for i$i in 1..val$i loop
    rest_id$u := exts.uuid_generate_v4();
    insert into restaurant (
      restaurant_id, restaurant_name, address_id, description,
      work_start, work_end, company_details, rating, status
    ) values (
      rest_id$u,
      'ресторан ' || nextval('seq_restaurant_num')::text,
      rest_addrs$u[i$i],
      'описание ресторана',
      time '09:00:00',
      time '23:00:00',
      'инн ' || lpad(floor(random() * 8999999999 + 1000000000)::bigint::text, 10, '0') || ', огрн 1234567890123',
      null,
      enums_restaurant_status$c[1]
    );
    restaurants$u := array_append(restaurants$u, rest_id$u);
  end loop;

  -- 6. блюда: value * 5 (по 5 блюд на ресторан, BR-11.7)
  for i$i in 1..val$i loop
    rest_id$u := restaurants$u[i$i];
    for j$i in 1..5 loop
      prod_id$u := exts.uuid_generate_v4();
      insert into product (
        product_id, product_name, product_category_id, price,
        restaurant_id, photo_url, rating, status, description
      ) values (
        prod_id$u,
        'блюдо ' || nextval('seq_product_num')::text || ' (ресторан ' || i$i || ')',
        categories$u[(i$i - 1 + j$i - 1) % val$i + 1],
        (200.00 + j$i * 100.00),
        rest_id$u,
        'https://foodexpress.ru/img/' || md5(random()::text) || '.jpg',
        null,
        enums_product_status$c[1],
        'вкусное свежее блюдо'
      );
    end loop;
  end loop;

  -- 7. заказы, состав заказа, оплаты, отзывы х5
  for j$i in 1..(val$i * 5) loop
    order_id$u := exts.uuid_generate_v4();
    m$i := (j$i - 1) % 6; -- распределение по месяцам

    -- дата заказа внутри соответствующего месяца
    order_ts$t := date_trunc('month', current_date - (m$i || ' months')::interval) + interval '2 days' + (((j$i * 11) % 500) || ' hours')::interval;

    cur_courier$u := couriers$u[(j$i - 1) % val$i + 1];
    cur_rest$u := restaurants$u[(j$i - 1) % val$i + 1];
    cur_client$u := clients$u[(j$i - 1) % val$i + 1];

    select address_id
      into cur_addr$u
      from client_address
     where client_id = cur_client$u
     order by address_id
     limit 1;

    if j$i % 10 != 0 then
      order_status$c := enums_order_status$c[4];
      delivery_ts$t := order_ts$t + interval '35 minutes';
    else
      order_status$c := enums_order_status$c[2];
      delivery_ts$t := null;
    end if;

    select array_agg(product_id), 
           array_agg(price)
      into prod_ids$u, 
           prod_prices$n
      from (
        select product_id, price
          from product
         where restaurant_id = cur_rest$u
         order by product_id
         limit 2
      ) t;

    dish1$u := prod_ids$u[1];
    dish2$u := prod_ids$u[2];
    qty1$n := 2.0;
    qty2$n := 1.0;
    order_amt$n := round(qty1$n * prod_prices$n[1] + qty2$n * prod_prices$n[2], 2);

    -- заказ
    insert into "order" (
      order_id, courier_id, client_id, address_id, restaurant_id,
      order_timestamp, delivery_timestamp, order_amount, status, pay_status, description
    ) values (
      order_id$u, cur_courier$u, cur_client$u, cur_addr$u, cur_rest$u,
      order_ts$t, delivery_ts$t, order_amt$n, order_status$c, enums_order_pay_status$c[2], 'тестовый заказ'
    );

    -- позиции заказа
    insert into order_structure (order_id, product_id, quantity)
    values
      (order_id$u, dish1$u, qty1$n),
      (order_id$u, dish2$u, qty2$n);

    -- оплата
    select total_amount
      into tot_amt$n
      from "order"
     where order_id = order_id$u;

    insert into payment (
      payment_id, order_id, payment_type, amount, transaction_, payment_timestamp, status
    ) values (
      exts.uuid_generate_v4(),
      order_id$u,
      enums_payment_type$c[(j$i % 3) + 1],
      tot_amt$n,
      'tx_' || md5(random()::text || order_id$u::text),
      order_ts$t,
      enums_payment_status$c[1]
    );

    -- отзыв
    if j$i % 2 = 1 then
      insert into review (
        review_id, client_id, order_id, review_timestamp, entity_id, entity_type, description, photo_url, rating
      ) values (
        exts.uuid_generate_v4(),
        cur_client$u,
        order_id$u,
        order_ts$t + interval '1 hour',
        dish1$u,
        enums_review_type$c[1],
        'отличное блюдо, вкусно!',
        null,
        (3.0 + (j$i % 3))
      );
    else
      insert into review (
        review_id, client_id, order_id, review_timestamp, entity_id, entity_type, description, photo_url, rating
      ) values (
        exts.uuid_generate_v4(),
        cur_client$u,
        order_id$u,
        order_ts$t + interval '1 hour',
        cur_rest$u,
        enums_review_type$c[2],
        'отличный ресторан!',
        null,
        (4.0 + (j$i % 2))
      );
    end if;
  end loop;

  -- 8. пересчет рейтингов
  update product
     set rating = (
           select round(avg(rating), 2)
             from review
            where entity_type = enums_review_type$c[1]
              and entity_id = product_id
         );
  update restaurant
     set rating = (
           select round(avg(rating), 2)
             from review
            where entity_type = enums_review_type$c[2]
              and entity_id = restaurant_id
         );

  -- 9. зарплата курьеров
  for i$i in 1..array_length(couriers$u, 1) loop
    courier_id$u := couriers$u[i$i];
    --curr_coef$n := 0.1; -- начальный коэффициент
	curr_coef$n := (0.1 + ((i$i - 1) % 5) * 0.1)::numeric(3, 1);
    -- от самого старого месяца к текущему
    for m$i in reverse 5..0 loop
      m_date$d := (date_trunc('month', current_date) - (m$i || ' months')::interval)::date;
      m_year$i := extract(year from m_date$d)::int;
      m_month$i := extract(month from m_date$d)::int;

      select coalesce(count(*), 0),
        	 coalesce(sum(commission), 0)
        into deliv_cnt$i, 
			 comm_sum$n
        from "order"
       where courier_id = courier_id$u
         and status = enums_order_status$c[4]
         and extract(year from order_timestamp) = m_year$i
         and extract(month from order_timestamp) = m_month$i;

      pay_amt$n := round(comm_sum$n * curr_coef$n, 2);

	  insert into courier_pay (year, month, courier_id, amount, coefficient_used)
	  values (m_year$i, m_month$i, courier_id$u, pay_amt$n, curr_coef$n);

      -- расчет нового коэффициента на следующий месяц
      /*if deliv_cnt$i <= 150 then
        next_coef$n := 0.1;
      elsif deliv_cnt$i <= 250 then
        next_coef$n := 0.2;
      elsif deliv_cnt$i <= 500 then
        next_coef$n := 0.3;
      else
        next_coef$n := 0.5;
      end if;

      if not exists (select 1 from courier where courier_id = courier_id$u and status = 'уволен') then
        curr_coef$n := next_coef$n;
      end if;*/
    end loop;

    -- обновляем courier.coefficient итоговым коэффициентом на следующий месяц
    update courier
       set coefficient = curr_coef$n
     where courier_id = courier_id$u
       and status != enums_courier_status$c[4];
  end loop;
end;
$$ language plpgsql;


