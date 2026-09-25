# Lecture 3: where should reporting logic execute?

Four mechanisms produce the same figure — daily captured revenue per operator — and behave differently when the source data changes. The point is the differences, not the query.

- `database/postgres/queries/base_revenue.sql` — the direct aggregate over the base tables
- `database/postgres/migrations/020_reporting_function.sql` — the same read logic wrapped in a function
- `database/postgres/migrations/022_daily_captured_revenue.sql` — a materialized view, created with no data
- `database/postgres/migrations/021_daily_revenue_trigger.sql` — a summary table maintained by a trigger on insert, supplied deliberately incomplete
- `database/postgres/experiments/reporting_cases.sql` — six changes to the source data: a captured payment, a failed one, two status corrections, a delete, and a duplicate gateway reference
- `docs/reporting-comparison.md` — the full write-up: evidence for every case, responsibility matrix, side-effect trace, issue register and decision record

Run from `lecture03/`. Only one lecture's database can run at a time, since they all use port 5432 — stop any other with `docker compose down` first.

```
docker compose up -d
docker compose exec -T postgres psql -U mobility -d mobility < database/postgres/migrations/020_reporting_function.sql
docker compose exec -T postgres psql -U mobility -d mobility < database/postgres/migrations/021_daily_revenue_trigger.sql
docker compose exec -T postgres psql -U mobility -d mobility < database/postgres/migrations/022_daily_captured_revenue.sql
docker compose exec postgres psql -U mobility -d mobility -c "refresh materialized view daily_captured_revenue;"
```

Apply the three migrations in that order, then run the cases in `reporting_cases.sql` one at a time, measuring all four mechanisms between each. Reproducing the figures requires a fresh database: `docker compose down -v` followed by `docker compose up -d`.