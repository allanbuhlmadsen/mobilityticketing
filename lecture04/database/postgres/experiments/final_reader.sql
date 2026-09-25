-- Final reader: resolves the product through the identity only. This query
-- must keep working after tickets.product_code is removed, so it does not
-- reference that column at all. The product code shown comes from the
-- catalogue row, where it remains a business-facing value.

select t.id,
       t.product_id,
       p.code as product_code,
       p.name as product_name,
       t.price,
       t.currency
from tickets t
join products p on p.id = t.product_id
order by t.id;