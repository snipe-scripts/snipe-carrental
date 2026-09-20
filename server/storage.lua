RentalStorage = RentalStorage or {}

local STATIONS = 'snipe_carrental_stations'
local VEHICLES = 'snipe_carrental_vehicles'

local function decode(value, fallback)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return fallback end
    local ok, decoded = pcall(json.decode, value)
    return ok and type(decoded) == 'table' and decoded or fallback
end

local function encode(value)
    local ok, encoded = pcall(json.encode, value)
    if not ok then error(('Could not JSON encode SQL value: %s'):format(encoded)) end
    return encoded
end

function RentalStorage.init()
    -- Active rentals are intentionally runtime-only. Remove the legacy table so
    -- a previous version can never recover or respawn stale rental records.
    MySQL.query.await('DROP TABLE IF EXISTS `snipe_carrental_rentals`')
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `snipe_carrental_stations` (
            `id` VARCHAR(48) NOT NULL,
            `label` VARCHAR(80) NOT NULL,
            `variant` VARCHAR(16) NOT NULL DEFAULT 'tablet',
            `coords` JSON NOT NULL,
            `platform` JSON NOT NULL,
            `color` VARCHAR(9) NOT NULL DEFAULT '#00d7c8',
            `sort_order` INT UNSIGNED NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `snipe_carrental_vehicles` (
            `station_id` VARCHAR(48) NOT NULL,
            `id` VARCHAR(48) NOT NULL,
            `model` VARCHAR(64) NOT NULL,
            `label` VARCHAR(64) NOT NULL,
            `base_price` INT UNSIGNED NOT NULL DEFAULT 0,
            `enabled` TINYINT(1) NOT NULL DEFAULT 1,
            `sort_order` INT UNSIGNED NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`station_id`, `id`),
            KEY `idx_snipe_carrental_vehicle_model` (`model`),
            CONSTRAINT `fk_snipe_carrental_vehicle_station`
                FOREIGN KEY (`station_id`) REFERENCES `snipe_carrental_stations` (`id`)
                ON DELETE CASCADE ON UPDATE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    -- The freestanding tablet is now the only supported terminal. Preserve the
    -- column for schema compatibility while migrating every existing station.
    MySQL.query.await(('ALTER TABLE `%s` MODIFY `variant` VARCHAR(16) NOT NULL DEFAULT \'tablet\''):format(STATIONS))
    MySQL.update.await(('UPDATE `%s` SET `variant` = \'tablet\' WHERE `variant` <> \'tablet\''):format(STATIONS))

    -- The current catalog has no disabled-state control. Older builds parsed
    -- MySQL TINYINT booleans inconsistently and could write valid rows back as
    -- enabled=0, leaving a populated station with no rentable vehicles.
    MySQL.update.await(('UPDATE `%s` SET `enabled` = 1 WHERE `enabled` <> 1'):format(VEHICLES))
end

function RentalStorage.loadStations()
    local stationRows = MySQL.query.await(([[
        SELECT `id`, `label`, `variant`, `coords`, `platform`, `color`
        FROM `%s` ORDER BY `sort_order`, `id`
    ]]):format(STATIONS)) or {}
    local vehicleRows = MySQL.query.await(([[
        SELECT `station_id`, `id`, `model`, `label`, `base_price`
        FROM `%s` ORDER BY `station_id`, `sort_order`, `id`
    ]]):format(VEHICLES)) or {}

    local output, byId = {}, {}
    for i = 1, #stationRows do
        local row = stationRows[i]
        local station = {
            id = row.id,
            label = row.label,
            variant = row.variant,
            coords = decode(row.coords, {}),
            platform = decode(row.platform, {}),
            color = row.color,
            vehicles = {},
        }
        output[#output + 1] = station
        byId[station.id] = station
    end
    for i = 1, #vehicleRows do
        local row = vehicleRows[i]
        local station = byId[row.station_id]
        if station then
            station.vehicles[#station.vehicles + 1] = {
                id = row.id,
                model = row.model,
                label = row.label,
                price = tonumber(row.base_price) or 0,
            }
        end
    end
    return output
end

function RentalStorage.saveStations(stations)
    local queries = {}
    local stationIds = {}
    for stationIndex = 1, #stations do
        local station = stations[stationIndex]
        stationIds[#stationIds + 1] = station.id
        queries[#queries + 1] = {
            query = ([=[
                INSERT INTO `%s` (`id`, `label`, `variant`, `coords`, `platform`, `color`, `sort_order`)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `variant` = VALUES(`variant`),
                    `coords` = VALUES(`coords`), `platform` = VALUES(`platform`),
                    `color` = VALUES(`color`), `sort_order` = VALUES(`sort_order`)
            ]=]):format(STATIONS),
            values = { station.id, station.label, station.variant, encode(station.coords), encode(station.platform), station.color, stationIndex },
        }
        queries[#queries + 1] = {
            query = ('DELETE FROM `%s` WHERE `station_id` = ?'):format(VEHICLES),
            values = { station.id },
        }
        for vehicleIndex = 1, #station.vehicles do
            local vehicle = station.vehicles[vehicleIndex]
            queries[#queries + 1] = {
                query = ([=[
                    INSERT INTO `%s` (`station_id`, `id`, `model`, `label`, `base_price`, `enabled`, `sort_order`)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                ]=]):format(VEHICLES),
                values = {
                    station.id, vehicle.id, vehicle.model, vehicle.label, vehicle.price or 0,
                    1, vehicleIndex,
                },
            }
        end
    end
    if #stationIds == 0 then
        queries[#queries + 1] = { query = ('DELETE FROM `%s`'):format(STATIONS), values = {} }
    else
        local placeholders = {}
        for i = 1, #stationIds do placeholders[i] = '?' end
        queries[#queries + 1] = {
            query = ('DELETE FROM `%s` WHERE `id` NOT IN (%s)'):format(STATIONS, table.concat(placeholders, ',')),
            values = stationIds,
        }
    end
    return MySQL.transaction.await(queries) == true
end

function RentalStorage.isPlateReserved(plate, framework)
    local query
    if framework == 'qbx' or framework == 'qb' then
        query = 'SELECT 1 FROM `player_vehicles` WHERE TRIM(`plate`) = ? LIMIT 1'
    elseif framework == 'esx' then
        query = 'SELECT 1 FROM `owned_vehicles` WHERE TRIM(`plate`) = ? LIMIT 1'
    end
    if not query then return false end

    local ok, owned = pcall(function()
        return MySQL.scalar.await(query, { plate })
    end)
    return ok and owned ~= nil and owned ~= false
end
