local uiOpen = false
local uiMode = nil
local draftStation = nil
local draftAssembly = nil

local function copy(value)
    return json.decode(json.encode(value or {}))
end

local function responseOk(response)
    return type(response) == 'table' and response.ok ~= false and response.success ~= false
end

local function setFocus(enabled)
    uiOpen = enabled
    SetNuiFocusKeepInput(false)
    SetNuiFocus(enabled, enabled)
end

local function clearDraftAssembly()
    if draftAssembly then RentalWorld.destroy(draftAssembly) end
    draftAssembly = nil
end

local function showDraftAssembly(station, assembly)
    clearDraftAssembly()
    draftAssembly = assembly or RentalWorld.create(station, true)
end

local function closeUi(sendMessage)
    local closingMode = uiMode
    uiMode = nil
    if closingMode == 'rental' and CapsuleDui then
        CapsuleDui.CloseRental()
    else
        setFocus(false)
    end
    if sendMessage ~= false then SendNUIMessage({ action = 'close' }) end
end

local function openCreator(station)
    local bootstrap = RentalClient.GetBootstrap()
    if not bootstrap.isAdmin then
        RentalClient.Notify('You do not have permission to manage rental stations.', 'error')
        return false
    end
    if station then
        clearDraftAssembly()
        draftStation = copy(station)
    else
        draftStation = copy(draftStation or {})
    end
    draftStation.variant = 'tablet'
    draftStation.color = draftStation.color or '#17d7c4'
    uiMode = 'creator'
    setFocus(true)
    SendNUIMessage({ action = 'openCreator', station = draftStation, stations = bootstrap.stations or {} })
    return true
end

function RentalClient.OpenCreator(station)
    if not station and not draftStation then
        local player = GetEntityCoords(PlayerPedId())
        local nearestDistance = 20.0
        for _, candidate in pairs(RentalClient.GetStations() or {}) do
            for _, coords in ipairs({ candidate.coords, candidate.platform }) do
                if coords then
                    local distance = #(player - vector3(coords.x, coords.y, coords.z))
                    if distance < nearestDistance then
                        station, nearestDistance = candidate, distance
                    end
                end
            end
        end
    end
    return openCreator(station)
end

