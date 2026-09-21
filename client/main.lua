RentalClient = RentalClient or {}

local bootstrap = { stations = {}, rentals = {}, isAdmin = false }
local stations, pending, rentalVehicles, pendingVehicles = {}, {}, {}, {}
local busy, stopped, displayedPrompt = false, false, nil
local prefix = 'snipe-carrental:server:'

local function unwrap(value)
    if type(value) ~= 'table' then return nil end
    if value.success == false or value.ok == false then return nil end
    return value.data or value
end

function RentalClient.Notify(message, kind)
    lib.notify({ title = 'Capsule Rentals', description = tostring(message or ''), type = kind or 'inform' })
end

function RentalClient.GetStations() return stations end
function RentalClient.GetBootstrap() return bootstrap end
function RentalClient.GetStation(id)
    for _, station in pairs(stations) do
        if tostring(station.id) == tostring(id) then return station end
    end
end

local function updateStations(value, capsuleSnapshot)
    stations = value or {}
    bootstrap.stations = stations
    RentalWorld.setStations(stations)
    -- Only apply a fresh server snapshot here. Station CRUD broadcasts do not
    -- include capsule state and must not rewind a newer local animation.
    if capsuleSnapshot then RentalCapsule.Sync(capsuleSnapshot) end
    TriggerEvent('snipe-carrental:client:bootstrapUpdated', bootstrap)
end

function RentalClient.Refresh()
    local response = lib.callback.await(prefix .. 'getBootstrap', false)
    local data = unwrap(response)
    if not data then
        RentalClient.Notify(response and (response.message or response.error) or 'Unable to load rental stations.', 'error')
        return nil
    end
    bootstrap = data
    updateStations(data.stations, data.capsules)
    return data
end

function RentalClient.IsPlatformClear(station, ignoreVehicle)
    local platform = RentalWorld.platform(station)
    if not platform then return false, 'Place a vehicle platform first.' end
    local centre = vector3(platform.x, platform.y, platform.z)
    for _, entity in ipairs(GetGamePool('CVehicle')) do
        if entity ~= ignoreVehicle and DoesEntityExist(entity) and #(GetEntityCoords(entity) - centre) < 3.6 then
            return false, 'The platform is occupied. Move the vehicle before continuing.'
        end
    end
    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) and #(GetEntityCoords(ped) - centre) < 2.8 then
            return false, 'Someone is standing on the platform. Stand clear before continuing.'
        end
    end
    return true
end

local function distanceToSegment2d(point, startPoint, endPoint)
    local dx, dy = endPoint.x - startPoint.x, endPoint.y - startPoint.y
    local lengthSquared = dx * dx + dy * dy
    if lengthSquared < 0.001 then
        local px, py = point.x - startPoint.x, point.y - startPoint.y
        return math.sqrt(px * px + py * py)
    end
    local progress = ((point.x - startPoint.x) * dx + (point.y - startPoint.y) * dy) / lengthSquared
    progress = math.max(0.0, math.min(1.0, progress))
    local nearestX, nearestY = startPoint.x + dx * progress, startPoint.y + dy * progress
    local px, py = point.x - nearestX, point.y - nearestY
    return math.sqrt(px * px + py * py)
end

function RentalClient.IsDeliveryPathClear(station, ignoreVehicle)
    local platform = RentalWorld.platform(station)
    if not platform then return false, 'Place a vehicle platform first.' end
    local distance = tonumber(Config.CapsuleAnimation.vehiclePushDistance) or 6.0
    local finish = RentalWorld.offset(platform, 0.0, distance, 0.0)
    local corridorRadius = 2.25

    for _, entity in ipairs(GetGamePool('CVehicle')) do
        if entity ~= ignoreVehicle and DoesEntityExist(entity) then
            local coords = GetEntityCoords(entity)
            if math.abs(coords.z - platform.z) < 2.5
                and distanceToSegment2d(coords, platform, finish) < corridorRadius then
                return false, 'The delivery lane is blocked. Move the vehicle in front of the platform.'
            end
        end
    end
    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) then
            local coords = GetEntityCoords(ped)
            if math.abs(coords.z - platform.z) < 2.5
                and distanceToSegment2d(coords, platform, finish) < corridorRadius then
                return false, 'The delivery lane is blocked. Everyone must stand clear in front of the platform.'
            end
        end
    end
    return true
