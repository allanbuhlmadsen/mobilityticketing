-- Completed teaching baseline for lecture 4. These are explicit fixture policies.
begin;
alter table trips
 alter column capacity set not null,
 alter column reserved_seats set not null,
 add constraint trips_capacity_nonnegative check (capacity >= 0),
 add constraint trips_reserved_valid check (reserved_seats between 0 and capacity);
alter table products
 alter column price set not null, alter column currency set not null,
 add constraint products_price_valid check (price >= 0),
 add constraint products_currency_valid check (currency ~ '^[A-Z]{3}$');
alter table tickets
 alter column user_id set not null, alter column trip_id set not null,
 alter column ticket_code set not null, alter column product_code set not null,
 alter column status set not null, alter column price set not null,
 alter column currency set not null, alter column valid_from_utc set not null,
 alter column valid_to_utc set not null,
 add constraint tickets_user_fk foreign key (user_id) references users(id),
 add constraint tickets_trip_fk foreign key (trip_id) references trips(id),
 add constraint tickets_product_code_fk foreign key (product_code) references products(code),
 add constraint tickets_code_unique unique (ticket_code),
 add constraint tickets_identity_unique unique (id,ticket_code),
 add constraint tickets_status_valid check (status in ('Active','Validated','Expired','Cancelled')),
 add constraint tickets_price_valid check (price >= 0),
 add constraint tickets_currency_valid check (currency ~ '^[A-Z]{3}$'),
 add constraint tickets_validity_valid check (valid_to_utc >= valid_from_utc);
alter table payments
 alter column ticket_id set not null, alter column user_id set not null,
 alter column amount set not null, alter column currency set not null,
 alter column status set not null,
 add constraint payments_ticket_fk foreign key (ticket_id) references tickets(id),
 add constraint payments_user_fk foreign key (user_id) references users(id),
 add constraint payments_amount_valid check (amount >= 0),
 add constraint payments_currency_valid check (currency ~ '^[A-Z]{3}$'),
 add constraint payments_status_valid check (status in ('Pending','Captured','Failed','Refunded'));
create unique index payments_capture_reference_unique on payments(external_payment_reference) where status='Captured';
alter table validations
 alter column ticket_id set not null, alter column ticket_code set not null,
 add constraint validations_ticket_identity_fk foreign key (ticket_id,ticket_code) references tickets(id,ticket_code),
 add constraint validations_stop_fk foreign key (stop_id) references stops(id);
commit;
