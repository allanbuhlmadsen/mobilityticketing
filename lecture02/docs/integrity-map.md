# Integrity map

| Invariant | Affected tables and columns | Current protection | Missing protection or limitation | Expected failure behaviour | Evidence |
| --- | --- | --- | --- | --- | --- |
| Capacity cannot be negative | `trips.capacity` | `trips_capacity_non_negative`, `not null` | None | Write rejected, SQLSTATE 23514 | Negative test 1; positive test 1 shows zero is accepted |
| Reserved seats within capacity | `trips.reserved_seats`, `trips.capacity` | `trips_reserved_seats_valid`, `not null` | Protects one row only; cannot arbitrate two concurrent purchases | Write rejected, SQLSTATE 23514 | Negative test 2; positive test 2 shows equality is accepted |
| Prices and amounts cannot be negative | `products.price`, `tickets.price`, `payments.amount` | `products_price_non_negative`, `tickets_price_non_negative`, `payments_amount_non_negative` | Does not model refunds; a refund is a positive amount with a status, not a negative amount | Write rejected, SQLSTATE 23514 | Negative test 7; positive test 5 shows zero is accepted; negative test 11 shows a null price is rejected with 23502 |
| Currency present and consistently represented | `products.currency`, `tickets.currency`, `payments.currency` | `*_currency_format` regex, `not null` | Format only; does not verify the code exists in ISO 4217 | Write rejected, SQLSTATE 23514 | Migration DDL; `\d tickets` |
| Tickets reference existing users, trips and products | `tickets.user_id`, `trip_id`, `product_code` | `tickets_user_fk`, `tickets_trip_fk`, `tickets_product_fk` | None for existence; does not verify the price matches the product | Write rejected, SQLSTATE 23503 | Negative test 3; positive test 3 |
| Payments reference existing tickets | `payments.ticket_id`, `user_id` | `payments_ticket_fk`, `payments_user_fk`, `not null` | Forces the ticket to exist before the payment, which conflicts with the purchase order of operations (Issue 1) | Write rejected, SQLSTATE 23503 | Negative test 8 |
| A validation refers to one existing ticket, and its id and code describe that same ticket | `validations.ticket_id`, `ticket_code`; `tickets.id`, `ticket_code` | `validations_ticket_fk` as a composite foreign key, made possible by `tickets_id_code_unique` | None. A single-column key on `ticket_id` would have accepted a mismatched code, since both values exist individually | Write rejected, SQLSTATE 23503 | Negative test 10; positive test 8 |
| Ticket codes identify tickets unambiguously | `tickets.ticket_code` | `tickets_code_unique`, `not null` | None | Write rejected, SQLSTATE 23505 | Negative test 5 |
| Validity end not before start | `tickets.valid_from_utc`, `valid_to_utc` | `tickets_validity_window`, `not null` | Does not keep `status = 'Expired'` in step with the window; expiry happens through time, not through a write | Write rejected, SQLSTATE 23514 | Negative test 4; positive test 4 shows equal timestamps are accepted |
| Status values come from a known set | `trips.status`, `tickets.status`, `payments.status`, `validations.result` | `trips_status_known`, `tickets_status_known`, `payments_status_known`, `validations_result_known` | Capitalisation is now part of the contract; `'active'` is rejected as firmly as `'Unknown'` | Write rejected, SQLSTATE 23514 | Negative test 6; positive test 10 |
| One captured payment recorded once | `payments.external_payment_reference` | `payments_external_reference_unique` | Nullable by design, so in-flight payments are unconstrained until the reference arrives | Write rejected, SQLSTATE 23505 | Negative test 9; positive tests 6 and 7 |
| Reserved seats match the number of active tickets | `trips.reserved_seats`; `tickets` | None | Spans two tables and many rows; no row-level constraint can express it. Seed data already violates it | Not detected at write time; visible only through a reconciliation query | `TRIP-M2-20260429-0800` has `reserved_seats = 2` and one ticket |
| Payment amount matches ticket price | `payments.amount`; `tickets.price` | None | Spans two tables; partial refunds and fees make strict equality wrong | Not detected | Issue 2 |
| A disabled user must not buy tickets | `users.is_disabled`; `tickets` | None | Requires reading another table at write time | Not detected | Open domain decision |
| Vehicle and device identifiers refer to real equipment | `validations.vehicle_id`, `device_id` | None | No `vehicles` or `devices` table exists | Not detected | Open domain decision |

