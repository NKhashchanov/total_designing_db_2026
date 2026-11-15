-- Выполнять через psql -v ON_ERROR_STOP=1 -f db/install.sql в базе foodexpress.
-- Схема должна быть пустой. Существующие схемы не удаляются автоматически.
\set ON_ERROR_STOP on
-- Создаем все объекты в одной транзакции.
begin;
\ir schema/00_schema.sql
\ir schema/01_types.sql
\ir schema/02_tables.sql
\ir schema/03_constraints.sql
\ir schema/04_triggers.sql
-- Подключаем операции после создания таблиц и триггеров.
\ir schema/05_add_product.sql
\ir schema/06_courier_salary.sql
\ir schema/07_insert_test_data.sql
\ir schema/08_erase_test_data.sql
\ir schema/09_get_statistic.sql
\ir schema/10_how_much_money.sql
-- Настраиваем права после создания всех объектов.
\ir schema/grants.sql
commit;
