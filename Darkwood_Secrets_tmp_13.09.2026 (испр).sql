/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Крегель Наталья Александровна
 * Дата: 14.09.2026                                       ***ИСПРАВЛЕНО***
*/

-- Часть 1. Исследовательский анализ данных

-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
WITH total_users AS (
     -- Общее количество игроков
     SELECT COUNT(id) AS total_count_users
     FROM fantasy.users
),
pay_users AS (
     -- Количество платящих игроков
     SELECT COUNT(id) AS pay_count_users
     FROM fantasy.users
     WHERE payer = 1
)
SELECT 
    t.total_count_users,
    p.pay_count_users,
    -- Доля платящих игроков
    (p.pay_count_users * 1.0 / t.total_count_users)::float AS share_pay_users
FROM total_users AS t
CROSS JOIN pay_users AS p;     


-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
WITH race_users AS (
     -- Общее количество игроков по расам
     SELECT r.race,
            COUNT(u.id) AS total_count_users
     FROM fantasy.users AS u
     LEFT JOIN fantasy.race AS r ON u.race_id = r.race_id
     GROUP BY r.race
),
pay_users_race AS (
     -- Количество платящих игроков по расам
     SELECT r.race,
            COUNT(u.id) AS pay_count_users
     FROM fantasy.users AS u
     LEFT JOIN fantasy.race AS r ON u.race_id = r.race_id
     WHERE u.payer = 1
     GROUP BY r.race
)     
-- Доля платящих игороков по расам
SELECT 
    t.race,
    t.total_count_users,
    COALESCE(p.pay_count_users, 0) AS pay_count_users,
    (COALESCE(p.pay_count_users, 0) * 1.0 / t.total_count_users)::float AS payer_share
FROM race_users AS t
LEFT JOIN pay_users_race AS p ON t.race = p.race
ORDER BY t.race ASC;


-- Задача 2. Исследование внутриигровых покупок

-- 2.1. Статистические показатели по полю amount:
WITH basic_metric AS (
   SELECT 
     COUNT(amount) AS count_amount,
     SUM(amount) AS sum_amount,
     MIN(amount) AS min_amount,
     MAX(amount) AS max_amount,
     ROUND(AVG(amount)::numeric, 2) AS avg_amount,
     PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount) AS mediana_amount,
     STDDEV(amount) AS std_amount
   FROM fantasy.events
),
-- 2.2: Нулевые покупки:                 -- 2. покупки с нулевой стоиомостью
null_metrics AS (                        -- этот запрос разве не показывает это  
    SELECT COUNT(amount) AS null_amount  -- количество здесь, а в основном запросе доля и количество без учета нулевых
    FROM fantasy.events                  -- ????
    WHERE amount = 0
)
SELECT  
		count_amount,
		sum_amount, 
		min_amount, 
		max_amount, 
		avg_amount, 
		mediana_amount,
		std_amount,
		null_amount,
--Доля нулевых покупок
		(null_amount * 1.0 / NULLIF(count_amount, 0)) AS per_null_amount,
		count_amount - null_amount AS count_not_null
FROM basic_metric AS b
CROSS JOIN null_metrics; 


-- 2.3: Популярные эпические предметы:
WITH count_transaction_items AS (
-- Количество транзакций для каждого предмета
   SELECT i.game_items,
          COUNT(DISTINCT e.id) AS count_buyers,          
          COUNT(transaction_id) AS count_transaction     
   FROM fantasy.events AS e                              
   LEFT JOIN fantasy.items AS i ON e.item_code = i.item_code
   WHERE amount > 0 AND amount IS NOT NULL
   GROUP BY i.game_items
),
unique_buyers AS(
   SELECT COUNT(DISTINCT id) AS total_count_buyers
   FROM fantasy.events
   WHERE amount > 0 AND amount IS NOT NULL       
)
-- Общее количество всех транзакций 
SELECT game_items, 
      c.count_transaction,
-- Доля покупки конкретного предмета в общем объеме продаж (умножение на 1.0 делает деление дробным)
      (c.count_transaction * 1.0 / SUM(count_transaction) OVER ())::float AS share_transaction,
-- Доля  игроков, которые покупали конкретный предмет в общем объеме продаж
       (c.count_buyers * 1.0 / b.total_count_buyers)::float AS share_buyers      --исправила
FROM count_transaction_items AS c
CROSS JOIN unique_buyers AS b     
ORDER BY count_transaction DESC;

-- Часть 2. Решение ad hoc-задачи
-- Общее число игроков в каждой расе
WITH total_users AS (
   SELECT 
       u.race_id,
       r.race,
       COUNT(u.id) AS total_race_users       --убрала DISTINCT, т.к. можно не использовать, т.к. в таблице users id первичный ключ и каждая строка будет уникальной по отношению к игроку.
   FROM fantasy.users AS u
   LEFT JOIN fantasy.race AS r ON u.race_id = r.race_id
   WHERE r.race IS NOT NULL
   GROUP BY u.race_id, r.race
),
-- Количество покупателей и количество платящих среди них (в разрезе расы)
buyers_stats AS (
   SELECT 
       u.race_id,
       -- Все, кто совершил хотя бы одну покупку (есть запись в events)
       COUNT(DISTINCT e.id) AS total_buyers,
       -- Платящие среди них (где amount > 0). 
       COUNT(DISTINCT e.id) FILTER (WHERE u.payer = 1) AS paying_buyers      
   FROM fantasy.users AS u
   INNER JOIN fantasy.events AS e ON u.id = e.id
   GROUP BY u.race_id
),
-- Шаг 3: Подсчитываем общее число покупок и их сумму в разрезе расы
transactions_stats AS (
   SELECT 
       u.race_id,
       COUNT(e.transaction_id) AS total_transactions,
       SUM(e.amount) AS total_revenue
   FROM fantasy.users AS u
   INNER JOIN fantasy.events AS e ON u.id = e.id
   GROUP BY u.race_id
)
-- Финальный ad hoc-отчет: собираем всё вместе 
SELECT 
    t.race,
    t.total_race_users,
        -- Количество игроков, совершающих внутриигровые покупки (покупатели)
    COALESCE(b.total_buyers, 0) AS total_buyers,
        -- Доля покупателей от общего количества игроков
    ROUND((COALESCE(b.total_buyers, 0) * 1.0 / t.total_race_users)::numeric, 4)::float AS buyers_share,
        -- Доля платящих игроков от количества игроков, совершивших покупки
    ROUND((b.paying_buyers * 1.0 / NULLIF(b.total_buyers, 0))::numeric, 4)::float AS paying_share_of_buyers,
        -- Среднее количество покупок на одного игрока (строго на покупателя)
    ROUND((tr.total_transactions * 1.0 / NULLIF(b.total_buyers, 0))::numeric, 4)::float AS avg_transactions_per_buyer,
        -- Средняя стоимость одной покупки на одного игрока
    ROUND((tr.total_revenue * 1.0 / NULLIF(tr.total_transactions, 0))::numeric, 4)::float AS avg_price_per_transaction,
        -- Средняя суммарная стоимость всех покупок на одного игрока (на покупателя)
    ROUND((tr.total_revenue * 1.0 / NULLIF(b.total_buyers, 0))::numeric, 4)::float AS avg_revenue_per_buyer
FROM total_users AS t
LEFT JOIN buyers_stats AS b ON t.race_id = b.race_id
LEFT JOIN transactions_stats AS tr ON t.race_id = tr.race_id
ORDER BY avg_transactions_per_buyer DESC;
