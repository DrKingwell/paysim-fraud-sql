SELECT SUM(is_fraud) FROM transactions;
WITH daily AS (
    SELECT
        (step - 1) / 24 + 1 AS day,
        SUM(is_fraud)       AS fraud_count
    FROM transactions
    GROUP BY (step - 1) / 24 + 1
)
SELECT
    day,
    fraud_count,
    SUM(fraud_count) OVER (ORDER BY day) AS running_total
FROM daily
ORDER BY day;