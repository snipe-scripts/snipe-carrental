RentalWorld = {}

local stations, assemblies = {}, {}
local stopped = false
local maxDistance = 85.0
local warnedModels = {}
local models = {
    tablet = 'snipe_capsule_tablet_v1',
    platform = 'snipe_capsule_deck_v2', canopy = 'snipe_capsule_canopy_v2', shell = 'snipe_capsule_shell_v2',
}
local capsuleOffsets = { raised = 0.0, retracted = -3.50 }
local palette = {
    {255,255,255}, {255,32,32}, {255,112,24}, {255,224,32},
    {128,255,32}, {32,255,72}, {24,255,176}, {24,240,255},
    {64,176,255}, {48,72,255}, {144,48,255}, {240,32,255},
    {255,48,144}, {255,214,170}, {190,220,255}, {8,8,12},
}

local function position(value)
    if not value then return nil end
    return { x = tonumber(value.x) or 0.0, y = tonumber(value.y) or 0.0,
        z = tonumber(value.z) or 0.0, w = tonumber(value.w or value.heading) or 0.0 }
end

function RentalWorld.platform(station)
    return position(station.platform or station.spawn)
end

function RentalWorld.offset(origin, x, y, z)
    local angle = math.rad(origin.w or origin.heading or 0.0)
    return vector3(origin.x + x * math.cos(angle) - y * math.sin(angle),
        origin.y + x * math.sin(angle) + y * math.cos(angle), origin.z + z)
end

function RentalWorld.color(value)
    if type(value) == 'table' then return value.r or 0, value.g or 215, value.b or 200 end
    local hex = tostring(value or '#00d7c8'):gsub('#', '')
    if not hex:match('^%x%x%x%x%x%x$') then hex = '00d7c8' end
    return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

function RentalWorld.loadModel(model, timeout)
    if type(model) ~= 'string' and type(model) ~= 'number' then return nil, 'invalid_model' end
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil, 'not_streamed' end
    RequestModel(hash)
    local deadline = GetGameTimer() + (timeout or 5000)
    while not HasModelLoaded(hash) do
        if stopped then return nil, 'resource_stopping' end
        if GetGameTimer() > deadline then return nil, 'load_timeout' end
        Wait(0)
    end
    return hash
end

function RentalWorld.colorIndex(value)
    local r, g, b = RentalWorld.color(value)
    local closest, best = 0, math.huge
    for index, color in ipairs(palette) do
        local distance = (r - color[1]) ^ 2 + (g - color[2]) ^ 2 + (b - color[3]) ^ 2
        if distance < best then best, closest = distance, index - 1 end
    end
    return closest
end

local function makeObject(model, origin, x, y, z, rotation, preview)
    local hash, reason = RentalWorld.loadModel(model)
    if not hash then return nil, reason end
    local location = RentalWorld.offset(origin, x, y, z)
    local entity = CreateObjectNoOffset(hash, location.x, location.y, location.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if entity == 0 then return nil, 'create_failed' end
    SetEntityHeading(entity, (origin.w or 0) + (rotation or 0))
    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true)
    if preview then SetEntityCollision(entity, false, false) SetEntityAlpha(entity, 210, false) end
    return entity
end

