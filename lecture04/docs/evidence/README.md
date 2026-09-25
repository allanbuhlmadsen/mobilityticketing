# Lecture 4 evidence: change product identity without breaking tickets

## Step 0: baseline before any change

Run from the repository root:

```
docker compose exec -T postgres psql -U mobility -d mobility -v ON_ERROR_STOP=1 < database/postgres/experiments/baseline.sql
```

Output:

```
    id    | product_code | price | currency
----------+--------------+-------+----------
 TICKET-1 | SINGLE       | 36.00 | DKK
 TICKET-2 | SINGLE       | 36.00 | DKK
 TICKET-3 | DAY          | 65.00 | DKK
(3 rows)
```

The orphan check returned zero rows, and the assertion block completed without raising, so every ticket refers to a product that exists and the fixture holds three tickets across two products.

### Product catalogue at baseline

```
  code  |    name     | price | currency
--------+-------------+-------+----------
 DAY    | Day pass    | 80.00 | DKK
 SINGLE | Single trip | 36.00 | DKK
(2 rows)
```

`TICKET-3` was bought for 65.00 DKK while the catalogue lists the DAY product at 80.00 DKK. This gap is deliberate: it is the value that proves whether the migration touched historical prices. Every check later in this document compares against the three rows above.

## Step 1: the unsafe change, predicted before running it

The obvious approach is to drop the old reference and add the new one as a required column in a single step:

```sql
alter table tickets drop column product_code;
alter table tickets add column product_id uuid not null;
```

Three predictions before running it.

### Existing tickets lose their product for good

`product_code` is the only place a ticket records which product it was sold under. Dropping it leaves `TICKET-3` holding a price of 65.00 DKK and no way to tell whether that was DAY or SINGLE. The price is no help: 65.00 matches neither the catalogue price of DAY at 80.00 nor SINGLE at 36.00. Nothing in any other table carries the link, so it cannot be reconstructed — only restored from a backup.

### The new column cannot be required immediately

PostgreSQL will reject the second statement. A `not null` column with no default cannot be added to a table that already holds rows, because those rows would receive null, which the constraint itself forbids. Expected error: `column "product_id" of relation "tickets" contains null values`, SQLSTATE `23502`.

### Old application versions break the moment the migration commits

Any instance still running the previous release writes `product_code` on insert. From the moment the column is dropped, every one of those writes fails with `column "product_code" of relation "tickets" does not exist`, SQLSTATE `42703`. No ticket can be sold until every server has been upgraded. This is the reason for expanding first and contracting later: the two versions have to be able to run side by side.

### Two objects in the starter schema depend on the column

`database/postgres/init/012_completed_integrity.sql` contains both of these:

```sql
alter column product_code set not null,
add constraint tickets_product_code_fk foreign key (product_code) references products(code),
```

The foreign key `tickets_product_code_fk` depends on the column and disappears with it. That is what `remove_legacy.sql` warns about when it says not to reach for `cascade` — the point is to know what is being removed first.

The `not null` requirement matters later rather than now. For as long as the column exists and is required, a writer that supplies only `product_id` cannot insert a ticket at all. That is the trap referred to in `final_writer.sql`.

### What actually happened

The statements are recorded in `database/postgres/experiments/unsafe_change.sql`. They were run as four separate commands rather than from the file, which is why the database had to be rebuilt with `docker compose down -v` before Step 2.

Run from the repository root, one command at a time.

Dropping the column succeeded without comment:

```
alter table tickets drop column product_code;
ALTER TABLE
```

No warning, no confirmation, and no mention that `tickets_product_code_fk` was removed along with it. PostgreSQL drops a constraint that depends on a column silently; only views and functions would have required `cascade`. The most destructive statement in this lab is the one that produces no visible objection.

The damage is visible immediately:

```
    id    | price | currency
----------+-------+----------
 TICKET-1 | 36.00 | DKK
 TICKET-2 | 36.00 | DKK
 TICKET-3 | 65.00 | DKK
(3 rows)
```

