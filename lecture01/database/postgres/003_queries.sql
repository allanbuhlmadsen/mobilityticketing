-- Query 1: upcoming trips
select
    t.id,
    t.scheduled_departure_utc,
    t.status
from trips t
where t.route_id = :route_id
  and t.scheduled_departure_utc >= :after_utc
order by t.scheduled_departure_utc
limit 20;

-- Query 2: ordered route stops
-- Joins route_stops to stops on the foreign key route_stops.stop_id -> stops.id
-- to resolve stop names. An inner join is correct here: every route_stops row
-- is guaranteed by that foreign key to have a matching stop.
-- Ordering by stop_sequence reproduces the route's travel order rather than
-- alphabetical or insertion order. A stop may appear more than once in the
-- result: on LINE-5C, STOP-NORREPORT is returned at both sequence 1 and 4.
select
    rs.stop_sequence,
    s.id as stop_id,
    s.name as stop_name
from route_stops rs
join stops s on s.id = rs.stop_id
where rs.route_id = :route_id
order by rs.stop_sequence;

-- Query 3: routes and trip count, including routes with zero trips
-- Both the service-date and status filters must sit in the ON clause, not in
-- WHERE: a WHERE condition on t.* would discard the NULL rows produced by the
-- LEFT JOIN and silently turn it back into an inner join.
-- count(t.id) counts non-null values only, so routes without trips report 0.
-- Assumption: "scheduled trips" means status = 'scheduled'; cancelled trips
-- are excluded from the count.
select
    r.id,
    r.short_name,
    count(t.id) as trip_count
from routes r
left join trips t
       on t.route_id = r.id
      and t.service_date = :service_date
      and t.status = 'scheduled'
group by r.id, r.short_name
order by r.id;