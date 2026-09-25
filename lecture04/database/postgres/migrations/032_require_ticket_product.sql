-- Contract phase, part one: make the new reference the required one.
-- Apply only after the backfill and verification have both passed, and only
-- once no instance of the old release is still writing.

begin;
set local lock_timeout = '3s';

-- Check the rows that were skipped when the constraint was created NOT VALID.
-- This does not take an exclusive lock, but it does scan the table.
alter table tickets
  validate constraint tickets_product_id_fk;

-- From here, a ticket without a product identity cannot be stored.
alter table tickets
  alter column product_id set not null;

commit;