Three tickets, three prices, and nothing recording what was sold.

Both predicted errors occurred. Adding the required column:

```
ERROR:  column "product_id" of relation "tickets" contains null values
```

And an insert from the old application version:

```
ERROR:  column "product_code" of relation "tickets" does not exist
LINE 1: ...ckets (id, user_id, trip_id, ticket_code, status, product_co...
```

The lesson is not that these statements fail. It is that the one which succeeded is the one that could not be undone.

## Step 2: the expand migration

Database reset with `docker compose down -v` and `docker compose up -d`, then verified against the baseline before continuing. The migration lives in `database/postgres/migrations/030_expand_product_identity.sql` and was run once from the repository root:

```
docker compose exec -T postgres psql -U mobility -d mobility -v ON_ERROR_STOP=1 < database/postgres/migrations/030_expand_product_identity.sql
```

```
BEGIN
SET
ALTER TABLE
UPDATE 2
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
COMMIT
```

`UPDATE 2` is the two catalogue products receiving their identities. Every statement in the file is additive: nothing is dropped, nothing becomes required, and no existing value is rewritten.

### Products now carry an identity

```
                  id                  |  code  |    name     | price | currency
--------------------------------------+--------+-------------+-------+----------
 a0e9b60e-dcd0-4a42-8121-bc51a2491b42 | DAY    | Day pass    | 80.00 | DKK
 8f792c1a-8d8c-43a0-bbc7-b43721094296 | SINGLE | Single trip | 36.00 | DKK
```

These values are generated per database. Resetting the container with `docker compose down -v` produces different ones, so they are read again rather than hard-coded into any later script.

### Tickets are untouched

```
    id    | product_code | product_id | price | currency
----------+--------------+------------+-------+----------
 TICKET-1 | SINGLE       |            | 36.00 | DKK
 TICKET-2 | SINGLE       |            | 36.00 | DKK
 TICKET-3 | DAY          |            | 65.00 | DKK
```

`product_id` is empty on all three rows, and that is the intended state. `product_code` is unchanged, so an application that has not been upgraded still reads and writes exactly as before. `TICKET-3` still shows the 65.00 DKK it was sold for.

### The foreign key is not yet validated

```
        conname        | convalidated
-----------------------+--------------
 tickets_product_id_fk | f
```

`convalidated = f` means the constraint applies to new and changed rows only. The three existing rows were never checked, and they would pass anyway: a foreign key requires that a value, if present, resolves — not that a value is present. Checking the existing rows is deferred to `validate constraint` once the backfill is complete.

### What a much larger table would change

Nothing in this file is unsafe at this size, but two statements would behave differently on millions of rows. The `update products set id = gen_random_uuid()` rewrites every row and would need to run in batches outside the DDL transaction. The `not valid` clause on the foreign key is precisely what avoids the other problem: without it, PostgreSQL scans the whole of `tickets` while holding a lock that blocks writes. `lock_timeout = '3s'` covers the remaining risk, that a statement queues behind a long-running query and blocks everything behind it while it waits.

## Step 3: the old application still works after expansion

Both scripts were used as supplied. They represent the release that was deployed before the migration and knows nothing about `product_id`.

`old_writer.sql` inserts a ticket by copying the fields of `TICKET-1` and supplying only `product_code`:

```
docker compose exec -T postgres psql -U mobility -d mobility -v ON_ERROR_STOP=1 < database/postgres/experiments/old_writer.sql
INSERT 0 1
```

`old_reader.sql` selects on `product_code` alone:

```
     id      | product_code | price | currency
-------------+--------------+-------+----------
 LAB04-OLD-1 | SINGLE       | 36.00 | DKK
 TICKET-1    | SINGLE       | 36.00 | DKK
 TICKET-2    | SINGLE       | 36.00 | DKK
 TICKET-3    | DAY          | 65.00 | DKK
(4 rows)
```

Two observations matter here.

