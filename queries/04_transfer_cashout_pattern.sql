-- Hypothesis: a fraudulent TRANSFER is followed by a CASH_OUT of the same amount
-- from the receiving (intermediary) account.
--
-- Tested by self-joining transactions (t = transfer, c = cash-out) and adding
-- one condition at a time, counting the pairs that survive:
--
--   TRANSFER + CASH_OUT linked by account (t.id_account_dest = c.id_account_orig)    572
--   ... and same amount (t.amount = c.amount)                                          0
--   ... only fraudulent transfers, cash-out not before the transfer                    1
--
-- Conclusion: the pattern does not exist in PaySim when followed by account name.
--   - The 572 linked pairs are coincidences: the account cashed out early and
--     received a transfer later (cash-out step < transfer step), amounts unrelated.
--   - The single fraudulent pair below cashes out 18,091.05 about 481 hours after
--     receiving 1,282,971.57, and the cash-out is not flagged as fraud.

SELECT
    t.id_account_orig AS victim_account,
    t.id_account_dest AS intermediary_account,
    t.amount          AS transfer_amount,
    c.amount          AS cashout_amount,
    t.step            AS transfer_step,
    c.step            AS cashout_step,
    t.is_fraud        AS transfer_fraud,
    c.is_fraud        AS cashout_fraud
FROM transactions t
JOIN transactions c
  ON t.id_account_dest = c.id_account_orig
WHERE t.type = 'TRANSFER'
  AND c.type = 'CASH_OUT'
  AND t.is_fraud = 1
  AND c.step >= t.step;
