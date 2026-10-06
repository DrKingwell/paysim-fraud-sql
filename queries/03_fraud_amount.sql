-- Average transfer amount per origin account (accounts with 2+ transfers)
SELECT
    id_account_orig,
    COUNT(*)                 AS total,
    ROUND(AVG(amount), 2)    AS avg_amount
FROM transactions
WHERE type = 'TRANSFER'
GROUP BY id_account_orig
HAVING COUNT(*) > 1
ORDER BY avg_amount DESC
LIMIT 20;