function RentalClient.OpenRental(station)
    if not station then return false end
    local bootstrap = RentalClient.GetBootstrap()
    local vehicles = {}
    for _, vehicle in ipairs(station.vehicles or {}) do
        vehicles[#vehicles + 1] = vehicle
    end
    if #vehicles == 0 then
        RentalClient.Notify('No vehicles are available at this station.', 'error')
        return false
    end
    uiMode = 'rental'
    if not CapsuleDui or not CapsuleDui.OpenRental(station) then
        uiMode = nil
        RentalClient.Notify('The rental terminal screen is not available. Move closer and try again.', 'error')
        return false
    end
    return true
end

local function beginPlacement(kind, incoming)
    draftStation = copy(incoming or draftStation)
    clearDraftAssembly()
    closeUi(false)
    SendNUIMessage({ action = 'close' })
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    RentalPlacement.start(kind, draftStation, function(result, assembly, errorCode)
        if result then
            draftStation = copy(result)
            showDraftAssembly(draftStation, assembly)
            SendNUIMessage({ action = 'stationUpdate', station = draftStation })
            RentalClient.Notify('Placement confirmed. Focus returned to the game; press F7 to continue editing.', 'success')
        else
            showDraftAssembly(draftStation)
            if not errorCode then
                RentalClient.Notify('Placement cancelled. Press F7 to continue editing.', 'inform')
            end
        end
    end)
end

RegisterNUICallback('close', function(_, cb)
    if RentalPlacement.isActive() then RentalPlacement.cancel() end
    closeUi(false)
    cb({ ok = true })
end)

RegisterNUICallback('duiPointer', function(data, cb)
    cb({ ok = CapsuleDui and CapsuleDui.Pointer(data) or false })
end)

RegisterNUICallback('setStationVariant', function(data, cb)
    draftStation = draftStation or {}
    draftStation.variant = 'tablet'
    cb({ ok = true })
end)

RegisterNUICallback('setStripColor', function(data, cb)
    draftStation = draftStation or {}
    if type(data.color) == 'string' and data.color:match('^#%x%x%x%x%x%x$') then draftStation.color = data.color end
    cb({ ok = true })
end)

RegisterNUICallback('placePlatform', function(data, cb)
    beginPlacement('platform', data)
    cb({ ok = true })
end)

RegisterNUICallback('placeBooth', function(data, cb)
    beginPlacement('coords', data)
    cb({ ok = true })
end)

RegisterNUICallback('newStation', function(_, cb)
    clearDraftAssembly()
    draftStation = { variant = 'tablet', color = '#17d7c4' }
    cb({ ok = true, station = draftStation })
end)

RegisterNUICallback('selectStation', function(data, cb)
    local station = type(data) == 'table' and RentalClient.GetStation(data.id) or nil
    if not station then
        cb({ ok = false, message = 'That rental location is no longer available.' })
        return
    end
    clearDraftAssembly()
    draftStation = copy(station)
    cb({ ok = true, station = draftStation })
end)

RegisterNUICallback('lockPlacement', function(data, cb)
    draftStation = copy(data or draftStation)
    cb({ ok = true, station = draftStation })
end)

RegisterNUICallback('saveStation', function(data, cb)
    draftStation = copy(data or draftStation)
    if not draftStation.coords or not draftStation.platform then
        cb({ ok = false, message = 'Place both the rental terminal and vehicle platform first.' })
        return
    end
    local callback = draftStation.id and 'updateStation' or 'createStation'
    local response
    if callback == 'updateStation' then
        response = lib.callback.await('snipe-carrental:server:updateStation', false, draftStation.id, draftStation)
    else
        response = lib.callback.await('snipe-carrental:server:createStation', false, draftStation)
    end
    if responseOk(response) then
        local savedStation = copy(response.station or draftStation)
        clearDraftAssembly()
        RentalClient.Refresh()
        closeUi(true)
        draftStation = nil
        RentalClient.Notify(('Rental station "%s" saved.'):format(savedStation.label or 'Unnamed'), 'success')
    else
        RentalClient.Notify(response and response.message or 'Station could not be saved.', 'error')
    end
    cb(response or { ok = false, message = 'No response from the server.' })
end)

local function closestVehicleToStation(station)
    local platform = station and RentalWorld.platform(station)
    if not platform then return 0 end
    local centre = vector3(platform.x, platform.y, platform.z)
    local closest, distance = 0, 4.0
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        local current = #(GetEntityCoords(vehicle) - centre)
        if current < distance then closest, distance = vehicle, current end
    end
    return closest
end

local function draftVehicle(data)
    local model = type(data.model) == 'string' and data.model:lower():gsub('^%s+', ''):gsub('%s+$', '') or ''
    local label = type(data.label) == 'string' and data.label:gsub('^%s+', ''):gsub('%s+$', '') or ''
    local price = math.floor(tonumber(data.price) or 0)
    local hash = model ~= '' and joaat(model) or 0
    if hash == 0 or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return nil, 'That vehicle model is not available on this client.'
    end
    if label == '' or price < 1 then return nil, 'Enter a display name and price.' end
    local id = type(data.id) == 'string' and data.id or model
    id = id:lower():gsub('[^%w%-_]', '-'):sub(1, 48)
    return { id = id, model = model, label = label:sub(1, 64), price = price }
end

local function saveDraftVehicle(vehicle)
    draftStation = draftStation or {}
    draftStation.vehicles = draftStation.vehicles or {}
    local replaced = false
    for index = 1, #draftStation.vehicles do
        local current = draftStation.vehicles[index]
        if current.id == vehicle.id or current.model == vehicle.model then
            draftStation.vehicles[index] = vehicle
            replaced = true
            break
        end
    end
    if not replaced then draftStation.vehicles[#draftStation.vehicles + 1] = vehicle end
    SendNUIMessage({ action = 'vehiclesUpdate', vehicles = draftStation.vehicles })
end

RegisterNUICallback('captureVehicle', function(data, cb)
    local station = RentalClient.GetStation(data.stationId) or draftStation
    local vehicle = closestVehicleToStation(station)
    if vehicle == 0 then
        cb({ ok = false, message = 'Park the vehicle on the capsule platform first.' })
        return
    end
    if not NetworkGetEntityIsNetworked(vehicle) then
        NetworkRegisterEntityAsNetworked(vehicle)
        Wait(0)
    end
    local model = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)):lower()
    if model == '' or model == 'carnotfound' then
        cb({ ok = false, message = 'This vehicle model cannot be captured.' })
        return
    end
    local label = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)))
    if not label or label == 'NULL' then label = model:gsub('^%l', string.upper) end
    local requestedLabel = type(data.label) == 'string' and data.label:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if requestedLabel ~= '' then label = requestedLabel end
    if not station.id then
        local captured, captureError = draftVehicle({
            id = data.id,
            model = model,
            label = label,
            price = tonumber(data.price) or 250,
        })
        if not captured then cb({ ok = false, message = captureError }) return end
        saveDraftVehicle(captured)
        cb({ ok = true, station = draftStation, vehicle = captured })
        return
    end
    local response = lib.callback.await('snipe-carrental:server:captureVehicle', false, {
        stationId = station.id,
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        id = data.id,
        model = model,
        label = label,
        price = tonumber(data.price) or 250,
    })
    if responseOk(response) then
        draftStation = copy(response.station or station)
        SendNUIMessage({ action = 'vehiclesUpdate', vehicles = draftStation.vehicles or {} })
        RentalClient.Refresh()
    else
        RentalClient.Notify(response and response.message or 'Vehicle capture failed.', 'error')
    end
    cb(response or { ok = false, message = 'No response from the server.' })
