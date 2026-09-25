insert into operators (id, name) values
    ('OP-METRO', 'City Metro'),
    ('OP-BUS', 'City Bus')
on conflict do nothing;

insert into routes (id, operator_id, city_id, mode, short_name) values
    ('LINE-M2', 'OP-METRO', 'CPH', 'metro', 'M2'),
    ('LINE-5C', 'OP-BUS', 'CPH', 'bus', '5C')
on conflict do nothing;

insert into stops (id, city_id, name) values
    ('STOP-NORREPORT', 'CPH', 'Nørreport'),
    ('STOP-KONGENS-NYTORV', 'CPH', 'Kongens Nytorv'),
    ('STOP-AIRPORT', 'CPH', 'Copenhagen Airport'),
    ('STOP-CENTRAL', 'CPH', 'Copenhagen Central Station')
on conflict do nothing;

-- Route stops define the ordered stop pattern of each route.
-- The primary key (route_id, stop_sequence) allows a stop to appear more than
-- once on the same route. LINE-5C demonstrates this: STOP-NORREPORT is both
-- the first and the last stop, which a (route_id, stop_id) key would reject.
insert into route_stops (route_id, stop_id, stop_sequence) values
    ('LINE-M2', 'STOP-AIRPORT', 1),
    ('LINE-M2', 'STOP-KONGENS-NYTORV', 2),
    ('LINE-M2', 'STOP-CENTRAL', 3),
    ('LINE-5C', 'STOP-NORREPORT', 1),
    ('LINE-5C', 'STOP-AIRPORT', 2),
    ('LINE-5C', 'STOP-KONGENS-NYTORV', 3),
    ('LINE-5C', 'STOP-NORREPORT', 4)
on conflict do nothing;

-- Trips are concrete departures on a route for a given service date.
-- Trip ids use local time for readability (TRIP-M2-0800 departs 08:00 local),
-- while scheduled_departure_utc stores the instant in UTC. Copenhagen is
-- UTC+2 in September, hence 08:00 local = 06:00Z.
-- One cancelled trip is included so query results can distinguish statuses.
insert into trips (id, route_id, service_date, scheduled_departure_utc, status) values
    ('TRIP-M2-0800', 'LINE-M2', date '2026-09-01', timestamptz '2026-09-01 06:00:00+00', 'scheduled'),
    ('TRIP-M2-0820', 'LINE-M2', date '2026-09-01', timestamptz '2026-09-01 06:20:00+00', 'scheduled'),
    ('TRIP-M2-0840', 'LINE-M2', date '2026-09-01', timestamptz '2026-09-01 06:40:00+00', 'cancelled'),
    ('TRIP-5C-0810', 'LINE-5C', date '2026-09-01', timestamptz '2026-09-01 06:10:00+00', 'scheduled'),
    ('TRIP-5C-0850', 'LINE-5C', date '2026-09-01', timestamptz '2026-09-01 06:50:00+00', 'scheduled')
on conflict do nothing;