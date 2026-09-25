-- Negative tests for the integrity migration.
-- Each statement below must be rejected. The block captures the SQLSTATE code
-- and the constraint name instead of matching an English error message, which
-- would break across PostgreSQL versions and server locales.
--
-- Run with:
--   docker compose exec -T postgres psql -U mobility -d mobility < database/postgres/experiments/constraints_should_fail_test.sql

do $$
declare
    v_sqlstate text;
    v_constraint text;
    v_passed integer := 0;
    v_failed integer := 0;
    
begin
    -- Helper pattern: each test runs inside its own savepoint so that a
    -- rejected write does not abort the remaining tests.

    -- Test 1: negative capacity. Expected 23514 (check_violation).
    begin
        update trips set capacity = -1 where id = 'TRIP-M2-20260429-0800';
        v_failed := v_failed + 1;
        raise notice 'FAIL  1  negative capacity was accepted';
    exception when others then
        get stacked diagnostics
            v_sqlstate = returned_sqlstate,
            v_constraint = constraint_name;
        v_passed := v_passed + 1;
        raise notice 'PASS  1  %  %', v_sqlstate, v_constraint;
    end;

    -- Test 2: reserved seats above capacity. Expected 23514.
    begin
        update trips set reserved_seats = capacity + 1 where id = 'TRIP-M2-20260429-0800';
        v_failed := v_failed + 1;
        raise notice 'FAIL  2  reserved_seats above capacity was accepted';
    exception when others then
        get stacked diagnostics
            v_sqlstate = returned_sqlstate, v_constraint = constraint_name;
        v_passed := v_passed + 1;
        raise notice 'PASS  2  %  %', v_sqlstate, v_constraint;
    end;

    -- Test 3: ticket for an unknown trip. Expected 23503 (foreign_key_violation).
    begin
        insert into tickets (id, user_id, trip_id, ticket_code, status,
            product_code, valid_from_utc, valid_to_utc, price, currency)
        values ('T-INVALID-TRIP', 'USER-1', 'TRIP-DOES-NOT-EXIST',
            'CODE-INVALID-TRIP', 'Active', 'SINGLE',
            '2026-04-29 08:00:00+00', '2026-04-29 09:00:00+00', 36, 'DKK');
        v_failed := v_failed + 1;
        raise notice 'FAIL  3  unknown trip was accepted';
    exception when others then
        get stacked diagnostics
            v_sqlstate = returned_sqlstate, v_constraint = constraint_name;
        v_passed := v_passed + 1;
        raise notice 'PASS  3  %  %', v_sqlstate, v_constraint;
    end;

    -- Test 4: validity window ends before it starts. Expected 23514.
    begin
        insert into tickets (id, user_id, trip_id, ticket_code, status,
            product_code, valid_from_utc, valid_to_utc, price, currency)
        values ('T-REVERSED', 'USER-1', 'TRIP-M2-20260429-0800',
            'CODE-REVERSED', 'Active', 'SINGLE',
            '2026-04-29 09:00:00+00', '2026-04-29 08:00:00+00', 36, 'DKK');
        v_failed := v_failed + 1;
        raise notice 'FAIL  4  reversed validity window was accepted';
    exception when others then
        get stacked diagnostics
            v_sqlstate = returned_sqlstate, v_constraint = constraint_name;
        v_passed := v_passed + 1;
        raise notice 'PASS  4  %  %', v_sqlstate, v_constraint;
    end;

    -- Test 5: duplicate ticket code. Expected 23505 (unique_violation).
    begin
        insert into tickets (id, user_id, trip_id, ticket_code, status,
            product_code, valid_from_utc, valid_to_utc, price, currency)
        select 'T-DUPLICATE-CODE', user_id, trip_id, ticket_code, status,
            product_code, valid_from_utc, valid_to_utc, price, currency
        from tickets where id = 'TICKET-1';
        v_failed := v_failed + 1;
        raise notice 'FAIL  5  duplicate ticket code was accepted';
    exception when others then
        get stacked diagnostics
            v_sqlstate = returned_sqlstate, v_constraint = constraint_name;
        v_passed := v_passed + 1;
        raise notice 'PASS  5  %  %', v_sqlstate, v_constraint;
    end;

    -- Test 6: unknown ticket status. Expected 23514.
    begin
        update tickets set status = 'Unknown' where id = 'TICKET-1';
        v_failed := v_failed + 1;
        raise notice 'FAIL  6  unknown ticket status was accepted';
    exception when others then
        get stacked diagnostics
            v_sqlstate = returned_sqlstate, v_constraint = constraint_name;
        v_passed := v_passed + 1;
        raise notice 'PASS  6  %  %', v_sqlstate, v_constraint;
    end;

    -- Test 7: negative product price. Expected 23514.
    begin
        update products set price = -1 where code = 'SINGLE';
        v_failed := v_failed + 1;
        raise notice 'FAIL  7  negative product price was accepted';
    exception when others then
        get stacked diagnostics
            v_sqlstate = returned_sqlstate, v_constraint = constraint_name;
        v_passed := v_passed + 1;
        raise notice 'PASS  7  %  %', v_sqlstate, v_constraint;
    end;

    -- Test 8: payment for an unknown ticket. Expected 23503.
    begin
        insert into payments (id, user_id, ticket_id, external_payment_reference,
            amount, currency, status)
        values ('PAYMENT-UNKNOWN-TICKET', 'USER-1', 'NO-SUCH-TICKET',
            'gateway-capture-invalid', 36, 'DKK', 'Captured');
        v_failed := v_failed + 1;
        raise notice 'FAIL  8  payment for unknown ticket was accepted';
    exception when others then
        get stacked diagnostics
            v_sqlstate = returned_sqlstate, v_constraint = constraint_name;
        v_passed := v_passed + 1;
        raise notice 'PASS  8  %  %', v_sqlstate, v_constraint;
    end;

    -- Test 9: duplicate external payment reference. Expected 23505.
    begin
        insert into payments (id, user_id, ticket_id, external_payment_reference,
            amount, currency, status)
        values ('PAYMENT-DUPLICATE-REFERENCE', 'USER-1', 'TICKET-1',
            'gateway-capture-0001', 36, 'DKK', 'Captured');
        v_failed := v_failed + 1;
        raise notice 'FAIL  9  duplicate payment reference was accepted';
    exception when others then
        get stacked diagnostics
            v_sqlstate = returned_sqlstate, v_constraint = constraint_name;
        v_passed := v_passed + 1;
        raise notice 'PASS  9  %  %', v_sqlstate, v_constraint;
    end;

    -- Test 10: validation combining one ticket id with another ticket's code.
    -- Expected 23503 from the composite foreign key.
    begin
        insert into validations (id, ticket_id, ticket_code, vehicle_id,
            stop_id, device_id, result)
        values ('VALIDATION-MISMATCH', 'TICKET-1', 'CODE-5C-0001',
            'BUS-5C-01', 'STOP-CENTRAL', 'DEVICE-01', 'Accepted');
        v_failed := v_failed + 1;
        raise notice 'FAIL 10  mismatched ticket id and code was accepted';
    exception when others then
        get stacked diagnostics
            v_sqlstate = returned_sqlstate, v_constraint = constraint_name;
        v_passed := v_passed + 1;
        raise notice 'PASS 10  %  %', v_sqlstate, v_constraint;
    end;

        -- Test 11: ticket without a price. Expected 23502 (not_null_violation).
    begin
        insert into tickets (id, user_id, trip_id, ticket_code, status,
            product_code, valid_from_utc, valid_to_utc, price, currency)
        values ('T-NO-PRICE', 'USER-1', 'TRIP-M2-20260429-0800',
            'CODE-NO-PRICE', 'Active', 'SINGLE',
            '2026-04-29 08:00:00+00', '2026-04-29 09:00:00+00', null, 'DKK');
        v_failed := v_failed + 1;
        raise notice 'FAIL 11  ticket without price was accepted';
    exception when others then
        get stacked diagnostics
            v_sqlstate = returned_sqlstate, v_constraint = constraint_name;
        v_passed := v_passed + 1;
        raise notice 'PASS 11  %  %', v_sqlstate, v_constraint;
    end;

    raise notice '----------------------------------------';
    raise notice 'Negative tests passed: %  failed: %', v_passed, v_failed;
end $$;