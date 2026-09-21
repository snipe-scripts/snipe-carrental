CapsuleDui = {}

local duiObject = nil
local runtimeTxd = nil
local runtimeTexture = nil
local replacementBound = false
local sourceTextureLoaded = false
local stations = {}
local nearestStationId = nil
local nearestStation = nil
local activeStation = nil
local terminalEntity = nil
local interacting = false
local focusCamera = nil
local focusedPed = nil
local nextDuiRetry = 0
local stopped = false

local resourceName = GetCurrentResourceName()
local resourceKey = resourceName:gsub('[^%w_]', '_')
local runtimeDictionary = ('%s_capsule_dui_txd'):format(resourceKey)
local runtimeTextureName = ('%s_capsule_dui_texture'):format(resourceKey)

local function number(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback or 0.0 end
    return value
end

local function stationPosition(station)
    local value = station and station.coords
    if not value then return nil end
    return vector3(number(value.x), number(value.y), number(value.z))
end

local function ensureSourceTexture()
    if HasStreamedTextureDictLoaded(CapsuleDuiConfig.textureDictionary) then
        sourceTextureLoaded = true
        return true
    end

    RequestStreamedTextureDict(CapsuleDuiConfig.textureDictionary, false)
    local timeoutAt = GetGameTimer() + 5000
    while not HasStreamedTextureDictLoaded(CapsuleDuiConfig.textureDictionary) and GetGameTimer() < timeoutAt do
        Wait(0)
    end
    sourceTextureLoaded = HasStreamedTextureDictLoaded(CapsuleDuiConfig.textureDictionary)
    return sourceTextureLoaded
end

local function bindReplacement(force)
    if not sourceTextureLoaded or not duiObject or not IsDuiAvailable(duiObject) or not runtimeTexture then
        return false
    end
    if force and replacementBound then
        RemoveReplaceTexture(CapsuleDuiConfig.textureDictionary, CapsuleDuiConfig.textureName)
        replacementBound = false
    end
    AddReplaceTexture(
        CapsuleDuiConfig.textureDictionary,
        CapsuleDuiConfig.textureName,
        runtimeDictionary,
        runtimeTextureName
    )
    replacementBound = true
    return true
end

local function ensureDui()
    if duiObject and IsDuiAvailable(duiObject) and replacementBound then return true end
    if GetGameTimer() < nextDuiRetry then return false end

    -- AddReplaceTexture silently fails when the source YTD has not streamed yet.
    -- Explicitly retain it so first player load behaves the same as a resource restart.
    if not ensureSourceTexture() then
        nextDuiRetry = GetGameTimer() + CapsuleDuiConfig.retryDelay
        return false
    end

    if duiObject then DestroyDui(duiObject) end
    duiObject, runtimeTxd, runtimeTexture = nil, nil, nil
    replacementBound = false

    local url = ('https://cfx-nui-%s/%s'):format(resourceName, CapsuleDuiConfig.page)
    duiObject = CreateDui(url, CapsuleDuiConfig.width, CapsuleDuiConfig.height)
    if not duiObject then
        nextDuiRetry = GetGameTimer() + CapsuleDuiConfig.retryDelay
        return false
    end

    local timeoutAt = GetGameTimer() + 5000
    while not IsDuiAvailable(duiObject) and GetGameTimer() < timeoutAt do Wait(0) end
    if not IsDuiAvailable(duiObject) then
        DestroyDui(duiObject)
        duiObject = nil
        nextDuiRetry = GetGameTimer() + CapsuleDuiConfig.retryDelay
        return false
    end

    runtimeTxd = CreateRuntimeTxd(runtimeDictionary)
    runtimeTexture = CreateRuntimeTextureFromDuiHandle(runtimeTxd, runtimeTextureName, GetDuiHandle(duiObject))
    if not runtimeTexture then
        DestroyDui(duiObject)
        duiObject, runtimeTxd = nil, nil
        nextDuiRetry = GetGameTimer() + CapsuleDuiConfig.retryDelay
        return false
    end

    return bindReplacement(false)
end

local function sendStation(station, action)
    if not station or not ensureDui() then return false end
    SendDuiMessage(duiObject, json.encode({
        action = action or 'station',
        station = station,
        stationId = station.id,
        label = station.label,
        color = station.color,
        vehicles = station.vehicles or {},
    }))
    return true
end

local function terminalFor(station)
    if not station or not RentalWorld or not RentalWorld.getAssembly then return nil end
    local assembly = RentalWorld.getAssembly(station.id)
    local entity = assembly and assembly.roles and assembly.roles.coords
    if entity and entity ~= 0 and DoesEntityExist(entity) then return entity end
end

local function normalized(from, to)
    local x, y, z = to.x - from.x, to.y - from.y, to.z - from.z
    local length = math.sqrt(x * x + y * y + z * z)
    if length < 0.000001 then return nil end
    return vector3(x / length, y / length, z / length)
end

local function dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function screenPlane(entity, station)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    local screen = CapsuleDuiConfig.screens.tablet
    if not screen then return nil end
    local centre = GetOffsetFromEntityInWorldCoords(entity, screen.x, screen.y, screen.z)
    local rightPoint = GetOffsetFromEntityInWorldCoords(entity, screen.x + 1.0, screen.y, screen.z)
    local upPoint = GetOffsetFromEntityInWorldCoords(entity, screen.x, screen.y, screen.z + 1.0)
    local normalPoint = GetOffsetFromEntityInWorldCoords(entity, screen.x, screen.y - 1.0, screen.z)
    local right = normalized(centre, rightPoint)
    local up = normalized(centre, upPoint)
    local normal = normalized(centre, normalPoint)
    if not right or not up or not normal then return nil end
    return screen, centre, right, up, normal
end

local function stopFocusCamera()
    local camera = CapsuleDuiConfig.camera or {}
    if focusCamera then
        SetCamActive(focusCamera, false)
        RenderScriptCams(false, true, tonumber(camera.transitionOut) or 250, true, true)
        DestroyCam(focusCamera, false)
        focusCamera = nil
    end
    if focusedPed and DoesEntityExist(focusedPed) then
        FreezeEntityPosition(focusedPed, false)
    end
    focusedPed = nil
end

local function startFocusCamera(entity, station)
    stopFocusCamera()
    local screen, centre, _, _, normal = screenPlane(entity, station)
    if not screen then return false end
    local camera = CapsuleDuiConfig.camera or {}
    local fov = tonumber(camera.fov) or 42.0
    local verticalRadians = math.rad(fov * 0.5)
    local resolutionX, resolutionY = GetActiveScreenResolution()
    local aspect = resolutionY > 0 and resolutionX / resolutionY or (16.0 / 9.0)
    local horizontalRadians = math.atan(math.tan(verticalRadians) * aspect)
    local verticalDistance = (screen.height * 0.5) / math.tan(verticalRadians)
    local horizontalDistance = (screen.width * 0.5) / math.tan(horizontalRadians)
    local distance = math.max(verticalDistance, horizontalDistance) + (tonumber(camera.padding) or 0.30)
    local position = vector3(
        centre.x + normal.x * distance,
        centre.y + normal.y * distance,
        centre.z + normal.z * distance
    )

    focusCamera = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        position.x, position.y, position.z, 0.0, 0.0, 0.0, fov, false, 0)
    if not focusCamera or focusCamera == 0 then
        focusCamera = nil
        return false
    end
    SetCamNearClip(focusCamera, tonumber(camera.nearClip) or 0.05)
    PointCamAtCoord(focusCamera, centre.x, centre.y, centre.z)
    SetCamActive(focusCamera, true)
    RenderScriptCams(true, true, tonumber(camera.transitionIn) or 350, true, true)
    focusedPed = PlayerPedId()
    FreezeEntityPosition(focusedPed, true)
    return true
