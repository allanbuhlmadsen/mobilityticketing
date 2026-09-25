-- Backfill: give existing tickets the product identity matching the code they
-- already carry. Written to be safe to run any number of times, because old
-- writers may keep producing rows without an identity until the last instance
-- of the previous release is stopped.

update tickets t
set product_id = p.id
from products p
where t.product_id is null
  and p.code = t.product_code;