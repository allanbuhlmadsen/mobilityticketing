-- Verification gate. Every row returned by the second query is a reason not to
-- make product_id required yet. Expect zero rows before continuing.

-- Current state of the stored references.
select t.id, t.product_code, t.product_id, t.price, t.currency
from tickets t
order by t.id;

-- Three failure conditions in one query:
--   1. a ticket with no identity stored;
--   2. an identity that resolves to no product;
--   3. a code and an identity that name two different products.
select t.id, t.product_code, t.product_id, p.code as product_id_resolves_to
from tickets t
left join products p on p.id = t.product_id
where t.product_id is null
   or p.id is null
   or t.product_code is distinct from p.code
order by t.id;