end

local function cursorToDui()
    if not GetWorldCoordFromScreenCoord or not interacting
        or not terminalEntity or not DoesEntityExist(terminalEntity) then return nil end
    local screen, centre, right, up, normal = screenPlane(terminalEntity, activeStation)
    if not screen then return nil end

    local cursorX, cursorY = GetNuiCursorPosition()
    local resolutionX, resolutionY = GetActiveScreenResolution()
    if resolutionX < 1 or resolutionY < 1 then return nil end
    cursorX, cursorY = cursorX / resolutionX, cursorY / resolutionY

    local rayOrigin, rayDirection = GetWorldCoordFromScreenCoord(cursorX, cursorY)
    if not rayOrigin or not rayDirection then return nil end
    local denominator = dot(rayDirection, normal)
    -- The authored screen normal points toward the user. Reject back-face hits
    -- so a terminal cannot be operated through the rear of the prop.
    if denominator >= -0.000001 then return nil end
    local toPlane = vector3(centre.x - rayOrigin.x, centre.y - rayOrigin.y, centre.z - rayOrigin.z)
    local distance = dot(toPlane, normal) / denominator
    if distance < 0.0 then return nil end
    local hit = vector3(
        rayOrigin.x + rayDirection.x * distance,
        rayOrigin.y + rayDirection.y * distance,
        rayOrigin.z + rayDirection.z * distance
    )
    local fromCentre = vector3(hit.x - centre.x, hit.y - centre.y, hit.z - centre.z)
    local u = dot(fromCentre, right) / screen.width + 0.5
    local v = 0.5 - dot(fromCentre, up) / screen.height
    local inside = u >= 0.0 and u <= 1.0 and v >= 0.0 and v <= 1.0
    local pixelX = math.floor(math.max(0.0, math.min(CapsuleDuiConfig.width - 1.0,
        u * CapsuleDuiConfig.width)))
    local pixelY = math.floor(math.max(0.0, math.min(CapsuleDuiConfig.height - 1.0,
        v * CapsuleDuiConfig.height)))
    return pixelX, pixelY, inside
