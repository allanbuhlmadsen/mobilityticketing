# Lecture 4: changing product identity without breaking tickets

Tickets refer to products by `product_code`. A code is fine on a price list but a poor identity, since an operator may want to rename it. This migration moves tickets onto a stable `product_id` while the previous application release is still running.

- `database/postgres/init/` — the supplied schema, including the completed integrity constraints and a fixture ticket bought for 65.00 DKK against a catalogue price of 80.00
- `database/postgres/migrations/030_expand_product_identity.sql` — adds the identity to products and a nullable reference to tickets, with a `not valid` foreign key; nothing is removed
- `database/postgres/migrations/031_backfill_ticket_product.sql` — fills the reference for existing tickets; repeatable, so late writes from the old release are picked up
- `database/postgres/migrations/032_require_ticket_product.sql` — validates the foreign key and makes the reference required; the first step that breaks the old release
- `database/postgres/experiments/` — the writers and readers for each stage: `old_` uses the code only, `new_` carries both references, `final_` uses the identity only; plus `baseline.sql`, `verify.sql`, `unsafe_change.sql` and the `remove_legacy.sql` rehearsal
- `docs/evidence/README.md` — the full write-up: every stage with output, a compatibility table across the four schema states, the rollout decision, and a comparison with what a migration tool would generate

Run from `lecture04/`. Only one lecture's database can run at a time, since they all use port 5432 — stop any other with `docker compose down` first.

```
docker compose up -d
docker compose exec -T postgres psql -U mobility -d mobility -v ON_ERROR_STOP=1 < database/postgres/experiments/baseline.sql
docker compose exec -T postgres psql -U mobility -d mobility -v ON_ERROR_STOP=1 < database/postgres/migrations/030_expand_product_identity.sql
docker compose exec -T postgres psql -U mobility -d mobility -v ON_ERROR_STOP=1 < database/postgres/migrations/031_backfill_ticket_product.sql
docker compose exec -T postgres psql -U mobility -d mobility -v ON_ERROR_STOP=1 < database/postgres/experiments/verify.sql
docker compose exec -T postgres psql -U mobility -d mobility -v ON_ERROR_STOP=1 < database/postgres/migrations/032_require_ticket_product.sql
```

Run `030` once. Run `031` as many times as needed — the second run changes zero rows. `032` only succeeds once `verify.sql` returns no rows. Product identities are generated per database, so the ones in the evidence file will differ after `docker compose down -v` followed by `docker compose up -d`.