end

local function takeControl(entity, timeout)
    if not DoesEntityExist(entity) then return false end
    local deadline = GetGameTimer() + (timeout or 1500)
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end
    return NetworkHasControlOfEntity(entity)
end

local function deleteOwnedVehicle(entity)
    if entity and DoesEntityExist(entity) and takeControl(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteVehicle(entity)
    end
end

local function groundVehicleOnPlatform(vehicle, location)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local heading = location.w or location.heading or 0.0
    SetEntityHeading(vehicle, heading)
    SetEntityCoordsNoOffset(vehicle, location.x, location.y, location.z + 1.5, false, false, false)
    SetEntityCollision(vehicle, true, true)
    FreezeEntityPosition(vehicle, false)
    RequestCollisionAtCoord(location.x, location.y, location.z)

    local deadline = GetGameTimer() + 2000
    while not HasCollisionLoadedAroundEntity(vehicle) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(location.x, location.y, location.z)
        Wait(0)
    end

    local grounded = false
    for _ = 1, 3 do
        SetEntityCollision(vehicle, true, true)
        local placed = SetVehicleOnGroundProperly(vehicle)
        grounded = placed == true or placed == 1
        if grounded then break end
        Wait(0)
    end

    FreezeEntityPosition(vehicle, true)
    SetEntityCollision(vehicle, false, false)
    return grounded
end

local function easeMovement(value)
    value = math.max(0.0, math.min(1.0, value))
    return value * value * (3.0 - 2.0 * value)
end

local function pushVehicleOffPlatform(vehicle, location, capsule)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false, 'vehicle_missing' end
    local config = Config.CapsuleAnimation or {}
    local pushAt = tonumber(config.vehiclePushAt) or 5000
    local duration = math.max(250, tonumber(config.vehiclePushDuration) or 3200)
    local releaseAt = math.max(pushAt + duration, tonumber(config.releaseAt) or 8200)
    local distance = tonumber(config.vehiclePushDistance) or 6.0
    local drop = tonumber(config.vehiclePushDrop) or 0.15
    local startCoords = GetEntityCoords(vehicle)
    local finish = RentalWorld.offset(location, 0.0, distance, 0.0)
    local finishZ = startCoords.z - drop
    local heading = location.w or location.heading or 0.0

    SetEntityCollision(vehicle, false, false)
    FreezeEntityPosition(vehicle, true)
    while DoesEntityExist(vehicle) do
        local elapsed, elapsedError = RentalCapsule.GetElapsed(capsule)
        if not elapsed then return false, elapsedError end
        local progress = easeMovement((elapsed - pushAt) / (releaseAt - pushAt))
        SetEntityCoordsNoOffset(vehicle,
            startCoords.x + (finish.x - startCoords.x) * progress,
            startCoords.y + (finish.y - startCoords.y) * progress,
            startCoords.z + (finishZ - startCoords.z) * progress,
            false, false, false)
        SetEntityHeading(vehicle, heading)
        if elapsed >= releaseAt then return true end
        Wait(0)
    end
    return false, 'vehicle_missing'
end

function RentalClient.SpawnRental(authorization)
    local auth = unwrap(authorization)
    if not auth then return false, 'The rental was not authorized.' end
    if auth.rental then
        local envelope = auth
        auth = {}
        for key, value in pairs(envelope.rental) do auth[key] = value end
        auth.token = envelope.token
        auth.platform = envelope.platform or envelope.spawn
        auth.properties = envelope.properties or auth.properties
    end
    local token = auth.token or auth.rentalId or auth.id
    if not token then return false, 'The rental authorization is missing its token.' end
    if pending[token] then return false, 'This rental is already being prepared.' end
    pending[token] = true
    busy = true
    local vehicle, capsule
    local function fail(message)
        if vehicle then deleteOwnedVehicle(vehicle) end
        pendingVehicles[token] = nil
        if capsule then RentalCapsule.AbortDelivery(capsule) end
        local cancellation = lib.callback.await(prefix .. 'cancelSpawn', false, token)
        if cancellation and cancellation.ok then message = message .. ' Payment refunded.' end
        pending[token] = nil
        busy = false
        RentalClient.Notify(message, 'error')
        return false, message
    end
    local location = auth.platform or auth.spawn
    if not location then return fail('No delivery position was supplied. Contact staff.') end
    local hash = RentalWorld.loadModel(auth.model, 10000)
    if not hash or not IsModelAVehicle(hash) then
        return fail('The vehicle model could not load.')
    end
    local clear, reason = RentalClient.IsPlatformClear({ platform = location })
    if not clear then
        SetModelAsNoLongerNeeded(hash)
        return fail(reason)
    end
    clear, reason = RentalClient.IsDeliveryPathClear({ platform = location })
    if not clear then
        SetModelAsNoLongerNeeded(hash)
        return fail(reason)
    end
    RentalClient.Notify('Preparing your rental. Stand clear of the platform.')
    RequestCollisionAtCoord(location.x, location.y, location.z)
    vehicle = CreateVehicle(hash, location.x, location.y, location.z + 1.5, location.w or location.heading or 0, true, true)
    SetModelAsNoLongerNeeded(hash)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return fail('Vehicle delivery failed.') end
    pendingVehicles[token] = vehicle
    SetEntityAsMissionEntity(vehicle, true, true)
    SetEntityAlpha(vehicle, 0, false)
    pcall(function() Entity(vehicle).state:set('snipeRentalCapsuleHidden', true, true) end)
    SetVehicleNumberPlateText(vehicle, auth.plate)
    if auth.properties and lib.setVehicleProperties then lib.setVehicleProperties(vehicle, auth.properties) end
    if type(auth.color) == 'table' then
        local r = math.floor(tonumber(auth.color.r) or 235)
        local g = math.floor(tonumber(auth.color.g) or 238)
        local b = math.floor(tonumber(auth.color.b) or 240)
        SetVehicleCustomPrimaryColour(vehicle, r, g, b)
        SetVehicleCustomSecondaryColour(vehicle, r, g, b)
    end
    -- The server-issued plate wins over any captured showroom properties.
    SetVehicleNumberPlateText(vehicle, auth.plate)
    groundVehicleOnPlatform(vehicle, location)
    SetVehicleFuelLevel(vehicle, 100.0)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    SetNetworkIdCanMigrate(netId, true)

    -- The car exists, is networked and is hidden before the shared animation
    -- starts. This prevents model/network latency from making it appear late.
    local cycle = lib.callback.await(prefix .. 'startCapsuleDelivery', false, token)
    if not unwrap(cycle) then return fail('The delivery capsule lost server synchronization.') end
    local capsuleError
    capsule, capsuleError = RentalCapsule.BeginDelivery(auth.stationId, token, cycle.elapsed or 0)
    if not capsule then
        return fail(('The delivery capsule could not start (%s).'):format(capsuleError or 'unavailable'))
    end

    local response
    local confirmDeadline = GetGameTimer() + 5000
    repeat
        response = lib.callback.await(prefix .. 'confirmSpawn', false, token, netId, auth.plate)
        if response and (response.code == 'vehicle_not_ready' or response.code == 'rate_limited') then Wait(600)
        else break end
    until GetGameTimer() > confirmDeadline
    if not unwrap(response) then
        return fail(response and (response.message or response.error) or 'Vehicle delivery was rejected. The payment will be refunded.')
    end
    rentalVehicles[token] = { id = auth.id, entity = vehicle, plate = auth.plate, netId = netId, stationId = auth.stationId }
    pendingVehicles[token] = nil

    local visibleAt = tonumber(Config.CapsuleAnimation.vehicleVisibleAt) or 3000
    local visible, visibleError = RentalCapsule.WaitUntil(capsule, visibleAt)
    if not visible then
        RentalClient.Notify(('The capsule visual ended early (%s); releasing the confirmed vehicle safely.'):format(
            visibleError or 'unavailable'), 'warning')
    end
    pcall(function() Entity(vehicle).state:set('snipeRentalCapsuleHidden', false, true) end)
    if DoesEntityExist(vehicle) then
        SetEntityVisible(vehicle, true, false)
        ResetEntityAlpha(vehicle)
    end

    local pushAt = tonumber(Config.CapsuleAnimation.vehiclePushAt) or 5000
    local readyToPush, pushWaitError = RentalCapsule.WaitUntil(capsule, pushAt)
    local pushed, pushError = false, pushWaitError
    if readyToPush and DoesEntityExist(vehicle) then
        pushed, pushError = pushVehicleOffPlatform(vehicle, location, capsule)
    end
    if not pushed and visible then
        RentalClient.Notify(('The capsule rollout ended early (%s); releasing the vehicle safely.'):format(
            pushError or 'unavailable'), 'warning')
    end
    if DoesEntityExist(vehicle) then
        SetEntityCollision(vehicle, true, true)
        FreezeEntityPosition(vehicle, false)
        RequestCollisionAtCoord(GetEntityCoords(vehicle).x, GetEntityCoords(vehicle).y, GetEntityCoords(vehicle).z)
        SetVehicleOnGroundProperly(vehicle)
        SetVehicleDoorsLocked(vehicle, 1)
        if GetResourceState('qbx_vehiclekeys') == 'started' then
            -- Supported installations normally grant keys server-side. This event
            -- is retained for qb-vehiclekeys compatibility without a dependency.
            TriggerEvent('vehiclekeys:client:SetOwner', auth.plate)
        elseif GetResourceState('qb-vehiclekeys') == 'started' then
            TriggerEvent('vehiclekeys:client:SetOwner', auth.plate)
        end
    end
    busy = false
    RentalClient.Notify('Your rental is ready. Return it to a rental platform before the timer expires.', 'success')
    TriggerEvent('snipe-carrental:client:rentalDelivered', auth)
    RentalClient.Refresh()
    return true
end

local function rentalForVehicle(entity)
    if entity == 0 or not DoesEntityExist(entity) then return nil end
    local plate = GetVehicleNumberPlateText(entity):gsub('^%s*(.-)%s*$', '%1')
    for _, rental in pairs(bootstrap.rentals or bootstrap.activeRentals or {}) do
        if tostring(rental.plate):gsub('^%s*(.-)%s*$', '%1') == plate then return rental end
    end
    for token, rental in pairs(rentalVehicles) do if rental.plate == plate then return rental, token end end
end

function RentalClient.FindReturnVehicle(station)
    local platform = RentalWorld.platform(station)
    if not platform then return nil end
    local centre = vector3(platform.x, platform.y, platform.z)
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if #(GetEntityCoords(vehicle) - centre) < 3.6 and rentalForVehicle(vehicle) then return vehicle end
    end
end

function RentalClient.ReturnRental(station)
    if busy then return false, 'Please wait for the current rental action.' end
    local vehicle = RentalClient.FindReturnVehicle(station)
    if not vehicle then RentalClient.Notify('Park your rental on the platform first.', 'error') return false end
    if IsPedInAnyVehicle(PlayerPedId(), false) then RentalClient.Notify('Park on the platform, then exit the vehicle.') return false end
    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if GetPedInVehicleSeat(vehicle, seat) ~= 0 then RentalClient.Notify('Everyone must exit the vehicle before it is returned.', 'error') return false end
    end
    local centre = RentalWorld.platform(station)
    if #(GetEntityCoords(PlayerPedId()) - vector3(centre.x, centre.y, centre.z)) < 2.8 then
        RentalClient.Notify('Stand clear of the platform before returning the vehicle.') return false
    end
    local rental = rentalForVehicle(vehicle)
    if not rental then return false end
    busy = true
    local canAnimate = takeControl(vehicle)
    if not canAnimate then
        busy = false
        RentalClient.Notify('The rental vehicle could not be secured for return.', 'error')
        return false
    end
    FreezeEntityPosition(vehicle, true)
    local returnPayload = {
        rentalId = rental.id, stationId = station.id,
        netId = NetworkGetNetworkIdFromEntity(vehicle), plate = GetVehicleNumberPlateText(vehicle),
    }
    local prepared = lib.callback.await(prefix .. 'beginReturn', false, returnPayload)
    if not unwrap(prepared) then
        FreezeEntityPosition(vehicle, false)
        busy = false
        RentalClient.Notify(prepared and (prepared.message or prepared.error) or 'The return capsule could not be prepared.', 'error')
        return false
    end
    local capsule, capsuleError = RentalCapsule.BeginReturn(station.id, rental.id)
    if not capsule then
        lib.callback.await(prefix .. 'cancelReturn', false, rental.id)
        FreezeEntityPosition(vehicle, false)
        busy = false
        RentalClient.Notify(('The return capsule could not start (%s).'):format(capsuleError or 'unavailable'), 'error')
        return false
    end
    if not DoesEntityExist(vehicle) then
        RentalCapsule.AbortReturn(capsule)
        lib.callback.await(prefix .. 'cancelReturn', false, rental.id)
        busy = false
        return false
    end

    local closeAt = tonumber(Config.CapsuleAnimation.doorCloseAt) or 9600
    local closeDuration = tonumber(Config.CapsuleAnimation.doorDuration) or 1200
    local hideAt = math.max(tonumber(Config.CapsuleAnimation.returnHideAt) or 10900,
        closeAt + closeDuration + 100)
    local enclosed, enclosedError = RentalCapsule.WaitUntil(capsule, hideAt)
    if not enclosed then
        RentalCapsule.AbortReturn(capsule)
        lib.callback.await(prefix .. 'cancelReturn', false, rental.id)
        FreezeEntityPosition(vehicle, false)
        busy = false
        RentalClient.Notify(('The return animation stopped (%s).'):format(enclosedError or 'unavailable'), 'error')
        return false
    end
    SetEntityAlpha(vehicle, 0, false)
    SetEntityCollision(vehicle, false, false)
    pcall(function() Entity(vehicle).state:set('snipeRentalCapsuleHidden', true, true) end)
    local response = lib.callback.await(prefix .. 'returnRental', false, returnPayload)
    busy = false
    if not unwrap(response) then
        RentalCapsule.AbortReturn(capsule)
        lib.callback.await(prefix .. 'cancelReturn', false, rental.id)
        if DoesEntityExist(vehicle) then
            pcall(function() Entity(vehicle).state:set('snipeRentalCapsuleHidden', false, true) end)
            ResetEntityAlpha(vehicle)
            SetEntityCollision(vehicle, true, true)
            FreezeEntityPosition(vehicle, false)
        end
        RentalClient.Notify(response and (response.message or response.error) or 'The vehicle could not be returned.', 'error')
        return false
    end
    RentalCapsule.CompleteReturn(capsule)
    if rental.stationId and tostring(rental.stationId) ~= tostring(station.id) then
        RentalCapsule.SetIdle(rental.stationId, true)
    end
    RentalClient.Notify('Vehicle returned.', 'success')
    return true
end

RegisterNetEvent('snipe-carrental:client:stationsChanged', function(value)
    if type(value) == 'table' then updateStations(value.stations or value) else RentalClient.Refresh() end
end)
RegisterNetEvent('snipe-carrental:client:rentalAuthorized', function(auth)
    CreateThread(function() RentalClient.SpawnRental(auth) end)
end)
RegisterNetEvent('snipe-carrental:client:notify', function(message, kind)
    if type(message) == 'table' then lib.notify(message) else RentalClient.Notify(message, kind) end
end)
RegisterNetEvent('snipe-carrental:client:rentalEnded', function(payload)
    local token = type(payload) == 'table' and (payload.token or payload.id or payload.rentalId) or payload
    if token then rentalVehicles[token] = nil pending[token] = nil end
    for key, rental in pairs(rentalVehicles) do
        if rental.id == token then rentalVehicles[key] = nil pending[key] = nil end
    end
    if type(payload) == 'table' and payload.stationId then
        CreateThread(function()
            local returned = payload.reason == 'returned'
            local sameReturnStation = payload.returnStationId
                and tostring(payload.returnStationId) == tostring(payload.stationId)
            if not returned or not sameReturnStation then RentalCapsule.SetIdle(payload.stationId) end
            if not returned and payload.returnStationId
                and tostring(payload.returnStationId) ~= tostring(payload.stationId) then
                RentalCapsule.SetIdle(payload.returnStationId, true)
            end
        end)
    end
    TriggerEvent('snipe-carrental:client:rentalStateChanged', payload)
    CreateThread(function() Wait(800) if not stopped then RentalClient.Refresh() end end)
end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(250) end
    Wait(1000)
    RentalClient.Refresh()
end)

-- Coordinate-based interaction deliberately avoids relying on the tablet's
-- narrow collision mesh. Returning remains available beside the platform.
CreateThread(function()
    while not stopped do
        local delay, prompt, selected, returning = 350, nil, nil, false
        if not busy and not RentalPlacement.isActive() and not IsNuiFocused() then
            local player = GetEntityCoords(PlayerPedId())
            local tabletDistance = tonumber(Config.TabletInteractionDistance) or 2.5
            local closestDistance = tabletDistance
            for _, station in pairs(stations) do
                local coords, platform = station.coords, RentalWorld.platform(station)
                if coords then
                    local distance = #(player - vector3(coords.x, coords.y, coords.z))
                    if distance < closestDistance then
                        closestDistance, selected = distance, station
                        prompt = '[E] Browse rental vehicles'
                    end
                end
                if platform and #(player - vector3(platform.x, platform.y, platform.z)) < 5.5 then
                    local vehicle = RentalClient.FindReturnVehicle(station)
                    if vehicle then
                        selected, returning = station, true
                        prompt = IsPedInAnyVehicle(PlayerPedId(), false)
                            and 'Park on the platform, then exit the vehicle'
                            or '[E] Return rental vehicle'
                        break
                    end
                end
            end
            if selected then
                delay = 0
                if IsControlJustReleased(0, 38) and not IsPedInAnyVehicle(PlayerPedId(), false) then
                    if returning then RentalClient.ReturnRental(selected)
                    elseif RentalClient.OpenRental then RentalClient.OpenRental(selected) end
                end
            end
        end
        if prompt ~= displayedPrompt then
            if displayedPrompt and not RentalPlacement.isActive() then lib.hideTextUI() end
            if prompt then lib.showTextUI(prompt, { position = 'left-center' }) end
            displayedPrompt = prompt
        end
        Wait(delay)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    stopped = true
    if displayedPrompt then lib.hideTextUI() end
    SetNuiFocus(false, false)
    for _, vehicle in pairs(pendingVehicles) do
        if DoesEntityExist(vehicle) and NetworkHasControlOfEntity(vehicle) then DeleteVehicle(vehicle) end
    end
    -- The server owns confirmed rental cleanup. Never delete an unrelated or
    -- occupied vehicle here merely because its client handle was cached.
end)
