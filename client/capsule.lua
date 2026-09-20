RentalCapsule = RentalCapsule or {}

local states = {}
local stopped = false

local function settings()
    return Config.CapsuleAnimation or {}
end

local function hiddenOffset()
    if RentalWorld and type(RentalWorld.getCapsuleModels) == 'function' then
        local models = RentalWorld.getCapsuleModels()
        if type(models) == 'table' and tonumber(models.retractedZ) then
            return tonumber(models.retractedZ)
        end
    end
    return tonumber(settings().hiddenOffset) or -3.5
end

local function stateFor(stationId)
    stationId = tostring(stationId or '')
    if stationId == '' then return nil end
    if not states[stationId] then
        states[stationId] = {
            stationId = stationId,
            phase = 'idle',
            canopyZ = hiddenOffset(),
            shellZ = hiddenOffset(),
            generation = 0,
        }
    end
    return states[stationId]
end

local function validAssembly(assembly)
    if type(assembly) ~= 'table' or assembly.cancelled or type(assembly.roles) ~= 'table' then return false end
    local canopy, shell = assembly.roles.canopy, assembly.roles.shell
    return canopy and shell and DoesEntityExist(canopy) and DoesEntityExist(shell)
end

local function waitForAssembly(stationId, timeout)
    if not RentalWorld or type(RentalWorld.getAssembly) ~= 'function' then return nil, 'capsule_api_missing' end
    local deadline = GetGameTimer() + (timeout or settings().assemblyTimeout or 6000)
    repeat
        if stopped then return nil, 'resource_stopping' end
        local assembly = RentalWorld.getAssembly(stationId)
        if validAssembly(assembly) then return assembly end
        Wait(50)
    until GetGameTimer() >= deadline
    return nil, 'capsule_not_streamed'
end

local function applyPose(state)
    if stopped or not RentalWorld or type(RentalWorld.setCapsulePose) ~= 'function' then return false end
    local ok, applied = pcall(RentalWorld.setCapsulePose, state.stationId, {
        canopyZ = state.canopyZ,
        shellZ = state.shellZ,
        canopyVisible = true,
        shellVisible = true,
        collision = false,
    })
    return ok and applied ~= false
end

local function ease(value)
    value = math.max(0.0, math.min(1.0, value))
    return value * value * (3.0 - 2.0 * value)
end

-- All moving pieces use one clock: rise, open, release, close, retract. Late
-- clients catch up from elapsed time instead of replaying stale stages.
local function poseAt(elapsed)
    local config = settings()
    local liftDuration = tonumber(config.liftDuration) or 3000
    local retractAt = tonumber(config.retractAt) or 11000
    local doorOpenAt = tonumber(config.doorOpenAt) or 3200
    local doorDuration = tonumber(config.doorDuration) or 1200
    local doorCloseAt = tonumber(config.doorCloseAt) or 9600
    local lift = ease(elapsed / liftDuration)
        * (1.0 - ease((elapsed - retractAt) / liftDuration))
    local door = ease((elapsed - doorOpenAt) / doorDuration)
        * (1.0 - ease((elapsed - doorCloseAt) / doorDuration))
    local hidden = hiddenOffset()
    local canopyZ = hidden * (1.0 - lift)
    local shellZ = canopyZ + hidden * door
    return canopyZ, shellZ
end

local function forceIdle(stationId)
    local state = stateFor(stationId)
    if not state then return end
    state.generation = state.generation + 1
    state.phase = 'idle'
    state.mode = nil
    state.operationId = nil
    state.anchor = nil
    state.canopyZ = hiddenOffset()
    state.shellZ = hiddenOffset()
    applyPose(state)
end

local function startCycle(stationId, operationId, mode, elapsed, requireAssembly)
    local state = stateFor(stationId)
    if not state then return nil, 'invalid_station' end
    if mode ~= 'delivery' and mode ~= 'return' then return nil, 'invalid_cycle' end
    if requireAssembly then
        local _, reason = waitForAssembly(state.stationId)
        if reason then return nil, reason end
    end
    state.generation = state.generation + 1
    state.phase = mode
    state.mode = mode
    state.operationId = tostring(operationId or '')
    state.anchor = GetGameTimer() - math.max(0, tonumber(elapsed) or 0)
    state.canopyZ, state.shellZ = poseAt(GetGameTimer() - state.anchor)
    applyPose(state)
    return {
        state = state,
        generation = state.generation,
        operationId = state.operationId,
        mode = mode,
    }
end

