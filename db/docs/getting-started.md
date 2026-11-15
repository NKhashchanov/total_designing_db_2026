# Развертывание FoodExpress

## Требования

- PostgreSQL 17 и клиентские утилиты `psql`, `pg_dump`, `pg_restore` той же основной версии.
- Расширение `uuid-ossp`.

Имя базы данных — `foodexpress`, рабочая схема — `mineev_food`, кодировка — UTF-8, часовой пояс — UTC. Команды выполняются из корня репозитория.

## Установка

Подключиться с ролью, имеющей право создавать базы, схемы, расширения и роли. Проверить версию сервера:

```sql
show server_version;
```

Создать базу и установить часовой пояс:

```sql
create database foodexpress with encoding 'UTF8' template template0;
alter database foodexpress set timezone to 'UTC';
```

Если база уже существует, создание пропустить. Рабочая схема должна быть пустой: установка поверх существующих типов и таблиц не поддерживается.

Установить объекты с помощью клиента PostgreSQL 17 (пример подключения к локальному серверу с настроенной аутентификацией):

```bash
psql -h 127.0.0.1 -U postgres -d foodexpress -X -v ON_ERROR_STOP=1 -f db/install.sql
```

[Установщик](../install.sql) выполняет SQL-файлы в порядке зависимостей и применяет права в одной транзакции. При ошибке изменения откатываются. Существующие схемы и базы не удаляются.

## Подключение и права

Роль `inspector` создается скриптом [grants.sql](../schema/grants.sql). Она получает права на рабочую схему, таблицы, представления, процедуры, функции и использование расширения UUID. Если роль существует, скрипт устанавливает заданный пароль повторно. Роли PostgreSQL действуют в пределах всего кластера, поэтому установку следует выполнять в выделенном экземпляре.

```bash
psql -h 127.0.0.1 -U inspector -d foodexpress -W
```

Пароль роли — `NetoSQL2025`. Сервер должен разрешать подключение роли к базе. Для парольной аутентификации применяется соответствующее правило `pg_hba.conf`, например `scram-sha-256`. Метод `trust` не проверяет пароль. `set role inspector` проверяет права, но не аутентификацию.

После подключения установить путь поиска объектов:

```sql
set search_path to mineev_food, exts;
```

Фиксированный пароль роли и MD5-хеши клиентских паролей не предназначены для эксплуатации с реальными учетными данными.

## Работа с базой

```sql
call insert_test_data(10);
select * from get_statistic();
call courier_salary();
select * from how_much_money order by year_month;
```

Заголовок заказа и его позиции создаются в одной транзакции. Отложенные ограничения проверяют итоговое состояние при завершении транзакции. При изменении стоимости заказа сначала обновляется заказ, затем связанные платежи в той же транзакции.

`call erase_test_data();` удаляет все данные рабочей схемы, сохраняя ее структуру. Операция предназначена для экземпляра с тестовыми данными.

Контракты операций описаны в [операциях БД](operations.md), правила целостности — в [ограничениях](../constraints.md).

## Резервная копия и восстановление

Резервная копия `db/foodexpress_mineev.backup` содержит объекты схемы `mineev_food` без данных. Расширение `uuid-ossp` и кластерные роли в архив не входят. Права применяются отдельно.

Создание архива средствами PostgreSQL 17:

```bash
pg_dump -h 127.0.0.1 -U postgres -d foodexpress \
    -n mineev_food -Fc --schema-only --no-acl \
    -f db/foodexpress_mineev.backup
```

Просмотр состава архива клиентом PostgreSQL 17:

```bash
pg_restore --list db/foodexpress_mineev.backup
```

Для ручного восстановления создать отдельную пустую базу `foodexpress_restore`, установить UTC, схему расширений и `uuid-ossp`:

```bash
createdb -h 127.0.0.1 -U postgres --encoding=UTF8 --template=template0 foodexpress_restore
psql -h 127.0.0.1 -U postgres -d foodexpress_restore -X -v ON_ERROR_STOP=1 <<'SQL'
alter database foodexpress_restore set timezone to 'UTC';
create schema if not exists exts;
create extension if not exists "uuid-ossp" with schema exts;
SQL
```

Восстановить объекты и применить права:

```bash
pg_restore -h 127.0.0.1 -U postgres --exit-on-error --no-owner --no-acl \
    -d foodexpress_restore db/foodexpress_mineev.backup
psql -h 127.0.0.1 -U postgres -d foodexpress_restore -X \
    -v ON_ERROR_STOP=1 -f db/schema/grants.sql
```

После восстановления выполнить [основные и граничные тесты](../tests.md#отдельные-сценарии) в базе `foodexpress_restore`. Существующая база не удаляется автоматически.

## Диагностика

| Ошибка | Действие |
|---|---|
| Нет соединения | Проверить запуск сервера, адрес, порт и имя базы |
| Нет `exts.uuid_generate_v4()` | Проверить наличие `uuid-ossp` в схеме `exts` |
| Объект уже существует | Использовать пустую рабочую схему или новую базу |
| Permission denied | Проверить роль, права и путь поиска объектов |
| Ошибка восстановления | Проверить версию PostgreSQL 17, наличие архива и состояние целевой базы |
