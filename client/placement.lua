RentalPlacement = {}
local active, generation = nil, 0

local function clone(value)
    return json.decode(json.encode(value))
end

local function cameraTarget()
    local camera, rotation = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local cosine = math.abs(math.cos(pitch))
    local direction = vector3(-math.sin(yaw) * cosine, math.cos(yaw) * cosine, math.sin(pitch))
    local destination = camera + direction * 25.0
    local ray = StartShapeTestRay(camera.x, camera.y, camera.z, destination.x, destination.y, destination.z, 1, PlayerPedId(), 0)
    local result, hit, location
    repeat result, hit, location = GetShapeTestResult(ray) Wait(0) until result ~= 1
    if hit == 1 or hit == true then return location end
    local player = GetEntityCoords(PlayerPedId())
    return vector3(player.x + direction.x * 4.0, player.y + direction.y * 4.0, player.z - 1.0)
end

function RentalPlacement.isActive()
    return active ~= nil
end

function RentalPlacement.cancel()
    generation = generation + 1
    if not active then return end
    local state = active
    active = nil
    RentalWorld.destroy(state.assembly)
    lib.hideTextUI()
    if state.callback then state.callback(nil) end
end

-- The UI releases focus before placement and leaves focus in the game after confirmation.
-- kind='coords'/'kiosk' places the kiosk; kind='platform'/'spawn' places the bay.
function RentalPlacement.start(kind, station, onComplete)
    RentalPlacement.cancel()
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    local value = clone(station or {})
    value.variant = 'tablet'
    value.color = value.color or '#00d7c8'
    local player = GetEntityCoords(PlayerPedId())
    local field = (kind == 'platform' or kind == 'spawn') and 'platform' or 'coords'
    if field == 'platform' then
        value.platform = value.platform or value.spawn or { x = player.x, y = player.y, z = player.z - 1, w = GetEntityHeading(PlayerPedId()) }
    else
        value.coords = value.coords or { x = player.x, y = player.y, z = player.z - 1, w = GetEntityHeading(PlayerPedId()) }
    end
    local state = { station = value, field = field, callback = onComplete, heading = value[field].w or value[field].heading or 0, elevation = 0 }
    active = state
    local token = generation
    lib.showTextUI('[E] Place  ·  [Esc] Cancel  ·  [← / →] Rotate  ·  [↑ / ↓] Height', { position = 'top-center' })
    CreateThread(function()
        state.assembly = RentalWorld.create(value, true)
        if active ~= state or token ~= generation then RentalWorld.destroy(state.assembly) return end
        if not state.assembly.roles[field] then
            active = nil
            RentalWorld.destroy(state.assembly)
            lib.hideTextUI()
            RentalClient.Notify(('The custom %s model is not available. Restart snipe-carrental and reconnect so its streamed assets load.'):format(
                field == 'platform' and 'capsule platform' or 'rental terminal'), 'error')
            if onComplete then onComplete(nil, nil, 'model_unavailable') end
            return
        end
        while active == state do
            if IsNuiFocused() then
                SetNuiFocusKeepInput(false)
                SetNuiFocus(false, false)
            end
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 201, true)
            DisableControlAction(0, 202, true)
            DisableControlAction(0, 38, true)
            DisableControlAction(0, 174, true)
            DisableControlAction(0, 175, true)
            DisableControlAction(0, 172, true)
            DisableControlAction(0, 173, true)
            local speed = IsControlPressed(0, 21) and 90.0 or 30.0
            if IsDisabledControlPressed(0, 174) then state.heading = state.heading + speed * GetFrameTime() end
            if IsDisabledControlPressed(0, 175) then state.heading = state.heading - speed * GetFrameTime() end
            if IsDisabledControlPressed(0, 172) then state.elevation = state.elevation + 0.5 * GetFrameTime() end
            if IsDisabledControlPressed(0, 173) then state.elevation = state.elevation - 0.5 * GetFrameTime() end
            local point = cameraTarget()
            if active ~= state then break end
            value[field] = { x = point.x, y = point.y, z = point.z + state.elevation, w = state.heading % 360 }
            RentalWorld.moveAssembly(state.assembly, value)
            RentalWorld.draw(value, true)
            DrawMarker(28, point.x, point.y, point.z + state.elevation + 0.1, 0, 0, 0, 0, 0, 0,
                0.08, 0.08, 0.08, 0, 215, 200, 210, false, false, 2, false, nil, nil, false)
            if IsDisabledControlJustPressed(0, 38) then
                active = nil
                lib.hideTextUI()
                if onComplete then onComplete(value, state.assembly) end
            elseif IsDisabledControlJustPressed(0, 202) or IsDisabledControlJustPressed(0, 200) then
                RentalPlacement.cancel()
            end
            Wait(0)
        end
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then RentalPlacement.cancel() end
end)
