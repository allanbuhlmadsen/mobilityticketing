# Implementation lab: Where should reporting logic execute?

## Purpose

Implement and compare a direct SQL query, a user-defined function, a materialized view, and a trigger-maintained summary for daily captured revenue. Use the differences to decide where the responsibility belongs.

The aim is not to simply choose the option with the most or the least SQL. Make a fair comparison of the options. Take into account execution timing, dependencies, transaction scope, freshness, and recovery.

## Scenario

Operators need daily captured revenue. The initial design proposes a `daily_revenue_by_operator` table maintained when payments are inserted. Reports may also be calculated directly from the transactional tables or exposed through a materialized view.

The `payments` table is the authority for this experiment. Treat the stored reporting results as derived data.

## Before you start

Start the database from the repository root:

```bash
docker compose up -d
docker compose ps
```

Run the base query in [`../database/postgres/queries/base_revenue.sql`](../database/postgres/queries/base_revenue.sql) and save its result. Do not edit the files in `database/postgres/init/`.

## Tasks

1. Run the reference revenue query and verify its result from the base tables.
2. Wrap the read logic in a SQL function.
3. Create a materialized view and observe when it becomes stale.
4. Create the supplied trigger-maintained summary.
5. Test all four approaches against:
   - a captured payment insert;
   - a failed payment insert;
   - a status correction from `Failed` to `Captured`;
   - a correction from `Captured` to `Refunded`;
   - deletion or replacement of test data;
   - duplicate delivery of the same external payment reference.
6. Produce a responsibility matrix comparing correctness, freshness, write cost, read cost, hidden side effects, rebuildability, and operational complexity.
7. Recommend one approach for the current case. A hybrid answer is allowed, but each stored copy must have a clear authority and rebuild path.

The migration examples identify the intended object names. Complete them in dependency order and apply them from the repository root:

```bash
docker compose exec -T postgres psql -U mobility -d mobility < database/postgres/migrations/020_reporting_function.sql
docker compose exec -T postgres psql -U mobility -d mobility < database/postgres/migrations/021_daily_revenue_trigger.sql
docker compose exec -T postgres psql -U mobility -d mobility < database/postgres/migrations/022_daily_captured_revenue.sql
```

Use a clean container when you need to repeat the experiment:

```bash
docker compose down
docker compose up -d
```

## Required evidence

- SQL object definitions for all four approaches.
- Output before and after each test case.
- One captured example where two approaches disagree.
- A side-effect trace showing everything caused by one payment write.
- A responsibility matrix with a named authority, freshness rule, and rebuild path.
- One issue in the issue register and one defended decision record.

## Side-effect trace

For one `INSERT INTO payments`, record:

1. constraints or references checked;
2. trigger execution, if any;
3. summary-table writes;
4. rows or locks touched, where observable;
5. commit or rollback behaviour;
6. the point at which each report becomes current;
7. what the application can observe.

## Your recommendation

What's your final recommendation?

It's important to not **only** choose the fastest option. Think about the effects on coupling, correction behavior, duplicate delivery, observability and recovery.

Remember that the lab does not require a final architecture. We will address problems like ticket-purchase concurrency and payment capture in later lectures.
