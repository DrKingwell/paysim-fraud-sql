CREATE TABLE clients (
    id_client   VARCHAR(20) PRIMARY KEY,
    client_type CHAR(1)     NOT NULL CHECK (client_type IN ('C', 'M'))
);

CREATE TABLE accounts (
    id_account VARCHAR(20) PRIMARY KEY,
    id_client  VARCHAR(20) NOT NULL REFERENCES clients(id_client)
);

CREATE TABLE transactions (
    id_transaction   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    step             INTEGER       NOT NULL,
    type             VARCHAR(10)   NOT NULL,
    amount           NUMERIC(14,2) NOT NULL,
    id_account_orig  VARCHAR(20)   NOT NULL REFERENCES accounts(id_account),
    old_balance_orig NUMERIC(14,2) NOT NULL,
    new_balance_orig NUMERIC(14,2) NOT NULL,
    id_account_dest  VARCHAR(20)   NOT NULL REFERENCES accounts(id_account),
    old_balance_dest NUMERIC(14,2),
    new_balance_dest NUMERIC(14,2),
    is_fraud         SMALLINT      NOT NULL CHECK (is_fraud IN (0, 1)),
    is_flagged_fraud SMALLINT      NOT NULL CHECK (is_flagged_fraud IN (0, 1))
);
