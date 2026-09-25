-- Copy this file to 011_ticketing_integrity.sql and complete it from your integrity map.
-- Keep the starter DDL unchanged.

begin;

-- Trips: capacity is operational data that every purchase decision depends on,
-- so it must always be present and meaningful.
alter table trips
    alter column capacity set not null,
    alter column reserved_seats set not null,
    add constraint trips_capacity_non_negative
        check (capacity >= 0),
    add constraint trips_reserved_seats_valid
        check (reserved_seats between 0 and capacity),
    add constraint trips_status_known
        check (status in ('Scheduled', 'Cancelled', 'Departed', 'Completed'));

-- Products: a product with no price or no currency cannot be sold.
alter table products
    alter column name set not null,
    alter column price set not null,
    alter column currency set not null,
    add constraint products_price_non_negative
        check (price >= 0),
    add constraint products_currency_format
        check (currency ~ '^[A-Z]{3}$');

-- Users: email identifies the account for login and receipts, so it must be
-- present and unique. is_disabled has a default but nothing prevents a null.
alter table users
    alter column email set not null,
    alter column is_disabled set not null,
    add constraint users_email_unique
        unique (email);

-- Tickets: the record a passenger relies on when boarding. Every column below
-- is required at insert time, because a ticket that cannot be identified,
-- priced or presented is not a ticket.
alter table tickets
    alter column user_id set not null,
    alter column trip_id set not null,
    alter column ticket_code set not null,
    alter column status set not null,
    alter column product_code set not null,
    alter column valid_from_utc set not null,
    alter column valid_to_utc set not null,
    alter column price set not null,
    alter column currency set not null,
    add constraint tickets_user_fk
        foreign key (user_id) references users(id),
    add constraint tickets_trip_fk
        foreign key (trip_id) references trips(id),
    add constraint tickets_product_fk
        foreign key (product_code) references products(code),
    add constraint tickets_code_unique
        unique (ticket_code),
    add constraint tickets_id_code_unique
        unique (id, ticket_code),
    add constraint tickets_price_non_negative
        check (price >= 0),
    add constraint tickets_currency_format
        check (currency ~ '^[A-Z]{3}$'),
    add constraint tickets_validity_window
        check (valid_to_utc >= valid_from_utc),
    add constraint tickets_status_known
        check (status in ('Active', 'Validated', 'Expired', 'Refunded', 'Cancelled'));

-- Payments: the money side of a purchase. The gateway reference is deliberately
-- nullable, because the row exists before the external system answers.
alter table payments
    alter column user_id set not null,
    alter column ticket_id set not null,
    alter column amount set not null,
    alter column currency set not null,
    alter column status set not null,
    alter column created_utc set not null,
    add constraint payments_user_fk
        foreign key (user_id) references users(id),
    add constraint payments_ticket_fk
        foreign key (ticket_id) references tickets(id),
    add constraint payments_amount_non_negative
        check (amount >= 0),
    add constraint payments_currency_format
        check (currency ~ '^[A-Z]{3}$'),
    add constraint payments_status_known
        check (status in ('Pending', 'Captured', 'Failed', 'Refunded')),
    add constraint payments_external_reference_unique
        unique (external_payment_reference);

-- Validations: the record of a ticket being presented when boarding.
-- The composite foreign key guarantees that ticket_id and ticket_code
-- describe the same ticket, not two different ones.
alter table validations
    alter column ticket_id set not null,
    alter column ticket_code set not null,
    alter column result set not null,
    alter column validated_utc set not null,
    add constraint validations_ticket_fk
        foreign key (ticket_id, ticket_code) references tickets (id, ticket_code),
    add constraint validations_stop_fk
        foreign key (stop_id) references stops(id),
    add constraint validations_result_known
        check (result in ('Accepted', 'Rejected', 'Expired'));

commit;