end)

RegisterNUICallback('saveCatalogVehicle', function(data, cb)
    local station = RentalClient.GetStation(data.stationId) or draftStation
    if not station then cb({ ok = false, message = 'Open a rental location first.' }) return end
    local vehicle, vehicleError = draftVehicle(data)
    if not vehicle then cb({ ok = false, message = vehicleError }) return end
    if not station.id then
        saveDraftVehicle(vehicle)
        cb({ ok = true, station = draftStation, vehicle = vehicle })
        return
    end
    local response = lib.callback.await('snipe-carrental:server:upsertCatalogVehicle', false, {
        stationId = station.id,
        id = vehicle.id,
        model = vehicle.model,
        label = vehicle.label,
        price = vehicle.price,
    })
    if responseOk(response) then
        draftStation = copy(response.station or station)
        SendNUIMessage({ action = 'vehiclesUpdate', vehicles = draftStation.vehicles or {} })
        RentalClient.Refresh()
        RentalClient.Notify(response.message or 'Rental vehicle saved.', 'success')
    else
        RentalClient.Notify(response and response.message or 'Rental vehicle could not be saved.', 'error')
    end
    cb(response or { ok = false, message = 'No response from the server.' })
end)

RegisterNUICallback('deleteCatalogVehicle', function(data, cb)
    local station = RentalClient.GetStation(data.stationId) or draftStation
    if not station then cb({ ok = false, message = 'Open a rental location first.' }) return end
    if not station.id then
        for index = #station.vehicles, 1, -1 do
            local vehicle = station.vehicles[index]
            if vehicle.id == data.vehicleId or vehicle.model == data.vehicleId then table.remove(station.vehicles, index) end
        end
        draftStation = copy(station)
        SendNUIMessage({ action = 'vehiclesUpdate', vehicles = draftStation.vehicles or {} })
        cb({ ok = true, station = draftStation })
        return
    end
    local response = lib.callback.await('snipe-carrental:server:deleteCatalogVehicle', false, {
        stationId = station.id,
        vehicleId = data.vehicleId,
    })
    if responseOk(response) then
        draftStation = copy(response.station or station)
        SendNUIMessage({ action = 'vehiclesUpdate', vehicles = draftStation.vehicles or {} })
        RentalClient.Refresh()
        RentalClient.Notify(response.message or 'Rental vehicle removed.', 'success')
    else
        RentalClient.Notify(response and response.message or 'Rental vehicle could not be removed.', 'error')
    end
    cb(response or { ok = false, message = 'No response from the server.' })
end)

RegisterNUICallback('rentVehicle', function(data, cb)
    local response = lib.callback.await('snipe-carrental:server:createRental', false, {
        stationId = data.stationId,
        vehicleId = data.vehicleId,
        model = data.model,
        payment = data.payment,
        color = data.color,
    })
    if not responseOk(response) then
        RentalClient.Notify(response and response.message or 'Rental could not be created.', 'error')
    end
    cb(response or { ok = false, message = 'No response from the server.' })
end)

RegisterCommand('rentalcreator', function(_, args)
    local station = args[1] and RentalClient.GetStation(args[1]) or nil
    RentalClient.OpenCreator(station)
end, false)

RegisterKeyMapping('rentalcreator', 'Open capsule rental creator', 'keyboard', 'F7')

AddEventHandler('snipe-carrental:client:bootstrapUpdated', function(bootstrap)
    if CapsuleDui then CapsuleDui.Sync(bootstrap.stations or {}) end
end)

AddEventHandler('snipe-carrental:client:duiClosed', function()
    if uiMode == 'rental' then uiMode = nil end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearDraftAssembly()
    closeUi(false)
end)
