-- Final writer: supplies the product identity only. This is the version that
-- must work after tickets.product_code is removed, so it never writes that
-- column.

select id, code, price, currency from products order by code;

\set product_id '8f792c1a-8d8c-43a0-bbc7-b43721094296'
\set ticket_id 'LAB04-FINAL-1'
\set ticket_code 'LAB04-CODE-FINAL-1'
\set agreed_price 36.00

insert into tickets
    (id, user_id, trip_id, ticket_code, status,
     product_id,
     valid_from_utc, valid_to_utc, price, currency)
select
    :'ticket_id',
    t.user_id,
    t.trip_id,
    :'ticket_code',
    'Active',
    p.id,
    t.valid_from_utc,
    t.valid_to_utc,
    :agreed_price,
    t.currency
from products p
cross join tickets t
where p.id = :'product_id'::uuid
  and t.id = 'TICKET-1';