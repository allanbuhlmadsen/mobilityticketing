# Lecture 2: making invalid states difficult to store

The starter schema for tickets, payments and validations is deliberately permissive. This migration turns business rules into constraints the database enforces, whatever writes to it.

- `database/postgres/init/` — the supplied baseline and the weak ticketing schema, unchanged
- `database/postgres/migrations/011_ticketing_integrity.sql` — the constraints: not-null columns, foreign keys, value ranges, status sets, unique ticket codes and gateway references, and a composite foreign key tying a validation's ticket id to its ticket code
- `database/postgres/experiments/constraints_should_fail_test.sql` — eleven invalid writes, each expected to be rejected; captures the SQLSTATE code and constraint name rather than the error text
- `database/postgres/experiments/constraints_should_pass_test.sql` — ten valid writes, proving the rules are not simply rejecting everything
- `docs/integrity-map.md` — the full write-up: integrity map, issue register, state-transition traces, delete and update behaviour, and evidence

Run from `lecture02/`. Only one lecture's database can run at a time, since they all use port 5432 — stop any other with `docker compose down` first.

```
docker compose up -d
docker compose exec -T postgres psql -U mobility -d mobility < database/postgres/migrations/011_ticketing_integrity.sql
docker compose exec -T postgres psql -U mobility -d mobility < database/postgres/experiments/constraints_should_fail_test.sql
docker compose exec -T postgres psql -U mobility -d mobility < database/postgres/experiments/constraints_should_pass_test.sql
```

The migration applies once against a fresh database. To start over: `docker compose down -v` followed by `docker compose up -d`.