# Implementation lab: Change product identity without breaking tickets

## Scenario

The transport operator wants to rename product codes without breaking existing tickets. Your job is to give each product an ID that stays the same when its code changes. You cannot update every application instance at once, so your migration needs to support old code that still reads and writes `product_code`.

For this exercise, keep product codes unique and do not rename or reuse them while old and new code run together. Assign each product ID once. Keep every ticket linked to the same product, with its original price and currency.

## Before you start

Create a branch, then run these commands from the repository root to start your lab database:

```bash
git switch -c product-identity-lab
docker compose up -d
docker compose ps
docker compose exec -T postgres psql -U mobility -d mobility -v ON_ERROR_STOP=1 < database/postgres/experiments/lecture04/baseline.sql
```

Check that you have three tickets covering two products and that every ticket refers to an existing product. Save the ticket IDs, product codes, prices and currencies so you can compare them later. Leave `database/postgres/init/` unchanged.

If you are continuing in your own repository, use your earlier migrations and load at least three valid tickets covering two products. Check whether your reporting views or functions from lecture 3 use the columns you will change.

Copy each `.sql.example` file you need to `.sql` and complete its TODOs. Some examples contain runnable queries; others need your SQL before they can run.

Before running a migration, check its nullable columns, keys, backfill and any statements that remove data. If you already use an ORM, inspect its generated SQL too.

Run your scripts from the repository root, for example:

```bash
docker compose exec -T postgres psql -U mobility -d mobility -v ON_ERROR_STOP=1 < database/postgres/migrations/030_expand_product_identity.sql
```

Use the same command pattern for each file. Run each DDL migration once, in order. The backfill should be safe to repeat. If a statement fails inside a transaction, roll it back before continuing.

## Tasks

1. Try removing the old reference before updating the application code. Before running it, predict what will happen. Explain how you could lose the link between tickets and products, and show which old query or insert breaks. Roll back or reset your lab database before continuing.
2. Complete `030_expand_product_identity.sql.example`. Add a stored UUID to each product and a unique constraint on that column. Add a nullable `tickets.product_id` with a foreign key to the product ID. Keep `product_code`. Use a short lock timeout and explain what you would need to consider with a much larger table.
3. Write an insert and a query that use only `product_code`, as the old application would. Show that both still work after you add the new columns.
4. Write a new insert that accepts a product ID and looks up the code from that product. Store both references and the agreed purchase price. If the caller supplies a conflicting product code, either reject it or ignore it and use the code you looked up.
5. Write a query that finds a ticket's product by `product_id`, using `product_code` only when `product_id` is null. Test it before you fill in the IDs on existing tickets.
6. Complete `031_backfill_ticket_product.sql.example`. Fill in `product_id` only where it is null. Run the backfill twice and check that the second run changes zero rows. Then insert another ticket using the old writer and run the backfill again. It should fill in the new ticket's reference without changing any IDs you already assigned.
7. Write checks for null product IDs, missing products, and code/ID pairs that point to different products. Compare the original tickets, prices and currencies with your starting data. Separately, try writing a mismatched pair directly in SQL and record whether the database rejects it.
8. Complete `032_require_ticket_product.sql.example`. First, try making `product_id` required while one ticket still has a null reference. Capture the failure. Once you meet the conditions below, validate the foreign key and make the column required. Show that the old writer now fails.
9. Write an insert and a query that use only `product_id`. Check for views and functions that still use `tickets.product_code`, then try dropping that column in your lab database without `CASCADE`. Keep `products.code` for the catalogue.
## Before you require the new reference

Before making `product_id` required, make sure no old-only writers are still running and that the new readers and writers are in place. Run the backfill one last time and check for missing or mismatched references. Explain whether you could still return to the old application version and what that would involve. You cannot tell which versions are running just by looking at the repository.

Before dropping `tickets.product_code`, switch to readers and writers that use only the ID and check for database objects that still need the code. Explain whether you would keep the old column for a while and why. A UUID default does not stop someone from updating an ID, so explain how your application code or database permissions would prevent that.

## What to record

Keep your SQL, commands and important results in `docs/evidence/lecture04/README.md`. Show the failures as well as the successful runs, and check that the original tickets still have the same products, prices and currencies.

Add a small table showing which inserts and queries work before expansion, after expansion, once the ID is required, and after the old column is removed. Note any query that runs but misses tickets.

Finish with your rollout decision: when would you stop the old writers, and could you still return to the old application version? Support your answer with a result from your tests.
