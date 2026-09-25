-- The obvious but unsafe approach. Run only on a disposable database.
-- Predict the outcome before running it; the predictions are recorded in
-- docs/evidence/lecture04/README.md under Step 1.
--
-- Wrapped in a transaction so the rehearsal can be reversed. The original run
-- documented in the evidence file was made as four separate statements outside
-- a transaction, which is why the database had to be rebuilt afterwards with
-- docker compose down -v.

begin;

-- Succeeds silently, and takes tickets_product_code_fk with it. This is the
-- statement that destroys the link between tickets and products: nothing else
-- in the database records which product a ticket was sold under.
alter table tickets drop column product_code;

-- Nothing is left to reconstruct the links from. TICKET-3 holds a price of
-- 65.00 DKK, which matches neither DAY at 80.00 nor SINGLE at 36.00.
select id, price, currency from tickets order by id;

-- Fails: 23502. Three existing rows would receive null, which the constraint
-- being added forbids.
alter table tickets add column product_id uuid not null;

rollback;
-- If psql stops on the error above, the connection closing rolls back this
-- transaction. In an interactive session, issue ROLLBACK yourself.