The reader never mentions `product_id`, so the old application cannot tell that the column exists. A column added to a table is invisible to code that does not ask for it, which is exactly why the expand migration can run while the previous release is still serving traffic.

The new row `LAB04-OLD-1` was written with `product_id` left null, because the old writer has no value to supply. Rows in this shape will keep arriving for as long as one instance of the old release is running. That is the reason the backfill has to be repeatable rather than a one-off statement.

## Step 4: the new writer, and what it does not protect

`database/postgres/experiments/new_writer.sql` represents the upgraded release. It receives a product ID and an agreed price, and derives the product code from the product row:

```sql
insert into tickets
    (id, user_id, trip_id, ticket_code, status,
     product_code, product_id,
     valid_from_utc, valid_to_utc, price, currency)
select
    :'ticket_id', t.user_id, t.trip_id, :'ticket_code', 'Active',
    p.code,                 -- derived from the product row, never supplied
    p.id,
    t.valid_from_utc, t.valid_to_utc,
    :agreed_price,          -- the price agreed at purchase, not p.price
    t.currency
from products p
cross join tickets t
where p.id = :'product_id'::uuid
  and t.id = 'TICKET-1';
```

The caller never supplies a product code, so the two references on the ticket cannot contradict each other. The price is an input rather than `p.price`, which is what keeps a discounted sale from being silently repriced to the catalogue.

After running it, `LAB04-NEW-1` is the only ticket carrying both references:

```
     id      | product_code |              product_id              | price
-------------+--------------+--------------------------------------+-------
 LAB04-NEW-1 | SINGLE       | 8f792c1a-8d8c-43a0-bbc7-b43721094296 | 36.00
 LAB04-OLD-1 | SINGLE       |                                      | 36.00
 TICKET-1    | SINGLE       |                                      | 36.00
 TICKET-2    | SINGLE       |                                      | 36.00
 TICKET-3    | DAY          |                                      | 65.00
```

### The writer prevents a mismatch; the database does not

Written directly in SQL, with `product_code` naming SINGLE and `product_id` holding the DAY identity:

```
INSERT 0 1
```

The row was accepted. Both foreign keys are satisfied independently — `SINGLE` exists in `products.code`, and the DAY identity exists in `products.id` — and nothing compares the two columns to each other.

These are not the same protection. Application logic prevents the mismatch; the schema permits it. Any script, manual correction or older code path that writes directly to the table can produce a row whose two references disagree, and neither foreign key can detect it.

The composite foreign key used for `validations` in lecture 2 does not apply here, because the two columns reference two different unique keys on `products` rather than one composite target. Closing the gap would require a trigger, or removing one of the columns — which is what the rest of this migration does.

The test row was removed afterwards with `delete from tickets where id = 'LAB04-MISMATCH';`

## Step 5: the new reader, working before the backfill

`database/postgres/experiments/new_reader.sql` joins `products` twice under two aliases: once by identity, once by code as a fallback.

```sql
select t.id,
       coalesce(p_new.id, p_old.id) as resolved_product_id,
       coalesce(p_new.code, p_old.code) as resolved_product_code,
       t.price,
       t.currency
from tickets t
left join products p_new
  on p_new.id = t.product_id
left join products p_old
  on t.product_id is null
 and p_old.code = t.product_code
order by t.id;
```

The condition `t.product_id is null` on the second join is what keeps the two paths exclusive: the code lookup runs only where no identity is stored, so each row resolves through exactly one of them. `coalesce` then returns whichever value was found.

Run against the current data, where only one ticket has an identity stored:

```
     id      |         resolved_product_id          | resolved_product_code | price | currency
-------------+--------------------------------------+-----------------------+-------+----------
 LAB04-NEW-1 | 8f792c1a-8d8c-43a0-bbc7-b43721094296 | SINGLE                | 36.00 | DKK
 LAB04-OLD-1 | 8f792c1a-8d8c-43a0-bbc7-b43721094296 | SINGLE                | 36.00 | DKK
 TICKET-1    | 8f792c1a-8d8c-43a0-bbc7-b43721094296 | SINGLE                | 36.00 | DKK
 TICKET-2    | 8f792c1a-8d8c-43a0-bbc7-b43721094296 | SINGLE                | 36.00 | DKK
 TICKET-3    | a0e9b60e-dcd0-4a42-8121-bc51a2491b42 | DAY                   | 65.00 | DKK
(5 rows)
```

