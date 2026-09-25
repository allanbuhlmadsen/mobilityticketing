-- Positive tests for the integrity migration.
-- A constraint that rejects everything would also pass the negative tests.
-- These writes must all succeed, and each one corresponds to a deliberate
-- design decision recorded in the integrity map.
--
-- Everything runs inside one transaction that is rolled back at the end,
-- so the database is unchanged afterwards and the file can be re-run.
--
-- Run with:
--   docker compose exec -T postgres psql -U mobility -d mobility < database/postgres/experiments/constraints_should_pass_test.sql

begin;

do $$
declare
    v_passed integer := 0;
    v_failed integer := 0;
    v_message text;
begin
    -- Test 1: capacity of zero is legitimate. A trip may be closed for sale
    -- or fully booked while still appearing in the timetable.
    begin
        update trips set capacity = 0, reserved_seats = 0
        where id = 'TRIP-M2-20260429-1200';
        v_passed := v_passed + 1;
        raise notice 'PASS  1  zero capacity accepted';
    exception when others then
        get stacked diagnostics v_message = message_text;
        v_failed := v_failed + 1;
        raise notice 'FAIL  1  %', v_message;
    end;

    -- Test 2: reserved seats may equal capacity. The trip is full, not invalid.
    begin
        update trips set reserved_seats = capacity
        where id = 'TRIP-5C-20260429-1700';
        v_passed := v_passed + 1;
        raise notice 'PASS  2  reserved_seats equal to capacity accepted';
    exception when others then
        get stacked diagnostics v_message = message_text;
        v_failed := v_failed + 1;
        raise notice 'FAIL  2  %', v_message;
    end;

    -- Test 3: a valid ticket referencing existing user, trip and product.
    begin
        insert into tickets (id, user_id, trip_id, ticket_code, status,
            product_code, valid_from_utc, valid_to_utc, price, currency)
        values ('T-VALID-1', 'USER-1', 'TRIP-M2-20260429-0800',
            'CODE-VALID-0001', 'Active', 'SINGLE',
            '2026-04-29 07:45:00+00', '2026-04-29 10:00:00+00', 36.00, 'DKK');
        v_passed := v_passed + 1;
        raise notice 'PASS  3  valid ticket accepted';
    exception when others then
        get stacked diagnostics v_message = message_text;
        v_failed := v_failed + 1;
        raise notice 'FAIL  3  %', v_message;
    end;

    -- Test 4: a zero-length validity window is allowed. The rule is that the
    -- end must not precede the start, not that the ticket must last.
    begin
        insert into tickets (id, user_id, trip_id, ticket_code, status,
            product_code, valid_from_utc, valid_to_utc, price, currency)
        values ('T-VALID-2', 'USER-2', 'TRIP-M2-20260429-0800',
            'CODE-VALID-0002', 'Active', 'SINGLE',
            '2026-04-29 08:00:00+00', '2026-04-29 08:00:00+00', 36.00, 'DKK');
        v_passed := v_passed + 1;
        raise notice 'PASS  4  zero-length validity window accepted';
    exception when others then
        get stacked diagnostics v_message = message_text;
        v_failed := v_failed + 1;
        raise notice 'FAIL  4  %', v_message;
    end;

    -- Test 5: a free ticket. Price zero is a discount or compensation case,
    -- not an error, which is why the check is >= 0 rather than > 0.
    begin
        insert into tickets (id, user_id, trip_id, ticket_code, status,
            product_code, valid_from_utc, valid_to_utc, price, currency)
        values ('T-VALID-3', 'USER-1', 'TRIP-5C-20260429-0900',
            'CODE-VALID-0003', 'Active', 'SINGLE',
            '2026-04-29 08:45:00+00', '2026-04-29 11:00:00+00', 0.00, 'DKK');
        v_passed := v_passed + 1;
        raise notice 'PASS  5  zero-price ticket accepted';
    exception when others then
        get stacked diagnostics v_message = message_text;
        v_failed := v_failed + 1;
        raise notice 'FAIL  5  %', v_message;
    end;

    -- Test 6: a pending payment with no gateway reference yet. This is the
    -- state between creating the row and receiving the gateway response.
    begin
        insert into payments (id, user_id, ticket_id, external_payment_reference,
            amount, currency, status)
        values ('PAY-PENDING-1', 'USER-1', 'T-VALID-1', null,
            36.00, 'DKK', 'Pending');
        v_passed := v_passed + 1;
        raise notice 'PASS  6  pending payment without reference accepted';
    exception when others then
        get stacked diagnostics v_message = message_text;
        v_failed := v_failed + 1;
        raise notice 'FAIL  6  %', v_message;
    end;

    -- Test 7: a second pending payment, also without a reference. PostgreSQL
    -- treats each null as unknown and therefore distinct, so the unique
    -- constraint permits many in-flight payments at once. This behaviour is
    -- relied upon deliberately.
    begin
        insert into payments (id, user_id, ticket_id, external_payment_reference,
            amount, currency, status)
        values ('PAY-PENDING-2', 'USER-2', 'T-VALID-2', null,
            36.00, 'DKK', 'Pending');
        v_passed := v_passed + 1;
        raise notice 'PASS  7  concurrent null references accepted';
    exception when others then
        get stacked diagnostics v_message = message_text;
        v_failed := v_failed + 1;
        raise notice 'FAIL  7  %', v_message;
    end;

    -- Test 8: a validation with matching ticket id and ticket code.
    begin
        insert into validations (id, ticket_id, ticket_code, vehicle_id,
            stop_id, device_id, result)
        values ('VAL-VALID-1', 'T-VALID-1', 'CODE-VALID-0001',
            'BUS-5C-01', 'STOP-CENTRAL', 'DEVICE-01', 'Accepted');
        v_passed := v_passed + 1;
        raise notice 'PASS  8  matching validation accepted';
    exception when others then
        get stacked diagnostics v_message = message_text;
        v_failed := v_failed + 1;
        raise notice 'FAIL  8  %', v_message;
    end;

    -- Test 9: a validation without location data. Handheld or offline devices
    -- may not report a stop, and a passenger must not be refused because of it.
    begin
        insert into validations (id, ticket_id, ticket_code, vehicle_id,
            stop_id, device_id, result)
        values ('VAL-VALID-2', 'T-VALID-2', 'CODE-VALID-0002',
            null, null, null, 'Accepted');
        v_passed := v_passed + 1;
        raise notice 'PASS  9  validation without location accepted';
    exception when others then
        get stacked diagnostics v_message = message_text;
        v_failed := v_failed + 1;
        raise notice 'FAIL  9  %', v_message;
    end;

    -- Test 10: a rejected validation. The result column must carry outcomes
    -- other than success, or refusals could not be recorded at all.
    begin
        insert into validations (id, ticket_id, ticket_code, vehicle_id,
            stop_id, device_id, result)
        values ('VAL-VALID-3', 'T-VALID-3', 'CODE-VALID-0003',
            'BUS-5C-01', 'STOP-NORREPORT', 'DEVICE-02', 'Rejected');
        v_passed := v_passed + 1;
        raise notice 'PASS 10  rejected validation accepted';
    exception when others then
        get stacked diagnostics v_message = message_text;
        v_failed := v_failed + 1;
        raise notice 'FAIL 10  %', v_message;
    end;

    raise notice '----------------------------------------';
    raise notice 'Positive tests passed: %  failed: %', v_passed, v_failed;
end $$;

rollback;