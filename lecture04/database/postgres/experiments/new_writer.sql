-- New writer: the application version that knows product identities.
-- It receives a product ID and an agreed price, and derives the product code
-- from the product row rather than accepting one from the caller.

-- Read the current identities first. These values differ per database, so they
-- are looked up rather than assumed.
select id, code, price, currency from products order by code;

\set product_id '8f792c1a-8d8c-43a0-bbc7-b43721094296'
\set ticket_id 'LAB04-NEW-2'
\set ticket_code 'LAB04-CODE-NEW-2'
\set agreed_price 36.00

insert into tickets
    (id, user_id, trip_id, ticket_code, status,
     product_code, product_id,
     valid_from_utc, valid_to_utc, price, currency)
select
    :'ticket_id',
    t.user_id,
    t.trip_id,
    :'ticket_code',
    'Active',
    p.code,                 -- derived from the product row, never supplied
    p.id,
    t.valid_from_utc,
    t.valid_to_utc,
    :agreed_price,          -- the price agreed at purchase, not p.price
    t.currency
from products p
cross join tickets t
where p.id = :'product_id'::uuid
  and t.id = 'TICKET-1';