All five resolve. Four of them do so through the code fallback, because they carry no identity yet. `TICKET-3` resolves to DAY with its 65.00 DKK unchanged.

This is what allows the upgraded release to be deployed before the backfill has run. The rollout and the data migration do not have to wait for each other.

Both joins are outer joins on purpose. A ticket whose references resolve to nothing still appears, with `resolved_product_id` null, rather than being dropped from the result. A query that silently returns fewer rows is harder to diagnose than one that returns an unresolved row.

## Step 6: the repeatable backfill

`database/postgres/migrations/031_backfill_ticket_product.sql`:

```sql
update tickets t
set product_id = p.id
from products p
where t.product_id is null
  and p.code = t.product_code;
```

Run from the repository root. First run, second run:

```
UPDATE 4
UPDATE 0
```

The condition `t.product_id is null` is what makes the statement repeatable. The second run finds nothing to change, and an identity that has already been assigned is never overwritten. Without that condition the statement would rewrite every row on every run: harmless here, but it would also overwrite any value a person or another process had set deliberately.

Note what the statement does not mention: `price` and `currency`. A backfill that had set `price = p.price` would have repriced `TICKET-3` from the 65.00 DKK it was sold for to the 80.00 DKK now in the catalogue.

### A late write from the old application

Idempotence is not decoration. Instances of the previous release can keep inserting rows without an identity for as long as they are running. Simulated by changing the two variables in `old_writer.sql` to `LAB04-OLD-2` and rerunning it, then running the backfill once more:

```
INSERT 0 1
UPDATE 1
```

`UPDATE 1`, not `UPDATE 6`. Only the new row was touched.

```
     id      | product_code |              product_id              | price
-------------+--------------+--------------------------------------+-------
 LAB04-NEW-1 | SINGLE       | 8f792c1a-8d8c-43a0-bbc7-b43721094296 | 36.00
 LAB04-OLD-1 | SINGLE       | 8f792c1a-8d8c-43a0-bbc7-b43721094296 | 36.00
 LAB04-OLD-2 | SINGLE       | 8f792c1a-8d8c-43a0-bbc7-b43721094296 | 36.00
 TICKET-1    | SINGLE       | 8f792c1a-8d8c-43a0-bbc7-b43721094296 | 36.00
 TICKET-2    | SINGLE       | 8f792c1a-8d8c-43a0-bbc7-b43721094296 | 36.00
 TICKET-3    | DAY          | a0e9b60e-dcd0-4a42-8121-bc51a2491b42 | 65.00
(6 rows)
```

Every ticket now carries an identity. Compared against the baseline in Step 0, `TICKET-1`, `TICKET-2` and `TICKET-3` have the same products, the same prices and the same currencies. `TICKET-3` still shows 65.00 DKK against a catalogue price of 80.00.

## Step 7: verification before the reference becomes required

`database/postgres/experiments/verify.sql` checks three failure conditions in one query: a ticket with no identity, an identity that resolves to no product, and a code and an identity naming two different products.

```sql
select t.id, t.product_code, t.product_id, p.code as product_id_resolves_to
from tickets t
left join products p on p.id = t.product_id
where t.product_id is null
   or p.id is null
   or t.product_code is distinct from p.code
order by t.id;
```

`is distinct from` rather than `<>` matters here. Comparing two values with `<>` yields null when either side is null, and a null in a `where` clause is treated as not true — so the row would be omitted, which is precisely the row the check exists to find. `is distinct from` treats null as an ordinary value in the comparison.

After the backfill, the check returns zero rows:

```
 id | product_code | product_id | product_id_resolves_to
----+--------------+------------+------------------------
(0 rows)
```

