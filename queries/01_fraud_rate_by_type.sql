-- Fraud rate by transaction type
SELECT
    type,
    COUNT(*)                                  AS total_transactions,
    SUM(is_fraud)                             AS fraud_count,
    ROUND(100.0 * SUM(is_fraud) / COUNT(*), 4) AS fraud_rate_pct
FROM transactions
GROUP BY type
ORDER BY fraud_rate_pct DESC;