## Issue register

### Issue 1: Payment references a ticket that does not exist yet

- **Evidence:** `payments_ticket_fk` requires `payments.ticket_id` to match an existing row in `tickets`, and `payments.ticket_id` is `not null`. The purchase trace, however, creates the payment row before the ticket, so that a gateway call that fails or times out still leaves a record of the attempt. The constraint and the intended order of operations contradict each other.

- **Problem:** The database cannot represent the state "a payment has been started for a purchase that has not yet produced a ticket". Every payment row must point at a ticket from the moment it is inserted.

- **Consequence:** The application is forced into one of two positions. Either it calls the gateway before writing anything, in which case a crash between the charge and the insert leaves money taken with no record in the database at all. Or it creates the ticket first, which means an unpaid ticket row exists and is visible to any query that does not know to exclude it. The first loses the audit trail; the second weakens the meaning of a ticket row.

- **Specific improvement:** Create the ticket first with a status such as `'Pending'`, add that value to `tickets_status_known`, and exclude it wherever tickets are treated as usable. This keeps the foreign key strict and confines the ambiguity to a named, queryable state. Making `payments.ticket_id` nullable would also work, but weakens the constraint permanently to solve a temporary ordering problem.

- **Open question:** Should an unpaid `'Pending'` ticket count towards `reserved_seats`? Counting it holds the seat during checkout but overstates occupancy if payment is abandoned. Not counting it means the seat can be sold twice while a payment is in flight. This is a transaction and timeout question rather than a constraint question.

### Issue 2: Reserved seats and ticket count can disagree

- **Evidence:** The supplied seed data contains
  `TRIP-M2-20260429-0800` with `reserved_seats = 2`, while only one ticket (`TICKET-1`) references that trip. No constraint rejects this state, because the two facts live in different tables. A reconciliation query can detect the drift after the fact:

      select t.id, t.reserved_seats, count(k.id)
      from trips t left join tickets k on k.trip_id = t.id
      group by t.id, t.reserved_seats;

- **Problem:** `trips.reserved_seats` is a running total maintained by the application. Nothing ties it to the rows it is supposed to summarise. A row-level check can compare `reserved_seats` to `capacity` in the same row, but cannot count rows in `tickets`.

- **Consequence:** The counter drifts. A purchase that inserts a ticket but fails before incrementing the counter undercounts, and the trip is oversold. A refund that cancels a ticket without decrementing overcounts, and seats go unsold on a full vehicle. Neither is detectable by any single write, and the error accumulates silently across a service day.

- **Specific improvement:** Two directions are available. Derive availability from `count(*)` over `tickets` and drop the stored counter, which is always correct but reads more rows on the hottest path in the system. Or keep the counter and make the ticket insert and the counter update a single atomic unit, with a reconciliation job that recomputes totals periodically and reports drift.

- **Open question:** Journey search and purchase have different accuracy requirements. The brief states that a slightly stale availability figure is acceptable for search but not for a purchase decision. Whether one number can serve both purposes, or whether the two paths need different sources, is a design decision for the transactions lecture.

## Delete and update behaviour

None of the foreign keys in `011_ticketing_integrity.sql` declare an `on delete` or `on update` action, so PostgreSQL applies `no action` — a delete or key change is rejected while a referencing row exists. That default is the correct starting point here, because every relationship below points at data that has already happened. The table records what each relationship should do and why.

| Relationship | On delete | On update | Reasoning |
| --- | --- | --- | --- |
| `tickets` → `users` | Restrict, then soft delete | Reject | A ticket must remain attributable after the account is closed. Deleting a user would erase the counterparty of a completed sale. Add `users.deleted_utc` and exclude such users from new purchases instead. |
| `tickets` → `trips` | Restrict | Reject | A sold ticket fixes what was sold. A trip with tickets is cancelled by setting `status = 'Cancelled'`, never removed. |
| `tickets` → `products` | Restrict | Reject | The product a ticket was sold under must stay resolvable for refunds and disputes. Withdraw a product with a validity flag rather than a delete. |
| `payments` → `tickets` | Restrict | Reject | Financial records outlive operational ones. A payment with no ticket cannot be reconciled against the gateway. |
| `payments` → `users` | Restrict, then soft delete | Reject | As for tickets. Accounting requires the payer to remain identifiable. |
| `validations` → `tickets` | Restrict | Reject | A validation is evidence that a passenger boarded. Removing the ticket would leave the event unexplained. |
| `validations` → `stops` | Restrict | Reject | A historical validation must keep its location. Retire a stop with an inactive flag rather than deleting the row. |
| `route_stops` → `routes` | Cascade | Cascade | The only exception. A route's stop pattern has no meaning without the route, holds no historical record, and is replaced wholesale during timetable maintenance. |

