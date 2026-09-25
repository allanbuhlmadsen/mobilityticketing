create table operators (
    id text primary key,
    name text not null
);

create table routes (
    id text primary key,
    operator_id text not null references operators(id),
    city_id text not null,
    mode text not null,
    short_name text not null
);

create table stops (
    id text primary key,
    city_id text not null,
    name text not null
);

create table route_stops (
    -- FK: the route this row belongs to; rejects rows for routes that do not exist
    route_id text not null references routes(id),
    -- FK: the physical stop; deliberately not unique per route
    stop_id text not null references stops(id),
    stop_sequence integer not null,
    -- Composite natural key: position on a route is unique, so a stop MAY occur
    -- more than once on the same route (ring lines, turnarounds).
    constraint route_stops_pkey primary key (route_id, stop_sequence),
    constraint route_stops_sequence_positive check (stop_sequence > 0)
);

create table trips (
    id text primary key,
    route_id text not null references routes(id),
    service_date date not null,
    scheduled_departure_utc timestamptz not null,
    status text not null
);
