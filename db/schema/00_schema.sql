-- FOOD-101: схема проекта и расширение для генерации UUID.
create schema if not exists exts;
create extension if not exists "uuid-ossp" with schema exts;
-- Проверяем, что функция UUID доступна именно в схеме exts.
do $$
begin
    if to_regprocedure('exts.uuid_generate_v4()') is null then
        raise exception 'Функция exts.uuid_generate_v4() отсутствует';
    end if;
end $$;
create schema if not exists mineev_food;
