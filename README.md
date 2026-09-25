# MobilityTicketing

Database design coursework, lectures 1 to 4. Each lecture is a self-contained folder with its own PostgreSQL container, schema, scripts and documentation.

# Compulsory Assignment 1 review guide

Group members: Allan Buhl Blindbæk (individual submission)
Submitted commit: TO BE FILLED IN
Setup and reset instructions: see the README in each lecture folder

Every folder runs the same way. From the lecture folder, `docker compose up -d` starts the database and runs the initialisation scripts; `docker compose down -v` followed by `docker compose up -d` resets it. Only one lecture can run at a time, since all four use port 5432.

## Where to find the work

**Lecture 1: model, workload map and queries** — [`lecture01/`](lecture01/)
Schema in [`001_relational_baseline.sql`](lecture01/database/postgres/001_relational_baseline.sql), seed in [`002_seed.sql`](lecture01/database/postgres/002_seed.sql), the three workload queries in [`003_queries.sql`](lecture01/database/postgres/003_queries.sql). The system context, access-pattern map, ER diagram, functional dependency and results are in [`docs/lab.md`](lecture01/docs/lab.md), appended below the brief.

**Lecture 2: constraints and tests** — [`lecture02/`](lecture02/)
The migration is [`011_ticketing_integrity.sql`](lecture02/database/postgres/migrations/011_ticketing_integrity.sql). Eleven rejected writes in [`constraints_should_fail_test.sql`](lecture02/database/postgres/experiments/constraints_should_fail_test.sql) and ten accepted ones in [`constraints_should_pass_test.sql`](lecture02/database/postgres/experiments/constraints_should_pass_test.sql), each capturing the SQLSTATE code and constraint name. Integrity map, issue register and state-transition traces in [`docs/integrity-map.md`](lecture02/docs/integrity-map.md).

**Lecture 3: reporting experiment and comparison** — [`lecture03/`](lecture03/)
Four mechanisms for the same figure: the direct query in [`base_revenue.sql`](lecture03/database/postgres/queries/base_revenue.sql), a function, a materialized view and a trigger-maintained table in [`migrations/`](lecture03/database/postgres/migrations/). Six changes to the source data in [`reporting_cases.sql`](lecture03/database/postgres/experiments/reporting_cases.sql). Evidence, responsibility matrix and decision in [`docs/reporting-comparison.md`](lecture03/docs/reporting-comparison.md).

**Lecture 4: migration stages and verification** — [`lecture04/`](lecture04/)
Three migrations in [`migrations/`](lecture04/database/postgres/migrations/): expand, backfill, require. Writers and readers for each stage in [`experiments/`](lecture04/database/postgres/experiments/). Full write-up with a compatibility table across four schema states in [`docs/evidence/README.md`](lecture04/docs/evidence/README.md).

## Two decisions worth discussing

### The route-stop key is `(route_id, stop_sequence)`, not `(route_id, stop_id)`

The alternative would have forbidden a route from visiting the same stop twice. That is a business assumption, not a fact about city transport: ring lines and turnarounds do exactly that. Keying on the position rather than on the stop leaves the model able to represent them, and the stricter rule can still be added later as a separate unique constraint without touching the primary key.

The seed data exercises it. On `LINE-5C`, `STOP-NORREPORT` appears at both sequence 1 and sequence 4 — two rows the alternative key would have rejected. See [`002_seed.sql`](lecture01/database/postgres/002_seed.sql) and the query 2 output in [`docs/lab.md`](lecture01/docs/lab.md).

Worth noting: this fact lives entirely in the key. The ER diagram cannot express it, so a reader of the diagram alone could not tell the two models apart.

### A ticket stores the price paid, rather than resolving it from the product

The alternative would be to join `tickets` to `products` and read the current price. That is simpler and never goes stale — but it is also wrong, because it answers a different question. A ticket records a completed sale; the catalogue records what something costs today. Repricing a historical ticket because someone edited a price list would break accounting and any refund based on it.

`TICKET-3` in lecture 4 was sold for 65.00 DKK while the DAY product lists at 80.00. That gap is the test: the backfill in [`031_backfill_ticket_product.sql`](lecture04/database/postgres/migrations/031_backfill_ticket_product.sql) never mentions `price`, and the evidence in [`docs/evidence/README.md`](lecture04/docs/evidence/README.md) shows 65.00 unchanged through every stage of the migration.

## One limitation or open question

While both `product_code` and `product_id` exist on a ticket, the database cannot tell that they agree. Both foreign keys are satisfied independently — the code resolves in `products.code`, the identity in `products.id` — and nothing compares them. A ticket naming SINGLE by code and DAY by identity was inserted successfully; see "The writer prevents a mismatch; the database does not" in [`lecture04/docs/evidence/README.md`](lecture04/docs/evidence/README.md).

The application writer prevents it by deriving the code from the product row, but that is application logic, not a schema guarantee. Any script or manual correction can bypass it.

Lecture 2 solved the equivalent problem for `validations` with a composite foreign key on `(ticket_id, ticket_code)`. That does not work here, because the two columns reference two different unique keys on `products` rather than one composite target.

What we would check next: how long the overlap period actually lasts in a real rollout, and whether a trigger is warranted for that window — or whether running `verify.sql` on a schedule is enough, given that the exposure ends when `product_code` is dropped.