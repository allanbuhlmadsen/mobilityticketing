-- Expand phase: add the new product identity without removing the old one.
-- Every statement here is additive. Old writers and readers keep working.

begin;
set local lock_timeout = '3s';

-- A stable identity for each product, independent of its business code.
alter table products add column id uuid;

-- Fill the existing two rows. Done as a separate update rather than a column
-- default, so that the values are assigned once and stay assigned.
update products
set id = gen_random_uuid()
where id is null;

-- New rows get an ID automatically from here on.
alter table products
  alter column id set default gen_random_uuid();

-- Safe only because the update above left no nulls behind.
alter table products
  alter column id set not null;

-- A foreign key must point at a unique or primary key, so this constraint
-- is what makes tickets.product_id able to reference it at all.
alter table products
  add constraint products_id_unique unique (id);

-- Nullable on purpose: existing tickets have no value yet, and old writers
-- do not supply one.
alter table tickets
  add column product_id uuid;

-- NOT VALID means the constraint applies to new and changed rows only.
-- Existing rows are not checked now, so the migration does not have to scan
-- the whole table while holding a lock.
alter table tickets
  add constraint tickets_product_id_fk
  foreign key (product_id)
  references products(id)
  not valid;

commit;