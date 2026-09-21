local RESOURCE = GetCurrentResourceName()
local stations = {}
local rentals = {}
local rateLimit = {}
local capsuleStates = {}

local function debugLog(message, ...)
    if not Config.Debug then return end
    print(('[%s] %s'):format(RESOURCE, message:format(...)))
end

local function result(ok, code, message, data)
    local response = { ok = ok, code = code, message = message }
    if data then
        for key, value in pairs(data) do response[key] = value end
    end
    return response
end

local function publishCapsuleState(stationId, phase, operationId, excludedSource)
    if not stationId then return end
    stationId = tostring(stationId)
    local state = { phase = phase, operationId = operationId }
    if phase == 'delivery' or phase == 'return' then state.startedAt = GetGameTimer() end
    capsuleStates[stationId] = state
    for _, player in ipairs(GetPlayers()) do
        local target = tonumber(player)
        if not excludedSource or target ~= excludedSource then
            TriggerClientEvent('snipe-carrental:client:capsuleCommand', target, {
                stationId = stationId, phase = phase, operationId = operationId, elapsed = 0,
            })
        end
    end
end

local function capsuleSnapshot()
    local output = {}
    for stationId, state in pairs(capsuleStates) do
        output[stationId] = {
            phase = state.phase,
            operationId = state.operationId,
            elapsed = state.startedAt and math.max(0, GetGameTimer() - state.startedAt) or 0,
        }
    end
    return output
end

local function beginCapsuleCycle(stationId, phase, operationId, excludedSource)
    publishCapsuleState(stationId, phase, operationId, excludedSource)
    local expected = capsuleStates[tostring(stationId)]
    SetTimeout(tonumber(Config.CapsuleAnimation.duration) or 14000, function()
        if capsuleStates[tostring(stationId)] == expected then
            publishCapsuleState(stationId, 'idle', nil)
        end
    end)
end

local function cleanString(value, maxLength)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' or #value > maxLength then return nil end
    return value
end

local function slug(value, maxLength)
    value = cleanString(value, maxLength or 48)
    if not value then return nil end
    value = value:lower():gsub('[^%w%-_]', '-')
    value = value:gsub('%-+', '-'):gsub('^%-', ''):gsub('%-$', '')
    if value == '' then return nil end
    return value:sub(1, maxLength or 48)
end

