-- Rehearsal for removing the legacy reference. Dependencies were checked first:
-- no views and no functions use tickets.product_code. Two objects do, and both
-- disappear with the column: the NOT NULL requirement, and the foreign key
-- tickets_product_code_fk.
--
-- No CASCADE. If anything unexpected depended on the column, this statement
-- should fail rather than silently remove it.

begin;
set local lock_timeout = '3s';

alter table tickets drop column product_code;

-- The final writer, which supplies the identity only.
insert into tickets
    (id, user_id, trip_id, ticket_code, status, product_id,
     valid_from_utc, valid_to_utc, price, currency)
select 'LAB04-FINAL-1', t.user_id, t.trip_id, 'LAB04-CODE-FINAL-1', 'Active',
       '8f792c1a-8d8c-43a0-bbc7-b43721094296'::uuid,
       t.valid_from_utc, t.valid_to_utc, 36.00, t.currency
from tickets t
where t.id = 'TICKET-1';

-- The final reader, which joins the catalogue through the identity only.
select t.id, t.product_id, p.code as product_code, t.price, t.currency
from tickets t
join products p on p.id = t.product_id
order by t.id;

rollback;
-- Rolled back deliberately. In a real rollout this would be committed only
-- after the ID-only release is running everywhere and no query, report or
-- script still reads tickets.product_code.