### Proving the check is not simply always empty

A check that has only been run against correct data is not evidence of anything. A deliberate mismatch was introduced inside a transaction and rolled back:

```
BEGIN
UPDATE 1
    id    | product_code | product_id_resolves_to
----------+--------------+------------------------
 TICKET-1 | SINGLE       | DAY
(1 row)

ROLLBACK
```

The check caught it immediately, and the rollback left the database unchanged — the verification returned zero rows again afterwards.

Note how the mismatch had to be created: by writing to the table directly. The new writer derives the code from the product row and cannot produce it. The division from Step 4 holds throughout — the application prevents it, the schema permits it, and this query detects it after the fact.

### Comparison against the baseline

`TICKET-1`, `TICKET-2` and `TICKET-3` still exist, with the same product codes, prices and currencies recorded in Step 0. `TICKET-3` remains at 65.00 DKK while the DAY catalogue price is 80.00. Every ticket now also carries the correct product identity.

## Step 8: making the identity required

`database/postgres/migrations/032_require_ticket_product.sql`:

```sql
begin;
set local lock_timeout = '3s';

alter table tickets
  validate constraint tickets_product_id_fk;

alter table tickets
  alter column product_id set not null;

commit;
```

### The migration failing on purpose

A ticket was first inserted the way the old release writes, with a product code but no identity, and the migration was then attempted:

```
BEGIN
SET
ALTER TABLE
ERROR:  column "product_id" of relation "tickets" contains null values
```

Two things are visible in that output.

`validate constraint` succeeded — that is the single `ALTER TABLE` before the error. A foreign key requires that a value, if present, resolves; it says nothing about whether a value must be present. The null row does not violate it. Only `not null` catches that row, and it is the stricter of the two rules.

Because both statements sit between `begin` and `commit`, the successful validation was rolled back along with the failure. Nothing at all was applied. Run outside a transaction, the same two statements would have left a validated foreign key and a still-optional column — a half-applied state that no migration file describes.

### Completing it

Backfill, verify, then migrate:

```
UPDATE 1
(0 rows)
BEGIN
SET
ALTER TABLE
ALTER TABLE
COMMIT
```

The same migration file failed a moment earlier and succeeded now. Nothing about the file changed; only the state of the data did. This is the sequence the lab brief calls for before requiring the new reference — the three commands are not independent, each depends on the one before it.

### The old writer is now dead

```
ERROR:  null value in column "product_id" of relation "tickets" violates not-null constraint
DETAIL:  Failing row contains (LAB04-OLD-3, USER-1, TRIP-M2-20260429-0800, LAB04-CODE-OLD-3, Active, SINGLE, 2026-04-29 07:45:00+00, 2026-04-29 10:00:00+00, 36.00, DKK, null).
```

The `DETAIL` line shows the whole rejected row, ending in the null that is now forbidden. The new writer, run immediately afterwards against the same schema:

```
INSERT 0 1
```

Same database, two application versions, two outcomes. Before this migration both worked; after it, only one does.

This is the point at which rolling back to the previous release stops being an option. Until now, reverting the application would have worked without touching the database. From here, a rollback of the application would also require reverting `product_id` to nullable — and any ticket sold in the meantime by the new release would still carry an identity the old code cannot read. The migration must not be run until every instance of the old release has stopped writing, and that is not something the repository can tell you.

## Step 9: removing the legacy reference

### Dependencies checked first

`\d tickets` shows two objects hanging on the column, both of which disappear with it and neither of which PostgreSQL warns about:

```
 product_code   | text  | not null
    "tickets_product_code_fk" FOREIGN KEY (product_code) REFERENCES products(code)
```

Two catalogue queries returned zero rows: one searching `pg_depend` and `pg_rewrite` for views referencing the column, one searching `pg_proc` for functions whose source mentions it. Nothing else depends on it.

`validations_ticket_identity_fk` points into `tickets(id, ticket_code)` and is untouched by this change — worth noting because it is the kind of dependency a quick column search would miss.

