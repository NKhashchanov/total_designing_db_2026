/**
 * Триггерная функция для  проверки соответствия продукта ресторану
 */
create or replace function check_order_product_restaurant()
returns trigger as $$
declare
  order_rest_id$u uuid;
  product_rest_id$u uuid;
begin
  select restaurant_id 
    into order_rest_id$u
    from "order"
   where order_id = new.order_id;

  select restaurant_id 
    into product_rest_id$u
    from product
   where product_id = new.product_id;

  if order_rest_id$u != product_rest_id$u then
    raise exception 'блюдо % (ресторан %) не принадлежит ресторану заказа % (ресторан %)', 
				    new.product_id, product_rest_id$u, new.order_id, order_rest_id$u;
  end if;

  return new;
end;
$$ language plpgsql;

create trigger trg_check_order_product_restaurant
  before insert or update on order_structure
  for each row
  execute function check_order_product_restaurant();

/**
 * Триггерная функция для пересчета рейтингов
 */
create or replace function rating_change()
returns trigger as $$
begin
  if tg_op = 'INSERT' or tg_op = 'UPDATE' then
    if new.entity_type = 'блюдо' then
      update product
         set rating = (
               select round(avg(rating), 2)
                 from review
                where entity_type = 'блюдо'
                  and entity_id = new.entity_id
             )
       where product_id = new.entity_id;
    elsif new.entity_type = 'ресторан' then
      update restaurant
         set rating = (
               select round(avg(rating), 2)
                 from review
                where entity_type = 'ресторан'
                  and entity_id = new.entity_id
             )
       where restaurant_id = new.entity_id;
    end if;
  end if;

  if tg_op = 'DELETE' or tg_op = 'UPDATE' and (old.entity_id != new.entity_id or old.entity_type != new.entity_type)then
    if old.entity_type = 'блюдо' then
      update product
         set rating = (
               select round(avg(rating), 2)
                 from review
                where entity_type = 'блюдо'
                  and entity_id = old.entity_id
             )
       where product_id = old.entity_id;
    elsif old.entity_type = 'ресторан' then
      update restaurant
         set rating = (
               select round(avg(rating), 2)
                 from review
                where entity_type = 'ресторан'
                  and entity_id = old.entity_id
             )
       where restaurant_id = old.entity_id;
    end if;
  end if;

  return null;
end;
$$ language plpgsql;

create trigger trg_rating_change
  after insert or update or delete on review
  for each row
  execute function rating_change();
