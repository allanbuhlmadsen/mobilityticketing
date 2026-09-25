# Notes

## Assumption most likely to change

Query 3 counts only trips with `status = 'scheduled'`, excluding cancelled
ones. An operator asking how many departures run tomorrow probably does not
want cancelled departures in the total, but an operator planning capacity
might want the opposite. The filter sits in one place and can be moved.

Query 1 follows the supplied skeleton and does not filter on status, so the
two queries interpret the same word differently. A customer looking at
departures should still see that a trip is cancelled, while an operator
counting departures should not. Both readings are defensible for their
audiences, but the inconsistency is deliberate rather than accidental.

Further assumptions are recorded in `lab.md` under Modelling assumptions:
the free-text status column, the separation of `service_date` from the date
part of `scheduled_departure_utc`, the absence of `on delete` behaviour on
the foreign keys, and the lack of any rule requiring `stop_sequence` values
to be contiguous.