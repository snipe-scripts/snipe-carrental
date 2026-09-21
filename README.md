# Snipe Car Rental

[▶ Watch the showcase](https://youtu.be/qe6XEv45w4o)

FiveM vehicle rentals with an in-world DUI tablet, animated delivery platform, SQL-backed stations, flat pricing, vehicle color selection, and cash/bank payments.

## Requirements

- One framework: `qbx_core`, `qb-core`, or `es_extended`
- `ox_lib`
- `oxmysql`

## Install

Start the dependencies before the resource:

```cfg
ensure ox_lib
ensure oxmysql
ensure qbx_core # or qb-core / es_extended
ensure snipe-carrental
```

Tables are created automatically. A manual schema is available at [`sql/snipe_carrental.sql`](sql/snipe_carrental.sql).

Optional ACE permission:

```cfg
add_ace group.admin carrental.admin allow
```

## Usage

- `F7` or `/rentalcreator` — create or edit a station.
- `E` — confirm prop placement, use the rental tablet, or return a vehicle.
- Add each vehicle model, display name, and one flat rental price in the creator.

Stations and catalogs persist in SQL. Active rentals and spawned vehicles intentionally do not survive restarts. Configuration is in [`config.lua`](config.lua).
