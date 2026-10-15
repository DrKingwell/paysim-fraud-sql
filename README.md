# SQL Credit Risk: PaySim Fraud Analysis

Relational modelling and SQL analysis of the [PaySim](https://www.kaggle.com/datasets/ealaxi/paysim1) synthetic mobile-money dataset (Kaggle), using PostgreSQL.

**Status:** schema and data load done; first five analysis queries written; indexes, views and the Python / Power BI connection are next.

## Goals

1. Model a flat transactional CSV into a proper relational schema (clients, accounts, transactions).
2. Load ~6.3M rows into PostgreSQL through a staging table.
3. Analyse fraud patterns with SQL (aggregations, CTEs, window functions).

## Dataset

- Source: PaySim (`paysim.csv`), 6,362,620 rows, 11 columns:
  `step, type, amount, nameOrig, oldbalanceOrg, newbalanceOrig, nameDest, oldbalanceDest, newbalanceDest, isFraud, isFlaggedFraud`
- `step` is one hour of simulated time (1-743).
- Transaction types: `PAYMENT`, `TRANSFER`, `CASH_OUT`, `CASH_IN`, `DEBIT`.

### Things the dataset does *not* give us

- **No transaction ID.** A surrogate key (`id_transaction`) is generated.
- **No customer data.** `nameOrig` / `nameDest` identify the account itself (prefix `C` = customer, `M` = merchant), so there is no demographic information.
- **No balances for merchants.** Rows whose destination is a merchant (`M...`) always have `oldbalanceDest = newbalanceDest = 0.0`. These zeros mean "not recorded", not "empty account".

## Schema

Three tables, created in `schema.sql`:

| Table | Purpose | Key |
|---|---|---|
| `clients` | Who the account holder is and their type (`C` or `M`) | `id_client` (PK) |
| `accounts` | The accounts held by clients | `id_account` (PK), `id_client` (FK to `clients`) |
| `transactions` | One row per transaction | `id_transaction` (PK, generated), `id_account_orig` and `id_account_dest` (FKs to `accounts`) |

### Modelling decisions

- **Why `clients` and `accounts` are separate even though they are 1:1 here.** The dataset has no customer attributes, so the two entities carry the same identifier. They are kept apart because in a real bank one client can hold several accounts; the FK sits on `accounts`, so allowing more than one account per client later does not require restructuring.
- **Client type is derived from the name prefix** (`C` / `M`) and stored once, in `clients.client_type`, with a `CHECK` constraint.
- **Balances live in `transactions`, not in `accounts`.** `old/new balance` describe the state of an account *at the time of a transaction*; storing them on the account would keep only one value and lose the history.
- **Two FKs from `transactions` to `accounts`** (origin and destination), named `_orig` and `_dest` to make each role explicit.
- **Money is `NUMERIC(14,2)`**, never `FLOAT`, to avoid rounding errors.
- **Merchant destination balances are stored as `NULL`**, not `0`. A `0` would be ambiguous (real empty balance vs. not recorded) and would distort averages. Where a zero is wanted for presentation, use `COALESCE(col, 0)` in a view or query.
- **Fraud flags are `SMALLINT` with `CHECK (... IN (0, 1))`** to match the CSV format and keep loading simple.

## Load process

1. Create the database and schema:
   ```sql
   CREATE DATABASE credit_risk;
   \c credit_risk
   \i 'schema.sql'
   ```
2. Create an unconstrained staging table `staging_paysim` with the 11 CSV columns and load the CSV with the client-side `\copy`:
   ```sql
   \copy staging_paysim FROM 'paysim.csv' WITH (FORMAT csv, HEADER true)
   ```
   Result: 6,362,620 rows.
3. Populate `clients` from the distinct account names found in both name columns (`UNION` removes duplicates), deriving the type with `LEFT(name, 1)`:
   Result: 9,073,900 clients (6,923,499 customers, 2,150,401 merchants).
4. Populate `accounts` from `clients` (1:1): 9,073,900 rows.
5. Populate `transactions` from the staging table, setting merchant destination balances to `NULL` with a `CASE` expression. The load was first tested with `LIMIT 1000`.

Notes from the process:
- `UNION` (not `UNION ALL`) is required in step 3, otherwise the primary key rejects repeated names.
- `TRUNCATE ... RESTART IDENTITY` is needed to reset the generated `id_transaction` after a test load.
- Bulk inserts of ~9M rows with PK and FK checks take several minutes on a laptop.

## Queries

All queries live in [`queries/`](queries/) and run against the `transactions` table.

| # | File | Question it answers | SQL concepts |
|---|---|---|---|
| 01 | [01_fraud_rate_by_type.sql](queries/01_fraud_rate_by_type.sql) | Which transaction types have the highest fraud rate? | `GROUP BY`, `COUNT`, `SUM`, `ROUND`, `ORDER BY` |
| 02 | [02_drained_accounts.sql](queries/02_drained_accounts.sql) | How many `TRANSFER` / `CASH_OUT` transactions leave the origin account at zero, split by fraud flag? | `WHERE` with `AND` / `IN`, `GROUP BY` |
| 03 | [03_avg_transfer_per_account.sql](queries/03_avg_transfer_per_account.sql) | What is the average transfer amount per origin account? | `WHERE`, `GROUP BY`, `HAVING`, `AVG`, `ORDER BY`, `LIMIT` |
| 04 | [04_transfer_cashout_pattern.sql](queries/04_transfer_cashout_pattern.sql) | Is a fraudulent `TRANSFER` followed by a `CASH_OUT` from the receiving account? | self-join, table aliases, incremental filtering |
| 05 | [05_fraud_over_time.sql](queries/05_fraud_over_time.sql) | How many frauds happen per day, and what is the running total? | CTE (`WITH`), window function (`SUM() OVER (ORDER BY ...)`), integer division |

Notes:
- **Query 03 only considers accounts with 2+ transfers** (`HAVING COUNT(*) > 1`). In PaySim almost every origin account appears in a single transaction, so an "average per account" over one value is meaningless.
- **Query 02 is a first approximation** of the draining pattern: it counts transactions that empty the origin account, without linking a transfer to a later cash-out.
- **Query 04 tests the classic mule pattern and does not find it.** Self-joining `transactions` (transfer `t`, cash-out `c`, linked by `t.id_account_dest = c.id_account_orig`) and adding one condition at a time:

  | Condition added | Pairs |
  |---|---|
  | `TRANSFER` + `CASH_OUT` linked by account | 572 |
  | same `amount` | 0 |
  | only fraudulent transfers, cash-out not before the transfer (`c.step >= t.step`) | 1 |

  The 572 linked pairs are coincidences: the account cashed out early and received a transfer later, with unrelated amounts. The single fraudulent pair cashes out 18,091.05 about 481 hours after receiving 1,282,971.57, and that cash-out is not flagged as fraud. In this synthetic dataset, fraud chains cannot be followed through account names, so the draining pattern has to be studied per transaction (query 02) rather than as a transfer-to-cash-out chain.

- **Query 05 groups by day, not by `step`.** `step` is one hour, so the day is `(step - 1) / 24 + 1` (integer division in PostgreSQL), giving days 1 to 31. The running total is a window function over a CTE with the daily counts. As a check, the running total on day 31 equals `SELECT SUM(is_fraud) FROM transactions`. Fraud is steady across the month, between about 240 and 350 cases per day, with no outlier day. That fits a synthetic dataset where fraud is injected at a roughly constant pace.

## How to reproduce

1. Install PostgreSQL and create a database named `credit_risk`.
2. Download `paysim.csv` from the [Kaggle dataset](https://www.kaggle.com/datasets/ealaxi/paysim1) (not included in this repo because of its size).
3. Run `schema.sql`, then follow the steps in [Load process](#load-process), adjusting the CSV path to your machine.

Tools: PostgreSQL, `psql`, VS Code.

## Next steps

Analysis
- [x] Fraud rate by transaction type
- [x] Account-draining pattern: drained transactions counted (query 02); `TRANSFER` followed by `CASH_OUT` tested with a self-join (query 04), pattern not present in the data
- [x] Customer-level averages (mean transfer amount)
- [x] Fraud over time (`step`): fraud per day and a running total (CTE + window function)

Preparing the database for Python and Power BI
- [ ] Indexes on `transactions` foreign keys, `type` and `is_fraud`, and a comparison of query times (`EXPLAIN ANALYZE`)
- [ ] Views presenting merchant balances as `0` with `COALESCE`
- [ ] One view per analysis (e.g. `v_fraud_rate_by_type`), so Python and Power BI read a small, stable result instead of 6M raw rows
- [ ] Move the load steps (staging, `clients`, `accounts`, `transactions`) from this README into a `load.sql` script
- [ ] Read-only database user for the BI tools

Python and Power BI
- [ ] Python: connect with SQLAlchemy + `psycopg2`, load the views into pandas, charts with matplotlib / seaborn
- [ ] Power BI: connect through the PostgreSQL connector (import the views, not the raw table) and build a fraud dashboard