### The final reader works before the column is removed

`final_reader.sql` joins the catalogue through the identity only, so it survives the removal:

```
      id       |              product_id              | product_code | product_name | price | currency
---------------+--------------------------------------+--------------+--------------+-------+----------
 TICKET-3      | a0e9b60e-dcd0-4a42-8121-bc51a2491b42 | DAY          | Day pass     | 65.00 | DKK
```

The product code in the result comes from `products.code`, not from the ticket. The ticket keeps what was paid; the catalogue keeps what the product is called.

### The final writer cannot work until the column is removed

```
ERROR:  null value in column "product_code" of relation "tickets" violates not-null constraint
DETAIL:  Failing row contains (LAB04-FINAL-1, ..., null, ..., 8f792c1a-8d8c-43a0-bbc7-b43721094296).
```

The schema is briefly in a state where no single-reference writer can insert at all: the old one fails on `product_id`, the ID-only one fails on `product_code`. Only the transitional writer that supplies both succeeds. Dropping the column is therefore not tidying up — it is what allows the final release to run.

### Rehearsal

`remove_legacy.sql` drops the column, runs the ID-only writer and reader, and rolls back. No `cascade`: if something unexpected had depended on the column, the statement should fail rather than quietly remove it.

```
BEGIN
SET
ALTER TABLE
INSERT 0 1
      id       |              product_id              | product_code | price | currency
---------------+--------------------------------------+--------------+-------+----------
 LAB04-FINAL-1 | 8f792c1a-8d8c-43a0-bbc7-b43721094296 | SINGLE       | 36.00 | DKK
 ...
 TICKET-3      | a0e9b60e-dcd0-4a42-8121-bc51a2491b42 | DAY          | 65.00 | DKK
(9 rows)

ROLLBACK
```

The writer that failed moments earlier succeeded the instant the column was gone. It was never wrong; it was waiting for the schema to finish changing.

`products.code` is untouched. It remains the business-facing code on the price list — it is simply no longer the value stored on a ticket, which is what lets an operator rename it.

## Compatibility across the four schema states

Each row is a script in `database/postgres/experiments/`. Each column is a state the schema passed through during this lab, in order. The entries say whether that script succeeds against that state. Cells marked with a check were run and observed; the rest follow from the schema state and are noted as reasoned rather than tested.

| Script | Before expansion | After 030 (both columns) | After 032 (ID required) | After dropping `product_code` |
| --- | --- | --- | --- | --- |
| `old_writer.sql` — code only | works (reasoned) | works ✓ | fails, `23502` on `product_id` ✓ | fails, column gone (reasoned) |
| `new_writer.sql` — both references | column missing (reasoned) | works ✓ | works ✓ | fails, column gone (reasoned) |
| `final_writer.sql` — ID only | column missing (reasoned) | fails, `23502` on `product_code` (reasoned) | fails, `23502` on `product_code` ✓ | works ✓ |
| `old_reader.sql` — reads `product_code` | works (reasoned) | works ✓ | works (reasoned) | fails, column gone (reasoned) |
| `new_reader.sql` — ID with code fallback | column missing (reasoned) | works ✓ | works (reasoned) | fails, references the column (reasoned) |
| `final_reader.sql` — ID only | column missing (reasoned) | works ✓ | works ✓ | works ✓ |

Two things are worth reading out of this table.

Only one writer works in each state, and the working writer changes three times. There is no single moment where the old and the new writer both work and the final one does too — which is why the rollout has to move through the middle column and wait there.

`final_reader.sql` is the only script that works in every state where its columns exist. That is what makes it safe to deploy early: a reader that joins through the identity is correct before the backfill, during it, and after the old column is gone.

Note also which queries run but return less than expected. `old_reader.sql` keeps working right up until the column is dropped, but from the moment the new writer is in use it shows a `product_code` that is a copy rather than the authoritative reference. It never errors; it simply stops being the right question to ask.

## Rollout decision

