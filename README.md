# Snipe Capsule Car Rental

A Qbox-first FiveM vehicle rental resource with Snipe branding and a capsule-rental flow. It includes a staff station creator, a freestanding tablet with a world-space display, a vehicle platform with delivery/return effects, server-authoritative payments, and SQL persistence.

## Requirements

- `qbx_core` (QBCore and ESX bridges are also included)
- `ox_lib`
- `oxmysql`

The customer rental interface is an interactive DUI mapped directly onto the standing tablet's screen texture. Pressing `E` near the tablet smoothly moves a local scripted camera in front of the physical screen and projects cursor input into it. Rental returns use the same collision-independent `E` interaction near the platform. The F7 staff creator remains a fullscreen NUI for forms and world placement. There is no `ox_target`, `cr-3dnui`, generic texture renderer, or `[alphabets]` runtime dependency.

## Install

Ensure dependencies start before this resource:

```cfg
ensure ox_lib
ensure oxmysql
ensure qbx_core
ensure snipe-carrental
```

The resource creates its SQL tables idempotently on startup. For managed/manual migrations, import [`sql/snipe_carrental.sql`](sql/snipe_carrental.sql).

Grant creator access through Qbox/QBCore `god` or `admin`, or with ACE:

```cfg
add_ace group.admin carrental.admin allow
```

Use `/rentalcreator` or the default `F7` key mapping to open the station creator. Use `/rentalcreator <station-id>` to edit an existing nearby station.

The creator lists every saved rental location, and `F7` automatically selects the nearest location within 20 metres. Its three steps cover station details, placement, and vehicles. Each catalog vehicle has one flat price and can be typed by model or captured from the platform; station IDs do not need to be looked up in SQL.

World placement deliberately releases NUI focus. Press `E` to confirm a terminal or platform, inspect the persistent translucent draft in the world, then press `F7` to continue editing. Saving the complete station closes the creator and replaces the draft with the SQL-backed world props.

## Flow

1. Staff place the freestanding rental tablet.
2. Staff place the linked capsule platform and choose its light-strip color.
3. Staff add vehicles with a model, display name, and one flat price. A car parked on the platform can also be captured before the station's first save.
4. Customers approach the tablet, press `E`, and choose a vehicle, body color, and cash or bank payment on its world-space DUI.
5. The server validates and charges the catalog price. The car is created hidden and networked before a synchronized 14-second capsule cycle starts. The enclosure rises, opens to reveal the car, rolls it six metres clear of the deck, then closes and retracts underground.
6. For a return, the same anchored cycle encloses the parked rental and deletes it only after the side shell has completely covered it.

## Configuration

The fixed rental lifetime, flat catalog prices, rental limits, expiry behavior, permissions, animation clock, and optional seed station are in [`config.lua`](config.lua). The backend contract is documented in [`BACKEND_API.md`](BACKEND_API.md).

The resource streams its own collidable platform/canopy and portrait tablet models. Their accent materials support the same 16 texture variations used by `[alphabets]`, but all required YDR/YTD/YTYP files are bundled here. Asset dimensions, DUI texture names, palette indices, rebuild steps, and structural-validation evidence are documented in [`PROP_ASSETS.md`](PROP_ASSETS.md).

Stations and vehicle catalogs persist in SQL. Active rentals and their spawned cars are intentionally runtime-only; they are cleaned up instead of recovered or respawned across resource/server restarts.

Catalog vehicles are always available once added. Startup repairs legacy `enabled = 0` rows created by older boolean-loading behavior, so a populated station remains rentable after a resource or server restart.
