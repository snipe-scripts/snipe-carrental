# Snipe Car Rental backend API

The manifest must load `@ox_lib/init.lua`, `config.lua`, then `@oxmysql/lib/MySQL.lua` and server files in this order:

1. `server/storage.lua`
2. `server/framework.lua`
3. `server/main.lua`

Qbox is selected first when `Config.Framework = 'auto'`. QBCore and ESX bridges are also included. Add an ACE such as `add_ace group.admin carrental.admin allow`; Qbox/QBCore `god` and `admin` permissions are recognized as well.

All callbacks return `{ ok, code, message, ... }`. Never trust UI prices: the server resolves the station's single catalog price, payment, and ownership itself. The fixed lifetime comes from `Config.RentalDurationMinutes`. Rental plates are checked against live entities, current in-memory rentals, and the framework's `player_vehicles` (Qbox/QBCore) or `owned_vehicles` (ESX) table when available.

## Customer callbacks

- `snipe-carrental:server:getBootstrap()` returns `stations`, the caller's `rentals`, `isAdmin`, `rentalDurationMinutes`, `paymentAccounts`, and the current capsule snapshots.
- `snipe-carrental:server:createRental(payload)` accepts `{ stationId, vehicleId, payment }`. On success it returns `{ rental, token, platform }` after charging the server-owned catalog price and reserving the platform.
- `snipe-carrental:server:confirmSpawn(payload)` accepts `{ rentalId?, token, netId, plate? }`. For compatibility it also accepts positional `(token, netId, plate)`. The calling client must create the authorized model at `platform`, network it, set the supplied plate, and call this within the configured timeout. The server verifies entity owner, model, optional plate and location, reapplies the plate, and marks it active.
- `snipe-carrental:server:cancelSpawn(token)` immediately cancels an unconfirmed authorization and refunds the complete charge. Spawn timeout and disconnect before confirmation do the same automatically.
- `snipe-carrental:server:startCapsuleDelivery(token)` starts the single anchored animation only after the owner has created and networked the hidden vehicle.
- `snipe-carrental:server:beginReturn(payload)` validates the rental vehicle and return platform before the capsule encloses it. `cancelReturn(rentalId)` restores the open pose if the final return fails.
- `snipe-carrental:server:returnRental(payload)` accepts `{ rentalId, stationId, netId }`. The server verifies the caller, entity, model, plate and return position before deleting it and applying the configured refund.

## Admin callbacks

- `snipe-carrental:server:createStation(station)`
- `snipe-carrental:server:updateStation(stationId, station)`
- `snipe-carrental:server:deleteStation(stationId)`
- `snipe-carrental:server:captureVehicle(payload)` accepts `{ stationId, netId, model, id?, label, price }`. `model` must hash to the nearby world vehicle's actual model.
- `snipe-carrental:server:upsertCatalogVehicle(payload)` accepts `{ stationId, id?, model, label, price }` from the creator's catalog editor. It adds or updates the SQL-backed station vehicle without requiring a parked capture vehicle.
- `snipe-carrental:server:deleteCatalogVehicle(payload)` accepts `{ stationId, vehicleId }` and removes that entry from the station catalog.

Canonical station shape:

```lua
{
    id = 'legion-rental',
    label = 'Downtown Vehicle Rental',
    variant = 'booth', -- booth | tablet
    coords = { x = 0.0, y = 0.0, z = 0.0, w = 0.0 },
    platform = { x = 0.0, y = 0.0, z = 0.0, w = 0.0 },
    color = '#00d7c8',
    vehicles = {
        { id = 'sultan', model = 'sultan', label = 'Sultan', price = 425 }
    }
}
```

## Client events and exports

- `snipe-carrental:client:stationsChanged` broadcasts the complete station list after successful CRUD or capture.
- `snipe-carrental:client:rentalAuthorized` is also sent to the renter after payment authorization.
- `snipe-carrental:client:rentalEnded` sends `{ id, reason, refund, plate, stationId, returnStationId? }` for returns, expiry, timeouts and disconnect cleanup when the player is still connected.
- `snipe-carrental:client:capsuleCommand` carries the server-validated phase and elapsed time to spectator clients. Bootstrap also includes a `capsules` snapshot so late-streamed assemblies catch up to the current pose.
- Server exports: `GetStations()` and `GetRentalByPlate(plate)`.

`client/capsule.lua` derives every moving part from one 14-second clock: rise, open, release, close, retract. Delivery creates and networks the hidden car before the clock begins, reveals it inside the raised enclosure, and releases it at the configured timestamp. Return uses the same clock and removes the secured car only once the enclosure has hidden it. One active or pending rental is allowed per station so animation lifecycles cannot overlap.

Stations and per-station catalog vehicles are stored in the normalized `snipe_carrental_stations` and `snipe_carrental_vehicles` tables. Active rentals are deliberately memory-only: they are neither recovered nor respawned after a resource/server restart. Startup drops the obsolete `snipe_carrental_rentals` table from older builds so stale rows cannot be reused. Tables are created idempotently at resource startup; `sql/snipe_carrental.sql` is also provided for managed/manual migrations. A demo station is seeded only when the stations table contains no valid entries and `Config.SeedDemoStation` is enabled.