end

function CapsuleDui.Sync(value)
    stations = value or {}
    nearestStationId = nil
    nearestStation = nil
    if interacting and activeStation then
        for key, station in pairs(stations) do
            if tostring(station.id or key) == tostring(activeStation.id) then
                activeStation = station
                sendStation(station, 'openRental')
                break
            end
        end
    end
end

function CapsuleDui.Update(station)
    if not station then return end
    for key, value in pairs(stations) do
        if tostring(value.id or key) == tostring(station.id) then
            stations[key] = station
            if interacting and activeStation and tostring(activeStation.id) == tostring(station.id) then
                activeStation = station
                sendStation(station, 'openRental')
            elseif nearestStationId == tostring(station.id) then
                nearestStation = station
                sendStation(station, 'station')
            end
            return
        end
    end
end

function CapsuleDui.OpenRental(station)
    if interacting or not GetWorldCoordFromScreenCoord or not station or not ensureDui() then return false end
    local entity = terminalFor(station)
    if not entity then return false end
    activeStation = station
    terminalEntity = entity
    if not startFocusCamera(entity, station) then
        activeStation = nil
        terminalEntity = nil
        return false
    end
    interacting = true
    sendStation(station, 'openRental')
    SetNuiFocusKeepInput(false)
    SetNuiFocus(true, true)
    SetCursorLocation(0.5, 0.5)
    SendNUIMessage({ action = 'duiInput', enabled = true })
    return true
end

function CapsuleDui.CloseRental()
    if not interacting then return end
    interacting = false
    stopFocusCamera()
    terminalEntity = nil
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'duiInput', enabled = false })
    if activeStation then sendStation(activeStation, 'station') end
    activeStation = nil
    TriggerEvent('snipe-carrental:client:duiClosed')
