-- FOOD-108. Месяцы от первого до последнего доставленного заказа.
set search_path to mineev_food, pg_catalog;
create view how_much_money as
-- Агрегируем стоимость доставленных заказов по месяцам.
with recursive monthly_orders as (
    select date_trunc('month', order_timestamp)::date as month_start,
           sum(order_amount) as no_commission, sum(total_amount) as with_commission
    from "order" where status = 'доставлен' group by 1
-- Определяем границы периода отчета.
), bounds as (
    select min(month_start) as first_month, max(month_start) as last_month from monthly_orders
-- Рекурсивно строим непрерывную последовательность месяцев.
), months(month_start, last_month) as (
    select first_month, last_month from bounds where first_month is not null
    union all
    select (month_start+interval '1 month')::date, last_month from months
    where month_start < last_month
-- Суммируем выплаты отдельно от заказов.
), monthly_pay as (
    select make_date(year, month, 1) as month_start, sum(amount) as paid from courier_pay group by 1
-- Подставляем нули для месяцев без заказов или выплат.
), amounts as (
    select m.month_start, coalesce(o.no_commission,0) as sum_no_commission,
           coalesce(o.with_commission,0) as sum_with_commission,
           coalesce(o.with_commission,0)-coalesce(o.no_commission,0) as commission,
           coalesce(p.paid,0) as courier_pay
    from months m left join monthly_orders o using(month_start) left join monthly_pay p using(month_start)
-- Получаем комиссию предыдущего календарного месяца.
), previous as (
    select a.*, lag(commission) over(order by month_start) as prev_commission from amounts a
)
-- Формируем итоговые показатели и чистую прибыль.
select to_char(month_start,'YYYY-MM') as year_month, sum_no_commission, sum_with_commission,
       commission, prev_commission, commission-prev_commission as commission_diff,
       courier_pay, commission-courier_pay as net_profit
from previous order by month_start;
