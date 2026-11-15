-- FOOD-107. Общий расчет для истории и текущего месяца.
set search_path to mineev_food, pg_catalog;
-- Определяем коэффициент следующего месяца по числу доставок.
create function next_coefficient(p_count bigint) returns numeric
language sql immutable strict parallel safe as $$
    select case when p_count <= 150 then 0.1 when p_count <= 250 then 0.2
                when p_count <= 500 then 0.3 else 0.5 end;
$$;

-- p_couriers ограничивает историю только новой порцией генератора.
-- NULL означает всех курьеров. p_month — начало расчетного месяца.
create procedure calculate_courier_month(p_month date, p_couriers uuid[] default null)
language plpgsql set search_path to mineev_food, pg_catalog as $$
declare
    v_year integer := extract(year from p_month)::int;
    v_month integer := extract(month from p_month)::int;
    v_end date := (p_month + interval '1 month')::date;
begin
    -- Повторные расчеты и параллельные вызовы блокируют те же строки в одном порядке.
    perform 1 from courier c
    where p_couriers is null or c.courier_id = any(p_couriers)
    order by c.courier_id for no key update;
    -- Суммируем комиссии доставленных заказов за расчетный период.
    with totals as (
        select o.courier_id, count(*) as cnt, sum(o.commission) as commission_sum
        from "order" o
        where o.status = 'доставлен' and o.order_timestamp >= p_month and o.order_timestamp < v_end
          and (p_couriers is null or o.courier_id = any(p_couriers))
        group by o.courier_id
    -- Используем сохраненный коэффициент при повторном расчете месяца.
    ), calculation as (
        select c.courier_id, coalesce(cp.coefficient_used, c.coefficient) as used,
               coalesce(t.commission_sum, 0) as commission_sum,
               next_coefficient(coalesce(t.cnt, 0)) as next_rate
        from courier c left join totals t using (courier_id)
        left join courier_pay cp on cp.courier_id = c.courier_id and cp.year = v_year and cp.month = v_month
        where p_couriers is null or c.courier_id = any(p_couriers)
    -- Создаем или обновляем выплату без дублирования периода.
    ), saved as (
        insert into courier_pay(year, month, courier_id, amount, coefficient_used)
        select v_year, v_month, courier_id, round(used * commission_sum, 2), used from calculation
        on conflict (year, month, courier_id) do update
        set amount = excluded.amount, coefficient_used = excluded.coefficient_used
        returning courier_id
    )
    -- Назначаем новый коэффициент только работающим курьерам.
    update courier c set coefficient = calc.next_rate
    from calculation calc join saved s using (courier_id)
    where c.courier_id = calc.courier_id and c.status <> 'уволен';
end $$;
-- Запускаем расчет зарплаты за текущий календарный месяц.
create procedure courier_salary()
language plpgsql set search_path to mineev_food, pg_catalog as $$
begin
    call calculate_courier_month(date_trunc('month', current_date)::date);
end $$;