local function owns(handle)
    return type(handle) == 'table' and handle.state
        and handle.state.generation == handle.generation
        and handle.state.mode == handle.mode
end

function RentalCapsule.BeginDelivery(stationId, operationId, elapsed)
    return startCycle(stationId, operationId, 'delivery', elapsed, true)
end

function RentalCapsule.BeginReturn(stationId, operationId, elapsed)
    return startCycle(stationId, operationId, 'return', elapsed, true)
end

function RentalCapsule.WaitUntil(handle, targetMs, timeoutMs)
    if not owns(handle) then return false, 'invalid_operation' end
    targetMs = math.max(0, tonumber(targetMs) or 0)
    local deadline = GetGameTimer() + (timeoutMs or targetMs + 3000)
    while not stopped and owns(handle) and GetGameTimer() < deadline do
        if GetGameTimer() - handle.state.anchor >= targetMs then return true end
        Wait(0)
    end
    if owns(handle) and GetGameTimer() - handle.state.anchor >= targetMs then return true end
    return false, owns(handle) and 'animation_timeout' or 'animation_cancelled'
end

function RentalCapsule.GetElapsed(handle)
    if not owns(handle) then return nil, 'invalid_operation' end
    return math.max(0, GetGameTimer() - handle.state.anchor)
end

function RentalCapsule.AbortDelivery(handle)
    if handle and handle.state then forceIdle(handle.state.stationId) end
end

function RentalCapsule.AbortReturn(handle)
    if handle and handle.state then forceIdle(handle.state.stationId) end
end

-- The shared clock owns completion so the structure can finish retracting.
function RentalCapsule.CompleteReturn(_) end

function RentalCapsule.SetIdle(stationId)
    forceIdle(stationId)
end

function RentalCapsule.SetOpen(stationId)
    forceIdle(stationId)
end

function RentalCapsule.Sync(snapshot)
    if type(snapshot) ~= 'table' then return end
    for stationId, value in pairs(snapshot) do
        local phase = type(value) == 'table' and value.phase or value
        local operationId = type(value) == 'table' and value.operationId or nil
        local elapsed = type(value) == 'table' and value.elapsed or 0
        if phase == 'delivery' or phase == 'return' then
            startCycle(stationId, operationId, phase, elapsed, false)
        else
            forceIdle(stationId)
        end
    end
end

function RentalCapsule.HandleCommand(command)
    if type(command) ~= 'table' or not command.stationId or not command.phase then return end
    if command.phase == 'delivery' or command.phase == 'return' then
        startCycle(command.stationId, command.operationId, command.phase, command.elapsed, false)
    elseif command.phase == 'idle' or command.phase == 'reserved' then
        forceIdle(command.stationId)
    end
end

function RentalCapsule.GetState(stationId)
    return stateFor(stationId)
end

CreateThread(function()
    while not stopped do
        local active = false
        local now = GetGameTimer()
        for _, state in pairs(states) do
            if state.mode and state.anchor then
                active = true
                local elapsed = math.max(0, now - state.anchor)
                local duration = tonumber(settings().duration) or 14000
                if elapsed >= duration then
                    forceIdle(state.stationId)
                else
                    state.canopyZ, state.shellZ = poseAt(elapsed)
                    applyPose(state)
                end
            else
                applyPose(state)
            end
        end
        Wait(active and 0 or 250)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    stopped = true
    for _, state in pairs(states) do state.generation = state.generation + 1 end
end)

RegisterNetEvent('snipe-carrental:client:capsuleCommand', function(command)
    RentalCapsule.HandleCommand(command)
end)

AddStateBagChangeHandler('snipeRentalCapsuleHidden', nil, function(bagName, _, hidden)
    CreateThread(function()
        local deadline = GetGameTimer() + 2500
        local entity = GetEntityFromStateBagName(bagName)
        while (not entity or entity == 0 or not DoesEntityExist(entity)) and GetGameTimer() < deadline do
            Wait(25)
            entity = GetEntityFromStateBagName(bagName)
        end
        if not entity or entity == 0 or not DoesEntityExist(entity) then return end
        if Entity(entity).state.snipeRentalCapsuleHidden ~= hidden then return end
        if hidden then
            SetEntityVisible(entity, false, false)
            SetEntityAlpha(entity, 0, false)
            SetEntityCollision(entity, false, false)
        else
            SetEntityVisible(entity, true, false)
            ResetEntityAlpha(entity)
            SetEntityCollision(entity, true, true)
        end
    end)
end)
