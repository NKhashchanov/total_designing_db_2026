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