**Updates.** Every identifier above is a stable business key such as `TICKET-1` or `LINE-M2`, chosen once and never edited. Changing one would silently rewrite the meaning of every historical row referencing it, so key updates are rejected rather than cascaded. Non-key attributes are a different matter: a stop may be renamed and an operator rebranded without affecting any relationship, which is precisely what normalisation buys.

**Retention rather than deletion.** Tickets, payments and validations are subject to accounting and passenger-rights obligations, so they are removed on a schedule rather than on request. The mechanism belongs in a later lecture, but the shape is: retain for the statutory period, then anonymise the user reference rather than deleting the financial row. Note that this conflicts with `payments.user_id` being `not null` and would need a nullable column or a dedicated placeholder user — an unresolved consequence of a decision made earlier in this migration.

**Timetable maintenance.** The brief states that an operator may replace the timetable for an entire route. With the constraints now in place, that operation cannot delete trips that have tickets sold against them. Replacing a timetable therefore means cancelling affected trips and creating new ones, not deleting and reinserting. The constraints have made a destructive operation impossible, which is the intended outcome.

## State-transition trace

### Ticket purchase

A customer selects a trip and a product, and pays. The following rows change.

1. **Read `trips`** for the selected trip. The row must exist and have `status = 'Scheduled'`. Read `capacity` and `reserved_seats` to establish whether a seat appears to be available. Enforced by: `trips_status_known` guarantees the status is a known value; nothing guarantees the reading is still true a moment later.

2. **Read `products`** for the selected product code. The row must exist and supplies `price` and `currency`. Enforced by: `products_price_non_negative` and `products_currency_format` guarantee the values are usable.

3. **Insert into `payments`** with `status = 'Pending'`, `external_payment_reference = null`, and the amount taken from the product. The referenced user and ticket must already exist. Enforced by: `payments_user_fk`, `payments_ticket_fk`, `payments_amount_non_negative`,
`payments_status_known`. Note the ordering problem below.

4. **Call the external payment gateway.** Outside the database entirely. No constraint can observe or arbitrate this step.

5. **Update `payments`** with the returned reference and `status = 'Captured'`, or `'Failed'` if the gateway declined. Enforced by: `payments_external_reference_unique` prevents the same captured payment being recorded twice if the response is retried.

6. **Insert into `tickets`** with `status = 'Active'`, a generated `ticket_code`, the price copied from the product, and the validity window derived from the trip. Enforced by: `tickets_user_fk`, `tickets_trip_fk`, `tickets_product_fk`, `tickets_code_unique`, `tickets_validity_window`, `tickets_price_non_negative`, `tickets_currency_format`, `tickets_status_known`, and nine `not null` columns.

7. **Update `trips`** by incrementing `reserved_seats`. Enforced by: `trips_reserved_seats_valid` rejects any single write that would push the count above capacity.

**Ordering problem.** Step 3 inserts a payment that references a ticket, but the ticket is not created until step 6. `payments_ticket_fk` therefore makes this order impossible as written. Two resolutions exist: create the ticket first with a status such as `'Pending'`, or make `payments.ticket_id` nullable until the ticket exists. The first keeps the foreign key strict and is preferred, but it means an unpaid ticket row exists briefly. This is a transaction-boundary question and is recorded as an open issue.

**What the database cannot guarantee here.** Steps 1 and 7 are separated in time. Two customers may both read `reserved_seats = 119` against a capacity of 120, both pass their row-level check, and both write 120. Each write is individually legal and the trip is oversold. This requires a transaction strategy and is out of scope for this migration.

### Ticket validation

A passenger presents a ticket when boarding. The device reads a code and the system decides whether to accept it. This path is latency-sensitive: it runs while people are stepping onto a vehicle.

1. **Read `tickets` by `ticket_code`.** The code is what the scanner supplies; the ticket id is not known until this lookup returns. Enforced by: `tickets_code_unique` guarantees the lookup returns at most one row, which is what makes the decision deterministic. Without it the same code could match several tickets and the outcome would depend on row order.

