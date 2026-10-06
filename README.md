# SQL Credit Risk: PaySim Fraud Analysis

Relational modelling and SQL analysis of the [PaySim](https://www.kaggle.com/datasets/ealaxi/paysim1) synthetic mobile-money dataset (Kaggle), using PostgreSQL.

**Status:** schema and data load done; fraud analysis queries in progress.

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

## How to reproduce

1. Install PostgreSQL and create a database named `credit_risk`.
2. Download `paysim.csv` from the [Kaggle dataset](https://www.kaggle.com/datasets/ealaxi/paysim1) (not included in this repo because of its size).
3. Run `schema.sql`, then follow the steps in [Load process](#load-process), adjusting the CSV path to your machine.

Tools: PostgreSQL, `psql`, VS Code.

## Next steps

- [ ] Fraud rate by transaction type
- [ ] Account-draining pattern (`TRANSFER` followed by `CASH_OUT` with the same amount)
- [ ] Customer-level averages (mean transfer amount)
- [ ] Indexes on `transactions` foreign keys and `type`, and a comparison of query times
- [ ] Views presenting merchant balances as `0` with `COALESCE`