local function recordFailure(assembly, role, model, reason)
    assembly.errors[#assembly.errors + 1] = { role = role, model = model, reason = reason or 'unknown' }
    local key = ('%s:%s'):format(model, reason or 'unknown')
    if warnedModels[key] then return end
    warnedModels[key] = true
    print(('[%s] Could not create %s prop %s (%s). Restart the resource after adding streamed assets.'):format(
        GetCurrentResourceName(), role, model, reason or 'unknown'))
end

function RentalWorld.destroy(assembly)
    if not assembly then return end
    assembly.cancelled = true
    for _, entity in ipairs(assembly.entities or {}) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
    assembly.entities = {}
end

function RentalWorld.create(station, preview)
    local assembly = { entities = {}, roles = {}, errors = {}, station = station, preview = preview,
        pose = { canopyZ = preview and 0.0 or capsuleOffsets.retracted,
            shellZ = preview and 0.0 or capsuleOffsets.retracted,
            canopyVisible = true, shellVisible = true } }
    local origin = position(station.coords)
    if origin then
        local entity, reason = makeObject(models.tablet, origin, 0, 0, 0, 0, preview)
        if entity then
            assembly.entities[#assembly.entities + 1] = entity
            assembly.roles.coords = entity
            SetObjectTextureVariation(entity, RentalWorld.colorIndex(station.color))
            if CapsuleDui and CapsuleDui.TerminalReady then CapsuleDui.TerminalReady() end
        else
            recordFailure(assembly, 'terminal', models.tablet, reason)
        end
    end
    local platform = RentalWorld.platform(station)
    if platform then
        for _, role in ipairs({ 'platform', 'canopy', 'shell' }) do
            local offsetZ = role == 'canopy' and assembly.pose.canopyZ
                or role == 'shell' and assembly.pose.shellZ or 0.0
            local entity, reason = makeObject(models[role], platform, 0, 0, offsetZ, 0, preview)
            if entity then
                assembly.entities[#assembly.entities + 1] = entity
                assembly.roles[role] = entity
                SetObjectTextureVariation(entity, RentalWorld.colorIndex(station.color))
                if role ~= 'platform' then
                    -- These animated models intentionally have no embedded bound.
                    SetEntityCollision(entity, false, false)
                end
            else
                recordFailure(assembly, role, models[role], reason)
            end
        end
    end
    return assembly
end

function RentalWorld.moveAssembly(assembly, station)
    if not assembly or assembly.cancelled then return end
    assembly.station = station
    for role, entity in pairs(assembly.roles or {}) do
        local point = role == 'coords' and position(station.coords) or RentalWorld.platform(station)
        if point and DoesEntityExist(entity) then
            local pose = assembly.pose or {}
            local offsetZ = role == 'canopy' and (pose.canopyZ or 0.0) or role == 'shell' and (pose.shellZ or 0.0) or 0.0
            SetEntityCoordsNoOffset(entity, point.x, point.y, point.z + offsetZ, false, false, false)
            SetEntityHeading(entity, point.w)
            SetObjectTextureVariation(entity, RentalWorld.colorIndex(station.color))
        end
    end
end

function RentalWorld.getAssembly(stationId)
    if type(stationId) == 'table' then
        if stationId.roles then return stationId end
        stationId = stationId.id
    end
    return assemblies[tostring(stationId)]
end

function RentalWorld.getCapsuleModels()
    return { deck = models.platform, canopy = models.canopy, shell = models.shell,
        raisedZ = capsuleOffsets.raised, retractedZ = capsuleOffsets.retracted }
end

-- Lifecycle code interpolates these two offsets independently. Deck/kiosk never move.
-- Collision cannot be enabled on moving parts: the YDRs have no collision bound.
function RentalWorld.setCapsulePose(stationIdOrAssembly, value)
    local assembly = RentalWorld.getAssembly(stationIdOrAssembly)
    if not assembly or assembly.cancelled or type(value) ~= 'table' then return false end
    assembly.pose = assembly.pose or {}
    for _, role in ipairs({ 'canopy', 'shell' }) do
        local key = role .. 'Z'
        if type(value[key]) == 'number' then assembly.pose[key] = value[key] end
        local visibleKey = role .. 'Visible'
        if type(value[visibleKey]) == 'boolean' then assembly.pose[visibleKey] = value[visibleKey] end
        local entity = assembly.roles[role]
        if entity and DoesEntityExist(entity) then
            SetEntityVisible(entity, assembly.pose[visibleKey] ~= false, false)
            SetEntityCollision(entity, false, false)
        end
    end
    RentalWorld.moveAssembly(assembly, assembly.station)
    return assembly.roles.canopy ~= nil and assembly.roles.shell ~= nil
end

function RentalWorld.drawText(location, text, scale)
    local visible, x, y = World3dToScreen2d(location.x, location.y, location.z)
    if not visible then return end
    SetTextScale(0.0, scale or 0.27)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(235, 249, 249, 230)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(tostring(text):sub(1, 90))
    EndTextCommandDisplayText(x, y)
end

function RentalWorld.draw(station, preview)
    -- Geometry/collision comes from streamed YDRs. Only local illumination is drawn.
    local origin = RentalWorld.platform(station)
    if not origin or preview then return end
    local r, g, b = RentalWorld.color(station.color)
    local light = RentalWorld.offset(origin, 0, 0, 2.8)
    DrawLightWithRange(light.x, light.y, light.z, r, g, b, 5.0, 0.55)
end

local function sameLocation(first, second)
    first, second = position(first), position(second)
    if not first or not second then return first == nil and second == nil end
    return math.abs(first.x - second.x) < 0.0001
        and math.abs(first.y - second.y) < 0.0001
        and math.abs(first.z - second.z) < 0.0001
        and math.abs(first.w - second.w) < 0.0001
end

function RentalWorld.setStations(value)
    local nextStations = value or {}
    local byId = {}
    for _, station in pairs(nextStations) do
        if station.id ~= nil then byId[tostring(station.id)] = station end
    end

    -- Bootstrap/rental refreshes replace Lua station tables, but the streamed
    -- world entities must keep their handles. Reconcile presentation in place;
    -- rebuilding here caused visible delete/recreate flashes during every cycle.
    for key, assembly in pairs(assemblies) do
        local station = byId[key]
        if not station then
            RentalWorld.destroy(assembly)
            assemblies[key] = nil
        elseif assembly.station and assembly.station.variant ~= station.variant then
            -- A terminal model change is the only normal update that requires a
            -- new assembly. Position, heading, color and capsule pose do not.
            RentalWorld.destroy(assembly)
            assemblies[key] = nil
        else
            local previous = assembly.station
            local presentationChanged = not previous
                or previous.color ~= station.color
                or not sameLocation(previous.coords, station.coords)
                or not sameLocation(previous.platform or previous.spawn, station.platform or station.spawn)
            assembly.station = station
            if presentationChanged then RentalWorld.moveAssembly(assembly, station) end
        end
    end

    stations = nextStations
end

local function currentStation(key)
    for _, station in pairs(stations) do
        if tostring(station.id) == key then return station end
    end
end

CreateThread(function()
    while not stopped do
        local pedCoords = GetEntityCoords(PlayerPedId())
        for _, station in pairs(stations) do
            local origin = position(station.coords)
            if origin then
                local near = #(pedCoords - vector3(origin.x, origin.y, origin.z)) < maxDistance
                local key = tostring(station.id)
                if near and not assemblies[key] then
                    local assembly = RentalWorld.create(station)
                    -- Model requests yield. Accept the assembly for the current
                    -- record with the same ID instead of relying on table identity.
                    local current = currentStation(key)
                    if current and current.variant == station.variant and not assemblies[key] then
                        assembly.station = current
                        RentalWorld.moveAssembly(assembly, current)
                        assemblies[key] = assembly
                    else
                        RentalWorld.destroy(assembly)
                    end
                elseif not near and assemblies[key] then
                    RentalWorld.destroy(assemblies[key])
                    assemblies[key] = nil
                end
            end
        end
        Wait(1000)
    end
end)

CreateThread(function()
    while not stopped do
        local delay = 500
        for _, assembly in pairs(assemblies) do
            delay = 0
            RentalWorld.draw(assembly.station, false)
        end
        Wait(delay)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    stopped = true
    for _, assembly in pairs(assemblies) do RentalWorld.destroy(assembly) end
    assemblies = {}
end)
