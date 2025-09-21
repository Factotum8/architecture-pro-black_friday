# Портирование данных в Cassandra

Для выноса в Cassandra были выделены коллекции: orders, products.

1. Orders - это уже оплаченный товар их потеря может вызвать репутационный урон и правовые разбирательства, 
поэтому коллекция была выбрана для выноса в кластер. 
2. Product - по этой коллекции в прошлом уже была авария, что бы избежать её в будущем переносим в кластер. 

## Концепция

### Orders
partition key = (customer_id, time_bucket),   
где  
time_bucket на старте 1 месяц,  
customer_id - целочисленный id.

Clustering columns = (order_datetime DESC, order_id).   

Псевдокод:
```sql
CREATE TABLE orders_by_customer (
  customer_id     uuid,
  bucket_yyyymm   text,             
  order_datetime  timestamp,
  order_id        uuid,
  status          text,
  total_amount    decimal,
  geozone         text,

  PRIMARY KEY ((customer_id, bucket_yyyymm), order_datetime, order_id)
) WITH CLUSTERING ORDER BY (order_datetime DESC, order_id ASC);

```

Данные о заказах (статусы, суммы) → Read Repair + Anti-Entropy Repair.
Критично для бизнеса, ошибки недопустимы.
При этом нужны и быстрые поправки (read repair), и гарантия «в конечном счёте» (Anti-Entropy repair).

#### Обоснование

* Получаете быстрое чтение «последних заказов клиента» и ровные по размеру партиции (за счёт месячного окна).
* Если взять customer_id без "бакетизации" по времени, у активных клиентов партиции разрастутся.
* Добавление order_id в clustering гарантирует уникальность строк на одинаковых метках времени и позволяет эффективно адресовать конкретный заказ внутри партиции.

### Product

Хорошим тонов в Cassandra делать дизайн от запросов и для запросов. 
Поэтому для операций можно завести несколько таблиц под разные паттерны. Базовая связка такая:

1. Карточка товара → партиционируем по product_id. 
   2. partition key = (product_id),   
Псевдокод:
```sql
CREATE TABLE products_by_id (
  product_id     uuid,
  name           text,
  category       text,
  price          decimal,
  description    text,
  attrs          map<text, text>,  -- цвет, размер и пр.
  PRIMARY KEY ((product_id))
);
```

Hinted Handoff + Anti-Entropy Repair
Не критично, если узел временно недоступен → hinted handoff дотянет данные.
Repair по расписанию наведёт порядок для тех строк, которые редко читаются.

2. Поиск по категории и цене → партиционируем по (category, price_bucket), сортируем по price. 
   3. partition key = (category, price_bucket), 
   4. Clustering columns = (price).   
Диапазоны по цене делают через price bucket (например, цена товара/100 округлённая вниз). Это держит партиции умеренными.
```sql
CREATE TABLE products_by_category_price (
  category       text,
  price_bucket   int,          
  price          decimal,
  product_id     uuid,
  name           text,
  PRIMARY KEY ((category, price_bucket), price, product_id)
) WITH CLUSTERING ORDER BY (price ASC, product_id ASC);
```

Read Repair + Anti-Entropy Repair.
Быстрые поправки (read repair), и гарантия «в конечном счёте» (Anti-Entropy repair).

3. Склады (остатки) по геозонам → партиционируем по product_id, кластеризуем по geozone.
   4. partition key = (product_id), 
   4. Clustering columns = (geozone).

```sql
CREATE TABLE stock_by_product_zone (
  product_id   uuid,
  geozone      text,
  stock        int,
  updated_at   timestamp,
  PRIMARY KEY ((product_id), geozone)
);
```
Read Repair + Anti-Entropy Repair.
Критично для бизнеса, ошибки недопустимы.
При этом нужны и быстрые поправки (read repair), и гарантия «в конечном счёте» (Anti-Entropy repair).