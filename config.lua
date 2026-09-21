Config = {}

-- TODO(observability): this FiveM project has no OpenTelemetry bootstrap; add one at the server host level before instrumenting rental flows.

-- qbx is preferred. "auto" also supports qb-core and es_extended when present.
Config.Framework = 'auto'
Config.Debug = false

Config.AdminAce = 'carrental.admin'
Config.AdminGroups = { 'god', 'admin' }

-- Rentals use one catalog price. The lifetime is fixed internally and is not
-- presented as a customer pricing choice.
Config.RentalDurationMinutes = 60
Config.PaymentAccounts = { cash = true, bank = true }
Config.DefaultRentalVehicleColor = { r = 235, g = 238, b = 240 }

Config.MaxActiveRentalsPerPlayer = 1
Config.MaxActiveRentalsPerStation = 1
Config.InteractionDistance = 6.0
Config.TabletInteractionDistance = 2.5
Config.AdminCaptureDistance = 12.0
Config.PlatformValidationDistance = 18.0
Config.ReturnDistance = 15.0
Config.SpawnConfirmationTimeoutSeconds = 60
Config.ExpirySweepSeconds = 10
Config.DeleteVehicleOnExpiry = true
Config.DeleteVehicleOnDisconnect = true

Config.CapsuleAnimation = {
    hiddenOffset = -3.5,
    duration = 14000,
    liftDuration = 3000,
    retractAt = 11000,
    doorOpenAt = 3200,
    doorDuration = 1200,
    doorCloseAt = 9600,
    vehicleVisibleAt = 3000,
    -- The car rolls forward while the capsule is fully open, then becomes
    -- driveable before the shell closes and the structure retracts.
    vehiclePushAt = 5000,
    vehiclePushDuration = 3200,
    vehiclePushDistance = 6.0,
    vehiclePushDrop = 0.15,
    releaseAt = 8200,
    -- Keep returned vehicles visible until the closing shell has completely
    -- covered them (doorCloseAt + doorDuration), then hide/delete them.
    returnHideAt = 10900,
    assemblyTimeout = 6000,
}

Config.PlatePrefix = 'RENT'
Config.RateLimits = {
    bootstrap = 750,
    rental = 1500,
    confirm = 500,
    returnVehicle = 1500,
    admin = 750,
}

-- Used only when the SQL stations table contains no stations.
Config.SeedDemoStation = true
Config.DemoStation = {
    id = 'legion-rental',
    label = 'Downtown Vehicle Rental',
    variant = 'tablet',
    coords = { x = 214.72, y = -808.42, z = 30.82, w = 339.0 },
    platform = { x = 229.39, y = -800.10, z = 30.57, w = 158.0 },
    color = '#00d7c8',
    vehicles = {
        {
            id = 'blista', model = 'blista', label = 'Blista', price = 250,
        },
        {
            id = 'sultan', model = 'sultan', label = 'Sultan', price = 425,
        },
        {
            id = 'baller', model = 'baller', label = 'Baller', price = 550,
        },
    },
}

-- Standalone is intended for UI development only; balances reset on restart.
Config.Standalone = {
    enabled = false,
    startingCash = 10000,
    startingBank = 50000,
}