2. **Decide the outcome** from the row just read. The ticket must exist, its `status` must be `'Active'`, and the current time must fall inside `valid_from_utc` and `valid_to_utc`. Enforced by: `tickets_status_known` guarantees the status is a value the application recognises;   `tickets_validity_window` guarantees the window is not reversed, so the comparison is meaningful. The decision itself is application logic.

3. **Insert into `validations`** with the ticket id from step 1, the code as scanned, the outcome, and whatever device and location data is available. Enforced by: `validations_ticket_fk` guarantees the id and the code describe the same ticket; `validations_result_known` guarantees the outcome is a recognised value; `validations_stop_fk` guarantees a supplied stop exists. `vehicle_id`, `stop_id` and `device_id` remain nullable so that a passenger is never refused because hardware failed to report its position.

4. **Update `tickets`** setting `status = 'Validated'` for single-use products, so the same ticket cannot be presented again. Enforced by: `tickets_status_known`. Nothing enforces that this update actually happens.

**Reporting is not updated here.** The brief states that reporting need not be current before validation completes, so no aggregate is touched on this path.

**What the database cannot guarantee here.** Steps 3 and 4 are separate writes. If the process fails between them, a validation is recorded while the ticket remains `'Active'` and can be presented again. Conversely, nothing prevents two validation rows being inserted for the same single-use ticket, because no constraint can count rows in another table. Whether a day pass may be validated repeatedly and a single ticket only once is a product rule that no row-level check can express.

**A second unenforced relationship.** `tickets.status = 'Expired'` and the `valid_to_utc` timestamp can disagree. A ticket may be past its validity window while still carrying `'Active'`, because expiry depends on the passage of time rather than on a write. Validation must therefore compare timestamps rather than trust the status column alone.

## Evidence

### 1. The migration applied cleanly

```
docker compose exec -T postgres psql -U mobility -d mobility < database/postgres/migrations/011_ticketing_integrity.sql
```

Output:

```
BEGIN
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
COMMIT
```

`COMMIT` rather than `ROLLBACK` shows that every constraint was accepted against the existing seed data. The whole migration runs inside one transaction, so a single failure would have left the schema untouched.

### 2. The constraints as the database reports them

Output of `\d tickets`, showing what PostgreSQL actually enforces rather than what the migration file claims:

```
Table "public.tickets"
     Column     |           Type           | Collation | Nullable | Default 
----------------+--------------------------+-----------+----------+---------
 id             | text                     |           | not null | 
 user_id        | text                     |           | not null | 
 trip_id        | text                     |           | not null | 
 ticket_code    | text                     |           | not null | 
 status         | text                     |           | not null | 
 product_code   | text                     |           | not null | 
 valid_from_utc | timestamp with time zone |           | not null | 
 valid_to_utc   | timestamp with time zone |           | not null | 
 price          | numeric                  |           | not null | 
 currency       | text                     |           | not null | 
Indexes: 
    "tickets_pkey" PRIMARY KEY, btree (id)
    "tickets_code_unique" UNIQUE CONSTRAINT, btree (ticket_code)
    "tickets_id_code_unique" UNIQUE CONSTRAINT, btree (id, ticket_code)
Check constraints:
    "tickets_currency_format" CHECK (currency ~ '^[A-Z]{3}$'::text)
    "tickets_price_non_negative" CHECK (price >= 0::numeric)
    "tickets_status_known" CHECK (status = ANY (ARRAY['Active'::text, 'Validated'::text, 'Expired'::text, 'Refunded'::text, 'Cancelled'::text]))
    "tickets_validity_window" CHECK (valid_to_utc >= valid_from_utc)
Foreign-key constraints:
    "tickets_product_fk" FOREIGN KEY (product_code) REFERENCES products(code)
    "tickets_trip_fk" FOREIGN KEY (trip_id) REFERENCES trips(id)
    "tickets_user_fk" FOREIGN KEY (user_id) REFERENCES users(id)
Referenced by:
    TABLE "payments" CONSTRAINT "payments_ticket_fk" FOREIGN KEY (ticket_id) REFERENCES tickets(id)
    TABLE "validations" CONSTRAINT "validations_ticket_fk" FOREIGN KEY (ticket_id, ticket_code) REFERENCES tickets(id, ticket_code)
```

Note that PostgreSQL rewrites `status in (...)` as `status = ANY (ARRAY[...])`. This is the same rule in the database's internal form.

Output of `\d validations`, showing the composite foreign key:

