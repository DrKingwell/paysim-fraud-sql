-- Transactions that empt the origin account, split by fraud flag
SELECT is_fraud, COUNT(*) AS total
FROM transactions
WHERE new_balance_orig = 0
  AND type IN ('TRANSFER', 'CASH_OUT')
GROUP BY is_fraud;