local function finiteNumber(value, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    if minimum and value < minimum then return nil end
    if maximum and value > maximum then return nil end
    return value + 0.0
end

local function normalizeCoords(value)
    if type(value) ~= 'table' then return nil end
    local x = finiteNumber(value.x or value[1], -10000, 10000)
    local y = finiteNumber(value.y or value[2], -10000, 10000)
    local z = finiteNumber(value.z or value[3], -1000, 3000)
    local w = finiteNumber(value.w or value[4] or 0, -360, 360)
    if not x or not y or not z or not w then return nil end
    return { x = x, y = y, z = z, w = w }
end

local function normalizeVehicleColor(value)
    if type(value) ~= 'table' then return nil end
    local r = finiteNumber(value.r, 0, 255)
    local g = finiteNumber(value.g, 0, 255)
    local b = finiteNumber(value.b, 0, 255)
    if not r or not g or not b then return nil end
    return { r = math.floor(r), g = math.floor(g), b = math.floor(b) }
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function playerCoords(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local coords = GetEntityCoords(ped)
    return { x = coords.x, y = coords.y, z = coords.z }
end

local function sourceNear(source, coords, maximum)
    local current = playerCoords(source)
    return current and distance(current, coords) <= maximum or false
end

local function normalizeVehicle(value)
    if type(value) ~= 'table' then return nil end
    local model = cleanString(value.model, 64)
    if not model or not model:match('^[%w_%-]+$') then return nil end
    local vehicle = {
        id = slug(value.id or model, 48),
        model = model:lower(),
        label = cleanString(value.label or model, 64),
    }
    if not vehicle.id or not vehicle.label then return nil end

    vehicle.price = math.floor(finiteNumber(value.price or value.rate, 1, 10000000) or 0)
    if vehicle.price == 0 then return nil end
    return vehicle
end

local function normalizeStation(value, forcedId)
    if type(value) ~= 'table' then return nil, 'invalid_station' end
    local station = {
        id = slug(forcedId or value.id, 48),
        label = cleanString(value.label, 80),
        variant = 'tablet',
        coords = normalizeCoords(value.coords),
        platform = normalizeCoords(value.platform or value.spawn),
        color = cleanString(value.color or '#00d7c8', 9),
        vehicles = {},
    }
    if not station.id or not station.label or not station.coords or not station.platform then
        return nil, 'invalid_station'
    end
    if not station.color:match('^#%x%x%x%x%x%x$') then station.color = '#00d7c8' end

    local inputVehicles = value.vehicles or {}
    if type(inputVehicles) ~= 'table' or #inputVehicles > 100 then return nil, 'invalid_vehicles' end
    local seen = {}
    for i = 1, #inputVehicles do
        local vehicle = normalizeVehicle(inputVehicles[i])
        if not vehicle or seen[vehicle.id] then return nil, 'invalid_vehicle' end
        seen[vehicle.id] = true
        station.vehicles[#station.vehicles + 1] = vehicle
    end
    return station
end

local function findStation(id)
    if type(id) ~= 'string' then return nil end
    for i = 1, #stations do
        if stations[i].id == id then return stations[i], i end
    end
end

local function findVehicle(station, idOrModel)
    if not station or type(idOrModel) ~= 'string' then return nil end
    local wanted = idOrModel:lower()
    for i = 1, #station.vehicles do
        local vehicle = station.vehicles[i]
        if vehicle.id == wanted or vehicle.model == wanted then return vehicle, i end
    end
end

local function saveStations()
    return RentalStorage.saveStations(stations)
end

local function throttle(source, action, delay)
    local now = GetGameTimer()
    local key = ('%s:%s'):format(source, action)
    local allowedAt = rateLimit[key] or 0
    if now < allowedAt and allowedAt - now < delay * 2 then return false end
    rateLimit[key] = now + delay
    return true
end

local function isPlateInUse(plate)
    for _, rental in pairs(rentals) do
        if rental.plate == plate and rental.status ~= 'ended' then return true end
    end
    local ok, vehicles = pcall(GetAllVehicles)
    if ok and vehicles then
        for i = 1, #vehicles do
            if GetVehicleNumberPlateText(vehicles[i]):gsub('%s+', '') == plate:gsub('%s+', '') then return true end
        end
    end
    if RentalStorage.isPlateReserved(plate, RentalBridge.name()) then return true end
    return false
end

local alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789'
local function randomCharacters(length)
    local output = {}
    for i = 1, length do
        local index = math.random(1, #alphabet)
        output[i] = alphabet:sub(index, index)
    end
    return table.concat(output)
end

local function uniquePlate()
    local prefix = (Config.PlatePrefix or 'RENT'):upper():gsub('[^A-Z0-9]', ''):sub(1, 4)
    for _ = 1, 50 do
        local plate = (prefix .. randomCharacters(8 - #prefix)):sub(1, 8)
        if not isPlateInUse(plate) then return plate end
    end
end

local function rentalId()
    return ('rental_%s_%s'):format(os.time(), randomCharacters(10):lower())
end

local function publicRental(rental)
    if not rental then return nil end
    return {
        id = rental.id,
        stationId = rental.stationId,
        vehicleId = rental.vehicleId,
        model = rental.model,
        label = rental.label,
        plate = rental.plate,
        duration = rental.duration,
        startedAt = rental.startedAt,
        expiresAt = rental.expiresAt,
        status = rental.status,
        netId = rental.netId,
        payment = rental.payment,
        pricing = rental.pricing,
        color = rental.color,
    }
end

local function activeRentalsFor(identifier)
    local output = {}
    for _, rental in pairs(rentals) do
        if rental.owner == identifier and (rental.status == 'awaiting_spawn' or rental.status == 'active') then
            output[#output + 1] = rental
        end
    end
    return output
end

local function stationHasRentals(stationId)
    for _, rental in pairs(rentals) do
        if rental.stationId == stationId and (rental.status == 'awaiting_spawn' or rental.status == 'active') then
            return true
        end
    end
    return false
end

local function capsuleIsBusy(stationId)
    local state = capsuleStates[tostring(stationId)]
    return state and state.phase ~= 'idle' or false
end

local function calculatePrice(vehicle)
    local price = math.floor(tonumber(vehicle.price) or 0)
    if price < 1 then return nil end
    return { subtotal = price, total = price }
end

local function deleteRentalEntity(rental)
    if not rental.netId then return end
    local entity = NetworkGetEntityFromNetworkId(rental.netId)
    if entity and entity ~= 0 and DoesEntityExist(entity) then DeleteEntity(entity) end
end

local function finishRental(rental, reason, explicitRefund)
    if not rental or rental.status == 'ended' then return 0 end
    local refund = math.floor(tonumber(explicitRefund) or 0)

    rental.status = 'ended'
    rental.endedAt = os.time()
    rental.endReason = reason
    if refund > 0 and rental.source and GetPlayerName(rental.source) then
        RentalBridge.addMoney(rental.source, rental.payment, refund, 'vehicle-rental-refund')
    end
    deleteRentalEntity(rental)
    rentals[rental.id] = nil
    local returnState = rental.capsuleStationId and capsuleStates[tostring(rental.capsuleStationId)] or nil
    local returnCycleActive = reason == 'returned' and returnState
        and returnState.phase == 'return' and returnState.operationId == rental.id
    if not returnCycleActive then
        publishCapsuleState(rental.stationId, 'idle', nil, rental.source)
        if rental.capsuleStationId and rental.capsuleStationId ~= rental.stationId then
            publishCapsuleState(rental.capsuleStationId, 'idle', nil, rental.source)
        end
    end

    if rental.source and GetPlayerName(rental.source) then
        TriggerClientEvent('snipe-carrental:client:rentalEnded', rental.source, {
            id = rental.id, reason = reason, refund = refund, plate = rental.plate,
            stationId = rental.stationId, returnStationId = rental.capsuleStationId,
        })
    end
    return refund
end

local function requireAdmin(source, action)
    if not throttle(source, action, Config.RateLimits.admin) then
        return nil, result(false, 'rate_limited', 'Please wait before trying again.')
    end
    if not RentalBridge.isAdmin(source) then
        return nil, result(false, 'forbidden', 'You do not have permission to manage rental stations.')
    end
    return true
end

local function broadcastStations()
    TriggerClientEvent('snipe-carrental:client:stationsChanged', -1, stations)
end

local function bootstrap(source)
    if not throttle(source, 'bootstrap', Config.RateLimits.bootstrap) then
        return result(false, 'rate_limited', 'Please wait before trying again.')
    end
    local identifier = RentalBridge.getIdentifier(source)
    local ownRentals = {}
    if identifier then
        local matches = activeRentalsFor(identifier)
        for i = 1, #matches do
            matches[i].source = source
            ownRentals[#ownRentals + 1] = publicRental(matches[i])
        end
    end
    return result(true, 'ok', nil, {
        stations = stations,
        rentals = ownRentals,
        isAdmin = RentalBridge.isAdmin(source),
        rentalDurationMinutes = Config.RentalDurationMinutes,
        paymentAccounts = Config.PaymentAccounts,
        capsules = capsuleSnapshot(),
    })
end

local function createRental(source, payload)
    if not throttle(source, 'rental', Config.RateLimits.rental) then
        return result(false, 'rate_limited', 'Please wait before trying again.')
    end
    if type(payload) ~= 'table' then return result(false, 'invalid_request', 'Invalid rental request.') end

    local identifier = RentalBridge.getIdentifier(source)
    if not identifier then return result(false, 'player_unavailable', 'Player data is not ready.') end
    if #activeRentalsFor(identifier) >= Config.MaxActiveRentalsPerPlayer then
        return result(false, 'rental_limit', 'You already have an active rental.')
    end

    local station = findStation(payload.stationId)
    if not station then return result(false, 'station_not_found', 'Rental station not found.') end
    if Config.MaxActiveRentalsPerStation > 0 and (stationHasRentals(station.id) or capsuleIsBusy(station.id)) then
        return result(false, 'station_busy', 'This delivery capsule is currently in use.')
    end
    if not sourceNear(source, station.coords, Config.InteractionDistance) then
        return result(false, 'too_far', 'Move closer to the rental station.')
    end
    local vehicle = findVehicle(station, payload.vehicleId or payload.model)
    if not vehicle then return result(false, 'vehicle_unavailable', 'That vehicle is unavailable.') end
    local vehicleColor = normalizeVehicleColor(payload.color)
        or normalizeVehicleColor(Config.DefaultRentalVehicleColor)
        or { r = 235, g = 238, b = 240 }
    local duration = math.max(1, math.floor(tonumber(Config.RentalDurationMinutes) or 60))
    local payment = cleanString(payload.payment, 8)
    if not payment or not Config.PaymentAccounts[payment] then
        return result(false, 'invalid_payment', 'Choose cash or bank payment.')
    end
    local pricing = calculatePrice(vehicle)
    if not pricing or pricing.total < 1 or pricing.total > 20000000 then
        return result(false, 'invalid_price', 'This rental has invalid pricing.')
    end
    local plate = uniquePlate()
    if not plate then return result(false, 'plate_unavailable', 'Could not allocate a rental plate.') end

    if not RentalBridge.removeMoney(source, payment, pricing.total, 'vehicle-rental') then
        return result(false, 'insufficient_funds', ('You need $%s in %s.'):format(pricing.total, payment))
    end

    local now = os.time()
    local id = rentalId()
    local rental = {
        id = id,
        token = randomCharacters(32),
        owner = identifier,
        source = source,
        stationId = station.id,
        vehicleId = vehicle.id,
        model = vehicle.model,
        label = vehicle.label,
        plate = plate,
        duration = duration,
        payment = payment,
        pricing = pricing,
        color = vehicleColor,
        status = 'awaiting_spawn',
        createdAt = now,
        startedAt = now,
        expiresAt = now + duration * 60,
        confirmBy = now + Config.SpawnConfirmationTimeoutSeconds,
    }
    rentals[id] = rental
    -- Reserve the platform while the owner loads and creates the network car.
    -- Visible motion starts only after the client reports that the car exists.
    publishCapsuleState(station.id, 'reserved', rental.id, source)

    local response = result(true, 'authorized', 'Rental payment approved.', {
        rental = publicRental(rental),
        token = rental.token,
        platform = station.platform,
    })
    TriggerClientEvent('snipe-carrental:client:rentalAuthorized', source, response)
    return response
end

local function rentalByToken(source, token)
    if type(token) ~= 'string' then return nil end
    for _, rental in pairs(rentals) do
        if rental.source == source and rental.token == token then return rental end
    end
end

local function startCapsuleDelivery(source, token)
    if not throttle(source, 'capsule_stage', 250) then
        return result(false, 'rate_limited', 'Please wait before starting the delivery capsule.')
    end
    local rental = rentalByToken(source, token)
    if not rental or rental.status ~= 'awaiting_spawn' then
        return result(false, 'invalid_authorization', 'Rental authorization is invalid or expired.')
    end
    local current = capsuleStates[tostring(rental.stationId)]
    if not current or current.operationId ~= rental.id or current.phase ~= 'reserved' then
        return result(false, 'invalid_stage_order', 'Delivery capsule is not reserved for this rental.')
    end
    beginCapsuleCycle(rental.stationId, 'delivery', rental.id, source)
    return result(true, 'delivery_started', nil, { elapsed = 0 })
end

local function confirmSpawn(source, payload, positionalNetId, positionalPlate)
    if not throttle(source, 'confirm', Config.RateLimits.confirm) then
        return result(false, 'rate_limited', 'Please wait before trying again.')
    end
    if type(payload) == 'string' then
        payload = { token = payload, netId = positionalNetId, plate = positionalPlate }
    end
    if type(payload) ~= 'table' then return result(false, 'invalid_request', 'Invalid spawn confirmation.') end
    local rental = payload.rentalId and rentals[payload.rentalId] or rentalByToken(source, payload.token)
    if not rental or rental.status ~= 'awaiting_spawn' or rental.source ~= source or rental.token ~= payload.token then
        return result(false, 'invalid_authorization', 'Rental authorization is invalid or expired.')
    end
    if os.time() > rental.confirmBy then
        local refund = finishRental(rental, 'spawn_timeout', rental.pricing.total)
        return result(false, 'authorization_expired', 'Vehicle delivery timed out.', { refund = refund })
    end

    local netId = tonumber(payload.netId)
    if not netId or netId < 1 then return result(false, 'invalid_vehicle', 'Invalid network vehicle.') end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then
        return result(false, 'vehicle_not_ready', 'Vehicle is not networked yet; try again.')
    end
    if GetEntityModel(entity) ~= GetHashKey(rental.model) then
        return result(false, 'model_mismatch', 'Delivered vehicle model does not match the rental.')
    end
    if payload.plate and type(payload.plate) ~= 'string' then
        return result(false, 'plate_mismatch', 'Delivered vehicle plate is invalid.')
    end
    if payload.plate and payload.plate:gsub('%s+', '') ~= rental.plate:gsub('%s+', '') then
        return result(false, 'plate_mismatch', 'Delivered vehicle plate does not match the authorization.')
    end
    local owner = NetworkGetEntityOwner(entity)
    if owner ~= source then return result(false, 'owner_mismatch', 'You must own the delivered network entity.') end
    local station = findStation(rental.stationId)
    local coords = GetEntityCoords(entity)
    if not station or distance({ x = coords.x, y = coords.y, z = coords.z }, station.platform) > Config.PlatformValidationDistance then
        return result(false, 'invalid_spawn_location', 'Vehicle must be delivered on the rental platform.')
    end

    SetVehicleNumberPlateText(entity, rental.plate)
    rental.netId = netId
    rental.status = 'active'
    rental.startedAt = os.time()
    rental.expiresAt = rental.startedAt + rental.duration * 60
    rental.confirmBy = nil
    local ok = pcall(function()
        local state = Entity(entity).state
        state:set('snipeRentalId', rental.id, true)
        state:set('snipeRentalOwner', rental.owner, true)
        state:set('snipeRentalExpiresAt', rental.expiresAt, true)
    end)
    if not ok then debugLog('Could not assign rental state bag for %s', rental.id) end
    if GetResourceState('qbx_vehiclekeys') == 'started' then
        local keysOk, keysError = pcall(function()
            exports.qbx_vehiclekeys:GiveKeys(source, entity)
        end)
        if not keysOk then debugLog('Could not grant qbx vehicle keys for %s: %s', rental.id, keysError) end
    end
    return result(true, 'active', 'Rental vehicle delivered.', { rental = publicRental(rental) })
end

local function cancelSpawn(source, payload)
    if not throttle(source, 'cancel', Config.RateLimits.confirm) then
        return result(false, 'rate_limited', 'Please wait before trying again.')
    end
    local token = type(payload) == 'table' and payload.token or payload
    local rental = rentalByToken(source, token)
    if not rental or rental.status ~= 'awaiting_spawn' then
        return result(false, 'invalid_authorization', 'Rental authorization is invalid or already active.')
    end
    local refund = finishRental(rental, 'spawn_cancelled', rental.pricing.total)
    return result(true, 'cancelled', 'Vehicle delivery cancelled and payment refunded.', { refund = refund })
end

local function beginReturn(source, payload)
    if not throttle(source, 'return_prepare', Config.RateLimits.returnVehicle) then
        return result(false, 'rate_limited', 'Please wait before trying again.')
    end
    if type(payload) ~= 'table' then return result(false, 'invalid_request', 'Invalid return request.') end
    local rental = rentals[payload.rentalId]
    local identifier = RentalBridge.getIdentifier(source)
    if not rental or rental.status ~= 'active' or rental.owner ~= identifier then
        return result(false, 'rental_not_found', 'Active rental not found.')
    end
    local station = findStation(payload.stationId or rental.stationId)
    if not station then return result(false, 'station_not_found', 'Return station not found.') end
    if capsuleIsBusy(station.id)
        or (station.id ~= rental.stationId and stationHasRentals(station.id)) then
        return result(false, 'station_busy', 'That return capsule is currently in use.')
    end
    if not sourceNear(source, station.coords, Config.ReturnDistance) and not sourceNear(source, station.platform, Config.ReturnDistance) then
        return result(false, 'too_far', 'Bring the rental back to a rental station.')
    end
    local netId = tonumber(payload.netId or rental.netId)
    if not netId or netId < 1 or netId ~= rental.netId then
        return result(false, 'vehicle_mismatch', 'That is not your rental vehicle.')
    end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityModel(entity) ~= GetHashKey(rental.model) then
        return result(false, 'vehicle_missing', 'The rented vehicle must be present for return.')
    end
    local plate = GetVehicleNumberPlateText(entity):gsub('^%s+', ''):gsub('%s+$', '')
    if plate ~= rental.plate then return result(false, 'plate_mismatch', 'Rental plate validation failed.') end
    local coords = GetEntityCoords(entity)
    if distance({ x = coords.x, y = coords.y, z = coords.z }, station.platform) > Config.ReturnDistance then
        return result(false, 'vehicle_too_far', 'Park the vehicle on the return platform.')
    end
    rental.capsuleStationId = station.id
    beginCapsuleCycle(station.id, 'return', rental.id, source)
    return result(true, 'return_prepared', nil)
end

local function cancelReturn(source, rentalId)
    local rental = rentals[rentalId]
    if not rental or rental.status ~= 'active' or rental.owner ~= RentalBridge.getIdentifier(source) then
        return result(false, 'rental_not_found', 'Active rental not found.')
    end
    if not rental.capsuleStationId then
        return result(false, 'return_not_prepared', 'The return capsule is not active.')
    end
    local stationId = rental.capsuleStationId
    rental.capsuleStationId = nil
    publishCapsuleState(stationId, 'idle', nil, source)
    return result(true, 'return_cancelled', nil)
end

local function returnRental(source, payload)
    if not throttle(source, 'return', Config.RateLimits.returnVehicle) then
        return result(false, 'rate_limited', 'Please wait before trying again.')
    end
    if type(payload) ~= 'table' then return result(false, 'invalid_request', 'Invalid return request.') end
    local rental = rentals[payload.rentalId]
    local identifier = RentalBridge.getIdentifier(source)
    if not rental or rental.status ~= 'active' or rental.owner ~= identifier then
        return result(false, 'rental_not_found', 'Active rental not found.')
    end
    local station = findStation(payload.stationId or rental.stationId)
    if not station then return result(false, 'station_not_found', 'Return station not found.') end
    if rental.capsuleStationId ~= station.id then
        return result(false, 'return_not_prepared', 'The return capsule has not finished preparing.')
    end
    if not sourceNear(source, station.coords, Config.ReturnDistance) and not sourceNear(source, station.platform, Config.ReturnDistance) then
        return result(false, 'too_far', 'Bring the rental back to a rental station.')
    end
    local netId = tonumber(payload.netId or rental.netId)
    if not netId or netId < 1 then return result(false, 'vehicle_missing', 'The rented vehicle is not networked.') end
    if netId ~= rental.netId then return result(false, 'vehicle_mismatch', 'That is not your rental vehicle.') end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityModel(entity) ~= GetHashKey(rental.model) then
        return result(false, 'vehicle_missing', 'The rented vehicle must be present to receive a return refund.')
    end
    local plate = GetVehicleNumberPlateText(entity):gsub('^%s+', ''):gsub('%s+$', '')
    if plate ~= rental.plate then return result(false, 'plate_mismatch', 'Rental plate validation failed.') end
    local coords = GetEntityCoords(entity)
    if distance({ x = coords.x, y = coords.y, z = coords.z }, station.platform) > Config.ReturnDistance then
        return result(false, 'vehicle_too_far', 'Park the vehicle on the return platform.')
    end

    rental.source = source
    local refund = finishRental(rental, 'returned')
    return result(true, 'returned', 'Rental returned successfully.', { refund = refund })
end

local function createStation(source, payload)
    local allowed, failure = requireAdmin(source, 'admin_create')
    if not allowed then return failure end
    if type(payload) ~= 'table' then return result(false, 'invalid_station', 'Station data is invalid.') end
    if not payload.id then
        local generated = slug(payload.label or 'rental', 36)
        if not generated then return result(false, 'invalid_station', 'Station data is invalid.') end
        payload.id = generated .. '-' .. randomCharacters(6):lower()
    end
    local station, errorCode = normalizeStation(payload)
    if not station then return result(false, errorCode, 'Station data is invalid.') end
    if findStation(station.id) then return result(false, 'duplicate_id', 'A station with that id already exists.') end
    if not sourceNear(source, station.coords, 30.0) then return result(false, 'too_far', 'Create stations near your current position.') end
    stations[#stations + 1] = station
    if not saveStations() then
        stations[#stations] = nil
        return result(false, 'storage_error', 'Station could not be saved.')
    end
    broadcastStations()
    return result(true, 'created', 'Rental station created.', { station = station })
end

local function updateStation(source, stationId, payload)
    local allowed, failure = requireAdmin(source, 'admin_update')
    if not allowed then return failure end
    local current, index = findStation(stationId)
    if not current then return result(false, 'station_not_found', 'Rental station not found.') end
    if not sourceNear(source, current.coords, 30.0) then return result(false, 'too_far', 'Move closer to the station to edit it.') end
    local station, errorCode = normalizeStation(payload, current.id)
    if not station then return result(false, errorCode, 'Station data is invalid.') end
    if distance(current.coords, station.coords) > 50.0 then
        return result(false, 'move_too_large', 'Move a station in smaller steps.')
    end
    stations[index] = station
    if not saveStations() then
        stations[index] = current
        return result(false, 'storage_error', 'Station changes could not be saved.')
    end
    broadcastStations()
    return result(true, 'updated', 'Rental station updated.', { station = station })
end

local function deleteStation(source, stationId)
    local allowed, failure = requireAdmin(source, 'admin_delete')
    if not allowed then return failure end
    local station, index = findStation(stationId)
    if not station then return result(false, 'station_not_found', 'Rental station not found.') end
    if not sourceNear(source, station.coords, 30.0) then return result(false, 'too_far', 'Move closer to the station to delete it.') end
    if stationHasRentals(station.id) then return result(false, 'station_in_use', 'This station has active rentals.') end
    table.remove(stations, index)
    if not saveStations() then
        table.insert(stations, index, station)
        return result(false, 'storage_error', 'Station could not be deleted.')
    end
    broadcastStations()
    return result(true, 'deleted', 'Rental station deleted.')
end

local function captureVehicle(source, payload)
    local allowed, failure = requireAdmin(source, 'admin_capture')
    if not allowed then return failure end
    if type(payload) ~= 'table' then return result(false, 'invalid_request', 'Invalid capture request.') end
    local station = findStation(payload.stationId)
    if not station then return result(false, 'station_not_found', 'Rental station not found.') end
    if not sourceNear(source, station.coords, 30.0) then return result(false, 'too_far', 'Move closer to the rental station.') end

    local netId = tonumber(payload.netId)
    local entity = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then
        return result(false, 'vehicle_not_found', 'Look at a networked vehicle to capture it.')
    end
    local entityCoords = GetEntityCoords(entity)
    local currentCoords = playerCoords(source)
    if not currentCoords or distance(currentCoords, { x = entityCoords.x, y = entityCoords.y, z = entityCoords.z }) > Config.AdminCaptureDistance then
        return result(false, 'vehicle_too_far', 'Move closer to the vehicle you are capturing.')
    end
    local model = cleanString(payload.model, 64)
    if not model or GetHashKey(model) ~= GetEntityModel(entity) then
        return result(false, 'model_mismatch', 'Vehicle model could not be verified.')
    end
    local vehicle = normalizeVehicle({
        id = payload.id or model,
        model = model,
        label = payload.label or model,
        price = payload.price or payload.rate,
    })
    if not vehicle then return result(false, 'invalid_vehicle', 'Vehicle pricing or label is invalid.') end
    local existing, index = findVehicle(station, vehicle.id)
    if existing then station.vehicles[index] = vehicle else station.vehicles[#station.vehicles + 1] = vehicle end
    if not saveStations() then
        if existing then station.vehicles[index] = existing else table.remove(station.vehicles) end
        return result(false, 'storage_error', 'Captured vehicle could not be saved.')
    end
    broadcastStations()
    return result(true, existing and 'updated' or 'captured', 'Vehicle added to the rental catalog.', {
        station = station, vehicle = vehicle,
    })
end

local function upsertCatalogVehicle(source, payload)
    local allowed, failure = requireAdmin(source, 'admin_vehicle_save')
    if not allowed then return failure end
    if type(payload) ~= 'table' then return result(false, 'invalid_request', 'Invalid vehicle data.') end
    local station = findStation(payload.stationId)
    if not station then return result(false, 'station_not_found', 'Rental station not found.') end
    if not sourceNear(source, station.coords, 30.0) then
        return result(false, 'too_far', 'Move closer to the rental station.')
    end

    local vehicle = normalizeVehicle(payload)
    if not vehicle then
        return result(false, 'invalid_vehicle', 'Enter a valid model, label and rental price.')
    end

    local existing, index = findVehicle(station, payload.id or vehicle.id)
    if not existing and payload.id and payload.id ~= vehicle.id then
        existing, index = findVehicle(station, vehicle.id)
    end
    if existing then station.vehicles[index] = vehicle else station.vehicles[#station.vehicles + 1] = vehicle end
    if not saveStations() then
        if existing then station.vehicles[index] = existing else table.remove(station.vehicles) end
        return result(false, 'storage_error', 'Vehicle catalog changes could not be saved.')
    end
    broadcastStations()
    return result(true, existing and 'updated' or 'created', existing and 'Rental vehicle updated.' or 'Rental vehicle added.', {
        station = station, vehicle = vehicle,
    })
end

local function deleteCatalogVehicle(source, payload)
    local allowed, failure = requireAdmin(source, 'admin_vehicle_delete')
    if not allowed then return failure end
    if type(payload) ~= 'table' then return result(false, 'invalid_request', 'Invalid vehicle data.') end
    local station = findStation(payload.stationId)
    if not station then return result(false, 'station_not_found', 'Rental station not found.') end
    if not sourceNear(source, station.coords, 30.0) then
        return result(false, 'too_far', 'Move closer to the rental station.')
    end
    local vehicle, index = findVehicle(station, tostring(payload.vehicleId or ''))
    if not vehicle then return result(false, 'vehicle_not_found', 'Rental vehicle not found.') end

    table.remove(station.vehicles, index)
    if not saveStations() then
        table.insert(station.vehicles, index, vehicle)
        return result(false, 'storage_error', 'Vehicle could not be removed.')
    end
    broadcastStations()
    return result(true, 'deleted', 'Rental vehicle removed.', { station = station, vehicle = vehicle })
end

local function registerCallbacks()
    lib.callback.register('snipe-carrental:server:getBootstrap', bootstrap)
    lib.callback.register('snipe-carrental:server:createRental', createRental)
    lib.callback.register('snipe-carrental:server:confirmSpawn', confirmSpawn)
    lib.callback.register('snipe-carrental:server:cancelSpawn', cancelSpawn)
    lib.callback.register('snipe-carrental:server:startCapsuleDelivery', startCapsuleDelivery)
    lib.callback.register('snipe-carrental:server:beginReturn', beginReturn)
    lib.callback.register('snipe-carrental:server:cancelReturn', cancelReturn)
    lib.callback.register('snipe-carrental:server:returnRental', returnRental)
    lib.callback.register('snipe-carrental:server:createStation', createStation)
    lib.callback.register('snipe-carrental:server:updateStation', updateStation)
    lib.callback.register('snipe-carrental:server:deleteStation', deleteStation)
    lib.callback.register('snipe-carrental:server:captureVehicle', captureVehicle)
    lib.callback.register('snipe-carrental:server:upsertCatalogVehicle', upsertCatalogVehicle)
    lib.callback.register('snipe-carrental:server:deleteCatalogVehicle', deleteCatalogVehicle)
end

local function initialize()
    math.randomseed(os.time() + GetGameTimer())
    RentalBridge.init()
    RentalStorage.init()

    local storedStations = RentalStorage.loadStations()
    for i = 1, #storedStations do
        local station = normalizeStation(storedStations[i])
        if station and not findStation(station.id) then stations[#stations + 1] = station end
    end
    if #stations == 0 and Config.SeedDemoStation then
        local station = normalizeStation(Config.DemoStation)
        if station then
            stations[1] = station
            saveStations()
        end
    end

    registerCallbacks()
    print(('[%s] Loaded %s station(s). Active rentals are memory-only.'):format(RESOURCE, #stations))
end

CreateThread(function()
    Wait(0)
    initialize()
    while true do
        Wait(Config.ExpirySweepSeconds * 1000)
        local now = os.time()
        local expired = {}
        for _, rental in pairs(rentals) do
            if rental.status == 'awaiting_spawn' and now > rental.confirmBy then
                expired[#expired + 1] = { rental = rental, reason = 'spawn_timeout', refund = rental.pricing.total }
            elseif rental.status == 'active' and now >= rental.expiresAt then
                expired[#expired + 1] = { rental = rental, reason = 'expired' }
            end
        end
        for i = 1, #expired do
            if not Config.DeleteVehicleOnExpiry and expired[i].reason == 'expired' then
                expired[i].rental.netId = nil
            end
            finishRental(expired[i].rental, expired[i].reason, expired[i].refund)
        end
    end
end)

AddEventHandler('playerDropped', function()
    local droppedSource = source
    local droppedRentals = {}
    for _, rental in pairs(rentals) do
        if rental.source == droppedSource and (rental.status == 'awaiting_spawn' or rental.status == 'active') then
            droppedRentals[#droppedRentals + 1] = rental
        end
    end
    for i = 1, #droppedRentals do
        local rental = droppedRentals[i]
        if not Config.DeleteVehicleOnDisconnect then rental.netId = nil end
        local fullRefund = rental.status == 'awaiting_spawn' and rental.pricing.total or nil
        finishRental(rental, 'disconnected', fullRefund)
    end
    for key in pairs(rateLimit) do
        if key:sub(1, #tostring(droppedSource) + 1) == tostring(droppedSource) .. ':' then rateLimit[key] = nil end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    local stoppingRentals = {}
    for _, rental in pairs(rentals) do stoppingRentals[#stoppingRentals + 1] = rental end
    for i = 1, #stoppingRentals do
        local rental = stoppingRentals[i]
        local refund = rental.status == 'awaiting_spawn' and rental.pricing.total or 0
        finishRental(rental, 'resource_stop', refund)
    end
end)

exports('GetStations', function() return stations end)
exports('GetRentalByPlate', function(plate)
    if type(plate) ~= 'string' then return nil end
    plate = plate:gsub('^%s+', ''):gsub('%s+$', '')
    for _, rental in pairs(rentals) do
        if rental.plate == plate then return publicRental(rental) end
    end
end)
