-- New reader: resolves a ticket's product by identity where one is stored,
-- and falls back to the product code where it is not. This lets the upgraded
-- application read correctly both before and after the backfill.

select t.id,
       coalesce(p_new.id, p_old.id) as resolved_product_id,
       coalesce(p_new.code, p_old.code) as resolved_product_code,
       t.price,
       t.currency
from tickets t
left join products p_new
  on p_new.id = t.product_id
left join products p_old
  on t.product_id is null
 and p_old.code = t.product_code
order by t.id;