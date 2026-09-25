# Lecture 1: relational model and timetable queries

The smallest relational model that supports route maintenance and upcoming-trip queries: operators, routes, stops, route stops and trips.

- `database/postgres/001_relational_baseline.sql` — schema, including the composite primary key `(route_id, stop_sequence)` on `route_stops`
- `database/postgres/002_seed.sql` — repeatable seed data
- `database/postgres/003_queries.sql` — the three workload queries
- `docs/lab.md` — the lab brief, with the solution appended: system context, access-pattern map, ER diagram, functional dependency, assumptions and results
- `docs/notes.md` — the assumption most likely to change

Run from `lecture01/`. Only one lecture's database can run at a time, since they all use port 5432 — stop any other with `docker compose down` first.

```
docker compose up -d
docker compose exec -T postgres psql -U mobility -d mobility -v ON_ERROR_STOP=1 < database/postgres/003_queries.sql
```

The initialisation scripts run only against an empty data directory. To replay them: `docker compose down -v` followed by `docker compose up -d`.