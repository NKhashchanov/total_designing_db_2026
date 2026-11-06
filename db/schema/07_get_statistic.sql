create or replace function get_statistic()
returns table (
  restaurant_name varchar,
  best_product_name varchar,
  total_amount numeric,
  avg_amount numeric,
  best_user varchar
)
as $$
begin
  return query
  with ord_stats as (
    select o.restaurant_id,
      	   sum(o.total_amount) total_amount,
           avg(o.total_amount) avg_amount
      from "order" o
     where o.status = 'доставлен'
     group by o.restaurant_id
  ),
  best_prod as (
    select distinct on (o.restaurant_id)
           o.restaurant_id,
           p.product_name best_product_name
      from "order" o
        join order_structure os on o.order_id = os.order_id
        join product p on os.product_id = p.product_id
     where o.status = 'доставлен'
     group by o.restaurant_id, p.product_name
     order by o.restaurant_id, sum(os.quantity) desc
  ),
  best_client as (
    select distinct on (o.restaurant_id)
           o.restaurant_id,
           c.login best_user
      from "order" o
        join client c on o.client_id = c.client_id
     where o.status = 'доставлен'
     group by o.restaurant_id, c.login
     order by o.restaurant_id, count(*) desc
  )
  select r.restaurant_name,
    	 bp.best_product_name,
	     coalesce(os.total_amount, 0),
	     coalesce(os.avg_amount, 0),
	     bc.best_user
    from restaurant r
      left join ord_stats os on r.restaurant_id = os.restaurant_id
      left join best_prod bp on r.restaurant_id = bp.restaurant_id
      left join best_client bc on r.restaurant_id = bc.restaurant_id
   order by r.restaurant_name;
end;
$$ language plpgsql;