**When to stop the old writers.** Before running `032_require_ticket_product.sql`, and not before. The expand migration and the backfill are both safe while the previous release is running — that is demonstrated in Step 3, where the old writer kept working after expansion, and in Step 6, where a late old-style write was picked up by rerunning the backfill. Making `product_id` required is the first step that breaks the old release, and the evidence is in Step 8: the same insert that succeeded throughout the lab returned `23502` immediately afterwards.

**Could the old application version still be used?** Up to and including the backfill, yes, and without touching the database. After `032`, no. Reverting the application alone is not enough: `product_id` would have to be made nullable again, and the foreign key would remain validated. Any ticket sold in the meantime by the new release carries an identity the old code cannot read — it would still resolve, because `product_code` is populated on those rows too, but only for as long as the transitional writer was the one that created them.

**What the repository cannot tell you.** Nothing in these files reveals how many instances of the old release are running, or whether a scheduled job somewhere still inserts tickets using `product_code`. The migration is safe to run from the database's point of view the moment `verify.sql` returns zero rows. Whether it is safe from the system's point of view is a question about deployments, and it has to be answered outside the repository.

**Why the identity must not be updatable.** A default of `gen_random_uuid()` assigns an identity; it does nothing to stop someone changing one afterwards. An update to `products.id` would leave every ticket pointing at a product that no longer exists — except that `tickets_product_id_fk` would reject it, which is the protection that matters here. Beyond the foreign key, the practical controls are that no application code issues an update to that column, and that the database role used by the application has no `UPDATE` privilege on it. Both are outside this migration.

## What a migration tool generates, and what it cannot know

This repository has no .NET project, so an EF Core migration for the same change was drafted for comparison rather than generated. Changing the model property from `ProductCode` to `ProductId` and running `dotnet ef migrations add` produces roughly this:

```csharp
migrationBuilder.DropForeignKey(name: "tickets_product_code_fk", table: "tickets");
migrationBuilder.DropColumn(name: "product_code", table: "tickets");
migrationBuilder.AddColumn<Guid>(
    name: "product_id", table: "tickets", type: "uuid",
    nullable: false,
    defaultValue: new Guid("00000000-0000-0000-0000-000000000000"));
migrationBuilder.AddColumn<Guid>(
    name: "id", table: "products", type: "uuid",
    nullable: false,
    defaultValue: new Guid("00000000-0000-0000-0000-000000000000"));
migrationBuilder.CreateIndex(name: "IX_products_id", table: "products", column: "id", unique: true);
migrationBuilder.AddForeignKey(
    name: "FK_tickets_products_product_id", table: "tickets",
    column: "product_id", principalTable: "products", principalColumn: "id");
```

This is the unsafe change from Step 1, reconstructed by a tool.

**What the tool works out correctly.** The shape of the target schema: which columns exist, their types, which keys and indexes are needed, and that a foreign key belongs between them. Given a model, it produces a correct description of where the database should end up.

**What it cannot work out.** Four things, and each one corresponds to a step in this lab.

`DropColumn` on `product_code` destroys the only record of which product each ticket was sold under. The tool has no way to know that the column it is removing is the source for the column it is adding.

`nullable: false` with a default of the zero GUID is worse than failing. The hand-written version in Step 1 failed with `23502` and stopped. This one would succeed, giving every existing ticket the same meaningless identity, and the foreign key would then reject the whole migration with an error that does not explain the cause.

The ordering has no overlap period. `product_code` is dropped before `products.id` exists, so there is no moment when both references are present — and therefore no window in which two application versions can run at once. The expand/contract sequence is a deployment decision, not a schema fact, and nothing in the model expresses it.

There is no backfill at all. Deriving `product_id` from `product_code` requires knowing that those two columns mean the same thing, which is knowledge about the data rather than about the model.

**The division.** A migration tool can answer "what should the schema look like". It cannot answer "what is in the table right now", "which versions of the application are running", or "in what order must these steps happen so that nothing breaks in between". Those three questions are what the rest of this document is about.