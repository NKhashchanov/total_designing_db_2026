# Концептуальная схема (ERD)

## Что это за документ

Это **концептуальная модель** данных FoodExpress: сущности, их связи и кардинальности. Она **готова и менять её не нужно**.

На её основе ты строишь:

- **логическую модель** — нормализация, детализация, атрибуты, типы данных, ключи, ограничения;
- **физическую модель** — SQL-скрипты под PostgreSQL.

Уровни намеренно разделены. Концептуальный отвечает на вопрос «что мы храним и как это связано», на данном уровне детализация и нормализация отсутствуют. Логический — «какими типами и ограничениями это описать». Физический — «как это ляжет в конкретную СУБД».

| Уровень | Что содержит | Кто делает |
|---|---|---|
| Концептуальный | Сущности, связи, кардинальности | Готово, в этом файле |
| Логический | Нормализация, атрибуты, типы, ключи, ограничения | Ты |
| Физический | SQL: типы PostgreSQL, индексы, процедуры | Ты |

> **Что значит «готова».** Все сущности на месте, все связи проведены, кардинальности определены. Это не значит, что у каждой сущности расписаны все атрибуты — часть атрибутов намеренно оставлена на логический уровень (то есть это твоя зона ответственности). Это часть задания, а не недоработка.

## Сущности

| Сущность | Что описывает |
|---|---|
| `client` | Клиент сервиса: логин, пароль, телефон |
| `address` | Физический адрес: улица, дом, квартира/офис |
| `client_address` | Связь M:N: у клиента может быть много адресов, один адрес может использоваться разными клиентами |
| `restaurant` | Ресторан-партнёр: название, адрес, график работы, рейтинг, статус |
| `courier` | Курьер: ФИО, телефон, статус, даты найма/увольнения, текущий коэффициент |
| `courier_pay` | Ежемесячная выплата курьеру: год, месяц, сумма, применённый коэффициент |
| `product_category` | Категория блюд |
| `product` | Блюдо: название, цена, ресторан, категория, рейтинг, статус |
| `order` | Заказ: клиент, ресторан, курьер, адрес доставки, суммы, статусы |
| `payment` | Попытка оплаты заказа |
| `order_structure` | Позиция заказа: блюдо и количество в рамках заказа |
| `review` | Отзыв клиента на блюдо, ресторан или заказ |

## Диаграмма

```mermaid
erDiagram
    CLIENT {
        uuid client_id PK
        varchar login
        varchar password
        char phone_number
    }
    ADDRESS {
        uuid address_id PK
        varchar street
        varchar house_number
        varchar apartment_office
    }
    CLIENT_ADDRESS {
        uuid client_id PK,FK
        uuid address_id PK,FK
    }
    RESTAURANT {
        uuid restaurant_id PK
        varchar restaurant_name
        uuid address_id FK
        text description
        time work_start
        time work_end
        text company_details
        numeric rating
        enum status
    }
    COURIER {
        uuid courier_id PK
        varchar FIO
        char phone_number
        enum status
        date hire_date
        date dismissal_date
        numeric coefficient
    }
    COURIER_PAY {
        int year PK
        int month PK
        uuid courier_id PK,FK
        numeric amount
        numeric coefficient_used
    }
    PRODUCT_CATEGORY {
        uuid product_category_id PK
        varchar product_category_name
    }
    PRODUCT {
        uuid product_id PK
        varchar product_name
        uuid product_category_id FK
        numeric price
        uuid restaurant_id FK
        text photo_url
        numeric rating
        enum status
        text description
    }
    ORDER {
        uuid order_id PK
        uuid courier_id FK
        uuid client_id FK
        uuid address_id FK
        uuid restaurant_id FK
        timestamp order_timestamp
        timestamp delivery_timestamp
        numeric order_amount
        numeric commission
        numeric total_amount
        enum status
        enum pay_status
        text description
    }
    PAYMENT {
        uuid payment_id PK
        uuid order_id FK
    }
    ORDER_STRUCTURE {
        uuid order_id PK,FK
        uuid product_id PK,FK
        numeric quantity
    }
    REVIEW {
        uuid review_id PK
        uuid client_id FK
        timestamp review_timestamp
        uuid entity_id
        enum entity_type
        uuid order_id FK
        text description
        text photo_url
        numeric rating
    }

    CLIENT ||--o{ CLIENT_ADDRESS : ""
    ADDRESS ||--o{ CLIENT_ADDRESS : ""
    ADDRESS ||--o| RESTAURANT : ""
    RESTAURANT ||--o{ PRODUCT : ""
    PRODUCT_CATEGORY ||--o{ PRODUCT : ""
    COURIER ||--o{ COURIER_PAY : ""
    CLIENT ||--o{ ORDER : ""
    ADDRESS ||--o{ ORDER : ""
    RESTAURANT ||--o{ ORDER : ""
    COURIER ||--o{ ORDER : ""
    ORDER ||--o{ PAYMENT : ""
    ORDER ||--o{ ORDER_STRUCTURE : ""
    PRODUCT ||--o{ ORDER_STRUCTURE : ""
    CLIENT ||--o{ REVIEW : ""
    ORDER ||--o{ REVIEW : ""