```
Table "public.validations"
    Column     |           Type           | Collation | Nullable | Default 
---------------+--------------------------+-----------+----------+---------
 id            | text                     |           | not null | 
 ticket_id     | text                     |           | not null | 
 ticket_code   | text                     |           | not null | 
 vehicle_id    | text                     |           |          | 
 stop_id       | text                     |           |          | 
 device_id     | text                     |           |          | 
 result        | text                     |           | not null | 
 validated_utc | timestamp with time zone |           | not null | now()
Indexes: 
    "validations_pkey" PRIMARY KEY, btree (id)
Check constraints:
    "validations_result_known" CHECK (result = ANY (ARRAY['Accepted'::text, 'Rejected'::text, 'Expired'::text]))
Foreign-key constraints:
    "validations_stop_fk" FOREIGN KEY (stop_id) REFERENCES stops(id)
    "validations_ticket_fk" FOREIGN KEY (ticket_id, ticket_code) REFERENCES tickets(id, ticket_code)
```

### 3. Invalid writes are rejected

Each statement in `experiments/constraints_should_fail_test.sql` runs in its own exception block, so one rejection does not prevent the others from running. The test captures the SQLSTATE code and the constraint name rather than the error message, which varies by PostgreSQL version and server locale.

```
NOTICE:  PASS  1  23514  trips_capacity_non_negative
NOTICE:  PASS  2  23514  trips_reserved_seats_valid
NOTICE:  PASS  3  23503  tickets_trip_fk
NOTICE:  PASS  4  23514  tickets_validity_window
NOTICE:  PASS  5  23505  tickets_code_unique
NOTICE:  PASS  6  23514  tickets_status_known
NOTICE:  PASS  7  23514  products_price_non_negative
NOTICE:  PASS  8  23503  payments_ticket_fk
NOTICE:  PASS  9  23505  payments_external_reference_unique
NOTICE:  PASS 10  23503  validations_ticket_fk
NOTICE:  PASS 11  23502  
NOTICE:  ----------------------------------------
NOTICE:  Negative tests passed: 11  failed: 0
DO
```

Four SQLSTATE classes appear: `23514` check violation, `23503` foreign key violation, `23505` unique violation, and `23502` not-null violation. Test 11 reports no constraint name, because a `not null` requirement is a property of the column itself rather than a separately named constraint object, so PostgreSQL has no name to return.

### 4. Valid writes are still accepted

A constraint that rejected everything would also have passed the tests above. `experiments/constraints_should_pass_test.sql` demonstrates that the rules sit where they were intended to. All writes run in one transaction that is rolled back, so the file is repeatable.

```
BEGIN
NOTICE:  PASS  1  zero capacity accepted
NOTICE:  PASS  2  reserved_seats equal to capacity accepted
NOTICE:  PASS  3  valid ticket accepted
NOTICE:  PASS  4  zero-length validity window accepted
NOTICE:  PASS  5  zero-price ticket accepted
NOTICE:  PASS  6  pending payment without reference accepted
NOTICE:  PASS  7  concurrent null references accepted
NOTICE:  PASS  8  matching validation accepted
NOTICE:  PASS  9  validation without location accepted
NOTICE:  PASS 10  rejected validation accepted
NOTICE:  ----------------------------------------
NOTICE:  Positive tests passed: 10  failed: 0
DO
ROLLBACK
```

Three of these correspond directly to design decisions. Test 4 shows why the validity check is `>=` and not `>`. Test 7 shows that several payments may be in flight with a null gateway reference at once, which is the reason that column is nullable. Test 9 shows that a passenger is not refused when a device fails to report its location.

## What every application can safely assume

With this migration applied, any application, script or future service writing to this database can rely on the following without checking first.

A trip has a known capacity and a reserved-seat count that never exceeds it in any single write. Prices and payment amounts are never negative. Every ticket belongs to a user, a trip and a product that exist, carries a code that identifies it uniquely, and has a validity window that does not run backwards. Every payment belongs to a ticket that exists, and a captured gateway reference appears at most once. Every validation refers to a ticket whose identifier and code describe the same row. All status and result values come from a known set.

It cannot assume that `reserved_seats` equals the number of tickets sold, that a payment amount matches the ticket price, that two concurrent purchases will not oversell the last seat, that a single-use ticket is validated only once, or that a ticket past its validity window carries the status `'Expired'`. Those guarantees require transactions, application logic, or scheduled work, and are recorded in the issue register above.