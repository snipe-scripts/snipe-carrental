RentalBridge = RentalBridge or {}

local framework
local standaloneBalances = {}

local function resolveFramework()
    if Config.Framework ~= 'auto' then return Config.Framework end
    if GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if GetResourceState('qb-core') == 'started' then return 'qb' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'standalone'
end

local function qbPlayer(source)
    if framework == 'qbx' then return exports.qbx_core:GetPlayer(source) end
    if framework == 'qb' then return exports['qb-core']:GetCoreObject().Functions.GetPlayer(source) end
end

local function esxPlayer(source)
    return exports.es_extended:getSharedObject().GetPlayerFromId(source)
end

local function getStandalone(source)
    if not standaloneBalances[source] then
        standaloneBalances[source] = {
            cash = Config.Standalone.startingCash,
            bank = Config.Standalone.startingBank,
        }
    end
    return standaloneBalances[source]
end

function RentalBridge.init()
    framework = resolveFramework()
    print(('[%s] Framework bridge: %s'):format(GetCurrentResourceName(), framework))
end

function RentalBridge.name()
    return framework
end

function RentalBridge.getIdentifier(source)
    if framework == 'qbx' or framework == 'qb' then
        local player = qbPlayer(source)
        return player and player.PlayerData and player.PlayerData.citizenid
    elseif framework == 'esx' then
        local player = esxPlayer(source)
        return player and player.identifier
    end

    return GetPlayerIdentifierByType(source, 'license') or GetPlayerIdentifier(source, 0)
end

function RentalBridge.removeMoney(source, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount < 0 then return false end

    if framework == 'qbx' or framework == 'qb' then
        local player = qbPlayer(source)
        return player and player.Functions.RemoveMoney(account, amount, reason) == true
    elseif framework == 'esx' then
        local player = esxPlayer(source)
        if not player then return false end
        if account == 'cash' then
            if player.getMoney() < amount then return false end
            player.removeMoney(amount, reason)
        else
            local balance = player.getAccount(account)
            if not balance or balance.money < amount then return false end
            player.removeAccountMoney(account, amount, reason)
        end
        return true
    elseif Config.Standalone.enabled then
        local balances = getStandalone(source)
        if not balances[account] or balances[account] < amount then return false end
        balances[account] = balances[account] - amount
        return true
    end

    return false
end

function RentalBridge.addMoney(source, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end

    if framework == 'qbx' or framework == 'qb' then
        local player = qbPlayer(source)
        return player and player.Functions.AddMoney(account, amount, reason) == true
    elseif framework == 'esx' then
        local player = esxPlayer(source)
        if not player then return false end
        if account == 'cash' then
            player.addMoney(amount, reason)
        else
            player.addAccountMoney(account, amount, reason)
        end
        return true
    elseif Config.Standalone.enabled then
        local balances = getStandalone(source)
        balances[account] = (balances[account] or 0) + amount
        return true
    end

    return false
end

function RentalBridge.isAdmin(source)
    if source == 0 then return true end
    if Config.AdminAce and IsPlayerAceAllowed(tostring(source), Config.AdminAce) then return true end

    if framework == 'qbx' then
        local ok, allowed = pcall(function()
            return exports.qbx_core:HasPermission(source, Config.AdminGroups)
        end)
        if ok and allowed then return true end
    elseif framework == 'qb' then
        local core = exports['qb-core']:GetCoreObject()
        if core.Functions.HasPermission(source, Config.AdminGroups) then return true end
    elseif framework == 'esx' then
        local player = esxPlayer(source)
        local group = player and player.getGroup and player.getGroup()
        for i = 1, #Config.AdminGroups do
            if group == Config.AdminGroups[i] then return true end
        end
    end

    return false
end

AddEventHandler('playerDropped', function()
    standaloneBalances[source] = nil
end)