end

function CapsuleDui.Pointer(data)
    if not interacting or not duiObject or not IsDuiAvailable(duiObject) then return false end
    local x, y, inside = cursorToDui()
    local eventType = type(data) == 'table' and data.type or nil
    if eventType == 'click' and inside then
        SendDuiMouseMove(duiObject, x, y)
        SendDuiMouseDown(duiObject, data.button or 'left')
        SendDuiMouseUp(duiObject, data.button or 'left')
        return true
    elseif eventType == 'down' and inside then
        SendDuiMouseMove(duiObject, x, y)
        SendDuiMouseDown(duiObject, data.button or 'left')
        return true
    elseif eventType == 'up' then
        SendDuiMouseUp(duiObject, data.button or 'left')
        return inside == true
    elseif eventType == 'wheel' and inside then
        SendDuiMouseMove(duiObject, x, y)
        SendDuiMouseWheel(duiObject, math.floor(number(data.deltaY)), math.floor(number(data.deltaX)))
        return true
    end
    return false
end

function CapsuleDui.IsOpen()
    return interacting
end

-- Re-apply the global texture replacement after a tablet entity is created.
-- This covers model streaming transitions without recreating the DUI browser.
function CapsuleDui.TerminalReady()
    if stopped then return false end
    CreateThread(function()
        -- Give the newly created drawable one frame to finish registering its
        -- material, then bind again without rebuilding the DUI page.
        Wait(0)
        if not stopped and sourceTextureLoaded then bindReplacement(true) end
    end)
    return true
end

function CapsuleDui.Destroy()
    stopped = true
    if interacting then CapsuleDui.CloseRental() end
    stations = {}
    if replacementBound then
        RemoveReplaceTexture(CapsuleDuiConfig.textureDictionary, CapsuleDuiConfig.textureName)
    end
    if duiObject then DestroyDui(duiObject) end
    duiObject, runtimeTxd, runtimeTexture = nil, nil, nil
    replacementBound = false
    if sourceTextureLoaded then
        SetStreamedTextureDictAsNoLongerNeeded(CapsuleDuiConfig.textureDictionary)
        sourceTextureLoaded = false
    end
end

CreateThread(function()
    Wait(500)
    ensureDui()
    while not stopped do
        if interacting then
            if focusedPed and DoesEntityExist(focusedPed) then SetEntityLocallyInvisible(focusedPed) end
            if not terminalEntity or not DoesEntityExist(terminalEntity) then
                CapsuleDui.CloseRental()
            else
                local distance = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(terminalEntity))
                if distance > CapsuleDuiConfig.maxInteractionDistance then
                    CapsuleDui.CloseRental()
                else
                    local x, y, inside = cursorToDui()
                    if x and y and inside and duiObject and IsDuiAvailable(duiObject) then
                        SendDuiMouseMove(duiObject, x, y)
                    elseif duiObject and IsDuiAvailable(duiObject) then
                        SendDuiMouseMove(duiObject, -100, -100)
                    end
                end
            end
            Wait(0)
        else
            local player = GetEntityCoords(PlayerPedId())
            local closest, closestDistance, closestId = nil, CapsuleDuiConfig.maxUpdateDistance + 1.0, nil
            for key, station in pairs(stations) do
                local pos = stationPosition(station)
                if pos then
                    local distance = #(player - pos)
                    if distance < closestDistance then
                        closest, closestDistance, closestId = station, distance, tostring(station.id or key)
                    end
                end
            end
            if closest and closestId ~= nearestStationId then
                -- Only cache the station after delivery succeeds. Otherwise a
                -- first-load DUI timeout would prevent this loop from retrying.
                if sendStation(closest, 'station') then
                    nearestStation, nearestStationId = closest, closestId
                end
            elseif not closest then
                nearestStation, nearestStationId = nil, nil
            end
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    if stoppedResource == resourceName then CapsuleDui.Destroy() end
end)
