-- SUSANO MENU < mx > discord.gg/

-- OPRAVENO: Odkaz nyní směřuje na skutečnou knihovnu (ui library), nikoliv sám na sebe
local LibraryURL = "https://raw.githubusercontent.com/Hvfhsksldkfhf/andrasovcemenu/refs/heads/main/menu.lua"


if not Susano or type(Susano) ~= "table" or type(Susano.HttpGet) ~= "function" then
    print("Error: Susano.HttpGet is not available")
    return
end

local status, LibraryCode = Susano.HttpGet(LibraryURL)

if status ~= 200 then
    return
end

if not string.find(LibraryCode, "Menu.OnRender") then
    LibraryCode = string.gsub(LibraryCode, "if Susano%.SubmitFrame then", [[
    if Menu.OnRender then
        local success, err = pcall(Menu.OnRender)
        if not success then end
    end
    if Susano.SubmitFrame then]])
end

if string.find(LibraryCode, "Susano%.ResetFrame") then
    LibraryCode = string.gsub(LibraryCode, "if Susano.ResetFrame and not Menu.PreventResetFrame then", "if Susano.ResetFrame and not Menu.PreventResetFrame then")
end

local chunk, err = load(LibraryCode)
if not chunk then
    print("Error loading library.lua: " .. tostring(err))
    print("Code received (first 100 chars): " .. string.sub(tostring(LibraryCode), 1, 100))
    return
end
local Menu = chunk()

local MAX_RAY_DISTANCE = 1000.0


local function RotationToDirection(rotation)
    local adjustedRotation = vector3((math.pi / 180) * rotation.x, (math.pi / 180) * rotation.y, (math.pi / 180) * rotation.z)
    local direction = vector3(-math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
                              math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
                              math.sin(adjustedRotation.x))
    return direction
end

local function getVehicleFromAim()
    local ped = PlayerPedId()
    local camCoords = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local direction = RotationToDirection(camRot)
    local endCoords = camCoords + direction * MAX_RAY_DISTANCE

    local ray = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z,
                                  endCoords.x, endCoords.y, endCoords.z,
                                  -1, ped, 4)
    local _, hit, _, _, entity = GetShapeTestResult(ray)
    if hit == 1 and DoesEntityExist(entity) and GetEntityType(entity) == 2 then
        return entity
    end
    return nil
end

local function getAimCoords(maxDist)
    local ped = PlayerPedId()
    local camCoords = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local direction = RotationToDirection(camRot)
    local endCoords = camCoords + direction * maxDist

    local ray = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z,
                                  endCoords.x, endCoords.y, endCoords.z,
                                  -1, ped, 0)
    local _, hit, coords, _, entity = GetShapeTestResult(ray)
    if hit == 1 then
        return coords, entity
    end
    return endCoords, nil
end

local function drawText(text, x, y, scale, font, color)
    if not Susano or not Susano.DrawText then return end
    local r, g, b, a = color[1], color[2], color[3], color[4] or 255
    Susano.DrawText(x, y, text, scale, r/255, g/255, b/255, a/255)
end

local function getTeleportPosForVehicle(veh)
    if not veh or not DoesEntityExist(veh) then return GetEntityCoords(PlayerPedId()) end
    local coords = GetEntityCoords(veh)
    return coords + vector3(0.0, 0.0, 2.0)
end

local function RequestControl(entity, timeoutMs)
    if not entity or not DoesEntityExist(entity) then return false end
    local start = GetGameTimer()
    NetworkRequestControlOfEntity(entity)
    while not NetworkHasControlOfEntity(entity) do
        Wait(0)
        if GetGameTimer() - start > (timeoutMs or 500) then
            return false
        end
        NetworkRequestControlOfEntity(entity)
    end
    return true
end

local function forcePedOutLocal(ped, vehicle)
    if not DoesEntityExist(ped) or not DoesEntityExist(vehicle) then return end
    
    if RequestControl(ped, 500) then
        
        ClearPedTasksImmediately(ped)
        TaskLeaveVehicle(ped, vehicle, 16) -- 16 = leave instantly
        
        local coords = GetEntityCoords(vehicle)
        SetEntityCoords(ped, coords.x, coords.y, coords.z + 2.0, false, false, false, false)
    end
end

local Bypass = {}

local function hookNativeSafe(nativeHash, callback)
    pcall(function()
        Susano.UnhookNative(nativeHash)
        Susano.HookNative(nativeHash, callback)
    end)
end

local function getResources()
    local res = {}
    for i=0,GetNumResources()-1 do
        local r = GetResourceByFindIndex(i)
        if r and GetResourceState(r)=="started" then
            res[#res+1] = r
        end
    end
    return res
end

function Bypass.ReaperV4(resource)
    local reaper_natives = {
        [0x5A4F9EDF1670F7F4] = function() return false end,
        [0x5B4F04F9DB4F7A1C] = function() return true end,
        [0x7E2F3E6D9F5C8B1A] = function() return 0 end,
    }
    for hash, cb in pairs(reaper_natives) do
        hookNativeSafe(hash, function(orig, ...) return cb() end)
    end
    local orgTrigger = TriggerServerEvent
    TriggerServerEvent = function(event, ...)
        if event and event:find("reaper_heartbeat") then return end
        return orgTrigger(event, ...)
    end
    Susano.InjectResource(resource, [[
        local ac = debug.getregistry().AC or _G.AC or {}
        for k,v in pairs(ac) do
            if type(v)=="table" then
                for x,y in pairs(v) do
                    if type(y)=="function" then
                        v[x] = function() return true end
                    end
                end
            end
        end
        local state = GlobalState or {}
        for k,v in pairs(state) do
            if tostring(k):find("reaper") then
                state[k] = nil
            end
        end
    ]])
    print("^2[Bypass] ReaperV4 neutralized")
end

function Bypass.Fiveguard(resource)
    Susano.InjectResource(resource, [[
        local handlers = debug.getregistry()._HANDLERS or _G._HANDLors or {}
        for evt, tbl in pairs(handlers) do
            if tostring(evt):find("Fiveguard") then
                for i=#tbl,1,-1 do
                    tbl[i] = function() return true end
                end
            end
        end
        local fg = _G.Fiveguard or _G.FG
        if fg then
            fg.Detection = function() return end
            fg.Trigger = function() return end
        end
        for i=1,100 do
            local t = _G["timer_"..i]
            if t and type(t)=="table" and t.stop then
                pcall(t.stop, t)
            end
        end
    ]])
    print("^2[Bypass] Fiveguard disabled")
end

function Bypass.ElectronAC(resource)
    local electron_natives = {
        [0xE37B2A6B9B9D1F0C] = function() return 0 end,
        [0x5A4F9EDF1670F7F4] = function() return false end,
    }
    for hash, cb in pairs(electron_natives) do
        hookNativeSafe(hash, function(orig, ...) return cb() end)
    end
    local orgTriggerLatent = TriggerLatentServerEvent
    TriggerLatentServerEvent = function(event, ...)
        if event and (event:find("electron") or event:find("ac")) then return end
        return orgTriggerLatent(event, ...)
    end
    print("^2[Bypass] ElectronAC bypassed")
end

function Bypass.EagleAC(resource)
    Susano.InjectResource(resource, [[
        local eagle = _G.Eagle or _G.EC_AC
        if eagle then
            for k,v in pairs(eagle) do
                if type(v)=="function" then
                    local info = debug.getinfo(v)
                    if info and info.name and info.name:find("detect") then
                        eagle[k] = function() return false end
                    end
                end
            end
        end
        TriggerEvent = function(evt, ...)
            if tostring(evt):find("eagle") or tostring(evt):find("EC_") then return end
            return _G._originalTriggerEvent(evt, ...)
        end
    ]])
    print("^2[Bypass] EagleAC evaded")
end

function Bypass.CyberAnticheat(resource)
    Susano.InjectResource(resource, [[
        local cyber = _G.CyberAnticheat or _G.Cyber
        if cyber then
            cyber.banPlayer = function() return end
            cyber.kickPlayer = function() return end
            cyber.detection = function() return end
        end
        local orgNet = NetworkSessionEnd
        NetworkSessionEnd = function(...) return end
    ]])
    local orgTrigger = TriggerServerEvent
    TriggerServerEvent = function(event, ...)
        if event and (event:find("Cyber") or event:find("ban") or event:find("kick")) then
            return
        end
        return orgTrigger(event, ...)
    end
    print("^2[Bypass] Cyber Anticheat nullified")
end

function Bypass.WaveShield(resource)
    local orgGet = GetStateBagValue
    GetStateBagValue = function(bag, key)
        if bag=="global" and key and tostring(key):find("Wave") then
            return nil
        end
        return orgGet(bag, key)
    end
    Susano.InjectResource(resource, [[
        local ws = _G.WaveShield or _G.WS
        if ws then
            ws.Config = {}
            ws.Entities = {}
            ws.Detections = {}
        end
    ]])
    print("^2[Bypass] WaveShield blinded")
end

local function LoadBypasses()
    if not Susano then return end
    local resources = getResources()
    for _, res in ipairs(resources) do
        local author = GetResourceMetadata(res, "author", 0) or ""
        local desc = GetResourceMetadata(res, "description", 0) or ""
        if author:find("reaper") or res:find("reaper") then
            Bypass.ReaperV4(res)
        end
        if author:find("Fiveguard") or res:find("fg") then
            Bypass.Fiveguard(res)
        end
        if author:find("Electron") or res:find("electron") then
            Bypass.ElectronAC(res)
        end
        if res:find("EC_AC") or desc:find("Eagle") then
            Bypass.EagleAC(res)
        end
        if res:find("Cyber") or author:find("Cyber") then
            Bypass.CyberAnticheat(res)
        end
        if author:find("WaveShield") then
            Bypass.WaveShield(res)
        end
    end

    print("^2[Bypass] All known anti-cheats have been bypassed")
end

function Menu.ActionBugPlayer()
    if not Menu.SelectedPlayer then return end
    
    local targetServerId = Menu.SelectedPlayer
    local mode = Menu.BugPlayerMode or "Bug"
    
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = ""
        
        if mode == "Bug" then
            code = string.format([[
                CreateThread(function()
                    local targetServerId = %d
                    local targetPlayerId = nil
                    for _, player in ipairs(GetActivePlayers()) do
                        if GetPlayerServerId(player) == targetServerId then
                            targetPlayerId = player
                            break
                        end
                    end
                    if not targetPlayerId then return end
                    
                    local targetPed = GetPlayerPed(targetPlayerId)
                    if not DoesEntityExist(targetPed) then return end
                    
                  
                    for i = 1, 50 do
                        if DoesEntityExist(targetPed) then
                            SetEntityCollision(targetPed, false, false)
                            SetEntityVisible(targetPed, false, false)
                            SetEntityAlpha(targetPed, 0)
                            Wait(10)
                            SetEntityCollision(targetPed, true, true)
                            SetEntityVisible(targetPed, true, false)
                            SetEntityAlpha(targetPed, 255)
                            Wait(10)
                        end
                    end
                end)
            ]], targetServerId)
        elseif mode == "Launch" then
            code = string.format([[
                CreateThread(function()
                    local targetServerId = %d
                    local targetPlayerId = nil
                    for _, player in ipairs(GetActivePlayers()) do
                        if GetPlayerServerId(player) == targetServerId then
                            targetPlayerId = player
                            break
                        end
                    end
                    if not targetPlayerId then return end
                    
                    local targetPed = GetPlayerPed(targetPlayerId)
                    if not DoesEntityExist(targetPed) then return end
                    
                    local coords = GetEntityCoords(targetPed)
                    SetEntityCoords(targetPed, coords.x, coords.y, coords.z + 1000.0, false, false, false, false)
                    ApplyForceToEntity(targetPed, 1, 0.0, 0.0, 10000.0, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
                end)
            ]], targetServerId)
        elseif mode == "Hard Launch" then
            code = string.format([[
                CreateThread(function()
                    local targetServerId = %d
                    local targetPlayerId = nil
                    for _, player in ipairs(GetActivePlayers()) do
                        if GetPlayerServerId(player) == targetServerId then
                            targetPlayerId = player
                            break
                        end
                    end
                    if not targetPlayerId then return end
                    
                    local targetPed = GetPlayerPed(targetPlayerId)
                    if not DoesEntityExist(targetPed) then return end
                    
                   
                    for i = 1, 10 do
                        ApplyForceToEntity(targetPed, 1, 0.0, 0.0, 50000.0, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
                        SetEntityVelocity(targetPed, 0.0, 0.0, 1000.0)
                        Wait(10)
                    end
                end)
            ]], targetServerId)
        elseif mode == "Attach" then
            code = string.format([[
                CreateThread(function()
                    local targetServerId = %d
                    local targetPlayerId = nil
                    for _, player in ipairs(GetActivePlayers()) do
                        if GetPlayerServerId(player) == targetServerId then
                            targetPlayerId = player
                            break
                        end
                    end
                    if not targetPlayerId then return end
                    
                    local targetPed = GetPlayerPed(targetPlayerId)
                    local playerPed = PlayerPedId()
                    if not DoesEntityExist(targetPed) or not DoesEntityExist(playerPed) then return end
                    
                    
                    AttachEntityToEntity(targetPed, playerPed, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
                end)
            ]], targetServerId)
        end
        
        Susano.InjectResource("any", code)
    end
end

function Menu.ActionCagePlayer()
    if not Menu.SelectedPlayer then return end
    
    local targetServerId = Menu.SelectedPlayer
    
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = string.format([[
            CreateThread(function()
                local targetServerId = %d
                local targetPlayerId = nil
                for _, player in ipairs(GetActivePlayers()) do
                    if GetPlayerServerId(player) == targetServerId then
                        targetPlayerId = player
                        break
                    end
                end
                if not targetPlayerId then return end
                
                local targetPed = GetPlayerPed(targetPlayerId)
                if not DoesEntityExist(targetPed) then return end
                
                local coords = GetEntityCoords(targetPed)
                
                
                local cageObjects = {}
                local objectHashes = {
                    `prop_barrier_work05`,
                    `prop_barrier_work06a`,
                    `prop_mp_barrier_02b`,
                    `prop_mp_barrier_02`
                }
                
                for i = 1, 4 do
                    local hash = objectHashes[i]
                    RequestModel(hash)
                    while not HasModelLoaded(hash) do Wait(0) end
                    
                    local offset = vector3(
                        (i == 1 or i == 3) and 2.0 or -2.0,
                        (i == 1 or i == 2) and 2.0 or -2.0,
                        0.0
                    )
                    
                    local obj = CreateObject(hash, coords.x + offset.x, coords.y + offset.y, coords.z, true, true, true)
                    PlaceObjectOnGroundProperly(obj)
                    FreezeEntityPosition(obj, true)
                    table.insert(cageObjects, obj)
                end
                
               
                local roofHash = `prop_rub_carwreck_3`
                RequestModel(roofHash)
                while not HasModelLoaded(roofHash) do Wait(0) end
                
                local roof = CreateObject(roofHash, coords.x, coords.y, coords.z + 5.0, true, true, true)
                FreezeEntityPosition(roof, true)
                table.insert(cageObjects, roof)
                
               
                Wait(30000)
                for _, obj in ipairs(cageObjects) do
                    if DoesEntityExist(obj) then
                        DeleteEntity(obj)
                    end
                end
            end)
        ]], targetServerId)
        
        Susano.InjectResource("any", code)
    end
end

function Menu.ActionRamPlayer()
    if not Menu.SelectedPlayer then return end
    
    local targetServerId = Menu.SelectedPlayer
    
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = string.format([[
            CreateThread(function()
                local targetServerId = %d
                local targetPlayerId = nil
                for _, player in ipairs(GetActivePlayers()) do
                    if GetPlayerServerId(player) == targetServerId then
                        targetPlayerId = player
                        break
                    end
                end
                if not targetPlayerId then return end
                
                local targetPed = GetPlayerPed(targetPlayerId)
                if not DoesEntityExist(targetPed) then return end
                
                local coords = GetEntityCoords(targetPed)
                local vehicleHash = `adder`
                RequestModel(vehicleHash)
                while not HasModelLoaded(vehicleHash) do Wait(0) end
                
              
                local veh = CreateVehicle(vehicleHash, coords.x - 50.0, coords.y, coords.z + 5.0, 0.0, true, true, true)
                SetVehicleEngineOn(veh, true, true, false)
                
               
                TaskVehicleDriveToCoord(veh, -1, coords.x, coords.y, coords.z, 200.0, 1.0, vehicleHash, 16777216, 10.0, true)
                
                
                Wait(1000)
                if DoesEntityExist(veh) then
                    SetEntityVelocity(veh, 100.0, 0.0, 0.0)
                end
            end)
        ]], targetServerId)
        
        Susano.InjectResource("any", code)
    end
end

function Menu.ActionCrush()
    if not Menu.SelectedPlayer then return end
    
    local targetServerId = Menu.SelectedPlayer
    local mode = Menu.CrushMode or "Rain"
    
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = ""
        
        if mode == "Rain" then
            code = string.format([[
                CreateThread(function()
                    local targetServerId = %d
                    local targetPlayerId = nil
                    for _, player in ipairs(GetActivePlayers()) do
                        if GetPlayerServerId(player) == targetServerId then
                            targetPlayerId = player
                            break
                        end
                    end
                    if not targetPlayerId then return end
                    
                    local targetPed = GetPlayerPed(targetPlayerId)
                    if not DoesEntityExist(targetPed) then return end
                    
                    local coords = GetEntityCoords(targetPed)
                    local objectHash = `prop_beachball_01`
                    RequestModel(objectHash)
                    while not HasModelLoaded(objectHash) do Wait(0) end
                    
                    
                    for i = 1, 100 do
                        local obj = CreateObject(objectHash, 
                            coords.x + math.random(-10, 10), 
                            coords.y + math.random(-10, 10), 
                            coords.z + math.random(20, 50), 
                            true, true, true
                        )
                        SetEntityVelocity(obj, 0.0, 0.0, -50.0)
                        Wait(50)
                    end
                end)
            ]], targetServerId)
        elseif mode == "Drop" then
            code = string.format([[
                CreateThread(function()
                    local targetServerId = %d
                    local targetPlayerId = nil
                    for _, player in ipairs(GetActivePlayers()) do
                        if GetPlayerServerId(player) == targetServerId then
                            targetPlayerId = player
                            break
                        end
                    end
                    if not targetPlayerId then return end
                    
                    local targetPed = GetPlayerPed(targetPlayerId)
                    if not DoesEntityExist(targetPed) then return end
                    
                    local coords = GetEntityCoords(targetPed)
                    local vehicleHash = `adder`
                    RequestModel(vehicleHash)
                    while not HasModelLoaded(vehicleHash) do Wait(0) end
                    
                    
                    local veh = CreateVehicle(vehicleHash, coords.x, coords.y, coords.z + 100.0, 0.0, true, true, true)
                    SetEntityVelocity(veh, 0.0, 0.0, -100.0)
                end)
            ]], targetServerId)
        elseif mode == "Ram" then
            code = string.format([[
                CreateThread(function()
                    local targetServerId = %d
                    local targetPlayerId = nil
                    for _, player in ipairs(GetActivePlayers()) do
                        if GetPlayerServerId(player) == targetServerId then
                            targetPlayerId = player
                            break
                        end
                    end
                    if not targetPlayerId then return end
                    
                    local targetPed = GetPlayerPed(targetPlayerId)
                    if not DoesEntityExist(targetPed) then return end
                    
                    local coords = GetEntityCoords(targetPed)
                    local vehicleHash = `adder`
                    RequestModel(vehicleHash)
                    while not HasModelLoaded(vehicleHash) do Wait(0) end
                    
                    
                    for i = 1, 5 do
                        local veh = CreateVehicle(vehicleHash, 
                            coords.x + math.random(-50, 50), 
                            coords.y + math.random(-50, 50), 
                            coords.z + 5.0, 
                            0.0, true, true, true
                        )
                        local targetCoords = GetEntityCoords(targetPed)
                        TaskVehicleDriveToCoord(veh, -1, targetCoords.x, targetCoords.y, targetCoords.z, 100.0, 1.0, vehicleHash, 16777216, 10.0, true)
                        Wait(1000)
                    end
                end)
            ]], targetServerId)
        end
        
        Susano.InjectResource("any", code)
    end
end

function Menu.ActionBugVehicle()
    if not Menu.SelectedPlayer then return end
    
    local targetServerId = Menu.SelectedPlayer
    local mode = Menu.BugVehicleMode or "V1"
    
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = string.format([[
            CreateThread(function()
                local targetServerId = %d
                local targetPlayerId = nil
                for _, player in ipairs(GetActivePlayers()) do
                    if GetPlayerServerId(player) == targetServerId then
                        targetPlayerId = player
                        break
                    end
                end
                if not targetPlayerId then return end
                
                local targetPed = GetPlayerPed(targetPlayerId)
                if not DoesEntityExist(targetPed) then return end
                
                if not IsPedInAnyVehicle(targetPed, false) then return end
                
                local targetVehicle = GetVehiclePedIsIn(targetPed, false)
                if not DoesEntityExist(targetVehicle) then return end
                
                
                if "%s" == "V1" then
                    
                    for i = 1, 20 do
                        SetEntityCollision(targetVehicle, false, false)
                        local coords = GetEntityCoords(targetVehicle)
                        SetEntityCoords(targetVehicle, coords.x, coords.y, coords.z - 1.0, false, false, false, false)
                        Wait(50)
                        SetEntityCollision(targetVehicle, true, true)
                        Wait(50)
                    end
                else
                    
                    SetEntityAlpha(targetVehicle, 0)
                    SetEntityVisible(targetVehicle, false, false)
                    Wait(5000)
                    SetEntityAlpha(targetVehicle, 255)
                    SetEntityVisible(targetVehicle, true, false)
                end
            end)
        ]], targetServerId, mode)
        
        Susano.InjectResource("any", code)
    end
end

function Menu.ActionKickVehicle()
    if not Menu.SelectedPlayer then return end
    
    local targetServerId = Menu.SelectedPlayer
    local mode = Menu.KickVehicleMode or "V1"
    
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = string.format([[
            CreateThread(function()
                local targetServerId = %d
                local targetPlayerId = nil
                for _, player in ipairs(GetActivePlayers()) do
                    if GetPlayerServerId(player) == targetServerId then
                        targetPlayerId = player
                        break
                    end
                end
                if not targetPlayerId then return end
                
                local targetPed = GetPlayerPed(targetPlayerId)
                if not DoesEntityExist(targetPed) then return end
                
                if not IsPedInAnyVehicle(targetPed, false) then return end
                
                local targetVehicle = GetVehiclePedIsIn(targetPed, false)
                if not DoesEntityExist(targetVehicle) then return end
                
                
                if "%s" == "V1" then
                    
                    ClearPedTasksImmediately(targetPed)
                    TaskLeaveVehicle(targetPed, targetVehicle, 16)
                else
                    
                    local coords = GetEntityCoords(targetVehicle)
                    DeleteEntity(targetVehicle)
                    SetEntityCoords(targetPed, coords.x, coords.y, coords.z + 1.0, false, false, false, false)
                end
            end)
        ]], targetServerId, mode)
        
        Susano.InjectResource("any", code)
    end
end

function Menu.ActionRemoveAllTires()
    if not Menu.SelectedPlayer then return end
    
    local targetServerId = Menu.SelectedPlayer
    
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = string.format([[
            CreateThread(function()
                local targetServerId = %d
                local targetPlayerId = nil
                for _, player in ipairs(GetActivePlayers()) do
                    if GetPlayerServerId(player) == targetServerId then
                        targetPlayerId = player
                        break
                    end
                end
                if not targetPlayerId then return end
                
                local targetPed = GetPlayerPed(targetPlayerId)
                if not DoesEntityExist(targetPed) then return end
                
                if not IsPedInAnyVehicle(targetPed, false) then return end
                
                local targetVehicle = GetVehiclePedIsIn(targetPed, false)
                if not DoesEntityExist(targetVehicle) then return end
                
                
                local tireCount = 0
                if IsThisModelACar(GetEntityModel(targetVehicle)) then
                    tireCount = 4
                elseif IsThisModelABike(GetEntityModel(targetVehicle)) then
                    tireCount = 2
                elseif IsThisModelATrailer(GetEntityModel(targetVehicle)) then
                    tireCount = 8
                end
                
                for i = 0, tireCount - 1 do
                    SetVehicleTyreBurst(targetVehicle, i, true, 1000.0)
                end
            end)
        ]], targetServerId)
        
        Susano.InjectResource("any", code)
    end
end

function Menu.ActionGive()
    if not Menu.SelectedPlayer then return end
    
    local targetServerId = Menu.SelectedPlayer
    local mode = Menu.GiveMode or "Vehicle"
    
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = ""
        
        if mode == "Vehicle" then
            code = string.format([[
                CreateThread(function()
                    local targetServerId = %d
                    local targetPlayerId = nil
                    for _, player in ipairs(GetActivePlayers()) do
                        if GetPlayerServerId(player) == targetServerId then
                            targetPlayerId = player
                            break
                        end
                    end
                    if not targetPlayerId then return end
                    
                    local targetPed = GetPlayerPed(targetPlayerId)
                    if not DoesEntityExist(targetPed) then return end
                    
                    local coords = GetEntityCoords(targetPed)
                    local vehicleHash = `adder`
                    RequestModel(vehicleHash)
                    while not HasModelLoaded(vehicleHash) do Wait(0) end
                    
                    local veh = CreateVehicle(vehicleHash, coords.x + 5.0, coords.y + 5.0, coords.z, 0.0, true, true, true)
                    SetVehicleEngineOn(veh, true, true, false)
                end)
            ]], targetServerId)
        elseif mode == "Ramp" then
            code = string.format([[
                CreateThread(function()
                    local targetServerId = %d
                    local targetPlayerId = nil
                    for _, player in ipairs(GetActivePlayers()) do
                        if GetPlayerServerId(player) == targetServerId then
                            targetPlayerId = player
                            break
                        end
                    end
                    if not targetPlayerId then return end
                    
                    local targetPed = GetPlayerPed(targetPlayerId)
                    if not DoesEntityExist(targetPed) then return end
                    
                    local coords = GetEntityCoords(targetPed)
                    local objectHash = `prop_mp_ramp_02`
                    RequestModel(objectHash)
                    while not HasModelLoaded(objectHash) do Wait(0) end
                    
                    local ramp = CreateObject(objectHash, coords.x + 5.0, coords.y, coords.z, true, true, true)
                    PlaceObjectOnGroundProperly(ramp)
                    FreezeEntityPosition(ramp, true)
                end)
            ]], targetServerId)
        elseif mode == "Wall" or mode == "Wall 2" then
            code = string.format([[
                CreateThread(function()
                    local targetServerId = %d
                    local targetPlayerId = nil
                    for _, player in ipairs(GetActivePlayers()) do
                        if GetPlayerServerId(player) == targetServerId then
                            targetPlayerId = player
                            break
                        end
                    end
                    if not targetPlayerId then return end
                    
                    local targetPed = GetPlayerPed(targetPlayerId)
                    if not DoesEntityExist(targetPed) then return end
                    
                    local coords = GetEntityCoords(targetPed)
                    local objectHash = "%s" == "Wall 2" and `prop_mp_barrier_02b` or `prop_fence_03a`
                    RequestModel(objectHash)
                    while not HasModelLoaded(objectHash) do Wait(0) end
                    
                    for i = 1, 5 do
                        local wall = CreateObject(objectHash, 
                            coords.x + 5.0, 
                            coords.y + (i * 2.0), 
                            coords.z, 
                            true, true, true
                        )
                        PlaceObjectOnGroundProperly(wall)
                        FreezeEntityPosition(wall, true)
                    end
                end)
            ]], targetServerId, mode)
        end
        
        Susano.InjectResource("any", code)
    end
end

function Menu.ActionTPTo()
    if not Menu.SelectedPlayer then return end
    
    local targetServerId = Menu.SelectedPlayer
    local location = Menu.TPLocation or "ocean"
    
    local locations = {
        ocean = {x = -2000.0, y = -1000.0, z = 0.0},
        mazebank = {x = -75.0, y = -818.0, z = 326.0},
        sandyshores = {x = 1856.0, y = 3689.0, z = 34.0}
    }
    
    local loc = locations[location] or locations.ocean
    
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = string.format([[
            CreateThread(function()
                local targetServerId = %d
                local targetPlayerId = nil
                for _, player in ipairs(GetActivePlayers()) do
                    if GetPlayerServerId(player) == targetServerId then
                        targetPlayerId = player
                        break
                    end
                end
                if not targetPlayerId then return end
                
                local targetPed = GetPlayerPed(targetPlayerId)
                if not DoesEntityExist(targetPed) then return end
                
               
                SetEntityCoords(targetPed, %f, %f, %f, false, false, false, false)
            end)
        ]], targetServerId, loc.x, loc.y, loc.z)
        
        Susano.InjectResource("any", code)
    end
end

function Menu.ActionNPCDrive()
    if not Menu.SelectedPlayer then return end
    
    local targetServerId = Menu.SelectedPlayer
    
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = string.format([[
            CreateThread(function()
                local targetServerId = %d
                local targetPlayerId = nil
                for _, player in ipairs(GetActivePlayers()) do
                    if GetPlayerServerId(player) == targetServerId then
                        targetPlayerId = player
                        break
                    end
                end
                if not targetPlayerId then return end
                
                local targetPed = GetPlayerPed(targetPlayerId)
                if not DoesEntityExist(targetPed) then return end
                
                if not IsPedInAnyVehicle(targetPed, false) then return end
                
                local targetVehicle = GetVehiclePedIsIn(targetPed, false)
                if not DoesEntityExist(targetVehicle) then return end
                
                
                local npcHash = `a_m_m_business_01`
                RequestModel(npcHash)
                while not HasModelLoaded(npcHash) do Wait(0) end
                
                local coords = GetEntityCoords(targetVehicle)
                local npc = CreatePed(4, npcHash, coords.x + 5.0, coords.y + 5.0, coords.z, 0.0, true, true)
                
                
                ClearPedTasksImmediately(targetPed)
                TaskLeaveVehicle(targetPed, targetVehicle, 16)
                Wait(2000)
                
                SetPedIntoVehicle(npc, targetVehicle, -1)
                TaskVehicleDriveWander(npc, targetVehicle, 100.0, 786603)
                
                
                SetEntityCoords(targetPed, coords.x, coords.y, coords.z + 1.0, false, false, false, false)
            end)
        ]], targetServerId)
        
        Susano.InjectResource("any", code)
    end
end

if Menu.DrawWatermark then
    Menu.DrawWatermark = function() return end
end

if Menu.UpdatePlayerCount then
    Menu.UpdatePlayerCount = function() return end
end

Menu.shooteyesEnabled = false
Menu.magicbulletEnabled = false
Menu.silentAimEnabled = false
Menu.superPunchEnabled = false
Menu.rapidFireEnabled = false
Menu.infiniteAmmoEnabled = false
Menu.noSpreadEnabled = false
Menu.noRecoilEnabled = false
Menu.noReloadEnabled = false
Menu.unlockAllVehicleEnabled = false

Menu.ShowBlossoms = false
Menu.FOVWarp = false
Menu.WarpPressW = false

local foundVehicles = {}
local Actions = {}
local attachedPlayers = {}

local attachTargetActive = false
local attachTargetServerId = nil
local banPlayerActive = false
local banPlayerThread = nil
local function ToggleAttachTarget(enable)
    attachTargetActive = enable
    if not enable then
        if attachTargetServerId then
            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                Susano.InjectResource("any", string.format([[
                    rawset(_G, 'attach_target_loop_%d', false)
                ]], attachTargetServerId))
            end
            attachTargetServerId = nil
        end
        return
    end

    Citizen.CreateThread(function()
        local function RotationToDirection(rotation)
            local adjustedRotation = vector3((math.pi / 180) * rotation.x, (math.pi / 180) * rotation.y, (math.pi / 180) * rotation.z)
            local direction = vector3(-math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)), math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)), math.sin(adjustedRotation.x))
            return direction
        end

        while attachTargetActive do
            Citizen.Wait(100)
            if IsControlJustPressed(0, 74) then
                local success, err = pcall(function()
                    local playerPed = PlayerPedId()
                    if not DoesEntityExist(playerPed) then return end

                    local camPos = GetGameplayCamCoord()
                    local camRot = GetGameplayCamRot(2)
                    local direction = RotationToDirection(camRot)
                    local dest = vector3(camPos.x + direction.x * 1000.0, camPos.y + direction.y * 1000.0, camPos.z + direction.z * 1000.0)

                    local rayHandle = StartShapeTestRay(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, 10, playerPed, 0)
                    Wait(0)
                    local _, hit, _, _, entityHit = GetShapeTestResult(rayHandle)

                local targetServerId = nil

                if hit == 1 and entityHit and entityHit ~= 0 and DoesEntityExist(entityHit) and IsEntityAPed(entityHit) then
                    local targetPed = entityHit

                    if targetPed == playerPed then
                        goto continue
                    end

                    for _, player in ipairs(GetActivePlayers()) do
                        local ped = GetPlayerPed(player)
                        if ped and ped ~= 0 and DoesEntityExist(ped) and ped == targetPed then
                            targetServerId = GetPlayerServerId(player)
                            break
                        end
                    end
                else
                    local closestPed = nil
                    local closestDistance = 5.0
                    local playerCoords = GetEntityCoords(playerPed)

                    for _, player in ipairs(GetActivePlayers()) do
                        if player ~= PlayerId() then
                            local targetPed = GetPlayerPed(player)
                            if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) and not IsPedDeadOrDying(targetPed, true) then
                                local pedCoords = GetEntityCoords(targetPed)
                                local distance = #(pedCoords - playerCoords)

                                if distance <= closestDistance and distance > 0.0 then
                                    local screenX, screenY = GetScreenCoordFromWorldCoord(pedCoords.x, pedCoords.y, pedCoords.z)
                                    if screenX >= 0.0 and screenX <= 1.0 and screenY >= 0.0 and screenY <= 1.0 then
                                        local dirToPed = pedCoords - camPos
                                        local distToPed = #dirToPed
                                        if distToPed > 0.1 then
                                            dirToPed = dirToPed / distToPed
                                            local dot = direction.x * dirToPed.x + direction.y * dirToPed.y + direction.z * dirToPed.z
                                            if dot > 0.9 then
                                                closestPed = targetPed
                                                closestDistance = distance
                                                targetServerId = GetPlayerServerId(player)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                if targetServerId then
                    if attachTargetServerId == targetServerId then
                        if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                            Susano.InjectResource("any", string.format([[
                                rawset(_G, 'attach_target_loop_%d', false)
                            ]], targetServerId))
                        end
                        attachTargetServerId = nil
                    else
                        if attachTargetServerId then
                            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                Susano.InjectResource("any", string.format([[
                                    rawset(_G, 'attach_target_loop_%d', false)
                                ]], attachTargetServerId))
                            end
                        end

                        attachTargetServerId = targetServerId

                        if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                            Susano.InjectResource("any", string.format([[
                                local targetServerId = %d
                                local playerPed = PlayerPedId()

                                local targetPlayerId = nil
                                for _, player in ipairs(GetActivePlayers()) do
                                    if GetPlayerServerId(player) == targetServerId then
                                        targetPlayerId = player
                                        break
                                    end
                                end

                                if not targetPlayerId then return end
                                local targetPed = GetPlayerPed(targetPlayerId)
                                if not DoesEntityExist(targetPed) then return end

                                rawset(_G, 'attach_target_loop_' .. targetServerId, true)

                                CreateThread(function()
                                    while rawget(_G, 'attach_target_loop_' .. targetServerId) do
                                        Wait(100)

                                        local success, err = pcall(function()
                                            if not DoesEntityExist(playerPed) or not DoesEntityExist(targetPed) then
                                                rawset(_G, 'attach_target_loop_' .. targetServerId, false)
                                                return
                                            end

                                            local myCoords = GetEntityCoords(playerPed)
                                            local myForward = GetEntityForwardVector(playerPed)
                                            local myHeading = GetEntityHeading(playerPed)

                                            if myCoords and myForward then
                                                SetEntityCoordsNoOffset(targetPed, myCoords.x + myForward.x, myCoords.y + myForward.y, myCoords.z + myForward.z, true, true, true)
                                                SetEntityHeading(targetPed, myHeading)
                                            end
                                        end)

                                        if not success then
                                            rawset(_G, 'attach_target_loop_' .. targetServerId, false)
                                            break
                                        end
                                    end
                                end)
                            ]], targetServerId))
                        end
                    end
                end
                ::continue::
                end)
                if not success then

                end
            end
        end
    end)
end

local selectedWeaponIndex = {
    melee = 1,
    pistol = 1,
    smg = 1,
    shotgun = 1,
    ar = 1,
    sniper = 1,
    heavy = 1
}

local weaponLists = {
    melee = {
        {name = "WEAPON_KNIFE", display = "Knife"},
        {name = "WEAPON_BAT", display = "Baseball Bat"},
        {name = "WEAPON_CROWBAR", display = "Crowbar"},
        {name = "WEAPON_GOLFCLUB", display = "Golf Club"},
        {name = "WEAPON_HAMMER", display = "Hammer"},
        {name = "WEAPON_HATCHET", display = "Hatchet"},
        {name = "WEAPON_KNUCKLE", display = "Brass Knuckles"},
        {name = "WEAPON_MACHETE", display = "Machete"},
        {name = "WEAPON_SWITCHBLADE", display = "Switchblade"},
        {name = "WEAPON_NIGHTSTICK", display = "Nightstick"},
        {name = "WEAPON_WRENCH", display = "Wrench"},
        {name = "WEAPON_BATTLEAXE", display = "Battle Axe"},
        {name = "WEAPON_POOLCUE", display = "Pool Cue"},
        {name = "WEAPON_STONE_HATCHET", display = "Stone Hatchet"}
    },
    pistol = {
        {name = "WEAPON_PISTOL", display = "Pistol"},
        {name = "WEAPON_PISTOL_MK2", display = "Pistol MK2"},
        {name = "WEAPON_COMBATPISTOL", display = "Combat Pistol"},
        {name = "WEAPON_PISTOL50", display = "Pistol .50"},
        {name = "WEAPON_SNSPISTOL", display = "SNS Pistol"},
        {name = "WEAPON_SNSPISTOL_MK2", display = "SNS Pistol MK2"},
        {name = "WEAPON_HEAVYPISTOL", display = "Heavy Pistol"},
        {name = "WEAPON_VINTAGEPISTOL", display = "Vintage Pistol"},
        {name = "WEAPON_FLAREGUN", display = "Flare Gun"},
        {name = "WEAPON_MARKSMANPISTOL", display = "Marksman Pistol"},
        {name = "WEAPON_REVOLVER", display = "Heavy Revolver"},
        {name = "WEAPON_REVOLVER_MK2", display = "Heavy Revolver MK2"},
        {name = "WEAPON_DOUBLEACTION", display = "Double Action Revolver"},
        {name = "WEAPON_APPISTOL", display = "AP Pistol"},
        {name = "WEAPON_STUNGUN", display = "Stun Gun"},
        {name = "WEAPON_CERAMICPISTOL", display = "Ceramic Pistol"},
        {name = "WEAPON_NAVYREVOLVER", display = "Navy Revolver"}
    },
    smg = {
        {name = "WEAPON_MICROSMG", display = "Micro SMG"},
        {name = "WEAPON_SMG", display = "SMG"},
        {name = "WEAPON_SMG_MK2", display = "SMG MK2"},
        {name = "WEAPON_ASSAULTSMG", display = "Assault SMG"},
        {name = "WEAPON_COMBATPDW", display = "Combat PDW"},
        {name = "WEAPON_MACHINEPISTOL", display = "Machine Pistol"},
        {name = "WEAPON_MINISMG", display = "Mini SMG"},
        {name = "WEAPON_GUSENBERG", display = "Gusenberg Sweeper"}
    },
    shotgun = {
        {name = "WEAPON_PUMPSHOTGUN", display = "Pump Shotgun"},
        {name = "WEAPON_PUMPSHOTGUN_MK2", display = "Pump Shotgun MK2"},
        {name = "WEAPON_SAWNOFFSHOTGUN", display = "Sawed-Off Shotgun"},
        {name = "WEAPON_ASSAULTSHOTGUN", display = "Assault Shotgun"},
        {name = "WEAPON_BULLPUPSHOTGUN", display = "Bullpup Shotgun"},
        {name = "WEAPON_MUSKET", display = "Musket"},
        {name = "WEAPON_HEAVYSHOTGUN", display = "Heavy Shotgun"},
        {name = "WEAPON_DBSHOTGUN", display = "Double Barrel Shotgun"},
        {name = "WEAPON_AUTOSHOTGUN", display = "Auto Shotgun"},
        {name = "WEAPON_COMBATSHOTGUN", display = "Combat Shotgun"}
    },
    ar = {
        {name = "WEAPON_ASSAULTRIFLE", display = "Assault Rifle"},
        {name = "WEAPON_ASSAULTRIFLE_MK2", display = "Assault Rifle MK2"},
        {name = "WEAPON_CARBINERIFLE", display = "Carbine Rifle"},
        {name = "WEAPON_CARBINERIFLE_MK2", display = "Carbine Rifle MK2"},
        {name = "WEAPON_ADVANCEDRIFLE", display = "Advanced Rifle"},
        {name = "WEAPON_SPECIALCARBINE", display = "Special Carbine"},
        {name = "WEAPON_SPECIALCARBINE_MK2", display = "Special Carbine MK2"},
        {name = "WEAPON_BULLPUPRIFLE", display = "Bullpup Rifle"},
        {name = "WEAPON_BULLPUPRIFLE_MK2", display = "Bullpup Rifle MK2"},
        {name = "WEAPON_COMPACTRIFLE", display = "Compact Rifle"},
        {name = "WEAPON_MILITARYRIFLE", display = "Military Rifle"},
        {name = "WEAPON_HEAVYRIFLE", display = "Heavy Rifle"},
        {name = "WEAPON_TACTICALRIFLE", display = "Tactical Rifle"}
    },
    sniper = {
        {name = "WEAPON_SNIPERRIFLE", display = "Sniper Rifle"},
        {name = "WEAPON_HEAVYSNIPER", display = "Heavy Sniper"},
        {name = "WEAPON_HEAVYSNIPER_MK2", display = "Heavy Sniper MK2"},
        {name = "WEAPON_MARKSMANRIFLE", display = "Marksman Rifle"},
        {name = "WEAPON_MARKSMANRIFLE_MK2", display = "Marksman Rifle MK2"},
        {name = "WEAPON_PRECISIONRIFLE", display = "Precision Rifle"}
    },
    heavy = {
        {name = "WEAPON_RPG", display = "RPG"},
        {name = "WEAPON_GRENADELAUNCHER", display = "Grenade Launcher"},
        {name = "WEAPON_GRENADELAUNCHER_SMOKE", display = "Grenade Launcher Smoke"},
        {name = "WEAPON_MINIGUN", display = "Minigun"},
        {name = "WEAPON_FIREWORK", display = "Firework Launcher"},
        {name = "WEAPON_RAILGUN", display = "Railgun"},
        {name = "WEAPON_HOMINGLAUNCHER", display = "Homing Launcher"},
        {name = "WEAPON_COMPACTLAUNCHER", display = "Compact Grenade Launcher"},
        {name = "WEAPON_RAYMINIGUN", display = "Widowmaker"},
        {name = "WEAPON_EMPLAUNCHER", display = "Compact EMP Launcher"},
        {name = "WEAPON_RAILGUNXM3", display = "Railgun XM3"}
    }
}

local function GenerateNativeHooks(nativesList)
    local hooks = [[
local function hNative(nativeName, newFunction)
    local originalNative = _G[nativeName]
    if not originalNative or type(originalNative) ~= "function" then return end
    _G[nativeName] = function(...) return newFunction(originalNative, ...) end
end
]]
    for _, nativeName in ipairs(nativesList) do
        hooks = hooks .. string.format('hNative("%s", function(originalFn, ...) return originalFn(...) end)\n', nativeName)
    end
    return hooks
end

local COMMON_NATIVES = {
    "GetActivePlayers", "GetPlayerServerId", "GetPlayerPed", "DoesEntityExist",
    "PlayerPedId", "GetEntityCoords", "SetEntityCoordsNoOffset", "GetEntityHeading",
    "SetEntityHeading", "IsPedInAnyVehicle", "GetVehiclePedIsIn"
}

local VEHICLE_NATIVES = {
    "TaskWarpPedIntoVehicle", "SetVehicleDoorsLocked", "SetVehicleDoorsLockedForAllPlayers",
    "IsVehicleSeatFree", "ClearPedTasksImmediately", "TaskEnterVehicle",
    "GetClosestVehicle", "SetPedIntoVehicle", "SetEntityAsMissionEntity",
    "NetworkGetEntityIsNetworked", "NetworkRequestControlOfEntity", "AttachEntityToEntity",
    "DetachEntity", "AttachEntityToEntityPhysically", "GetOffsetFromEntityInWorldCoords",
    "SetEntityRotation", "FreezeEntityPosition", "TaskLeaveVehicle", "DeletePed",
    "GetPedInVehicleSeat", "NetworkHasControlOfEntity"
}

local function WrapWithVehicleHooks(code)
    local allNatives = {}
    for _, n in ipairs(COMMON_NATIVES) do table.insert(allNatives, n) end
    for _, n in ipairs(VEHICLE_NATIVES) do table.insert(allNatives, n) end
    return GenerateNativeHooks(allNatives) .. "\n" .. code
end

Menu.Categories = {
    { name = "Main Menu", icon = "P" },
    { name = "Player", icon = "👤", hasTabs = true, tabs = {
        { name = "Self", items = {
            { name = "Godmode", type = "toggle", value = false },
            { name = "Semi Godmode", type = "toggle", value = false },
            { name = "Anti Headshot", type = "toggle", value = false },
            { name = "", isSeparator = true, separatorText = "Health" },
            { name = "Revive", type = "action" },
            { name = "Max Health", type = "action" },
            { name = "Max Armor", type = "action" },
            { name = "", isSeparator = true, separatorText = "other" },
            { name = "TP all vehicle to me", type = "action" },
            { name = "Detach All Entitys", type = "action" },
            { name = "Solo Session", type = "toggle", value = false },
            { name = "Throw Vehicle", type = "toggle", value = false },
            { name = "Tiny Player", type = "toggle", value = false },
            { name = "Infinite Stamina", type = "toggle", value = false }
        }},
        { name = "Movement", items = {
            { name = "", isSeparator = true, separatorText = "noclip" },
            { name = "Noclip", type = "toggle", value = false, hasSlider = true, sliderValue = 1.0, sliderMin = 1.0, sliderMax = 20.0, sliderStep = 0.5 },
            { name = "NoClip Type", type = "selector", options = {"normal", "staff"}, selected = 1 },
            { name = "", isSeparator = true, separatorText = "freecam" },
            { name = "Freecam", type = "toggle", value = false, hasSlider = true, sliderValue = 0.5, sliderMin = 0.1, sliderMax = 5.0, sliderStep = 0.1 },
            { name = "", isSeparator = true, separatorText = "other" },
            { name = "Fast Run", type = "toggle", value = false },
            { name = "No Ragdoll", type = "toggle", value = false }
        }},
        { name = "Wardrobe", items = {
            { name = "Random Outfit", type = "action" },
            { name = "Save Outfit", type = "action" },
            { name = "Load Outfit", type = "action" },
            { name = "Outfit", type = "selector", options = {"bnz outfit", "Staff Outfit", "Hitler Outfit", "jy", "w outfit"}, selected = 1 },
            { name = "", isSeparator = true, separatorText = "Clothing" },
            { name = "Hat", type = "selector", options = {}, selected = 1 },
            { name = "Mask", type = "selector", options = {}, selected = 1 },
            { name = "Glasses", type = "selector", options = {}, selected = 1 },
            { name = "Torso", type = "selector", options = {}, selected = 1 },
            { name = "Tshirt", type = "selector", options = {}, selected = 1 },
            { name = "Pants", type = "selector", options = {}, selected = 1 },
            { name = "Shoes", type = "selector", options = {}, selected = 1 }
        }}
    }},
    { name = "Online", icon = "👥", hasTabs = true, tabs = {
        { name = "Player List", items = {
            { name = "Loading players...", type = "action" }
        }},
        { name = "Troll", items = {
            { name = "", isSeparator = true, separatorText = "Appearance" },
            { name = "Copy Appearance", type = "action" },

            { name = "", isSeparator = true, separatorText = "Attacks" },
            { name = "Ban Player (test)", type = "toggle", value = false },
            { name = "Shoot Player", type = "action" },
            { name = "Attach Player", type = "toggle", value = false, onClick = function(val)
                local target = Menu.SelectedPlayer
                if not target then
                    local closestDist = 5.0
                    local pCoords = GetEntityCoords(PlayerPedId())
                    for _, p in ipairs(GetActivePlayers()) do
                        if p ~= PlayerId() then
                            local pPed = GetPlayerPed(p)
                            local pDist = #(GetEntityCoords(pPed) - pCoords)
                            if pDist < closestDist then
                                closestDist = pDist
                                target = p
                            end
                        end
                    end
                end

                if target then
                    if not attachedPlayers then attachedPlayers = {} end
                    local targetPed = GetPlayerPed(target)
                    if val then
                        attachedPlayers[target] = targetPed
                    else
                        attachedPlayers[target] = nil
                    end
                end
            end },

            { name = "", isSeparator = true, separatorText = "Bugs" },
            { name = "Bug Player", type = "selector", options = {"Bug", "Launch", "Hard Launch", "Attach"}, selected = 1 },
            { name = "Cage Player", type = "action" },
            { name = "Crush", type = "selector", options = {"Rain", "Drop", "Ram"}, selected = 1 },
            { name = "Black Hole", type = "toggle", value = false },

            { name = "", isSeparator = true, separatorText = "attach" },
            { name = "twerk", type = "toggle", value = false },
            { name = "baise le", type = "toggle", value = false },
            { name = "branlette", type = "toggle", value = false },
            { name = "piggyback", type = "toggle", value = false }
        }},
        { name = "Vehicle", items = {
            { name = "", isSeparator = true, separatorText = "Bugs" },
            { name = "Bug Vehicle", type = "selector", options = {"V1", "V2"}, selected = 1 },
            { name = "Warp", type = "selector", options = {"Classic", "Boost"}, selected = 1 },

            { name = "", isSeparator = true, separatorText = "Teleportation" },
            { name = "TP to", type = "selector", options = {"ocean", "mazebank", "sandyshores"}, selected = 1 },

            { name = "", isSeparator = true, separatorText = "Actions" },
            { name = "Remote Vehicle", type = "action" },
            { name = "Steal Vehicle", type = "action" },
            { name = "NPC Drive", type = "action" },
            { name = "Delete Vehicle", type = "action" },
            { name = "Kick Vehicle", type = "selector", options = {"V1", "V2"}, selected = 1 },
            { name = "remove all tires", type = "action" },
            { name = "Give", type = "selector", options = {"Vehicle", "Ramp", "Wall", "Wall 2"}, selected = 1 }
        }},
        { name = "all", items = {
            { name = "Launch All", type = "action" }
        }}
    }},
    { name = "Combat", icon = "🔫", hasTabs = true, tabs = {
        { name = "General", items = {
            { name = "Attach Target (H)", type = "toggle", value = false, onClick = function(val) ToggleAttachTarget(val) end },
            { name = "", isSeparator = true, separatorText = "Aimbot" },
            { name = "Silent Aim", type = "toggle", value = false },
            { name = "Magic Bullet", type = "toggle", value = false },
            { name = "Shoot Eyes", type = "toggle", value = false },
            { name = "Super Punch", type = "toggle", value = false },
            { name = "", isSeparator = true, separatorText = "Weapon Mods" },
            { name = "No Recoil", type = "toggle", value = false },
            { name = "No Spread", type = "toggle", value = false },
            { name = "Rapid Fire", type = "toggle", value = false },
            { name = "Infinite Ammo", type = "toggle", value = false },
            { name = "No Reload", type = "toggle", value = false },
            { name = "Give Ammo", type = "action" },
            { name = "", isSeparator = true, separatorText = "attachments" },
            { name = "Give all attachment", type = "action" },
            { name = "Give suppressor", type = "action" },
            { name = "Give flashlight", type = "action" },
            { name = "Give grip", type = "action" },
            { name = "Give scope", type = "action" }
        }},
        { name = "Spawn", items = {
            { name = "Protect Weapon", type = "toggle", value = false },
            { name = "give weapon_aa", type = "toggle", value = false },
            { name = "give weapon_caveira", type = "toggle", value = false },
            { name = "give weapon_SCOM", type = "toggle", value = false },
            { name = "give weapon_mcx", type = "toggle", value = false },
            { name = "give weapon_grau", type = "toggle", value = false },
            { name = "give weapon_midasgun", type = "toggle", value = false },
            { name = "give weapon_hackingdevice", type = "toggle", value = false },
            { name = "give weapon_akorus", type = "toggle", value = false },
            { name = "give WEAPON_MIDGARD", type = "toggle", value = false },
            { name = "give weapon_chainsaw", type = "toggle", value = false }
        }}
    }},
    { name = "Vehicle", icon = "🚗", hasTabs = true, tabs = {
          { name = "Spawn", items = {
            { name = "Teleport Into", type = "toggle", value = false },
            { name = "", isSeparator = true, separatorText = "spawn" },
            { name = "Car", type = "selector", options = {
                "Adder", "Zentorno", "T20", "Osiris", "Entity XF", "Cheetah", "Turismo R", "Infernus", "Vacca", "Bullet",
                "Voltic", "Banshee", "Sultan", "Elegy RH8", "Feltzer", "Rapid GT", "Coquette", "9F", "Carbonizzare",
                "Jester", "Massacro", "Kuruma", "Armored Kuruma", "Insurgent", "Insurgent Pick-Up", "Savage", "Hydra",
                "Lazer", "Buzzard", "Valkyrie", "Cargobob", "Annihilator", "Swift", "Luxor", "Miljet", "Shamal",
                "Dodo", "Sea Sparrow", "Sparrow", "Akula", "Hunter", "Havok", "Deluxo", "Oppressor", "Oppressor MK2",
                "Scramjet", "Vigilante", "Ruiner 2000", "Phantom Wedge", "Armored Boxville", "Technical", "Dune FAV",
                "Weaponized Tampa", "Halftrack", "APC", "Barrage", "Khanjali", "Thruster", "Jetpack", "Blazer Aqua",
                "Bifta", "Kalahari", "Dune Buggy", "Rancher XL", "Rebel", "Sandking XL", "Brawler", "Contender",
                "Dubsta", "Dubsta 6x6", "Granger", "Guardian", "Huntley S", "Landstalker", "Mesa", "Patriot",
                "Radius", "Rocoto", "Seminole", "Serrano", "XLS", "Baller", "Baller LE", "Cavalcade", "FQ 2",
                "Pilgrim", "Gresley", "Habanero", "Fugitive", "Intruder", "Premier", "Primo", "Stanier", "Stratum",
                "Surge", "Tailgater", "Warrener", "Washington", "Asea", "Asterope", "Bison", "Bobcat XL", "Burrito",
                "Camper", "Journey", "Minivan", "Paradise", "Pony", "Rumpo", "Speedo", "Surfer", "Youga",
                "Emperor", "Glendale", "Manana", "Peyote", "Virgo", "Voodoo", "Buccaneer", "Chino", "Moonbeam",
                "Primo Custom", "Faction", "Faction Custom", "Sabre Turbo", "Tornado", "Hermes", "Hustler",
                "Blade", "Rat Loader", "Rat Truck", "Yosemite", "Dukes", "Gauntlet", "Buffalo", "Buffalo S",
                "Dominator", "Hotknife", "Picador", "Phoenix", "Ruiner", "Stallion", "Vigero", "Virgo Classic",
                "Viseris", "Cheburek", "Fagaloa", "Nebula Turbo", "Peyote Gasser", "Dynasty", "Vamos",
                "Tulip", "Buccaneer Custom", "Chino Custom", "Faction Custom", "Moonbeam Custom", "Sabre Turbo Custom",
                "Tornado Custom", "Virgo Classic Custom", "Voodoo Custom", "BF Injection", "Blista", "Blista Compact",
                "Prairie", "Issi", "Issi Classic", "Weeny", "Club", "Brioso", "Rhapsody", "Dilettante", "Cognoscenti",
                "Cognoscenti 55", "Super Diamond", "Oracle", "Oracle XS", "Schafter", "Schafter LWB", "Windsor",
                "Windsor Drop", "Z Type", "Stinger", "Stinger GT", "JB 700", "Pigalle", "Roosevelt", "Roosevelt Valor",
                "Fränken Stange", "Zombie Bobber", "Zombie Chopper", "Daemon", "Wolfsbane", "Innovation", "Nightblade",
                "Esskey", "Gargoyle", "Cliffhanger", "Rat Bike", "Sanctus", "Shotaro", "Hakuchou", "Hakuchou Drag",
                "Bati 801", "Bati 801RR", "Double T", "Akuma", "PCJ 600", "Vader", "Faggio", "Faggio Mod", "Faggio Sport"
            }, selected = 1 },
            { name = "Moto", type = "selector", options = {
                "Bati 801", "Bati 801RR", "Double T", "Akuma", "PCJ 600", "Vader", "Faggio", "Faggio Mod", "Faggio Sport",
                "Nightblade", "Zombie Bobber", "Zombie Chopper", "Daemon", "Wolfsbane", "Innovation", "Esskey",
                "Gargoyle", "Cliffhanger", "Rat Bike", "Sanctus", "Shotaro", "Hakuchou", "Hakuchou Drag", "Sanchez",
                "Enduro", "Manchez", "BF400", "Lectro", "Ruffian", "Nemesis", "Sovereign", "Hexer", "Thrust"
            }, selected = 1 },
            { name = "Plane", type = "selector", options = {
                "Luxor", "Hydra", "Lazer", "Besra", "Miljet", "Shamal", "Cuban 800", "Dodo", "Duster", "Mallard",
                "Nimbus", "Velum", "Velum 5-Seater", "Vestra", "Howard NX-25", "Alpha-Z1", "Ultralight", "Seabreeze",
                "Tula", "Pyro", "Rogue", "Molotok", "Starling", "Nokota", "B-11 Strikeforce", "Bombushka",
                "Volatol", "Titan", "Cargoplane", "Jet", "Luxor Deluxe", "Swift Deluxe", "SuperVolito",
                "SuperVolito Carbon", "Frogger", "Maverick", "Buzzard", "Buzzard Attack Chopper", "Savage",
                "Valkyrie", "Annihilator", "Hunter", "Akula", "Havok", "Sea Sparrow", "Swift", "Sparrow",
                "FH-1 Hunter", "V-65 Molotok", "P-45 Nokota", "LF-22 Starling", "B-11 Strikeforce"
            }, selected = 1 },
            { name = "Boat", type = "selector", options = {
                "Seashark", "Speeder", "Jetmax", "Toro", "Dinghy", "Dinghy 4-Seat", "Dinghy 2-Seat", "Marquis",
                "Squalo", "Suntrap", "Tropic", "Tropic 2", "Predator", "Police Predator", "Rhib", "Submersible",
                "Submersible 2", "Kraken", "Avisa", "Toro 2", "Longfin", "Patrol Boat", "Wastelander", "Cutter"
            }, selected = 1 }
        }},
        { name = "Performance", items = {
            { name = "", isSeparator = true, separatorText = "Warp" },
            { name = "FOV Warp", type = "toggle", value = false, onClick = function(val) Menu.FOVWarp = val end },
            { name = "Warp when u press W", type = "toggle", value = false, onClick = function(val) Menu.WarpPressW = val end },
            { name = "Throw From Vehicle", type = "toggle", value = false },
            { name = "", isSeparator = true, separatorText = "performance" },
            { name = "Max Upgrade", type = "action" },
            { name = "Repair Vehicle", type = "action" },
            { name = "Flip Vehicle", type = "action" },
            { name = "Force Vehicle Engine", type = "toggle", value = false },
            { name = "Easy Handling", type = "toggle", value = false },
            { name = "Shift Boost", type = "toggle", value = false },
            { name = "Gravitate Vehicle", type = "toggle", value = false },
            { name = "Gravitate Speed", type = "slider", value = 100, min = 50, max = 500, step = 10 },
            { name = "", isSeparator = true, separatorText = "Maintenance" },
            { name = "Change Plate", type = "action" },
            { name = "Clean Vehicle", type = "action" },
            { name = "Delete Vehicle", type = "action" },

            { name = "", isSeparator = true, separatorText = "Access" },
            { name = "Unlock All Vehicle", type = "toggle", value = false },
            { name = "Teleport into Closest Vehicle", type = "action" },

            { name = "", isSeparator = true, separatorText = "Modifications" },
            { name = "No Collision", type = "toggle", value = false },
            { name = "Bunny Hop", type = "toggle", value = false },
            { name = "Back Flip", type = "toggle", value = false },

            { name = "", isSeparator = true, separatorText = "Give" },
            { name = "Give Nearest Vehicle", type = "action" },
            { name = "Give", type = "selector", options = {"Ramp", "Wall", "Wall 2"}, selected = 1 },
            { name = "Rainbow Paint", type = "toggle", value = false }
        }},
        { name = "Radar", items = {
            { name = "Select Vehicle", type = "selector", options = {"Scanning..."}, selected = 1 },
            { name = "Highlight Selected", type = "toggle", value = false },
            { name = "Teleport Into", type = "action", onClick = function()
                local radarTab = nil
                if Menu.Categories then
                    for _, cat in ipairs(Menu.Categories) do
                        if cat.name == "Vehicle" and cat.tabs then
                            for _, tab in ipairs(cat.tabs) do
                                if tab.name == "Radar" then radarTab = tab break end
                            end
                        end
                        if radarTab then break end
                    end
                end
                if radarTab and radarTab.items then
                    local selector = radarTab.items[1]
                    if selector and foundVehicles and #foundVehicles > 0 then
                         local vehData = foundVehicles[selector.selected]
                         if vehData then
                             local veh = vehData.entity
                             if veh and DoesEntityExist(veh) then
                                 local ped = PlayerPedId()
                                 if IsPedInAnyVehicle(ped, false) then ClearPedTasksImmediately(ped) end
                                 SetPedIntoVehicle(ped, veh, -1)
                             end
                         end
                    end
                end
            end },
            { name = "Teleport To Me", type = "action", onClick = function()
                local radarTab = nil
                if Menu.Categories then
                    for _, cat in ipairs(Menu.Categories) do
                        if cat.name == "Vehicle" and cat.tabs then
                            for _, tab in ipairs(cat.tabs) do
                                if tab.name == "Radar" then radarTab = tab break end
                            end
                        end
                        if radarTab then break end
                    end
                end
                if radarTab and radarTab.items then
                    local selector = radarTab.items[1]
                    if selector and foundVehicles and #foundVehicles > 0 then
                         local vehData = foundVehicles[selector.selected]
                         if vehData then
                             local veh = vehData.entity
                             if veh and DoesEntityExist(veh) then
                                 local ped = PlayerPedId()
                                 local myPos = GetEntityCoords(ped)
                                 if IsPedInAnyVehicle(ped, false) then ClearPedTasksImmediately(ped) end
                                 SetPedIntoVehicle(ped, veh, -1)
                                 SetEntityCoords(veh, myPos.x, myPos.y, myPos.z + 1.0, false, false, false, true)
                             end
                         end
                    end
                end
            end },
            { name = "Unlock Vehicle", type = "action", onClick = function()
                local radarTab = nil
                if Menu.Categories then
                    for _, cat in ipairs(Menu.Categories) do
                        if cat.name == "Vehicle" and cat.tabs then
                            for _, tab in ipairs(cat.tabs) do
                                if tab.name == "Radar" then radarTab = tab break end
                            end
                        end
                        if radarTab then break end
                    end
                end
                if radarTab and radarTab.items then
                    local selector = radarTab.items[1]
                    if selector and foundVehicles and #foundVehicles > 0 then
                         local vehData = foundVehicles[selector.selected]
                         if vehData then
                             local veh = vehData.entity
                             if veh and DoesEntityExist(veh) then
                                 SetVehicleDoorsLocked(veh, 1)
                                 SetVehicleDoorsLockedForAllPlayers(veh, false)
                             end
                         end
                    end
                end
            end },
            { name = "Lock Vehicle", type = "action", onClick = function()
                local radarTab = nil
                if Menu.Categories then
                    for _, cat in ipairs(Menu.Categories) do
                        if cat.name == "Vehicle" and cat.tabs then
                            for _, tab in ipairs(cat.tabs) do
                                if tab.name == "Radar" then radarTab = tab break end
                            end
                        end
                        if radarTab then break end
                    end
                end
                if radarTab and radarTab.items then
                    local selector = radarTab.items[1]
                    if selector and foundVehicles and #foundVehicles > 0 then
                         local vehData = foundVehicles[selector.selected]
                         if vehData then
                             local veh = vehData.entity
                             if veh and DoesEntityExist(veh) then
                                 SetVehicleDoorsLocked(veh, 2)
                                 SetVehicleDoorsLockedForAllPlayers(veh, true)
                             end
                         end
                    end
                end
            end },
            { name = "Delete Vehicle", type = "action", onClick = function()
                local radarTab = nil
                if Menu.Categories then
                    for _, cat in ipairs(Menu.Categories) do
                        if cat.name == "Vehicle" and cat.tabs then
                            for _, tab in ipairs(cat.tabs) do
                                if tab.name == "Radar" then radarTab = tab break end
                            end
                        end
                        if radarTab then break end
                    end
                end
                if radarTab and radarTab.items then
                    local selector = radarTab.items[1]
                    if selector and foundVehicles and #foundVehicles > 0 then
                         local vehData = foundVehicles[selector.selected]
                         if vehData then
                             local veh = vehData.entity
                             if veh and DoesEntityExist(veh) then
                                 local ped = PlayerPedId()
                                 if IsPedInAnyVehicle(ped, false) then ClearPedTasksImmediately(ped) end
                                 SetPedIntoVehicle(ped, veh, -1)
                                 SetEntityAsMissionEntity(veh, true, true)
                                 DeleteVehicle(veh)
                             end
                         end
                    end
                end
            end }
        }}
    }},
    { name = "Exploits", icon = "💥", hasTabs = true, tabs = {
        { name = "General", items = {
            { name = "", isSeparator = true, separatorText = "Exploits" },
            { name = "Crasher 2.0", type = "action" },
            { name = "Kill All", type = "toggle", value = false },
            { name = "Voice Radius (400m)", type = "toggle", value = false },
            { name = "Vehicle Storm", type = "toggle", value = false }
        }}
    }},
    { name = "Miscellaneous", icon = "📄", hasTabs = true, tabs = {
        { name = "General", items = {
            { name = "", isSeparator = true, separatorText = "Teleport" },
            { name = "Teleport To", type = "selector", options = {
                "Waypoint",
                "FIB Building",
                "Mission Row PD",
                "Pillbox Hospital",
                "Grove Street",
                "Legion Square"
            }, selected = 1 },
            { name = "Teleport Vision", type = "toggle", value = false },
            { name = "Teleport Shoot", type = "toggle", value = false },

            { name = "", isSeparator = true, separatorText = "Server Stuff" },
            { name = "Staff Mode", type = "toggle", value = false },
            { name = "Disable Weapon Damage", type = "toggle", value = false },
            { name = "Kill All Peds", type = "toggle", value = false },
            { name = "", isSeparator = true, separatorText = "Target" },
            { name = "Launch on Target", type = "toggle", value = false },
        }},
        { name = "Bypasses", items = {
            { name = "", isSeparator = true, separatorText = "Anti Cheat" },
            { name = "Bypass Putin", type = "action" },
        }},
        { name = "Exploits", items = {
            { name = "Menu Staff", type = "action" },
            { name = "Revive", type = "action" }
        }}
    }},
    { name = "Settings", icon = "⚙", hasTabs = true, tabs = {
        { name = "General", items = {
            { name = "Editor Mode", type = "toggle", value = false },
            { name = "Menu Size", type = "slider", value = 100.0, min = 50.0, max = 200.0, step = 1.0 },
            { name = "", isSeparator = true, separatorText = "Design" },
            { name = "Menu Theme", type = "selector", options = {"Purple", "pink", "Red", "Gray"}, selected = 3 },
            { name = "Flakes", type = "toggle", value = false },
            { name = "Blossoms", type = "toggle", value = false },
            { name = "Gradient", type = "selector", options = {"1", "2"}, selected = 1 },
            { name = "Scroll Bar Position", type = "selector", options = {"Left", "Right"}, selected = 1 },
            { name = "Black Background", type = "toggle", value = true }
        }},
        { name = "Keybinds", items = {
            { name = "Change Menu Keybind", type = "action" },
            { name = "Show Menu Keybinds", type = "toggle", value = false }
        }},
        { name = "Config", items = {
            { name = "Create Config", type = "action" },
            { name = "Load Config", type = "action" }
        }}
    }}
}

if Menu.ApplyTheme then
    Menu.ApplyTheme("Red")
end

Menu.Visible = false

Menu.SelectedPlayer = nil
Menu.SelectedPlayers = {}
Menu.PlayerListSelectIndex = 1
Menu.PlayerListTeleportIndex = 1
Menu.PlayerListTypeIndex = 1
Menu.PlayerListSpectateEnabled = false
Menu.StaffModeEnabled = false
Menu.DisableWeaponDamage = false
Menu.WeaponDamageHookSet = false

local Bones = {
    Pelvis = 11816,
    SKEL_Head = 31086,
    SKEL_Neck_1 = 39317,
    SKEL_L_Clavicle = 64729,
    SKEL_L_UpperArm = 45509,
    SKEL_L_Forearm = 61163,
    SKEL_L_Hand = 18905,
    SKEL_R_Clavicle = 10706,
    SKEL_R_UpperArm = 40269,
    SKEL_R_Forearm = 28252,
    SKEL_R_Hand = 57005,
    SKEL_L_Thigh = 58271,
    SKEL_L_Calf = 63931,
    SKEL_L_Foot = 14201,
    SKEL_R_Thigh = 51826,
    SKEL_R_Calf = 36864,
    SKEL_R_Foot = 52301,
}

local SkeletonConnections = {
    {Bones.Pelvis, Bones.SKEL_Neck_1},
    {Bones.SKEL_Neck_1, Bones.SKEL_Head},
    {Bones.SKEL_Neck_1, Bones.SKEL_L_Clavicle},
    {Bones.SKEL_L_Clavicle, Bones.SKEL_L_UpperArm},
    {Bones.SKEL_L_UpperArm, Bones.SKEL_L_Forearm},
    {Bones.SKEL_L_Forearm, Bones.SKEL_L_Hand},
    {Bones.SKEL_Neck_1, Bones.SKEL_R_Clavicle},
    {Bones.SKEL_R_Clavicle, Bones.SKEL_R_UpperArm},
    {Bones.SKEL_R_UpperArm, Bones.SKEL_R_Forearm},
    {Bones.SKEL_R_Forearm, Bones.SKEL_R_Hand},
    {Bones.Pelvis, Bones.SKEL_L_Thigh},
    {Bones.SKEL_L_Thigh, Bones.SKEL_L_Calf},
    {Bones.SKEL_L_Calf, Bones.SKEL_L_Foot},
    {Bones.Pelvis, Bones.SKEL_R_Thigh},
    {Bones.SKEL_R_Thigh, Bones.SKEL_R_Calf},
    {Bones.SKEL_R_Calf, Bones.SKEL_R_Foot},
}

local ESPColors = {
    {1.0, 1.0, 1.0},
    {1.0, 0.0, 0.0},
    {0.0, 1.0, 0.0},
    {0.0, 0.0, 1.0},
    {1.0, 1.0, 0.0},
    {1.0, 0.0, 1.0},
    {0.0, 1.0, 1.0},
}

local function GetWeaponNameFromHash(weaponHash)
    local weaponHashToName = {
        [GetHashKey("WEAPON_UNARMED")] = "Unarmed",
        [GetHashKey("WEAPON_KNIFE")] = "Knife",
        [GetHashKey("WEAPON_BAT")] = "Baseball Bat",
        [GetHashKey("WEAPON_CROWBAR")] = "Crowbar",
        [GetHashKey("WEAPON_GOLFCLUB")] = "Golf Club",
        [GetHashKey("WEAPON_HAMMER")] = "Hammer",
        [GetHashKey("WEAPON_HATCHET")] = "Hatchet",
        [GetHashKey("WEAPON_KNUCKLE")] = "Brass Knuckles",
        [GetHashKey("WEAPON_MACHETE")] = "Machete",
        [GetHashKey("WEAPON_SWITCHBLADE")] = "Switchblade",
        [GetHashKey("WEAPON_NIGHTSTICK")] = "Nightstick",
        [GetHashKey("WEAPON_WRENCH")] = "Wrench",
        [GetHashKey("WEAPON_BATTLEAXE")] = "Battle Axe",
        [GetHashKey("WEAPON_POOLCUE")] = "Pool Cue",
        [GetHashKey("WEAPON_STONE_HATCHET")] = "Stone Hatchet",
        [GetHashKey("WEAPON_PISTOL")] = "Pistol",
        [GetHashKey("WEAPON_PISTOL_MK2")] = "Pistol MK2",
        [GetHashKey("WEAPON_COMBATPISTOL")] = "Combat Pistol",
        [GetHashKey("WEAPON_PISTOL50")] = "Pistol .50",
        [GetHashKey("WEAPON_SNSPISTOL")] = "SNS Pistol",
        [GetHashKey("WEAPON_SNSPISTOL_MK2")] = "SNS Pistol MK2",
        [GetHashKey("WEAPON_HEAVYPISTOL")] = "Heavy Pistol",
        [GetHashKey("WEAPON_VINTAGEPISTOL")] = "Vintage Pistol",
        [GetHashKey("WEAPON_FLAREGUN")] = "Flare Gun",
        [GetHashKey("WEAPON_MARKSMANPISTOL")] = "Marksman Pistol",
        [GetHashKey("WEAPON_REVOLVER")] = "Heavy Revolver",
        [GetHashKey("WEAPON_REVOLVER_MK2")] = "Heavy Revolver MK2",
        [GetHashKey("WEAPON_DOUBLEACTION")] = "Double Action Revolver",
        [GetHashKey("WEAPON_APPISTOL")] = "AP Pistol",
        [GetHashKey("WEAPON_STUNGUN")] = "Stun Gun",
        [GetHashKey("WEAPON_CERAMICPISTOL")] = "Ceramic Pistol",
        [GetHashKey("WEAPON_NAVYREVOLVER")] = "Navy Revolver",
        [GetHashKey("WEAPON_MICROSMG")] = "Micro SMG",
        [GetHashKey("WEAPON_SMG")] = "SMG",
        [GetHashKey("WEAPON_SMG_MK2")] = "SMG MK2",
        [GetHashKey("WEAPON_ASSAULTSMG")] = "Assault SMG",
        [GetHashKey("WEAPON_COMBATPDW")] = "Combat PDW",
        [GetHashKey("WEAPON_MACHINEPISTOL")] = "Machine Pistol",
        [GetHashKey("WEAPON_MINISMG")] = "Mini SMG",
        [GetHashKey("WEAPON_GUSENBERG")] = "Gusenberg Sweeper",
        [GetHashKey("WEAPON_PUMPSHOTGUN")] = "Pump Shotgun",
        [GetHashKey("WEAPON_PUMPSHOTGUN_MK2")] = "Pump Shotgun MK2",
        [GetHashKey("WEAPON_SAWNOFFSHOTGUN")] = "Sawed-Off Shotgun",
        [GetHashKey("WEAPON_ASSAULTSHOTGUN")] = "Assault Shotgun",
        [GetHashKey("WEAPON_BULLPUPSHOTGUN")] = "Bullpup Shotgun",
        [GetHashKey("WEAPON_MUSKET")] = "Musket",
        [GetHashKey("WEAPON_HEAVYSHOTGUN")] = "Heavy Shotgun",
        [GetHashKey("WEAPON_DBSHOTGUN")] = "Double Barrel Shotgun",
        [GetHashKey("WEAPON_AUTOSHOTGUN")] = "Auto Shotgun",
        [GetHashKey("WEAPON_COMBATSHOTGUN")] = "Combat Shotgun",
        [GetHashKey("WEAPON_ASSAULTRIFLE")] = "Assault Rifle",
        [GetHashKey("WEAPON_ASSAULTRIFLE_MK2")] = "Assault Rifle MK2",
        [GetHashKey("WEAPON_CARBINERIFLE")] = "Carbine Rifle",
        [GetHashKey("WEAPON_CARBINERIFLE_MK2")] = "Carbine Rifle MK2",
        [GetHashKey("WEAPON_ADVANCEDRIFLE")] = "Advanced Rifle",
        [GetHashKey("WEAPON_SPECIALCARBINE")] = "Special Carbine",
        [GetHashKey("WEAPON_SPECIALCARBINE_MK2")] = "Special Carbine MK2",
        [GetHashKey("WEAPON_BULLPUPRIFLE")] = "Bullpup Rifle",
        [GetHashKey("WEAPON_BULLPUPRIFLE_MK2")] = "Bullpup Rifle MK2",
        [GetHashKey("WEAPON_COMPACTRIFLE")] = "Compact Rifle",
        [GetHashKey("WEAPON_MILITARYRIFLE")] = "Military Rifle",
        [GetHashKey("WEAPON_HEAVYRIFLE")] = "Heavy Rifle",
        [GetHashKey("WEAPON_TACTICALRIFLE")] = "Tactical Rifle",
        [GetHashKey("WEAPON_SNIPERRIFLE")] = "Sniper Rifle",
        [GetHashKey("WEAPON_HEAVYSNIPER")] = "Heavy Sniper",
        [GetHashKey("WEAPON_HEAVYSNIPER_MK2")] = "Heavy Sniper MK2",
        [GetHashKey("WEAPON_MARKSMANRIFLE")] = "Marksman Rifle",
        [GetHashKey("WEAPON_MARKSMANRIFLE_MK2")] = "Marksman Rifle MK2",
        [GetHashKey("WEAPON_PRECISIONRIFLE")] = "Precision Rifle",
        [GetHashKey("WEAPON_RPG")] = "RPG",
        [GetHashKey("WEAPON_GRENADELAUNCHER")] = "Grenade Launcher",
        [GetHashKey("WEAPON_GRENADELAUNCHER_SMOKE")] = "Grenade Launcher Smoke",
        [GetHashKey("WEAPON_MINIGUN")] = "Minigun",
        [GetHashKey("WEAPON_FIREWORK")] = "Firework Launcher",
        [GetHashKey("WEAPON_RAILGUN")] = "Railgun",
        [GetHashKey("WEAPON_HOMINGLAUNCHER")] = "Homing Launcher",
        [GetHashKey("WEAPON_COMPACTLAUNCHER")] = "Compact Grenade Launcher",
        [GetHashKey("WEAPON_RAYMINIGUN")] = "Widowmaker",
        [GetHashKey("WEAPON_EMPLAUNCHER")] = "Compact EMP Launcher",
        [GetHashKey("WEAPON_RAILGUNXM3")] = "Railgun XM3",
    }

    return weaponHashToName[weaponHash] or "Unknown Weapon"
end

local function GetESPSettings()
    local settings = {}
    for _, cat in ipairs(Menu.Categories) do
        if cat.name == "Visual" and cat.tabs then
            for _, tab in ipairs(cat.tabs) do
                if tab.name == "ESP" and tab.items then
                    for _, item in ipairs(tab.items) do
                        settings[item.name] = item
                    end
                end
            end
        end
    end
    return settings
end

local espSettings = nil

local ESPCache = {}
local ESPCacheTime = 0
local ESPCacheMaxAge = 0.016

local function GetScreenSize()
    if Susano and Susano.GetScreenWidth and Susano.GetScreenHeight then
        local w, h = Susano.GetScreenWidth(), Susano.GetScreenHeight()
        if w and h and w > 0 and h > 0 then
            return w, h
        end
    end

    local w, h = GetActiveScreenResolution()
    return w, h
end

if not GetScreenCoordFromWorldCoord or type(GetScreenCoordFromWorldCoord) ~= "function" then
    GetScreenCoordFromWorldCoord = function(x, y, z)
        if World3dToScreen2d then
            return World3dToScreen2d(x, y, z)
        else
            return false, 0.0, 0.0
        end
    end
end

local function Draw2DBox(x1, y1, x2, y2, r, g, b, a, screenW, screenH)
    if not Susano.DrawLine then return end

    local w = x2 - x1
    local h = y2 - y1

    Susano.DrawLine(x1 * screenW, y1 * screenH, x2 * screenW, y1 * screenH, r, g, b, a, 1)
    Susano.DrawLine(x1 * screenW, y2 * screenH, x2 * screenW, y2 * screenH, r, g, b, a, 1)
    Susano.DrawLine(x1 * screenW, y1 * screenH, x1 * screenW, y2 * screenH, r, g, b, a, 1)
    Susano.DrawLine(x2 * screenW, y1 * screenH, x2 * screenW, y2 * screenH, r, g, b, a, 1)
end

local function DrawFilledRect(x, y, w, h, r, g, b, a)
    if Susano.DrawRectFilled then
        Susano.DrawRectFilled(x, y, w, h, r, g, b, a, 0)
    elseif Susano.DrawRect then
        for i = 0, h do
            Susano.DrawRect(x, y + i, w, 1, r, g, b, a)
        end
    end
end

local infiniteStaminaActive = false
local function ToggleInfiniteStamina(enable)
    infiniteStaminaActive = enable
    if enable then
        Citizen.CreateThread(function()
            while infiniteStaminaActive do
                RestorePlayerStamina(PlayerId(), 1.0)
                Citizen.Wait(0)
            end
        end)
    end
end

local function DeleteAllProps()
    local handle, object = FindFirstObject()
    local success
    repeat
        if DoesEntityExist(object) then
            SetEntityAsMissionEntity(object, true, true)
            DeleteObject(object)
        end
        success, object = FindNextObject(handle)
    until not success
    EndFindObject(handle)
end

local throwVehicleActive = false
local function ToggleThrowVehicle(enable)
    throwVehicleActive = enable
    if enable then
        Citizen.CreateThread(function()
            local holdingEntity = false
            local heldEntity = nil

            local function RotationToDirection(rotation)
                local adjustedRotation = vector3((math.pi / 180) * rotation.x, (math.pi / 180) * rotation.y, (math.pi / 180) * rotation.z)
                local direction = vector3(-math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)), math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)), math.sin(adjustedRotation.x))
                return direction
            end

            while throwVehicleActive do
                Citizen.Wait(0)
                local playerPed = PlayerPedId()
                local screenW, screenH = GetScreenSize()

                if holdingEntity and heldEntity and DoesEntityExist(heldEntity) then
                    if not IsEntityPlayingAnim(playerPed, 'anim@mp_rollarcoaster', 'hands_up_idle_a_player_one', 3) then
                        RequestAnimDict('anim@mp_rollarcoaster')
                        while not HasAnimDictLoaded('anim@mp_rollarcoaster') do
                            Citizen.Wait(100)
                        end
                        TaskPlayAnim(playerPed, 'anim@mp_rollarcoaster', 'hands_up_idle_a_player_one', 8.0, -8.0, -1, 50, 0, false, false, false)
                    end

                    if IsControlJustReleased(0, 38) then
                        local camRot = GetGameplayCamRot(2)
                        local direction = RotationToDirection(camRot)
                        DetachEntity(heldEntity, true, true)
                        ApplyForceToEntity(heldEntity, 1, direction.x * 500.0, direction.y * 500.0, direction.z * 500.0, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
                        holdingEntity = false
                        heldEntity = nil
                        ClearPedTasks(playerPed)
                    end

                    if heldEntity and not IsEntityAttached(heldEntity) and holdingEntity then
                        NetworkRequestControlOfEntity(heldEntity)
                        AttachEntityToEntity(heldEntity, playerPed, GetPedBoneIndex(playerPed, 60309), 1.0, 0.5, 0.0, 0.0, 0.0, 0.0, true, true, false, false, 1, true)
                    end
                else
                    local camPos = GetGameplayCamCoord()
                    local camRot = GetGameplayCamRot(2)
                    local direction = RotationToDirection(camRot)
                    local dest = vector3(camPos.x + direction.x * 300.0, camPos.y + direction.y * 300.0, camPos.z + direction.z * 300.0)

                    local rayHandle = StartShapeTestRay(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, -1, playerPed, 0)
                    local _, hit, _, _, entityHit = GetShapeTestResult(rayHandle)

                    if hit == 1 and DoesEntityExist(entityHit) then
                        local entityType = GetEntityType(entityHit)
                        if entityType == 2 then
                            local min, max = GetModelDimensions(GetEntityModel(entityHit))
                            local corners = {
                                vector3(min.x, min.y, min.z), vector3(min.x, min.y, max.z),
                                vector3(min.x, max.y, min.z), vector3(min.x, max.y, max.z),
                                vector3(max.x, min.y, min.z), vector3(max.x, min.y, max.z),
                                vector3(max.x, max.y, min.z), vector3(max.x, max.y, max.z)
                            }

                            local minX, minY, maxX, maxY = 1.0, 1.0, 0.0, 0.0
                            local hasScreen = false
                            for _, corner in pairs(corners) do
                                local world = GetOffsetFromEntityInWorldCoords(entityHit, corner.x, corner.y, corner.z)
                                local onScreen, x, y = GetScreenCoordFromWorldCoord(world.x, world.y, world.z)
                                if onScreen then
                                    hasScreen = true
                                    if x < minX then minX = x end
                                    if x > maxX then maxX = x end
                                    if y < minY then minY = y end
                                    if y > maxY then maxY = y end
                                end
                            end

                            if hasScreen then
                                local r, g, b = 255, 0, 0
                                if NetworkHasControlOfEntity(entityHit) then
                                    r, g, b = 0, 255, 0
                                end
                                Draw2DBox(minX, minY, maxX, maxY, r, g, b, 255, screenW, screenH)
                            end

                            if IsControlJustReleased(0, 38) then
                                holdingEntity = true
                                heldEntity = entityHit
                                NetworkRequestControlOfEntity(heldEntity)
                                AttachEntityToEntity(heldEntity, playerPed, GetPedBoneIndex(playerPed, 60309), 1.0, 0.5, 0.0, 0.0, 0.0, 0.0, true, true, false, false, 1, true)
                            end
                        end
                    end
                end
            end

            if heldEntity then
                DetachEntity(heldEntity, true, true)
                ClearPedTasks(PlayerPedId())
            end
        end)
    end
end

local function RenderPedESP(targetPed, playerIdx, settings, screenW, screenH, myPos)
    if not DoesEntityExist(targetPed) then return end

    local targetPos = GetEntityCoords(targetPed)
    local dist = #(myPos - targetPos)

    if dist > 10000.0 then return end

    local cacheKey = tostring(targetPed) .. "_" .. tostring(playerIdx)
    local currentTime = GetGameTimer() or 0
    local cached = ESPCache[cacheKey]
    local onScreen, screenX, screenY

    if cached and (currentTime - cached.time) < 16 then
        onScreen = cached.onScreen
        screenX = cached.screenX
        screenY = cached.screenY
    else
        onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(targetPos.x, targetPos.y, targetPos.z)
        ESPCache[cacheKey] = {
            onScreen = onScreen,
            screenX = screenX,
            screenY = screenY,
            time = currentTime
        }
    end

    if onScreen then

        local drawSkeleton = settings["Draw Skeleton"] and settings["Draw Skeleton"].value
        local drawBox = settings["Draw Box"] and settings["Draw Box"].value
        local drawLine = settings["Draw Line"] and settings["Draw Line"].value
        local drawHealth = settings["Draw Health"] and settings["Draw Health"].value
        local drawArmor = settings["Draw Armor"] and settings["Draw Armor"].value

        local drawNameItem = settings["Draw Name"]
        local drawName = drawNameItem and drawNameItem.value
        local drawNamePosItem = settings["Name Position"]
        local drawNamePos = (drawNamePosItem and drawNamePosItem.selected) or 1

        local drawIDItem = settings["Draw ID"]
        local drawID = drawIDItem and drawIDItem.value
        local drawIDPosItem = settings["ID Position"]
        local drawIDPos = (drawIDPosItem and drawIDPosItem.selected) or 1

        local drawDistItem = settings["Draw Distance"]
        local drawDist = drawDistItem and drawDistItem.value
        local drawDistPosItem = settings["Distance Position"]
        local drawDistPos = (drawDistPosItem and drawDistPosItem.selected) or 1

        local drawWeaponItem = settings["Draw Weapon"]
        local drawWeapon = drawWeaponItem and drawWeaponItem.value
        local drawWeaponPosItem = settings["Weapon Position"]
        local drawWeaponPos = (drawWeaponPosItem and drawWeaponPosItem.selected) or 1

        local skelColor = ESPColors[1]
        if settings["Skeleton Color"] then skelColor = ESPColors[settings["Skeleton Color"].selected] or skelColor end

        local boxColor = ESPColors[1]
        if settings["Box Color"] then boxColor = ESPColors[settings["Box Color"].selected] or boxColor end

        local lineColor = ESPColors[1]
        if settings["Line Color"] then lineColor = ESPColors[settings["Line Color"].selected] or lineColor end

        local textColor = ESPColors[1]
        if settings["Text Color"] then textColor = ESPColors[settings["Text Color"].selected] or textColor end

        if drawSkeleton then
            local boneCache = {}
            for _, connection in ipairs(SkeletonConnections) do
                local bone1 = connection[1]
                local bone2 = connection[2]

                local pos1 = boneCache[bone1]
                if not pos1 then
                    pos1 = GetPedBoneCoords(targetPed, bone1, 0.0, 0.0, 0.0)
                    boneCache[bone1] = pos1
                end

                local pos2 = boneCache[bone2]
                if not pos2 then
                    pos2 = GetPedBoneCoords(targetPed, bone2, 0.0, 0.0, 0.0)
                    boneCache[bone2] = pos2
                end

                local os1, x1, y1 = GetScreenCoordFromWorldCoord(pos1.x, pos1.y, pos1.z)
                local os2, x2, y2 = GetScreenCoordFromWorldCoord(pos2.x, pos2.y, pos2.z)

                if os1 and os2 and x1 and y1 and x2 and y2 and
                   x1 >= 0 and x1 <= 1 and y1 >= 0 and y1 <= 1 and
                   x2 >= 0 and x2 <= 1 and y2 >= 0 and y2 <= 1 and
                   Susano.DrawLine then

                    Susano.DrawLine(x1 * screenW, y1 * screenH, x2 * screenW, y2 * screenH, 0.0, 0.0, 0.0, 1.0, 2)

                    Susano.DrawLine(x1 * screenW, y1 * screenH, x2 * screenW, y2 * screenH, skelColor[1], skelColor[2], skelColor[3], 1.0, 1)
                end
            end
        end

        local headPos = GetPedBoneCoords(targetPed, 31086, 0.0, 0.0, 0.0)
        local footPos = GetEntityCoords(targetPed)
        footPos = vector3(footPos.x, footPos.y, footPos.z - 1.0)

        local headCacheKey = cacheKey .. "_head"
        local footCacheKey = cacheKey .. "_foot"
        local cachedHead = ESPCache[headCacheKey]
        local cachedFoot = ESPCache[footCacheKey]
        local headX, headY, footX, footY

        if cachedHead and (currentTime - cachedHead.time) < 16 then
            headX = cachedHead.x
            headY = cachedHead.y
        else
            local _, hX, hY = GetScreenCoordFromWorldCoord(headPos.x, headPos.y, headPos.z + 0.3)
            headX, headY = hX, hY
            ESPCache[headCacheKey] = {x = headX, y = headY, time = currentTime}
        end

        if cachedFoot and (currentTime - cachedFoot.time) < 16 then
            footX = cachedFoot.x
            footY = cachedFoot.y
        else
            local _, fX, fY = GetScreenCoordFromWorldCoord(footPos.x, footPos.y, footPos.z)
            footX, footY = fX, fY
            ESPCache[footCacheKey] = {x = footX, y = footY, time = currentTime}
        end

        if not headX or not headY or not footX or not footY then return end

        local height = math.abs(headY - footY)
        if height < 0.01 then return end

        local width = height * 0.35

        local boxX1 = headX - width * 0.5
        local boxX2 = headX + width * 0.5
        local boxY1 = headY
        local boxY2 = footY

        if boxY1 > boxY2 then boxY1, boxY2 = boxY2, boxY1 end

        if drawBox and boxX1 and boxX2 and boxY1 and boxY2 then

            Draw2DBox(boxX1 - 0.0005, boxY1 - 0.0005, boxX2 + 0.0005, boxY2 + 0.0005, 0.0, 0.0, 0.0, 1.0, screenW, screenH)

            Draw2DBox(boxX1, boxY1, boxX2, boxY2, boxColor[1], boxColor[2], boxColor[3], 1.0, screenW, screenH)
        end

        if drawLine and Susano.DrawLine and footX and footY then
             Susano.DrawLine(screenW / 2, screenH, footX * screenW, footY * screenH, lineColor[1], lineColor[2], lineColor[3], 1.0, 1)
        end

        local textBuckets = { [2] = "", [3] = "", [4] = "", [5] = "" }

        local function AddToBucket(sel, text)
            if sel > 1 and textBuckets[sel] then
                textBuckets[sel] = textBuckets[sel] .. text .. "\n"
            end
        end

        if drawName then AddToBucket(drawNamePos + 1, GetPlayerName(playerIdx)) end
        if drawID then AddToBucket(drawIDPos + 1, "ID: " .. GetPlayerServerId(playerIdx)) end
        if drawDist then AddToBucket(drawDistPos + 1, math.floor(dist) .. "m") end
        if drawWeapon then
             local _, weaponHash = GetCurrentPedWeapon(targetPed, true)
             local weaponName = GetWeaponNameFromHash(weaponHash)

             AddToBucket(drawWeaponPos + 1, weaponName)
        end

        if Susano.DrawText then
            local function DrawTextWithOutline(x, y, text, size, r, g, b, a)

                Susano.DrawText(x - 1, y - 1, text, size, 0.0, 0.0, 0.0, 1.0)
                Susano.DrawText(x, y - 1, text, size, 0.0, 0.0, 0.0, 1.0)
                Susano.DrawText(x + 1, y - 1, text, size, 0.0, 0.0, 0.0, 1.0)
                Susano.DrawText(x - 1, y, text, size, 0.0, 0.0, 0.0, 1.0)
                Susano.DrawText(x + 1, y, text, size, 0.0, 0.0, 0.0, 1.0)
                Susano.DrawText(x - 1, y + 1, text, size, 0.0, 0.0, 0.0, 1.0)
                Susano.DrawText(x, y + 1, text, size, 0.0, 0.0, 0.0, 1.0)
                Susano.DrawText(x + 1, y + 1, text, size, 0.0, 0.0, 0.0, 1.0)

                Susano.DrawText(x, y, text, size, r, g, b, a)
            end

            if textBuckets[2] ~= "" and boxX1 and boxX2 and boxY1 then
                local textX = (boxX1 + boxX2)/2 * screenW
                local textY = boxY1 * screenH - 15
                DrawTextWithOutline(textX, textY, textBuckets[2], 14, textColor[1], textColor[2], textColor[3], 1.0)
            end

            if textBuckets[3] ~= "" and boxX1 and boxX2 and boxY2 then
                local textX = (boxX1 + boxX2)/2 * screenW
                local textY = boxY2 * screenH + 5
                DrawTextWithOutline(textX, textY, textBuckets[3], 14, textColor[1], textColor[2], textColor[3], 1.0)
            end

            if textBuckets[4] ~= "" and boxX1 and boxY1 then
                local textX = boxX1 * screenW - 50
                local textY = boxY1 * screenH
                DrawTextWithOutline(textX, textY, textBuckets[4], 14, textColor[1], textColor[2], textColor[3], 1.0)
            end

            if textBuckets[5] ~= "" and boxX2 and boxY1 then
                local textX = boxX2 * screenW + 5
                local textY = boxY1 * screenH
                DrawTextWithOutline(textX, textY, textBuckets[5], 14, textColor[1], textColor[2], textColor[3], 1.0)
            end
        end

        if (drawHealth or drawArmor) and boxX1 and boxY1 and boxY2 then
            local barW = 2

            if drawHealth then
                local health = GetEntityHealth(targetPed)
                local maxHealth = GetEntityMaxHealth(targetPed)
                local healthPct = (health - 100) / (maxHealth - 100)
                if healthPct < 0 then healthPct = 0 end
                if healthPct > 1 then healthPct = 1 end

                local barH = (boxY2 - boxY1) * screenH
                if barH > 0 then
                    local barX = (boxX1 * screenW) - (barW + 2)
                    local barY = boxY1 * screenH

                    DrawFilledRect(barX - 1, barY - 1, barW + 2, barH + 2, 0.0, 0.0, 0.0, 1.0)

                    local fillH = barH * healthPct
                    DrawFilledRect(barX, barY + (barH - fillH), barW, fillH, 0.0, 1.0, 0.0, 1.0)
                end
            end

            if drawArmor then
                local armor = GetPedArmour(targetPed)
                local armorPct = armor / 100.0
                if armorPct > 1 then armorPct = 1 end

                if armorPct > 0 then
                    local barH = (boxY2 - boxY1) * screenH
                    if barH > 0 then

                        local offset = (barW + 2)
                        if drawHealth then offset = offset + (barW + 2) end

                        local barX = (boxX1 * screenW) - offset
                        local barY = boxY1 * screenH

                        DrawFilledRect(barX - 1, barY - 1, barW + 2, barH + 2, 0.0, 0.0, 0.0, 1.0)

                        local fillH = barH * armorPct
                        DrawFilledRect(barX, barY + (barH - fillH), barW, fillH, 0.0, 0.0, 1.0, 1.0)
                    end
                end
            end
        end
    end
end

local function GetWorldSettings()
    local settings = {}
    for _, cat in ipairs(Menu.Categories) do
        if cat.name == "Visual" and cat.tabs then
            for _, tab in ipairs(cat.tabs) do
                if tab.name == "World" and tab.items then
                    for _, item in ipairs(tab.items) do
                        settings[item.name] = item
                    end
                end
            end
        end
    end
    return settings
end

local worldSettings = nil

local function RenderWorldVisuals(settings)
    if not settings then return end

    Actions.fpsBoostItem = settings["FPS Boost"]
    if Actions.fpsBoostItem and Actions.fpsBoostItem.value then
        if OverrideLodscaleThisFrame then OverrideLodscaleThisFrame(0.35) end
        if SetDisableDecalRenderingThisFrame then SetDisableDecalRenderingThisFrame() end

        if Menu.RopeDrawShadowEnabled then Menu.RopeDrawShadowEnabled(false) end
        if CascadeShadowsClearShadow then CascadeShadowsClearShadow() end

        if SetReducePedModelBudget then SetReducePedModelBudget(true) end
        if SetReduceVehicleModelBudget then SetReduceVehicleModelBudget(true) end
        if DisableVehicleDistantlights then DisableVehicleDistantlights(true) end
        if SetDeepOceanScaler then SetDeepOceanScaler(0.0) end
        if SetGrassCullDistanceScale then SetGrassCullDistanceScale(0.0) end
    else
        if Menu.RopeDrawShadowEnabled then Menu.RopeDrawShadowEnabled(true) end
        if SetReducePedModelBudget then SetReducePedModelBudget(false) end
        if SetReduceVehicleModelBudget then SetReduceVehicleModelBudget(false) end
        if DisableVehicleDistantlights then DisableVehicleDistantlights(false) end
        if SetDeepOceanScaler then SetDeepOceanScaler(1.0) end
        if SetGrassCullDistanceScale then SetGrassCullDistanceScale(1.0) end
    end

Actions.blossomItem = FindItem("Settings", "General", "Blossom")
if Actions.blossomItem then
    Actions.blossomItem.onClick = function(value)
        Menu.ShowBlossoms = value
    end
end

    Actions.timeItem = settings["Time"]
    Actions.freezeItem = settings["Freeze Time"]

    if Actions.freezeItem and Actions.freezeItem.value then
        if Actions.timeItem then
            NetworkOverrideClockTime(math.floor(Actions.timeItem.value), 0, 0)
        end
    end

    Actions.weatherItem = settings["Weather"]
    if Actions.weatherItem and Actions.weatherItem.options then
        local selectedWeather = Actions.weatherItem.options[Actions.weatherItem.selected]
        if selectedWeather then
             SetWeatherTypeNowPersist(selectedWeather)
        end
    end

    Actions.blackoutItem = settings["Blackout"]
    if Actions.blackoutItem then
        SetBlackout(Actions.blackoutItem.value)
    end
end

local function FindItem(categoryName, tabName, itemName)
    if not Menu or not Menu.Categories or type(Menu.Categories) ~= "table" then
        return nil
    end

    local success, result = pcall(function()
        for _, cat in ipairs(Menu.Categories) do
            if cat and type(cat) == "table" and cat.name == categoryName then
                if cat.tabs and type(cat.tabs) == "table" then
                    for _, tab in ipairs(cat.tabs) do
                        if tab and type(tab) == "table" and tab.name == tabName and tab.items and type(tab.items) == "table" then
                            for _, item in ipairs(tab.items) do
                                if item and type(item) == "table" and item.name == itemName then
                                    return item
                                end
                            end
                        end
                    end
                elseif cat.items and type(cat.items) == "table" and (tabName == nil or tabName == "") then
                    for _, item in ipairs(cat.items) do
                        if item and type(item) == "table" and item.name == itemName then
                            return item
                        end
                    end
                end
            end
        end
        return nil
    end)

    if success then
        return result
    else
        print("FindItem error: " .. tostring(result))
        return nil
    end
end

local lastNoclipSpeed = 1.0
local noclipType = "normal"

local spectateActive = false
local spectateCamera = nil

local function ToggleSpectate(enable)
    if enable then
        if not Menu.SelectedPlayer then
            Menu.PlayerListSpectateEnabled = false
            return
        end

        spectateActive = true
        local targetServerId = Menu.SelectedPlayer

        if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
            Susano.InjectResource("any", string.format([[
                local targetServerId = %d
                local spectateThreadActive = true
                local playerPed = PlayerPedId()

                CreateThread(function()
                    while spectateThreadActive do
                        Wait(0)

                        local targetPlayerId = nil
                        for _, player in ipairs(GetActivePlayers()) do
                            if GetPlayerServerId(player) == targetServerId then
                                targetPlayerId = player
                                break
                            end
                        end

                        if targetPlayerId then
                            local targetPed = GetPlayerPed(targetPlayerId)
                            if DoesEntityExist(targetPed) then
                                NetworkSetInSpectatorMode(true, targetPed)
                            else
                                spectateThreadActive = false
                                NetworkSetInSpectatorMode(false, playerPed)
                                break
                            end
                        else
                            spectateThreadActive = false
                            NetworkSetInSpectatorMode(false, playerPed)
                            break
                        end
                    end

                    NetworkSetInSpectatorMode(false, playerPed)
                end)

                rawset(_G, 'spectate_thread_active_' .. targetServerId, function()
                    spectateThreadActive = false
                    NetworkSetInSpectatorMode(false, playerPed)
                end)
            ]], targetServerId))
        end
    else
        spectateActive = false
        Menu.PlayerListSpectateEnabled = false

        if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
            local targetServerId = Menu.SelectedPlayer
            if targetServerId then
                Susano.InjectResource("any", string.format([[
                    local stopFunction = rawget(_G, 'spectate_thread_active_' .. %d)
                    if stopFunction then
                        stopFunction()
                        rawset(_G, 'spectate_thread_active_' .. %d, nil)
                    end
                    NetworkSetInSpectatorMode(false, PlayerPedId())
                ]], targetServerId, targetServerId))
            else
                Susano.InjectResource("any", [[
                    NetworkSetInSpectatorMode(false, PlayerPedId())
                ]])
            end
        end
    end
end

local function UpdatePlayerList()
    for _, cat in ipairs(Menu.Categories) do
        if cat.name == "Online" and cat.tabs then
            for tabIdx, tab in ipairs(cat.tabs) do
                if tab.name == "Player List" then
                    for _, item in ipairs(tab.items) do
                        if item.type == "selector" then
                            if item.name == "Select" then
                                Menu.PlayerListSelectIndex = item.selected or 1
                            elseif item.name == "Teleport" then
                                Menu.PlayerListTeleportIndex = item.selected or 1
                            elseif item.name == "Type" then
                                Menu.PlayerListTypeIndex = item.selected or 1
                            end
                        elseif item.type == "toggle" and item.name == "Spectate Player" then
                            Menu.PlayerListSpectateEnabled = item.value or false
                        end
                    end

                    tab.items = {}

                    Actions.spectateItem = {
                        name = "Spectate Player",
                        type = "toggle",
                        value = Menu.PlayerListSpectateEnabled
                    }
                    Actions.spectateItem.onClick = function(value)
                        Menu.PlayerListSpectateEnabled = value
                        ToggleSpectate(value)
                    end
                    table.insert(tab.items, Actions.spectateItem)

                    Actions.teleportItem = {
                        name = "Teleport",
                        type = "selector",
                        options = {"To Player", "Into Vehicle"},
                        selected = Menu.PlayerListTeleportIndex
                    }
                    Actions.teleportItem.onClick = function(index, option)
                        if not Menu.SelectedPlayer then return end

                        if index == 1 then
                            for _, player in ipairs(GetActivePlayers()) do
                                if GetPlayerServerId(player) == Menu.SelectedPlayer then
                                    local targetPed = GetPlayerPed(player)
                                    if DoesEntityExist(targetPed) then
                                        local coords = GetEntityCoords(targetPed)
                                        SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z)
                                    end
                                    break
                                end
                            end
                        elseif index == 2 then
                            for _, player in ipairs(GetActivePlayers()) do
                                if GetPlayerServerId(player) == Menu.SelectedPlayer then
                                    local targetPed = GetPlayerPed(player)
                                    if DoesEntityExist(targetPed) then
                                        local vehicle = GetVehiclePedIsIn(targetPed, false)
                                        if vehicle and vehicle ~= 0 then
                                            TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -2)
                                        end
                                    end
                                    break
                                end
                            end
                        end
                    end
                    table.insert(tab.items, Actions.teleportItem)

                    local localPed = PlayerPedId()
                    if not localPed or localPed == 0 then return end

                    local localCoords = GetEntityCoords(localPed)
                    local myPlayerId = PlayerId()
                    local myServerId = GetPlayerServerId(myPlayerId)
                    local myName = GetPlayerName(myPlayerId)

                    local otherPlayers = {}
                    local typeFilter = Menu.PlayerListTypeIndex or 1
                    for _, player in ipairs(GetActivePlayers()) do
                        if player ~= myPlayerId then
                            local targetPed = GetPlayerPed(player)
                            if targetPed and DoesEntityExist(targetPed) then
                                local isInVehicle = IsPedInAnyVehicle(targetPed, false)
                                local shouldShow = false
                                
                                if typeFilter == 1 then
                                    shouldShow = true
                                elseif typeFilter == 2 then
                                    shouldShow = not isInVehicle
                                elseif typeFilter == 3 then
                                    shouldShow = isInVehicle
                                end
                                
                                if shouldShow then
                                    local targetCoords = GetEntityCoords(targetPed)
                                    local distance = #(localCoords - targetCoords)

                                    local playerId = GetPlayerServerId(player)
                                    local playerName = GetPlayerName(player)
                                    table.insert(otherPlayers, {
                                        id = playerId,
                                        name = playerName,
                                        distance = math.floor(distance)
                                    })
                                end
                            end
                        end
                    end

                    table.sort(otherPlayers, function(a, b) return a.distance < b.distance end)

                    Actions.selectModeItem = {
                        name = "Select",
                        type = "selector",
                        options = {"Select All", "Unselect All"},
                        selected = Menu.PlayerListSelectIndex
                    }
                    Actions.selectModeItem.onClick = function(index, option)
                        if index == 1 then
                            Menu.SelectedPlayers = {}
                            table.insert(Menu.SelectedPlayers, myServerId)
                            Menu.SelectedPlayer = myServerId
                            for _, playerData in ipairs(otherPlayers) do
                                table.insert(Menu.SelectedPlayers, playerData.id)
                            end
                        elseif index == 2 then
                            Menu.SelectedPlayer = nil
                            Menu.SelectedPlayers = {}
                        end
                    end
                    table.insert(tab.items, Actions.selectModeItem)

                    Menu.PlayerListTypeIndex = Menu.PlayerListTypeIndex or 1
                    Actions.typeItem = {
                        name = "Type",
                        type = "selector",
                        options = {"None", "On Foot", "In Vehicle"},
                        selected = Menu.PlayerListTypeIndex
                    }
                    Actions.typeItem.onClick = function(index, option)
                        Menu.PlayerListTypeIndex = index
                    end
                    table.insert(tab.items, Actions.typeItem)

                    table.insert(tab.items, {
                        name = "",
                        isSeparator = true,
                        separatorText = "Player List"
                    })

                    local function isPlayerSelected(playerId)
                        for _, selectedId in ipairs(Menu.SelectedPlayers) do
                            if selectedId == playerId then
                                return true
                            end
                        end
                        return false
                    end

                    local function togglePlayerSelection(playerId)
                        local found = false
                        for i, selectedId in ipairs(Menu.SelectedPlayers) do
                            if selectedId == playerId then
                                table.remove(Menu.SelectedPlayers, i)
                                found = true
                                break
                            end
                        end
                        if not found then
                            table.insert(Menu.SelectedPlayers, playerId)
                            Menu.SelectedPlayer = playerId
                        else
                            if Menu.SelectedPlayer == playerId then
                                Menu.SelectedPlayer = Menu.SelectedPlayers[1] or nil
                            end
                        end
                    end

                    local myPed = PlayerPedId()
                    local myIsInVehicle = IsPedInAnyVehicle(myPed, false)
                    local shouldShowSelf = false
                    
                    if typeFilter == 1 then
                        shouldShowSelf = true
                    elseif typeFilter == 2 then
                        shouldShowSelf = not myIsInVehicle
                    elseif typeFilter == 3 then
                        shouldShowSelf = myIsInVehicle
                    end
                    
                    if shouldShowSelf then
                        local selfToggle = {
                            name = myName .. " (You)",
                            type = "toggle",
                            value = isPlayerSelected(myServerId),
                            playerId = myServerId,
                            isSelf = true
                        }
                        selfToggle.onClick = function(value)
                            togglePlayerSelection(selfToggle.playerId)
                        end
                        table.insert(tab.items, selfToggle)
                    end

                    for _, playerData in ipairs(otherPlayers) do
                        local playerToggle = {
                            name = playerData.name .. " (" .. playerData.distance .. "m)",
                            type = "toggle",
                            value = isPlayerSelected(playerData.id),
                            playerId = playerData.id
                        }
                        playerToggle.onClick = function(value)
                            togglePlayerSelection(playerToggle.playerId)
                        end
                        table.insert(tab.items, playerToggle)
                    end

                    return
                end
            end
        end
    end
end

Citizen.CreateThread(function()
    Wait(500)
    while true do
        UpdatePlayerList()
        Wait(0)
    end
end)

Menu.OnRender = function()
    Actions.noclipItem = FindItem("Player", "Movement", "Noclip")
    if Actions.noclipItem and Actions.noclipItem.value then
        local currentSpeed = Actions.noclipItem.sliderValue or 1.0
        if lastNoclipSpeed ~= currentSpeed then
            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                Susano.InjectResource("any", string.format([[
                    if _G then
                        _G.NoclipSpeed = %s
                    end
                ]], tostring(currentSpeed)))
            end
            lastNoclipSpeed = currentSpeed
        end
    end

    if not espSettings then espSettings = GetESPSettings() end
    if not worldSettings then worldSettings = GetWorldSettings() end

    RenderWorldVisuals(worldSettings)

    local drawSelf = espSettings["Draw Self"] and espSettings["Draw Self"].value
    local enablePlayerESP = espSettings["Enable Player ESP"] and espSettings["Enable Player ESP"].value

    if drawSelf or enablePlayerESP then
        Menu.PreventResetFrame = true

        local ped = PlayerPedId()
        local screenW, screenH = GetScreenSize()
        if not screenW or not screenH then return end

        local myPos = GetEntityCoords(ped)

        if drawSelf then
            RenderPedESP(ped, PlayerId(), espSettings, screenW, screenH, myPos)
        end

        if enablePlayerESP then

            local players = {}
            for _, player in ipairs(GetActivePlayers()) do
                local targetPed = GetPlayerPed(player)
                if targetPed and targetPed ~= 0 and targetPed ~= ped and DoesEntityExist(targetPed) then
                    local targetPos = GetEntityCoords(targetPed)
                    local dist = #(myPos - targetPos)
                    if dist <= 10000.0 then
                        table.insert(players, {player = player, ped = targetPed, dist = dist})
                    end
                end
            end

            table.sort(players, function(a, b) return a.dist < b.dist end)

            for _, data in ipairs(players) do
                RenderPedESP(data.ped, data.player, espSettings, screenW, screenH, myPos)
            end

            local currentTime = GetGameTimer() or 0
            if currentTime - ESPCacheTime > 1000 then
                ESPCacheTime = currentTime
                for k, v in pairs(ESPCache) do
                    if v.time and (currentTime - v.time) > 2000 then
                        ESPCache[k] = nil
                    end
                end
            end
        end
    else
        Menu.PreventResetFrame = false
    end
end

local godmodeActive = false
local godmodeThread = nil

local function ToggleFullGodmode(enable)
    if enable == godmodeActive then return end
    godmodeActive = enable

    if enable then
        godmodeThread = Citizen.CreateThread(function()
            local player = PlayerId()
            local ped = PlayerPedId()
            while godmodeActive do
                SetPlayerInvincible(player, true)
                SetEntityInvincible(ped, true)
                SetEntityProofs(ped, true, true, true, true, true, true, true, true)
                SetPedCanRagdoll(ped, false)
                SetPedRagdollOnCollision(ped, false)
                SetEntityHealth(ped, GetEntityMaxHealth(ped))
                Citizen.Wait(0)
            end
            SetPlayerInvincible(player, false)
            SetEntityInvincible(ped, false)
            SetEntityProofs(ped, false, false, false, false, false, false, false, false)
            SetPedCanRagdoll(ped, true)
            SetPedRagdollOnCollision(ped, true)
        end)
    else
        godmodeActive = false
        if godmodeThread then
            Citizen.StopThread(godmodeThread)
            godmodeThread = nil
        end
        local player = PlayerId()
        local ped = PlayerPedId()
        SetPlayerInvincible(player, false)
        SetEntityInvincible(ped, false)
        SetEntityProofs(ped, false, false, false, false, false, false, false, false)
        SetPedCanRagdoll(ped, true)
        SetPedRagdollOnCollision(ped, true)
    end
end

local function ToggleSemiGodmode(enable)
end

local function ToggleSemiGodmode(enable)
    if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
        return
    end

    local code = string.format([[
        local susano = rawget(_G, "Susano")

        if _G.SemiGodmodeEnabled == nil then _G.SemiGodmodeEnabled = false end
        _G.SemiGodmodeEnabled = %s

        if not _G.SemiGodmodeHooksInstalled and susano and type(susano.HookNative) == "function" then
            _G.SemiGodmodeHooksInstalled = true

            susano.HookNative(0xFAEE099C6F890BB8, function(entity)
                if _G.SemiGodmodeEnabled and entity == PlayerPedId() then
                    return false, false, false, false, false, false, false, false
                end
                return true
            end)

            susano.HookNative(0x697157CED63F18D4, function(ped, damage, armorDamage)
                if _G.SemiGodmodeEnabled and ped == PlayerPedId() then
                    return false
                end
                return true
            end)

            susano.HookNative(0x6B76DC1F3AE6E6A3, function(entity, health)
                if _G.SemiGodmodeEnabled and entity == PlayerPedId() then
                    local maxHealth = GetEntityMaxHealth(entity)
                    if health < maxHealth then
                        return false
                    end
                end
                return true
            end)

            susano.HookNative(0x7C6BCA42, function(ped)
                if _G.SemiGodmodeEnabled and ped == PlayerPedId() then
                    return false
                end
                return true
            end)
        end

        if not _G.SemiGodmodeLoopStarted then
            _G.SemiGodmodeLoopStarted = true
            _G.LastHealth = nil

            if susano and type(susano.HookNative) == "function" then
                susano.HookNative(0xFAEE099C6F890BB8, function(entity)
                    if _G.SemiGodmodeEnabled and entity == PlayerPedId() then
                        return false, false, false, false, false, false, false, false
                    end
                    return true
                end)
            end

            Citizen.CreateThread(function()
                while true do
                    Wait(200)
                    if _G.SemiGodmodeEnabled then
                        local ped = PlayerPedId()
                        if not DoesEntityExist(ped) then goto continue end

                        local currentHealth = GetEntityHealth(ped)
                        local maxHealth = GetEntityMaxHealth(ped)

                        if currentHealth < maxHealth then
                            local regenAmount = math.min(3, maxHealth - currentHealth)
                            SetEntityHealth(ped, currentHealth + regenAmount)
                        end

                        if math.random(1, 10) == 1 then
                            ClearPedBloodDamage(ped)
                            ResetPedVisibleDamage(ped)
                        end

                        _G.LastHealth = currentHealth

                        ::continue::
                    end
                end
            end)

            Citizen.CreateThread(function()
                while true do
                    Wait(10)
                    if _G.SemiGodmodeEnabled then
                        local ped = PlayerPedId()
                        if not DoesEntityExist(ped) then goto continue end

                        local currentHealth = GetEntityHealth(ped)
                        local maxHealth = GetEntityMaxHealth(ped)

                        if _G.LastHealth and currentHealth < _G.LastHealth then
                            local damageTaken = _G.LastHealth - currentHealth
                            if damageTaken > 10 then
                                SetEntityHealth(ped, maxHealth)
                            elseif damageTaken > 5 then
                                local regenAmount = math.min(20, maxHealth - currentHealth)
                                SetEntityHealth(ped, currentHealth + regenAmount)
                            end
                        end

                        if currentHealth < (maxHealth * 0.8) then
                            local regenAmount = math.min(15, maxHealth - currentHealth)
                            SetEntityHealth(ped, currentHealth + regenAmount)
                        end

                        if currentHealth < (maxHealth * 0.5) then
                            SetEntityHealth(ped, maxHealth)
                        end

                        _G.LastHealth = currentHealth

                        ::continue::
                    end
                end
            end)
        end
    ]], tostring(enable))
end

local function SetEntityScale(entity, scale)
    if _G.SetEntityScale then
        return _G.SetEntityScale(entity, scale)
    end
    return Citizen.InvokeNative(0x25223CA6B4D20B7F, entity, scale)
end

local function ToggleTinyPlayer(enable)
    local ped = PlayerPedId()
    if enable then
        SetPedConfigFlag(ped, 223, true)
        SetEntityScale(ped, 0.5)
    else
        SetPedConfigFlag(ped, 223, false)
        SetEntityScale(ped, 1.0)
    end
end

local function HSVToRGB(h, s, v)
    local r, g, b
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    elseif i == 5 then r, g, b = v, p, q
    end
    return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
end

local rainbowPaintActive = false
local function ToggleRainbowPaint(enable)
    rainbowPaintActive = enable
    if enable then
        Citizen.CreateThread(function()
            local hue = 0.0
            while rainbowPaintActive do
                local ped = PlayerPedId()
                if IsPedInAnyVehicle(ped, false) then
                    local veh = GetVehiclePedIsIn(ped, false)

                    hue = hue + 0.01
                    if hue > 1.0 then hue = 0.0 end

                    local r, g, b = HSVToRGB(hue, 1.0, 1.0)

                    SetVehicleCustomPrimaryColour(veh, r, g, b)
                    SetVehicleCustomSecondaryColour(veh, r, g, b)
                end
                Citizen.Wait(10)
            end
        end)
    end
end

local function ToggleAntiHeadshot(enable)
    if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
        return
    end

    local code = string.format([[
        local susano = rawget(_G, "Susano")

        if _G.AntiHeadshotEnabled == nil then _G.AntiHeadshotEnabled = false end
        _G.AntiHeadshotEnabled = %s

        if not _G.AntiHeadshotHooksInstalled and susano and type(susano.HookNative) == "function" then
            _G.AntiHeadshotHooksInstalled = true

            susano.HookNative(0x2D343D2219CD027A, function(ped, toggle)
                if _G.AntiHeadshotEnabled and ped == PlayerPedId() and toggle == true then
                    return false
                end
                return true
            end)

            susano.HookNative(0xD75960F6BD9EA49C, function(ped, bonePtr)
                return true
            end)
        end

        if not _G.AntiHeadshotLoopStarted then
            _G.AntiHeadshotLoopStarted = true
            Citizen.CreateThread(function()
                while true do
                    Wait(0)
                    if _G.AntiHeadshotEnabled then
                        local ped = PlayerPedId()
                        SetPedSuffersCriticalHits(ped, false)
                    end
                end
            end)
        end
    ]], tostring(enable))

    Susano.InjectResource("any", code)
end

local noclipVersion = 0

local function ToggleNoclipStaff(enable)
    if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
        return
    end

    if enable then
        Susano.InjectResource("Putin", [[
            if AdminSystem and AdminSystem.NoClip and AdminSystem.NoClip.Enable then
                AdminSystem.NoClip.Enable()
            end
        ]])
    else
        Susano.InjectResource("Putin", [[
            if AdminSystem and AdminSystem.NoClip and AdminSystem.NoClip.Disable then
                AdminSystem.NoClip.Disable()
            end
        ]])
    end
end

local function ToggleNoclip(enable, speed)
    if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
        return
    end

    speed = speed or 1.0

    noclipVersion = noclipVersion + 1
    local currentVersion = noclipVersion

    local code = string.format([[
        local susano = rawget(_G, "Susano")

        _G.NoclipEnabled = %s
        _G.NoclipSpeed = %s
        _G.NoclipVersion = %s

        if not _G.NoclipEnabled then
            _G.NoclipStopAll = true
            Wait(100)
            local ped = PlayerPedId()
            if DoesEntityExist(ped) then
                SetEntityCollision(ped, true, true)
                FreezeEntityPosition(ped, false)

                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                    SetEntityCollision(vehicle, true, true)
                    FreezeEntityPosition(vehicle, false)
                end
            end
            Wait(100)
            _G.NoclipStopAll = false
            _G.NoclipEnabled = false
        else
        if not _G.NoclipHooksInstalled and susano and type(susano.HookNative) == "function" then
            _G.NoclipHooksInstalled = true

            susano.HookNative(0xC5F68BE37759D056, function(entity)
                if _G.NoclipEnabled then
                    local ped = PlayerPedId()
                    if entity == ped then
                        return false
                    end
                    local vehicle = GetVehiclePedIsIn(ped, false)
                    if vehicle and vehicle ~= 0 and entity == vehicle then
                        return false
                    end
                end
                return true
            end)
        end

            CreateThread(function()
                local myVersion = %s
                local mySpeed = %s

                while true do
                    Wait(0)

                    if _G.NoclipStopAll or ( _G.NoclipVersion and _G.NoclipVersion ~= myVersion) or not _G.NoclipEnabled then
                        local ped = PlayerPedId()
                        if DoesEntityExist(ped) then
                            SetEntityCollision(ped, true, true)
                            FreezeEntityPosition(ped, false)

                            local vehicle = GetVehiclePedIsIn(ped, false)
                            if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                                SetEntityCollision(vehicle, true, true)
                                FreezeEntityPosition(vehicle, false)
                            end
                        end
                        _G.NoclipEnabled = false
                        break
                    end

                    local ped = PlayerPedId()
                    if not DoesEntityExist(ped) then
                        Wait(100)
                    else
                        local vehicle = GetVehiclePedIsIn(ped, false)
                        local entity = vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and vehicle or ped

                        SetEntityCollision(entity, false, false)
                        FreezeEntityPosition(entity, true)

                        local coords = GetEntityCoords(entity)
                        local camRot = GetGameplayCamRot(2)

                        local pitch = math.rad(camRot.x)
                        local yaw = math.rad(camRot.z)

                        local vx = -math.sin(yaw) * math.abs(math.cos(pitch))
                        local vy = math.cos(yaw) * math.abs(math.cos(pitch))
                        local vz = math.sin(pitch)

                        local rx = math.cos(yaw)
                        local ry = math.sin(yaw)

                        local currentSpeed = mySpeed
                        if _G and _G.NoclipSpeed then
                            currentSpeed = _G.NoclipSpeed
                        end

                        local moveSpeed = currentSpeed
                        if IsControlPressed(0, 21) or IsDisabledControlPressed(0, 21) then
                            moveSpeed = currentSpeed * 2.5
                        end

                        local newPos = coords

                        if IsControlPressed(0, 32) then
                            newPos = vector3(newPos.x + vx * moveSpeed, newPos.y + vy * moveSpeed, newPos.z + vz * moveSpeed)
                        end
                        if IsControlPressed(0, 33) then
                            newPos = vector3(newPos.x - vx * moveSpeed, newPos.y - vy * moveSpeed, newPos.z - vz * moveSpeed)
                        end
                        if IsControlPressed(0, 34) then
                            newPos = vector3(newPos.x - rx * moveSpeed, newPos.y - ry * moveSpeed, newPos.z)
                        end
                        if IsControlPressed(0, 35) then
                            newPos = vector3(newPos.x + rx * moveSpeed, newPos.y + ry * moveSpeed, newPos.z)
                        end

                        if IsControlPressed(0, 22) then
                            newPos = vector3(newPos.x, newPos.y, newPos.z + moveSpeed)
                        end
                        if IsControlPressed(0, 36) then
                            newPos = vector3(newPos.x, newPos.y, newPos.z - moveSpeed)
                        end

                        SetEntityCoordsNoOffset(entity, newPos.x, newPos.y, newPos.z, true, true, true)
                        if entity == ped then
                            SetEntityHeading(ped, camRot.z)
                        end
                    end
                end
            end)
        end
    ]], tostring(enable), tostring(speed), tostring(currentVersion), tostring(currentVersion), tostring(speed))

    Susano.InjectResource("any", code)
end

function Menu.ActionRevive()
    if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
        local ped = PlayerPedId()
        if not ped or not DoesEntityExist(ped) then return end

        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)

        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
        SetEntityHealth(ped, 200)
        return
    end

    Susano.InjectResource("any", [[
        local function hNative(nativeName, newFunction)
            local originalNative = _G[nativeName]
            if not originalNative or type(originalNative) ~= "function" then return end
            _G[nativeName] = function(...) return newFunction(originalNative, ...) end
        end

        hNative("PlayerPedId", function(originalFn, ...) return originalFn(...) end)
        hNative("DoesEntityExist", function(originalFn, ...) return originalFn(...) end)
        hNative("GetEntityCoords", function(originalFn, ...) return originalFn(...) end)
        hNative("GetEntityHeading", function(originalFn, ...) return originalFn(...) end)
        hNative("NetworkResurrectLocalPlayer", function(originalFn, ...) return originalFn(...) end)
        hNative("SetEntityHealth", function(originalFn, ...) return originalFn(...) end)

        local ped = PlayerPedId()
        if not ped or not DoesEntityExist(ped) then return end

        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)

        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
        SetEntityHealth(ped, 200)
        ClearPedBloodDamage(ped)
        ClearPedTasksImmediately(ped)
        SetPlayerInvincible(PlayerId(), false)
        SetEntityInvincible(ped, false)
        SetPedCanRagdoll(ped, true)
        SetPedCanRagdollFromPlayerImpact(ped, true)
        SetPedRagdollOnCollision(ped, true)

        if GetResourceState("scripts") == 'started' then
            TriggerEvent('deathscreen:revive')
        end

        if GetResourceState("framework") == 'started' then
            TriggerEvent('deathscreen:revive')
        end

        if GetResourceState("qb-jail") == 'started' then
            TriggerEvent('hospital:client:Revive')
        end
    ]])
end

function Menu.ActionMaxHealth()
    if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
        local ped = PlayerPedId()
        if ped and DoesEntityExist(ped) then
            SetEntityHealth(ped, 200)
        end
        return
    end

    Susano.InjectResource("any", [[
        local function hNative(nativeName, newFunction)
            local originalNative = _G[nativeName]
            if not originalNative or type(originalNative) ~= "function" then return end
            _G[nativeName] = function(...) return newFunction(originalNative, ...) end
        end

        hNative("PlayerPedId", function(originalFn, ...) return originalFn(...) end)
        hNative("DoesEntityExist", function(originalFn, ...) return originalFn(...) end)
        hNative("SetEntityHealth", function(originalFn, ...) return originalFn(...) end)

        local ped = PlayerPedId()
        if ped and DoesEntityExist(ped) then
            SetEntityHealth(ped, 200)
        end
    ]])
end

function Menu.ActionMaxArmor()
    if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
        local ped = PlayerPedId()
        if ped and DoesEntityExist(ped) then
            SetPedArmour(ped, 100)
        end
        return
    end

    Susano.InjectResource("any", [[
        local function hNative(nativeName, newFunction)
            local originalNative = _G[nativeName]
            if not originalNative or type(originalNative) ~= "function" then return end
            _G[nativeName] = function(...) return newFunction(originalNative, ...) end
        end

        hNative("PlayerPedId", function(originalFn, ...) return originalFn(...) end)
        hNative("DoesEntityExist", function(originalFn, ...) return originalFn(...) end)
        hNative("SetPedArmour", function(originalFn, ...) return originalFn(...) end)

        local ped = PlayerPedId()
        if ped and DoesEntityExist(ped) then
            SetPedArmour(ped, 100)
        end
    ]])
end

function Menu.ActionDetachAllEntitys()
    if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
        local ped = PlayerPedId()
        if ped and DoesEntityExist(ped) then
            ClearPedTasks(ped)
            DetachEntity(ped, true, true)
        end
        return
    end

    Susano.InjectResource("any", [[
        local function hNative(nativeName, newFunction)
            local originalNative = _G[nativeName]
            if not originalNative or type(originalNative) ~= "function" then return end
            _G[nativeName] = function(...) return newFunction(originalNative, ...) end
        end

        hNative("PlayerPedId", function(originalFn, ...) return originalFn(...) end)
        hNative("DoesEntityExist", function(originalFn, ...) return originalFn(...) end)
        hNative("ClearPedTasks", function(originalFn, ...) return originalFn(...) end)
        hNative("DetachEntity", function(originalFn, ...) return originalFn(...) end)

        local ped = PlayerPedId()
        if ped and DoesEntityExist(ped) then
            ClearPedTasks(ped)
            DetachEntity(ped, true, true)
        end
    ]])
end

local function ToggleSoloSession(enable)
    if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
        if enable then
            NetworkStartSoloTutorialSession()
        else
            NetworkEndTutorialSession()
        end
        return
    end

    local code = string.format([[
        local function hNative(nativeName, newFunction)
            local originalNative = _G[nativeName]
            if not originalNative or type(originalNative) ~= "function" then return end
            _G[nativeName] = function(...) return newFunction(originalNative, ...) end
        end

        hNative("NetworkStartSoloTutorialSession", function(originalFn, ...) return originalFn(...) end)
        hNative("NetworkEndTutorialSession", function(originalFn, ...) return originalFn(...) end)

        if %s then
            NetworkStartSoloTutorialSession()
        else
            NetworkEndTutorialSession()
        end
    ]], tostring(enable))

    Susano.InjectResource("any", code)
end

local function ToggleFastRun(enable)
    if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
        return
    end

    local code = string.format([[
        if _G.FastRunActive == nil then _G.FastRunActive = false end
        _G.FastRunActive = %s

        if not _G.FastRunLoopStarted then
            _G.FastRunLoopStarted = true
            Citizen.CreateThread(function()
                while true do
                    Wait(0)
                    if _G.FastRunActive then
                        local ped = PlayerPedId()
                        if ped and ped ~= 0 then
                            SetRunSprintMultiplierForPlayer(PlayerId(), 1.49)
                            SetPedMoveRateOverride(ped, 1.49)
                        end
                    else
                        Wait(500)
                    end
                end
            end)
        end

        if not _G.FastRunActive then
            SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
            SetPedMoveRateOverride(PlayerPedId(), 1.0)
        end
    ]], tostring(enable))

    Susano.InjectResource("any", code)
end

local function ToggleNoRagdoll(enable)
    if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
        return
    end

    local code = string.format([[
        local susano = rawget(_G, "Susano")

        if _G.NoRagdollEnabled == nil then _G.NoRagdollEnabled = false end
        _G.NoRagdollEnabled = %s

        if not _G.NoRagdollHooksInstalled and susano and type(susano.HookNative) == "function" then
            if susano.HasNativeHookInitializationFailed and susano.HasNativeHookInitializationFailed() then
                return
            end

            _G.NoRagdollHooksInstalled = true

            susano.HookNative(0xAE99FB955581844A, function(ped)
                if _G.NoRagdollEnabled and ped == PlayerPedId() then
                    return false
                end
                return true
            end)

            susano.HookNative(0xD76632D99E4966C8, function(ped)
                if _G.NoRagdollEnabled and ped == PlayerPedId() then
                    return false
                end
                return true
            end)
        end

        if not _G.NoRagdollLoopStarted then
            _G.NoRagdollLoopStarted = true
            Citizen.CreateThread(function()
                while true do
                    Wait(0)
                    if _G.NoRagdollEnabled then
                        local ped = PlayerPedId()
                        if ped and ped ~= 0 then
                            SetPedCanRagdoll(ped, false)
                            SetPedRagdollOnCollision(ped, false)
                            SetPedCanRagdollFromPlayerImpact(ped, false)
                            if IsPedRagdoll(ped) then
                                ClearPedTasksImmediately(ped)
                            end
                        end
                    else
                        Wait(500)
                        local ped = PlayerPedId()
                        if ped and ped ~= 0 then
                            SetPedCanRagdoll(ped, true)
                            SetPedRagdollOnCollision(ped, true)
                            SetPedCanRagdollFromPlayerImpact(ped, true)
                        end
                    end
                end
            end)
        end
    ]], tostring(enable))

    Susano.InjectResource("any", code)
end

function Menu.ActionRandomOutfit()
    if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
        local ped = PlayerPedId()
        if not ped or not DoesEntityExist(ped) then return end

        local torsoMax = GetNumberOfPedDrawableVariations(ped, 11)
        local shoesMax = GetNumberOfPedDrawableVariations(ped, 6)
        local pantsMax = GetNumberOfPedDrawableVariations(ped, 4)

        SetPedComponentVariation(ped, 11, math.random(0, torsoMax - 1), 0, 2)
        SetPedComponentVariation(ped, 6, math.random(0, shoesMax - 1), 0, 2)
        SetPedComponentVariation(ped, 8, 15, 0, 2)
        SetPedComponentVariation(ped, 3, 0, 0, 2)
        SetPedComponentVariation(ped, 4, math.random(0, pantsMax - 1), 0, 2)

        ClearPedProp(ped, 0)
        ClearPedProp(ped, 1)
        return
    end

    Susano.InjectResource("any", [[
        local ped = PlayerPedId()
        if not ped or not DoesEntityExist(ped) then return end

        local function GetRandomVariation(component, exclude)
            local total = GetNumberOfPedDrawableVariations(ped, component)
            if total <= 1 then return 0 end
            local choice = exclude
            while choice == exclude do
                choice = math.random(0, total - 1)
            end
            return choice
        end

        local function GetRandomComponent(component)
            local total = GetNumberOfPedDrawableVariations(ped, component)
            return total > 1 and math.random(0, total - 1) or 0
        end

        SetPedComponentVariation(ped, 11, GetRandomVariation(11, 15), 0, 2)
        SetPedComponentVariation(ped, 6, GetRandomVariation(6, 15), 0, 2)
        SetPedComponentVariation(ped, 8, 15, 0, 2)
        SetPedComponentVariation(ped, 3, 0, 0, 2)
        SetPedComponentVariation(ped, 4, GetRandomComponent(4), 0, 2)

        local face = math.random(0, 45)
        local skin = math.random(0, 45)
        SetPedHeadBlendData(ped, face, skin, 0, face, skin, 0, 1.0, 1.0, 0.0, false)

        local hairMax = GetNumberOfPedDrawableVariations(ped, 2)
        local hair = hairMax > 1 and math.random(0, hairMax - 1) or 0
        SetPedComponentVariation(ped, 2, hair, 0, 2)
        SetPedHairColor(ped, 0, 0)

        local brows = GetNumHeadOverlayValues(2)
        SetPedHeadOverlay(ped, 2, brows > 1 and math.random(0, brows - 1) or 0, 1.0)
        SetPedHeadOverlayColor(ped, 2, 1, 0, 0)

        ClearPedProp(ped, 0)
        ClearPedProp(ped, 1)
    ]])
end

local function SetPedClothing(componentId, drawableId, textureId)
    local ped = PlayerPedId()
    if ped and DoesEntityExist(ped) then
        SetPedComponentVariation(ped, componentId, drawableId or 0, textureId or 0, 0)
    end
end

local function SetPedAccessory(propId, drawableId, textureId)
    local ped = PlayerPedId()
    if ped and DoesEntityExist(ped) then
        if drawableId == -1 or not drawableId then
            ClearPedProp(ped, propId)
        else
            SetPedPropIndex(ped, propId, drawableId, textureId or 0, true)
        end
    end
end

function Menu.ActionTPAllVehiclesToMe()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            local playerPed = PlayerPedId()
            local myCoords = GetEntityCoords(playerPed)

            local function reqCtrl(entity)
                if not DoesEntityExist(entity) then return false end
                if not NetworkGetEntityIsNetworked(entity) then return true end

                    local attempts = 0
                NetworkRequestControlOfEntity(entity)
                while not NetworkHasControlOfEntity(entity) and attempts < 20 do
                    NetworkRequestControlOfEntity(entity)
                        Wait(0)
                        attempts = attempts + 1
                    end
                    return NetworkHasControlOfEntity(entity)
            end

            CreateThread(function()
                local vehicles = GetGamePool("CVehicle")
                local currentVehicle = GetVehiclePedIsIn(playerPed, false)
                local count = 0

                for _, vehicle in ipairs(vehicles) do
                    if DoesEntityExist(vehicle) and vehicle ~= currentVehicle then
                        SetEntityAsMissionEntity(vehicle, true, true)
                        if reqCtrl(vehicle) then
                            local offsetX = (count % 4) * 3.0 - 4.5
                            local offsetY = math.floor(count / 4) * 3.0 + 3.0

                            SetEntityCoordsNoOffset(vehicle, myCoords.x + offsetX, myCoords.y + offsetY, myCoords.z, false, false, false)
                            SetVehicleOnGroundProperly(vehicle)
                            count = count + 1
                        end
                    end
                end
            end)
        ]])
    end
end

function Menu.ActionTPToWaypoint()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            local playerPed = PlayerPedId()
            if not playerPed or not DoesEntityExist(playerPed) then return end

            local waypointBlip = GetFirstBlipInfoId(8)
            if waypointBlip ~= 0 then
                local waypointX, waypointY, waypointZ = table.unpack(GetBlipInfoIdCoord(waypointBlip))

                local found, groundZ = GetGroundZFor_3dCoord(waypointX, waypointY, waypointZ + 100.0, false)

                if found then
                    SetEntityCoordsNoOffset(playerPed, waypointX, waypointY, groundZ + 1.0, false, false, false)
                else
                    SetEntityCoordsNoOffset(playerPed, waypointX, waypointY, waypointZ, false, false, false)
                end
            end
        ]])
    end
end

function Menu.ActionTPToFIB()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            local playerPed = PlayerPedId()
            if not playerPed or not DoesEntityExist(playerPed) then return end
            SetEntityCoordsNoOffset(playerPed, 135.733, -749.339, 258.152, false, false, false)
        ]])
    end
end

function Menu.ActionTPToMissionRowPD()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            local playerPed = PlayerPedId()
            if not playerPed or not DoesEntityExist(playerPed) then return end
            SetEntityCoordsNoOffset(playerPed, 425.1, -979.5, 30.7, false, false, false)
        ]])
    end
end

function Menu.ActionTPToPillboxHospital()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            local playerPed = PlayerPedId()
            if not playerPed or not DoesEntityExist(playerPed) then return end
            SetEntityCoordsNoOffset(playerPed, 298.2, -584.5, 43.3, false, false, false)
        ]])
    end
end

function Menu.ActionTPToGroveStreet()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            local playerPed = PlayerPedId()
            if not playerPed or not DoesEntityExist(playerPed) then return end
            SetEntityCoordsNoOffset(playerPed, 85.0, -1960.0, 20.8, false, false, false)
        ]])
    end
end

function Menu.ActionTPToLegionSquare()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            local playerPed = PlayerPedId()
            if not playerPed or not DoesEntityExist(playerPed) then return end
            SetEntityCoordsNoOffset(playerPed, 195.0, -933.0, 30.7, false, false, false)
        ]])
    end
end

local function SpawnVehicle(modelName)
    if not modelName then return end

    Actions.tpItem = FindItem("Vehicle", "Spawn", "Teleport Into")
    local shouldTeleport = Actions.tpItem and Actions.tpItem.value or false

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
         Susano.InjectResource("any", string.format([[
             local susano = rawget(_G, "Susano")

             if susano and type(susano) == "table" and type(susano.HookNative) == "function" then

                 susano.HookNative(0x2B40A976, function(entity) return true end)

                 susano.HookNative(0x5324A0E3E4CE3570, function(entity) return true end)

                 susano.HookNative(0x8DE82BC774F3B862, function() return true end)

                 susano.HookNative(0x2B1813BA58063D36, function() return true end)

                 susano.HookNative(0x35FB78DC42B7BD21, function(modelHash) return false, true end)

                 susano.HookNative(0x392C8D8E07B70EFC, function(modelHash) return false, true end)

                 susano.HookNative(0x98A4EB5D89A0C952, function(modelHash) return false, true end)

                 susano.HookNative(0x963D27A58DF860AC, function(modelHash) return false end)

                 susano.HookNative(0xEA386986E786A54F, function(vehicle) return false end)

                 susano.HookNative(0xAE3CBE5BF394C9C9, function(entity)
                     local entityType = GetEntityType(entity)
                     if entityType == 2 then
                         return false
                     end
                     return true
                 end)

                 susano.HookNative(0x7D9EFB7AD6B19754, function(vehicle, toggle) return false end)

                 susano.HookNative(0x1CF38D529D7441D9, function(vehicle, toggle) return false end)

                 susano.HookNative(0x99AD4CCCB128CBC9, function(vehicle) return false end)

                 susano.HookNative(0xE5810AC70602F2F5, function(vehicle, speed) return false end)
             end

             Citizen.CreateThread(function()
                 Wait(1000)

                 local ped = PlayerPedId()
                 local coords = GetEntityCoords(ped)
                 local heading = GetEntityHeading(ped)
                 local offsetX = coords.x + math.sin(math.rad(heading)) * 3.0
                 local offsetY = coords.y + math.cos(math.rad(heading)) * 3.0
                 local offsetZ = coords.z

                 local modelHash = GetHashKey("%s")
                 if modelHash == 0 then
                     return
                 end

                 RequestModel(modelHash)
                 local timeout = 0
                 while not HasModelLoaded(modelHash) and timeout < 200 do
                     Citizen.Wait(10)
                     timeout = timeout + 1
                 end

                 if HasModelLoaded(modelHash) then
                     Citizen.Wait(200)

                     local groundZ = offsetZ
                     local found, ground = GetGroundZFor_3dCoord(offsetX, offsetY, offsetZ + 10.0, groundZ, false)
                     if found then
                         offsetZ = groundZ + 0.5
                     end

                     local vehicle = CreateVehicle(modelHash, offsetX, offsetY, offsetZ, heading, true, false)
                     if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                         local netId = NetworkGetNetworkIdFromEntity(vehicle)
                         if netId and netId ~= 0 then
                             SetNetworkIdCanMigrate(netId, false)
                             SetNetworkIdExistsOnAllMachines(netId, true)
                         end
                         SetEntityAsMissionEntity(vehicle, true, true)
                         SetVehicleHasBeenOwnedByPlayer(vehicle, true)
                         SetVehicleNeedsToBeHotwired(vehicle, false)
                         SetVehicleEngineOn(vehicle, true, true, false)
                         SetVehicleOnGroundProperly(vehicle)

                         if %s then
                             Citizen.Wait(300)
                             TaskWarpPedIntoVehicle(ped, vehicle, -1)
                         end

                         SetModelAsNoLongerNeeded(modelHash)
                     end
                 end
             end)
         ]], modelName, tostring(shouldTeleport)))
     end
end

local function MaxUpgrade()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            local susano = rawget(_G, "Susano")

            if susano and type(susano) == "table" and type(susano.HookNative) == "function" and not _max_upgrade_hooks_applied then
                _max_upgrade_hooks_applied = true

                susano.HookNative(0x8DE82BC774F3B862, function(entity)
                    return true
                end)

                susano.HookNative(0x4CEBC1ED31E8925E, function(entity)
                    return true
                end)

                susano.HookNative(0xAE3CBE5BF394C9C9, function(entity)
                    return true
                end)

                susano.HookNative(0x2B40A976, function(entity)
                    return true
                end)

                susano.HookNative(0xAD738C3085FE7E11, function(entity, p1, p2)
                    return true
                end)
            end

            CreateThread(function()
                Wait(100)

                local ped = PlayerPedId()
                local vehicle = GetVehiclePedIsIn(ped, false)

                if not vehicle or vehicle == 0 then
                    return
                end

                if not NetworkHasControlOfEntity(vehicle) then
                    NetworkRequestControlOfEntity(vehicle)
                    local timeout = 0
                    while not NetworkHasControlOfEntity(vehicle) and timeout < 200 do
                        Wait(10)
                        timeout = timeout + 1
                        NetworkRequestControlOfEntity(vehicle)
                    end
                end

                SetEntityAsMissionEntity(vehicle, true, true)

                SetVehicleModKit(vehicle, 0)

                SetVehicleWheelType(vehicle, 7)

                for modType = 0, 16 do
                    local numMods = GetNumVehicleMods(vehicle, modType)
                    if numMods and numMods > 0 then
                        SetVehicleMod(vehicle, modType, numMods - 1, false)
                    end
                end

                SetVehicleMod(vehicle, 14, 16, false)

                local numLivery = GetNumVehicleMods(vehicle, 15)
                if numLivery and numLivery > 1 then
                    SetVehicleMod(vehicle, 15, numLivery - 2, false)
                end

                for modType = 17, 22 do
                    ToggleVehicleMod(vehicle, modType, true)
                end

                SetVehicleMod(vehicle, 23, 1, false)
                SetVehicleMod(vehicle, 24, 1, false)

                for extra = 1, 12 do
                    if DoesExtraExist(vehicle, extra) then
                        SetVehicleExtra(vehicle, extra, false)
                    end
                end

                SetVehicleWindowTint(vehicle, 1)

                SetVehicleTyresCanBurst(vehicle, false)

                Wait(100)

                SetEntityAsMissionEntity(vehicle, false, true)
            end)
        ]])
    end
end

local function RepairVehicle()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            local susano = rawget(_G, "Susano")

            if susano and type(susano) == "table" and type(susano.HookNative) == "function" and not _repair_vehicle_hooks_applied then
                _repair_vehicle_hooks_applied = true

                susano.HookNative(0x8DE82BC774F3B862, function(entity)
                    return true
                end)

                susano.HookNative(0x4CEBC1ED31E8925E, function(entity)
                    return true
                end)

                susano.HookNative(0xAE3CBE5BF394C9C9, function(entity)
                    return true
                end)

                susano.HookNative(0x2B40A976, function(entity)
                    return true
                end)

                susano.HookNative(0xAD738C3085FE7E11, function(entity, p1, p2)
                    return true
                end)

                susano.HookNative(0x115722B1B9C14C1C, function(vehicle)
                    return true
                end)
            end

            CreateThread(function()
                Wait(100)

                local ped = PlayerPedId()
                local vehicle = GetVehiclePedIsIn(ped, false)

                if not vehicle or vehicle == 0 then
                    return
                end

                if not NetworkHasControlOfEntity(vehicle) then
                    NetworkRequestControlOfEntity(vehicle)
                    local timeout = 0
                    while not NetworkHasControlOfEntity(vehicle) and timeout < 200 do
                        Wait(10)
                        timeout = timeout + 1
                        NetworkRequestControlOfEntity(vehicle)
                    end
                end

                SetEntityAsMissionEntity(vehicle, true, true)

                SetVehicleFixed(vehicle)
                SetVehicleDeformationFixed(vehicle)
                SetVehicleUndriveable(vehicle, false)
                SetVehicleEngineOn(vehicle, true, true, false)

                SetVehicleTyresCanBurst(vehicle, true)
                for i = 0, 3 do
                    SetVehicleTyreFixed(vehicle, i)
                end

                SetVehicleDoorsLocked(vehicle, 1)
                SetVehicleDoorsLockedForAllPlayers(vehicle, false)

                SetVehicleEngineHealth(vehicle, 1000.0)
                SetVehicleBodyHealth(vehicle, 1000.0)
                SetVehiclePetrolTankHealth(vehicle, 1000.0)

                SetVehicleDirtLevel(vehicle, 0.0)
                WashDecalsFromVehicle(vehicle, 1.0)

                Wait(100)

                SetEntityAsMissionEntity(vehicle, false, true)
            end)
        ]])
    end
end

local function RampVehicle()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            function hNative(nativeName, newFunction)
                local originalNative = _G[nativeName]
                if not originalNative or type(originalNative) ~= "function" then
                    return
                end
                _G[nativeName] = function(...)
                    return newFunction(originalNative, ...)
                end
            end
            hNative("PlayerPedId", function(originalFn, ...) return originalFn(...) end)
            hNative("IsPedInAnyVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("GetVehiclePedIsIn", function(originalFn, ...) return originalFn(...) end)
            hNative("DoesEntityExist", function(originalFn, ...) return originalFn(...) end)
            hNative("GetPedInVehicleSeat", function(originalFn, ...) return originalFn(...) end)
            hNative("CreateThread", function(originalFn, ...) return originalFn(...) end)
            hNative("GetEntityCoords", function(originalFn, ...) return originalFn(...) end)
            hNative("GetEntityHeading", function(originalFn, ...) return originalFn(...) end)
            hNative("FindFirstVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("FindNextVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("EndFindVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("GetVehicleClass", function(originalFn, ...) return originalFn(...) end)
            hNative("SetPedIntoVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("Wait", function(originalFn, ...) return originalFn(...) end)
            hNative("SetEntityAsMissionEntity", function(originalFn, ...) return originalFn(...) end)
            hNative("NetworkGetEntityIsNetworked", function(originalFn, ...) return originalFn(...) end)
            hNative("NetworkRequestControlOfEntity", function(originalFn, ...) return originalFn(...) end)
            hNative("NetworkHasControlOfEntity", function(originalFn, ...) return originalFn(...) end)
            hNative("GetEntityForwardVector", function(originalFn, ...) return originalFn(...) end)
            hNative("AttachEntityToEntity", function(originalFn, ...) return originalFn(...) end)

            local playerPed = PlayerPedId()
            if not IsPedInAnyVehicle(playerPed, false) then
                return
            end

            local myVehicle = GetVehiclePedIsIn(playerPed, false)
            if not DoesEntityExist(myVehicle) or GetPedInVehicleSeat(myVehicle, -1) ~= playerPed then
                return
            end

            CreateThread(function()
                local myCoords = GetEntityCoords(myVehicle)
                local myHeading = GetEntityHeading(myVehicle)
                local vehicles = {}
                local searchRadius = 100.0
                local vehHandle, veh = FindFirstVehicle()
                local success

                repeat
                    local vehCoords = GetEntityCoords(veh)
                    local distance = #(myCoords - vehCoords)
                    local vehClass = GetVehicleClass(veh)
                    if distance <= searchRadius and veh ~= myVehicle and vehClass ~= 8 and vehClass ~= 13 then
                        table.insert(vehicles, {handle = veh, distance = distance})
                    end
                    success, veh = FindNextVehicle(vehHandle)
                until not success
                EndFindVehicle(vehHandle)

                if #vehicles < 3 then
                    return
                end

                table.sort(vehicles, function(a, b) return a.distance < b.distance end)
                local selectedVehicles = {vehicles[1].handle, vehicles[2].handle, vehicles[3].handle}

                local function takeControl(veh)
                    SetPedIntoVehicle(playerPed, veh, -1)
                    Wait(150)
                    SetEntityAsMissionEntity(veh, true, true)
                    if NetworkGetEntityIsNetworked(veh) then
                        NetworkRequestControlOfEntity(veh)
                        local timeout = 0
                        while not NetworkHasControlOfEntity(veh) and timeout < 50 do
                            NetworkRequestControlOfEntity(veh)
                            Wait(10)
                            timeout = timeout + 1
                        end
                    end
                end

                for i = 1, 3 do
                    if DoesEntityExist(selectedVehicles[i]) then
                        takeControl(selectedVehicles[i])
                    end
                end

                SetPedIntoVehicle(playerPed, myVehicle, -1)
                Wait(100)

                local heading = GetEntityHeading(myVehicle)
                local forwardVector = GetEntityForwardVector(myVehicle)
                local vehCoords = GetEntityCoords(myVehicle)
                local rampPositions = {
                    {offsetX = -2.0, offsetY = 2.5, offsetZ = 0.2, rotX = 160.0, rotY = 0.0, rotZ = 0.0},
                    {offsetX = 0.0,  offsetY = 2.5, offsetZ = 0.2, rotX = 160.0, rotY = 0.0, rotZ = 0.0},
                    {offsetX = 2.0,  offsetY = 2.5, offsetZ = 0.2, rotX = 160.0, rotY = 0.0, rotZ = 0.0},
                }

                for i = 1, 3 do
                    if DoesEntityExist(selectedVehicles[i]) then
                        local pos = rampPositions[i]
                        AttachEntityToEntity(selectedVehicles[i], myVehicle, 0, pos.offsetX, pos.offsetY, pos.offsetZ, pos.rotX, pos.rotY, pos.rotZ, false, false, true, false, 2, true)
                    end
                end
            end)
        ]])
    else
        local playerPed = PlayerPedId()
        if not IsPedInAnyVehicle(playerPed, false) then
            return
        end

        local myVehicle = GetVehiclePedIsIn(playerPed, false)
        if not DoesEntityExist(myVehicle) or GetPedInVehicleSeat(myVehicle, -1) ~= playerPed then
            return
        end

        CreateThread(function()
            local myCoords = GetEntityCoords(myVehicle)
            local myHeading = GetEntityHeading(myVehicle)
            local vehicles = {}
            local searchRadius = 100.0
            local vehHandle, veh = FindFirstVehicle()
            local success

            repeat
                local vehCoords = GetEntityCoords(veh)
                local distance = #(myCoords - vehCoords)
                local vehClass = GetVehicleClass(veh)
                if distance <= searchRadius and veh ~= myVehicle and vehClass ~= 8 and vehClass ~= 13 then
                    table.insert(vehicles, {handle = veh, distance = distance})
                end
                success, veh = FindNextVehicle(vehHandle)
            until not success
            EndFindVehicle(vehHandle)

            if #vehicles < 3 then
                return
            end

            table.sort(vehicles, function(a, b) return a.distance < b.distance end)
            local selectedVehicles = {vehicles[1].handle, vehicles[2].handle, vehicles[3].handle}

            local function takeControl(veh)
                SetPedIntoVehicle(playerPed, veh, -1)
                Wait(150)
                SetEntityAsMissionEntity(veh, true, true)
                if NetworkGetEntityIsNetworked(veh) then
                    NetworkRequestControlOfEntity(veh)
                    local timeout = 0
                    while not NetworkHasControlOfEntity(veh) and timeout < 50 do
                        NetworkRequestControlOfEntity(veh)
                        Wait(10)
                        timeout = timeout + 1
                    end
                end
            end

            for i = 1, 3 do
                if DoesEntityExist(selectedVehicles[i]) then
                    takeControl(selectedVehicles[i])
                end
            end

            SetPedIntoVehicle(playerPed, myVehicle, -1)
            Wait(100)

            local heading = GetEntityHeading(myVehicle)
            local forwardVector = GetEntityForwardVector(myVehicle)
            local vehCoords = GetEntityCoords(myVehicle)
            local rampPositions = {
                {offsetX = -2.0, offsetY = 2.5, offsetZ = 0.2, rotX = 160.0, rotY = 0.0, rotZ = 0.0},
                {offsetX = 0.0,  offsetY = 2.5, offsetZ = 0.2, rotX = 160.0, rotY = 0.0, rotZ = 0.0},
                {offsetX = 2.0,  offsetY = 2.5, offsetZ = 0.2, rotX = 160.0, rotY = 0.0, rotZ = 0.0},
            }

            for i = 1, 3 do
                if DoesEntityExist(selectedVehicles[i]) then
                    local pos = rampPositions[i]
                    AttachEntityToEntity(selectedVehicles[i], myVehicle, 0, pos.offsetX, pos.offsetY, pos.offsetZ, pos.rotX, pos.rotY, pos.rotZ, false, false, true, false, 2, true)
                end
            end
        end)
    end
end

local function WallVehicle()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            function hNative(nativeName, newFunction)
                local originalNative = _G[nativeName]
                if not originalNative or type(originalNative) ~= "function" then
                    return
                end
                _G[nativeName] = function(...)
                    return newFunction(originalNative, ...)
                end
            end
            hNative("PlayerPedId", function(originalFn, ...) return originalFn(...) end)
            hNative("IsPedInAnyVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("GetVehiclePedIsIn", function(originalFn, ...) return originalFn(...) end)
            hNative("DoesEntityExist", function(originalFn, ...) return originalFn(...) end)
            hNative("GetPedInVehicleSeat", function(originalFn, ...) return originalFn(...) end)
            hNative("CreateThread", function(originalFn, ...) return originalFn(...) end)
            hNative("GetEntityCoords", function(originalFn, ...) return originalFn(...) end)
            hNative("GetEntityHeading", function(originalFn, ...) return originalFn(...) end)
            hNative("FindFirstVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("FindNextVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("EndFindVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("GetVehicleClass", function(originalFn, ...) return originalFn(...) end)
            hNative("SetPedIntoVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("Wait", function(originalFn, ...) return originalFn(...) end)
            hNative("SetEntityAsMissionEntity", function(originalFn, ...) return originalFn(...) end)
            hNative("NetworkGetEntityIsNetworked", function(originalFn, ...) return originalFn(...) end)
            hNative("NetworkRequestControlOfEntity", function(originalFn, ...) return originalFn(...) end)
            hNative("NetworkHasControlOfEntity", function(originalFn, ...) return originalFn(...) end)
            hNative("AttachEntityToEntity", function(originalFn, ...) return originalFn(...) end)

            local playerPed = PlayerPedId()
            if not IsPedInAnyVehicle(playerPed, false) then
                return
            end

            local myVehicle = GetVehiclePedIsIn(playerPed, false)
            if not DoesEntityExist(myVehicle) or GetPedInVehicleSeat(myVehicle, -1) ~= playerPed then
                return
            end

            CreateThread(function()
                local myCoords = GetEntityCoords(myVehicle)
                local vehicles = {}
                local searchRadius = 100.0
                local vehHandle, veh = FindFirstVehicle()
                local success

                repeat
                    local vehCoords = GetEntityCoords(veh)
                    local distance = #(myCoords - vehCoords)
                    local vehClass = GetVehicleClass(veh)
                    if distance <= searchRadius and veh ~= myVehicle and vehClass ~= 8 and vehClass ~= 13 then
                        table.insert(vehicles, {handle = veh, distance = distance})
                    end
                    success, veh = FindNextVehicle(vehHandle)
                until not success
                EndFindVehicle(vehHandle)

                if #vehicles < 3 then
                    return
                end

                table.sort(vehicles, function(a, b) return a.distance < b.distance end)
                local selectedVehicles = {vehicles[1].handle, vehicles[2].handle, vehicles[3].handle}

                local function takeControl(veh)
                    SetPedIntoVehicle(playerPed, veh, -1)
                    Wait(150)
                    SetEntityAsMissionEntity(veh, true, true)
                    if NetworkGetEntityIsNetworked(veh) then
                        NetworkRequestControlOfEntity(veh)
                        local timeout = 0
                        while not NetworkHasControlOfEntity(veh) and timeout < 50 do
                            NetworkRequestControlOfEntity(veh)
                            Wait(10)
                            timeout = timeout + 1
                        end
                    end
                end

                for i = 1, 3 do
                    if DoesEntityExist(selectedVehicles[i]) then
                        takeControl(selectedVehicles[i])
                    end
                end

                SetPedIntoVehicle(playerPed, myVehicle, -1)
                Wait(100)

                local wallPositions = {
                    {offsetX = -2.0, offsetY = 2.5, offsetZ = 0.2, rotX = 0.0, rotY = 0.0, rotZ = 0.0},
                    {offsetX = 0.0,  offsetY = 2.5, offsetZ = 0.2, rotX = 0.0, rotY = 0.0, rotZ = 0.0},
                    {offsetX = 2.0,  offsetY = 2.5, offsetZ = 0.2, rotX = 0.0, rotY = 0.0, rotZ = 0.0},
                }

                for i = 1, 3 do
                    if DoesEntityExist(selectedVehicles[i]) then
                        local pos = wallPositions[i]
                        AttachEntityToEntity(selectedVehicles[i], myVehicle, 0, pos.offsetX, pos.offsetY, pos.offsetZ, pos.rotX, pos.rotY, pos.rotZ, false, false, true, false, 2, true)
                    end
                end
            end)
        ]])
    else
        local playerPed = PlayerPedId()
        if not IsPedInAnyVehicle(playerPed, false) then
            return
        end

        local myVehicle = GetVehiclePedIsIn(playerPed, false)
        if not DoesEntityExist(myVehicle) or GetPedInVehicleSeat(myVehicle, -1) ~= playerPed then
            return
        end

        CreateThread(function()
            local myCoords = GetEntityCoords(myVehicle)
            local vehicles = {}
            local searchRadius = 100.0
            local vehHandle, veh = FindFirstVehicle()
            local success

            repeat
                local vehCoords = GetEntityCoords(veh)
                local distance = #(myCoords - vehCoords)
                local vehClass = GetVehicleClass(veh)
                if distance <= searchRadius and veh ~= myVehicle and vehClass ~= 8 and vehClass ~= 13 then
                    table.insert(vehicles, {handle = veh, distance = distance})
                end
                success, veh = FindNextVehicle(vehHandle)
            until not success
            EndFindVehicle(vehHandle)

            if #vehicles < 3 then
                return
            end

            table.sort(vehicles, function(a, b) return a.distance < b.distance end)
            local selectedVehicles = {vehicles[1].handle, vehicles[2].handle, vehicles[3].handle}

            local function takeControl(veh)
                SetPedIntoVehicle(playerPed, veh, -1)
                Wait(150)
                SetEntityAsMissionEntity(veh, true, true)
                if NetworkGetEntityIsNetworked(veh) then
                    NetworkRequestControlOfEntity(veh)
                    local timeout = 0
                    while not NetworkHasControlOfEntity(veh) and timeout < 50 do
                        NetworkRequestControlOfEntity(veh)
                        Wait(10)
                        timeout = timeout + 1
                    end
                end
            end

            for i = 1, 3 do
                if DoesEntityExist(selectedVehicles[i]) then
                    takeControl(selectedVehicles[i])
                end
            end

            SetPedIntoVehicle(playerPed, myVehicle, -1)
            Wait(100)

            local wallPositions = {
                {offsetX = -2.0, offsetY = 2.5, offsetZ = 0.2, rotX = 0.0, rotY = 0.0, rotZ = 0.0},
                {offsetX = 0.0,  offsetY = 2.5, offsetZ = 0.2, rotX = 0.0, rotY = 0.0, rotZ = 0.0},
                {offsetX = 2.0,  offsetY = 2.5, offsetZ = 0.2, rotX = 0.0, rotY = 0.0, rotZ = 0.0},
            }

            for i = 1, 3 do
                if DoesEntityExist(selectedVehicles[i]) then
                    local pos = wallPositions[i]
                    AttachEntityToEntity(selectedVehicles[i], myVehicle, 0, pos.offsetX, pos.offsetY, pos.offsetZ, pos.rotX, pos.rotY, pos.rotZ, false, false, true, false, 2, true)
                end
            end
        end)
    end
end

local function Wall2Vehicle()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            function hNative(nativeName, newFunction)
                local originalNative = _G[nativeName]
                if not originalNative or type(originalNative) ~= "function" then
                    return
                end
                _G[nativeName] = function(...)
                    return newFunction(originalNative, ...)
                end
            end
            hNative("PlayerPedId", function(originalFn, ...) return originalFn(...) end)
            hNative("IsPedInAnyVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("GetVehiclePedIsIn", function(originalFn, ...) return originalFn(...) end)
            hNative("DoesEntityExist", function(originalFn, ...) return originalFn(...) end)
            hNative("GetPedInVehicleSeat", function(originalFn, ...) return originalFn(...) end)
            hNative("CreateThread", function(originalFn, ...) return originalFn(...) end)
            hNative("GetEntityCoords", function(originalFn, ...) return originalFn(...) end)
            hNative("FindFirstVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("FindNextVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("EndFindVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("GetVehicleClass", function(originalFn, ...) return originalFn(...) end)
            hNative("SetPedIntoVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("Wait", function(originalFn, ...) return originalFn(...) end)
            hNative("SetEntityAsMissionEntity", function(originalFn, ...) return originalFn(...) end)
            hNative("NetworkGetEntityIsNetworked", function(originalFn, ...) return originalFn(...) end)
            hNative("NetworkRequestControlOfEntity", function(originalFn, ...) return originalFn(...) end)
            hNative("NetworkHasControlOfEntity", function(originalFn, ...) return originalFn(...) end)
            hNative("AttachEntityToEntity", function(originalFn, ...) return originalFn(...) end)

            local playerPed = PlayerPedId()
            if not IsPedInAnyVehicle(playerPed, false) then
                return
            end

            local myVehicle = GetVehiclePedIsIn(playerPed, false)
            if not DoesEntityExist(myVehicle) or GetPedInVehicleSeat(myVehicle, -1) ~= playerPed then
                return
            end

            CreateThread(function()
                local myCoords = GetEntityCoords(myVehicle)
                local vehicles = {}
                local searchRadius = 100.0
                local vehHandle, veh = FindFirstVehicle()
                local success

                repeat
                    local vehCoords = GetEntityCoords(veh)
                    local distance = #(myCoords - vehCoords)
                    local vehClass = GetVehicleClass(veh)
                    if distance <= searchRadius and veh ~= myVehicle and vehClass ~= 8 and vehClass ~= 13 then
                        table.insert(vehicles, {handle = veh, distance = distance})
                    end
                    success, veh = FindNextVehicle(vehHandle)
                until not success
                EndFindVehicle(vehHandle)

                if #vehicles < 3 then
                    return
                end

                table.sort(vehicles, function(a, b) return a.distance < b.distance end)
                local selectedVehicles = {vehicles[1].handle, vehicles[2].handle, vehicles[3].handle}

                local function takeControl(veh)
                    SetPedIntoVehicle(playerPed, veh, -1)
                    Wait(150)
                    SetEntityAsMissionEntity(veh, true, true)
                    if NetworkGetEntityIsNetworked(veh) then
                        NetworkRequestControlOfEntity(veh)
                        local timeout = 0
                        while not NetworkHasControlOfEntity(veh) and timeout < 50 do
                            NetworkRequestControlOfEntity(veh)
                            Wait(10)
                            timeout = timeout + 1
                        end
                    end
                end

                for i = 1, 3 do
                    if DoesEntityExist(selectedVehicles[i]) then
                        takeControl(selectedVehicles[i])
                    end
                end

                SetPedIntoVehicle(playerPed, myVehicle, -1)
                Wait(100)

                local wall2Positions = {
                    {offsetX = -2.0, offsetY = 2.5, offsetZ = 0.6, rotX = 90.0, rotY = 0.0, rotZ = 0.0},
                    {offsetX = 0.0,  offsetY = 2.5, offsetZ = 0.6, rotX = 90.0, rotY = 0.0, rotZ = 0.0},
                    {offsetX = 2.0,  offsetY = 2.5, offsetZ = 0.6, rotX = 90.0, rotY = 0.0, rotZ = 0.0},
                }

                for i = 1, 3 do
                    if DoesEntityExist(selectedVehicles[i]) then
                        local pos = wall2Positions[i]
                        AttachEntityToEntity(selectedVehicles[i], myVehicle, 0, pos.offsetX, pos.offsetY, pos.offsetZ, pos.rotX, pos.rotY, pos.rotZ, false, false, true, false, 2, true)
                    end
                end
            end)
        ]])
    else
        local playerPed = PlayerPedId()
        if not IsPedInAnyVehicle(playerPed, false) then
            return
        end

        local myVehicle = GetVehiclePedIsIn(playerPed, false)
        if not DoesEntityExist(myVehicle) or GetPedInVehicleSeat(myVehicle, -1) ~= playerPed then
            return
        end

        CreateThread(function()
            local myCoords = GetEntityCoords(myVehicle)
            local vehicles = {}
            local searchRadius = 100.0
            local vehHandle, veh = FindFirstVehicle()
            local success

            repeat
                local vehCoords = GetEntityCoords(veh)
                local distance = #(myCoords - vehCoords)
                local vehClass = GetVehicleClass(veh)
                if distance <= searchRadius and veh ~= myVehicle and vehClass ~= 8 and vehClass ~= 13 then
                    table.insert(vehicles, {handle = veh, distance = distance})
                end
                success, veh = FindNextVehicle(vehHandle)
            until not success
            EndFindVehicle(vehHandle)

            if #vehicles < 3 then
                return
            end

            table.sort(vehicles, function(a, b) return a.distance < b.distance end)
            local selectedVehicles = {vehicles[1].handle, vehicles[2].handle, vehicles[3].handle}

            local function takeControl(veh)
                SetPedIntoVehicle(playerPed, veh, -1)
                Wait(150)
                SetEntityAsMissionEntity(veh, true, true)
                if NetworkGetEntityIsNetworked(veh) then
                    NetworkRequestControlOfEntity(veh)
                    local timeout = 0
                    while not NetworkHasControlOfEntity(veh) and timeout < 50 do
                        NetworkRequestControlOfEntity(veh)
                        Wait(10)
                        timeout = timeout + 1
                    end
                end
            end

            for i = 1, 3 do
                if DoesEntityExist(selectedVehicles[i]) then
                    takeControl(selectedVehicles[i])
                end
            end

            SetPedIntoVehicle(playerPed, myVehicle, -1)
            Wait(100)

            local wall2Positions = {
                {offsetX = -2.0, offsetY = 2.5, offsetZ = 0.6, rotX = 90.0, rotY = 0.0, rotZ = 0.0},
                {offsetX = 0.0,  offsetY = 2.5, offsetZ = 0.6, rotX = 90.0, rotY = 0.0, rotZ = 0.0},
                {offsetX = 2.0,  offsetY = 2.5, offsetZ = 0.6, rotX = 90.0, rotY = 0.0, rotZ = 0.0},
            }

            for i = 1, 3 do
                if DoesEntityExist(selectedVehicles[i]) then
                    local pos = wall2Positions[i]
                    AttachEntityToEntity(selectedVehicles[i], myVehicle, 0, pos.offsetX, pos.offsetY, pos.offsetZ, pos.rotX, pos.rotY, pos.rotZ, false, false, true, false, 2, true)
                end
            end
        end)
    end
end

local function ToggleForceVehicleEngine(enable)
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", string.format([[
            local susano = rawget(_G, "Susano")

            if susano and type(susano) == "table" and type(susano.HookNative) == "function" and not _force_engine_hooks_applied then
                _force_engine_hooks_applied = true

                susano.HookNative(0x8DE82BC774F3B862, function(entity)
                    return true
                end)

                susano.HookNative(0x4CEBC1ED31E8925E, function(entity)
                    return true
                end)

                susano.HookNative(0xAE3CBE5BF394C9C9, function(entity)
                    return true
                end)

                susano.HookNative(0x2B40A976, function(entity)
                    return true
                end)

                susano.HookNative(0xAD738C3085FE7E11, function(entity, p1, p2)
                    return true
                end)
            end

            _G.ForceVehicleEngineEnabled = %s

            if _G.ForceVehicleEngineThread then
            end

            _G.ForceVehicleEngineThread = CreateThread(function()
                while _G.ForceVehicleEngineEnabled do
                    Wait(0)

                    local ped = PlayerPedId()
                    local vehicle = GetVehiclePedIsIn(ped, false)

                    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                        if not NetworkHasControlOfEntity(vehicle) then
                            NetworkRequestControlOfEntity(vehicle)
                        end

                        SetVehicleEngineOn(vehicle, true, true, false)

                        SetVehicleEngineHealth(vehicle, 1000.0)

                        SetVehicleUndriveable(vehicle, false)
                    end
                end

                _G.ForceVehicleEngineThread = nil
            end)
        ]], tostring(enable)))
    end
end

local function ToggleShiftBoost(enable)
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", string.format([[
            if QwErTyUiOpSh == nil then QwErTyUiOpSh = false end
            QwErTyUiOpSh = %s

            if QwErTyUiOpSh then
                local function ZxCvBnMmLl()
                    CreateThread(function()
                        while QwErTyUiOpSh and not Unloaded do
                            local ped = PlayerPedId()
                            if IsPedInAnyVehicle(ped, false) then
                                local veh = GetVehiclePedIsIn(ped, false)
                                if veh ~= 0 and IsDisabledControlJustPressed(0, 21) then
                                    SetVehicleForwardSpeed(veh, 150.0)
                                end
                            end
                            Wait(0)
                        end
                    end)
                end
                ZxCvBnMmLl()
            end
        ]], tostring(enable)))
    end
end

local spawnItems = {"Car", "Moto", "Plane", "Boat"}
for _, itemName in ipairs(spawnItems) do
    local item = FindItem("Vehicle", "Spawn", itemName)
    if item then
        item.onClick = function(index, option)
            SpawnVehicle(option)
        end
    end
end

Actions.maxUpgradeItem = FindItem("Vehicle", "Performance", "Max Upgrade")
if Actions.maxUpgradeItem then
    Actions.maxUpgradeItem.onClick = function()
        MaxUpgrade()
    end
end

Actions.repairVehicleItem = FindItem("Vehicle", "Performance", "Repair Vehicle")
if Actions.repairVehicleItem then
    Actions.repairVehicleItem.onClick = function()
        RepairVehicle()
    end
end

Actions.throwFromVehicleItem = FindItem("Vehicle", "Performance", "Throw From Vehicle")
if Actions.throwFromVehicleItem then
    Actions.throwFromVehicleItem.onClick = function()
        local isEnabled = Actions.throwFromVehicleItem.value

        if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
            return
        end

        if isEnabled then
            Susano.InjectResource("any", [[
                rawset(_G, 'ThrowFromVehicleEnabled', true)

                if not rawget(_G, 'ThrowFromVehicleThread') then
                    rawset(_G, 'ThrowFromVehicleThread', true)

                    CreateThread(function()
                        while not Unloaded do
                            if rawget(_G, 'ThrowFromVehicleEnabled') then
                                SetRelationshipBetweenGroups(5, GetHashKey('PLAYER'), GetHashKey('PLAYER'))
                            else
                                SetRelationshipBetweenGroups(1, GetHashKey('PLAYER'), GetHashKey('PLAYER'))
                                SetRelationshipBetweenGroups(0, GetHashKey('PLAYER'), GetHashKey('PLAYER'))
                            end
                            Wait(0)
                        end

                        SetRelationshipBetweenGroups(1, GetHashKey('PLAYER'), GetHashKey('PLAYER'))
                        SetRelationshipBetweenGroups(0, GetHashKey('PLAYER'), GetHashKey('PLAYER'))
                    end)
                end
            ]])
        else
            Susano.InjectResource("any", [[
                rawset(_G, 'ThrowFromVehicleEnabled', false)
                SetRelationshipBetweenGroups(1, GetHashKey('PLAYER'), GetHashKey('PLAYER'))
                SetRelationshipBetweenGroups(0, GetHashKey('PLAYER'), GetHashKey('PLAYER'))
                ClearRelationshipBetweenGroups(5, GetHashKey('PLAYER'), GetHashKey('PLAYER'))
            ]])
        end
    end
end

local function ToggleEasyHandling(enable)
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", string.format([[
            if _G.EasyHandlingEnabled == nil then _G.EasyHandlingEnabled = false end
            _G.EasyHandlingEnabled = %s

            if _G.EasyHandlingEnabled then
                local function StartEasyHandling()
                    CreateThread(function()
                        while _G.EasyHandlingEnabled and not Unloaded do
                        Wait(0)
                        local ped = PlayerPedId()
                        if ped and ped ~= 0 then
                            local veh = GetVehiclePedIsIn(ped, false)
                                if veh and veh ~= 0 and DoesEntityExist(veh) then
                                    SetVehicleGravityAmount(veh, 73.0)
                                    SetVehicleHandlingFloat(veh, "CHandlingData", "fMass", 500.0)
                                    SetVehicleHandlingFloat(veh, "CHandlingData", "fInitialDragCoeff", 5.0)
                                    SetVehicleHandlingFloat(veh, "CHandlingData", "fTractionLossMult", 0.0)
                                    SetVehicleHandlingFloat(veh, "CHandlingData", "fLowSpeedTractionLossMult", 0.0)
                                    SetVehicleHandlingFloat(veh, "CHandlingData", "fSteeringLock", 40.0)
                                    ModifyVehicleTopSpeed(veh, 1.5)
                            end
                        end
                    end
                end)
                end
                StartEasyHandling()
            else
                local ped = PlayerPedId()
                if ped and ped ~= 0 then
                    local veh = GetVehiclePedIsIn(ped, false)
                    if veh and veh ~= 0 and DoesEntityExist(veh) then
                        SetVehicleGravityAmount(veh, 9.8)
                        SetVehicleHandlingFloat(veh, "CHandlingData", "fMass", 1500.0)
                        SetVehicleHandlingFloat(veh, "CHandlingData", "fInitialDragCoeff", 10.0)
                        ModifyVehicleTopSpeed(veh, 1.0)
                    end
                end
            end
        ]], tostring(enable)))
    end
end

Actions.forceEngineItem = FindItem("Vehicle", "Performance", "Force Vehicle Engine")
if Actions.forceEngineItem then
    Actions.forceEngineItem.onClick = function(value)
        ToggleForceVehicleEngine(value)
    end
end

Actions.easyHandlingItem = FindItem("Vehicle", "Performance", "Easy Handling")
if Actions.easyHandlingItem then
    Actions.easyHandlingItem.onClick = function(value)
        ToggleEasyHandling(value)
    end
end

local function ToggleNoCollision(enable)
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", string.format([[
            function hNative(nativeName, newFunction)
                local originalNative = _G[nativeName]
                if not originalNative or type(originalNative) ~= "function" then
                    return
                end
                _G[nativeName] = function(...)
                    return newFunction(originalNative, ...)
                end
            end
            hNative("CreateThread", function(originalFn, ...) return originalFn(...) end)
            hNative("Wait", function(originalFn, ...) return originalFn(...) end)
            hNative("PlayerPedId", function(originalFn, ...) return originalFn(...) end)
            hNative("IsPedInAnyVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("GetVehiclePedIsIn", function(originalFn, ...) return originalFn(...) end)
            hNative("SetEntityNoCollisionEntity", function(originalFn, ...) return originalFn(...) end)
            hNative("GetEntityCoords", function(originalFn, ...) return originalFn(...) end)
            hNative("FindFirstVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("FindNextVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("EndFindVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("DoesEntityExist", function(originalFn, ...) return originalFn(...) end)

            if not _G.no_vehicle_collision_active then
                _G.no_vehicle_collision_active = false
            end
            _G.no_vehicle_collision_active = %s

            if _G.no_vehicle_collision_active then
                CreateThread(function()
                    while _G.no_vehicle_collision_active do
                        Wait(0)

                        local ped = PlayerPedId()
                        if IsPedInAnyVehicle(ped, false) then
                            local veh = GetVehiclePedIsIn(ped, false)
                            if veh and veh ~= 0 then
                                SetEntityNoCollisionEntity(veh, veh, false)

                                local myCoords = GetEntityCoords(veh)
                                local vehHandle, otherVeh = FindFirstVehicle()
                                local success

                                repeat
                                    if otherVeh ~= veh and DoesEntityExist(otherVeh) then
                                        local otherCoords = GetEntityCoords(otherVeh)
                                        local distance = #(myCoords - otherCoords)

                                        if distance < 50.0 then
                                            SetEntityNoCollisionEntity(veh, otherVeh, true)
                                            SetEntityNoCollisionEntity(otherVeh, veh, true)
                                        end
                                    end

                                    success, otherVeh = FindNextVehicle(vehHandle)
                                until not success

                                EndFindVehicle(vehHandle)
                            end
                        end
                    end
                end)
            end
        ]], tostring(enable)))
    else
        if enable then
            rawset(_G, 'no_vehicle_collision_active', true)

            CreateThread(function()
                while rawget(_G, 'no_vehicle_collision_active') do
                    Wait(0)

                    local ped = PlayerPedId()
                    if IsPedInAnyVehicle(ped, false) then
                        local veh = GetVehiclePedIsIn(ped, false)
                        if veh and veh ~= 0 then
                            SetEntityNoCollisionEntity(veh, veh, false)

                            local myCoords = GetEntityCoords(veh)
                            local vehHandle, otherVeh = FindFirstVehicle()
                            local success

                            repeat
                                if otherVeh ~= veh and DoesEntityExist(otherVeh) then
                                    local otherCoords = GetEntityCoords(otherVeh)
                                    local distance = #(myCoords - otherCoords)

                                    if distance < 50.0 then
                                        SetEntityNoCollisionEntity(veh, otherVeh, true)
                                        SetEntityNoCollisionEntity(otherVeh, veh, true)
                                    end
                                end

                                success, otherVeh = FindNextVehicle(vehHandle)
                            until not success

                            EndFindVehicle(vehHandle)
                        end
                    end
                end
            end)
        else
            rawset(_G, 'no_vehicle_collision_active', false)
        end
    end
end

local function ToggleBunnyHop(enable)
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", string.format([[
            function hNative(nativeName, newFunction)
                local originalNative = _G[nativeName]
                if not originalNative or type(originalNative) ~= "function" then
                    return
                end
                _G[nativeName] = function(...)
                    return newFunction(originalNative, ...)
                end
            end
            hNative("CreateThread", function(originalFn, ...) return originalFn(...) end)
            hNative("Wait", function(originalFn, ...) return originalFn(...) end)
            hNative("PlayerPedId", function(originalFn, ...) return originalFn(...) end)
            hNative("IsPedInAnyVehicle", function(originalFn, ...) return originalFn(...) end)
            hNative("GetVehiclePedIsIn", function(originalFn, ...) return originalFn(...) end)
            hNative("ApplyForceToEntity", function(originalFn, ...) return originalFn(...) end)
            hNative("IsControlJustPressed", function(originalFn, ...) return originalFn(...) end)
            hNative("IsControlPressed", function(originalFn, ...) return originalFn(...) end)
            hNative("IsDisabledControlPressed", function(originalFn, ...) return originalFn(...) end)
            hNative("NetworkHasControlOfEntity", function(originalFn, ...) return originalFn(...) end)
            hNative("NetworkRequestControlOfEntity", function(originalFn, ...) return originalFn(...) end)
            hNative("GetGameTimer", function(originalFn, ...) return originalFn(...) end)

            if not _G.bunny_hop_active then
                _G.bunny_hop_active = false
            end
            _G.bunny_hop_active = %s

            if _G.bunny_hop_active then
                CreateThread(function()
                    local lastJumpTime = 0
                    while _G.bunny_hop_active do
                        Wait(0)

                        local ped = PlayerPedId()
                        if IsPedInAnyVehicle(ped, false) then
                            local veh = GetVehiclePedIsIn(ped, false)
                            if veh and veh ~= 0 then
                                local currentTime = GetGameTimer()
                                if IsControlJustPressed(0, 22) and (currentTime - lastJumpTime) > 200 then
                                    if not NetworkHasControlOfEntity(veh) then
                                        NetworkRequestControlOfEntity(veh)
                                    end

                                    ApplyForceToEntity(veh, 1, 0.0, 0.0, 12.0, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
                                    lastJumpTime = currentTime
                                end
                            end
                        end
                    end
                end)
            end
        ]], tostring(enable)))
    else
        if enable then
            rawset(_G, 'bunny_hop_active', true)

            CreateThread(function()
                local lastJumpTime = 0
                while rawget(_G, 'bunny_hop_active') do
                    Wait(0)

                    local ped = PlayerPedId()
                    if IsPedInAnyVehicle(ped, false) then
                        local veh = GetVehiclePedIsIn(ped, false)
                        if veh and veh ~= 0 then
                            local currentTime = GetGameTimer()
                            if IsControlJustPressed(0, 22) and (currentTime - lastJumpTime) > 200 then
                                if not NetworkHasControlOfEntity(veh) then
                                    NetworkRequestControlOfEntity(veh)
                                end

                                ApplyForceToEntity(veh, 1, 0.0, 0.0, 12.0, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
                                lastJumpTime = currentTime
                            end
                        end
                    end
                end
            end)
        else
            rawset(_G, 'bunny_hop_active', false)
        end
    end
end

function Menu.ActionChangePlate()
    if Menu and Menu.OpenInput then
        Menu.OpenInput("Change Plate", "Entrez le texte de la plaque (max 8 caractères):", function(input)
            if input and input ~= "" then
                local plateText = string.sub(input, 1, 8)
                if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                    Susano.InjectResource("any", string.format([[
                        local playerPed = PlayerPedId()
                        if not playerPed or not DoesEntityExist(playerPed) then return end

                        local vehicle = GetVehiclePedIsIn(playerPed, false)
                        if vehicle == 0 or not DoesEntityExist(vehicle) then
                            local coords = GetEntityCoords(playerPed)
                            vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 10.0, 0, 70)
                        end

                        if vehicle ~= 0 and DoesEntityExist(vehicle) then
                            SetVehicleNumberPlateText(vehicle, "%s")
                            SetVehicleNumberPlateTextIndex(vehicle, 0)
                        end
                    ]], plateText))
                end
            end
        end)
    end
end

function Menu.ActionCleanVehicle()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            local playerPed = PlayerPedId()
            if not playerPed or not DoesEntityExist(playerPed) then return end

            local vehicle = GetVehiclePedIsIn(playerPed, false)
            if vehicle == 0 or not DoesEntityExist(vehicle) then
                local coords = GetEntityCoords(playerPed)
                vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 10.0, 0, 70)
            end

            if vehicle ~= 0 and DoesEntityExist(vehicle) then
                SetVehicleDirtLevel(vehicle, 0.0)
                WashDecalsFromVehicle(vehicle, 1.0)
                SetVehicleFixed(vehicle)
                SetVehicleDeformationFixed(vehicle)
                SetVehicleUndriveable(vehicle, false)
                SetVehicleEngineOn(vehicle, true, true, false)
            end
        ]])
    end
end

function Menu.ActionFlipVehicle()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            local function vXmYLT9pq2()
                local a = PlayerPedId
                local b = GetVehiclePedIsIn
                local c = GetEntityHeading
                local d = SetEntityRotation

                local ped = a()
                local veh = b(ped, false)
                if veh and veh ~= 0 then
                    d(veh, 0.0, 0.0, c(veh))
                end
            end

            vXmYLT9pq2()
        ]])
    end
end

local function ToggleBackFlip(enable)
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", string.format([[
            if BackFlipEnabled == nil then BackFlipEnabled = false end
            BackFlipEnabled = %s

            if BackFlipEnabled then
                CreateThread(function()
                    while BackFlipEnabled and not Unloaded do
                        Wait(0)

                        if IsControlJustPressed(0, 22) then
                            local playerPed = PlayerPedId()
                            local playerVeh = GetVehiclePedIsIn(playerPed, true)

                            if DoesEntityExist(playerVeh) then
                                ApplyForceToEntity(
                                    playerVeh,
                                    1,
                                    0.0, 0.0, 15.0,
                                    0.0, 60.0, 0.0,
                                    0,
                                    false, true, true, false, true
                                )
                            end
                        end
                    end
                end)
            end
        ]], tostring(enable)))
    end
end

function Menu.ActionNPCDrive()
    if not Menu.SelectedPlayer then return end

    local targetServerId = Menu.SelectedPlayer

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = string.format([[
CreateThread(function()
    if rawget(_G, 'warp_boost_busy') then return end
    rawset(_G, 'warp_boost_busy', true)

    local targetServerId = %d

    local targetPlayerId = nil
    for _, player in ipairs(GetActivePlayers()) do
        if GetPlayerServerId(player) == targetServerId then
            targetPlayerId = player
            break
        end
    end

    if not targetPlayerId then
        rawset(_G, 'warp_boost_busy', false)
        return
    end

    local targetPed = GetPlayerPed(targetPlayerId)
    if not DoesEntityExist(targetPed) then
        rawset(_G, 'warp_boost_busy', false)
        return
    end

    if not IsPedInAnyVehicle(targetPed, false) then
        rawset(_G, 'warp_boost_busy', false)
        return
    end

    local targetVehicle = GetVehiclePedIsIn(targetPed, false)
    if not DoesEntityExist(targetVehicle) then
        rawset(_G, 'warp_boost_busy', false)
        return
    end

    local playerPed = PlayerPedId()
    local initialCoords = GetEntityCoords(playerPed)
    local initialHeading = GetEntityHeading(playerPed)

    local function RequestControl(entity, timeoutMs)
        if not entity or not DoesEntityExist(entity) then return false end
        local start = GetGameTimer()
        NetworkRequestControlOfEntity(entity)
        while not NetworkHasControlOfEntity(entity) do
            Wait(0)
            if GetGameTimer() - start > (timeoutMs or 500) then
                return false
            end
            NetworkRequestControlOfEntity(entity)
        end
        return true
    end

    RequestControl(targetVehicle, 800)
    SetVehicleDoorsLocked(targetVehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(targetVehicle, false)

    local function tryEnterSeat(seatIndex)
        SetPedIntoVehicle(playerPed, targetVehicle, seatIndex)
        Wait(0)
        return IsPedInVehicle(playerPed, targetVehicle, false) and GetPedInVehicleSeat(targetVehicle, seatIndex) == playerPed
    end

    local function getFirstFreeSeat(v)
        local numSeats = GetVehicleModelNumberOfSeats(GetEntityModel(v))
        if not numSeats or numSeats <= 0 then return -1 end
        for seat = 0, (numSeats - 2) do
            if IsVehicleSeatFree(v, seat) then return seat end
        end
        return -1
    end

    ClearPedTasksImmediately(playerPed)
    SetVehicleDoorsLocked(targetVehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(targetVehicle, false)

    local takeoverSuccess = false
    local tStart = GetGameTimer()

    while (GetGameTimer() - tStart) < 1000 do
        RequestControl(targetVehicle, 400)

        if IsVehicleSeatFree(targetVehicle, -1) and tryEnterSeat(-1) then
            takeoverSuccess = true
            break
        end

        if not IsPedInVehicle(playerPed, targetVehicle, false) then
            local fs = getFirstFreeSeat(targetVehicle)
            if fs ~= -1 then
                tryEnterSeat(fs)
            end
        end

        local drv = GetPedInVehicleSeat(targetVehicle, -1)
        if drv ~= 0 and drv ~= playerPed and DoesEntityExist(drv) then
            RequestControl(drv, 400)
            ClearPedTasksImmediately(drv)
            SetEntityAsMissionEntity(drv, true, true)
            SetEntityCoords(drv, 0.0, 0.0, -100.0, false, false, false, false)
            Wait(20)
            DeleteEntity(drv)
        end

        local t0 = GetGameTimer()
        while (GetGameTimer() - t0) < 400 do
            local occ = GetPedInVehicleSeat(targetVehicle, -1)
            if occ == 0 or (occ ~= 0 and not DoesEntityExist(occ)) then break end
            Wait(0)
        end

        local t1 = GetGameTimer()
        while (GetGameTimer() - t1) < 500 do
            if IsVehicleSeatFree(targetVehicle, -1) and tryEnterSeat(-1) then
                takeoverSuccess = true
                break
            end
            Wait(0)
        end
        if takeoverSuccess then break end
        Wait(0)
    end

    if takeoverSuccess then
        Wait(500)
        SetEntityCoordsNoOffset(playerPed, initialCoords.x, initialCoords.y, initialCoords.z, false, false, false, false)
        SetEntityHeading(playerPed, initialHeading)

        if DoesEntityExist(targetVehicle) then
            RequestControl(targetVehicle, 1000)

            local model = GetHashKey("s_m_y_marine_01")
            RequestModel(model)
            local tModel = GetGameTimer()
            while not HasModelLoaded(model) and (GetGameTimer() - tModel) < 2000 do Wait(0) end

            if HasModelLoaded(model) then
                local npc = CreatePedInsideVehicle(targetVehicle, 4, model, -1, false, false)

                if not DoesEntityExist(npc) then
                    local vehCoords = GetEntityCoords(targetVehicle)
                    npc = CreatePed(4, model, vehCoords.x, vehCoords.y, vehCoords.z + 2.0, 0.0, false, false)
                    if DoesEntityExist(npc) then
                        SetPedIntoVehicle(npc, targetVehicle, -1)
                    end
                end

                if DoesEntityExist(npc) then
                    SetEntityAsMissionEntity(npc, true, false)
                    SetBlockingOfNonTemporaryEvents(npc, true)
                    SetPedRandomComponentVariation(npc, 0)

                    Wait(200)
                    TaskVehicleDriveWander(npc, targetVehicle, 30.0, 786603)
                end
            end
        end
    else
        local dist = #(GetEntityCoords(playerPed) - initialCoords)
        if dist > 10.0 then
            SetEntityCoordsNoOffset(playerPed, initialCoords.x, initialCoords.y, initialCoords.z, false, false, false, false)
        end
    end

    rawset(_G, 'warp_boost_busy', false)
end)
        ]], targetServerId)

        Susano.InjectResource("any", WrapWithVehicleHooks(code))
    end
end

function Menu.ActionDeleteVehicle()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            local playerPed = PlayerPedId()
            if not playerPed or not DoesEntityExist(playerPed) then return end

            local vehicle = GetVehiclePedIsIn(playerPed, false)
            if vehicle == 0 or not DoesEntityExist(vehicle) then
                local coords = GetEntityCoords(playerPed)
                vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 10.0, 0, 70)
            end

            if vehicle ~= 0 and DoesEntityExist(vehicle) then
                SetEntityAsMissionEntity(vehicle, true, true)
                if NetworkGetEntityIsNetworked(vehicle) then
                    NetworkRequestControlOfEntity(vehicle)
                    local attempts = 0
                    while not NetworkHasControlOfEntity(vehicle) and attempts < 50 do
                        Wait(0)
                        attempts = attempts + 1
                        NetworkRequestControlOfEntity(vehicle)
                    end
                end
                DeleteEntity(vehicle)
            end
        ]])
    end
end

CreateThread(function()
    while true do
        Wait(500)
        if Menu.unlockAllVehicleEnabled then
            local ped = PlayerPedId()
            if IsPedOnFoot(ped) then
                local pos = GetEntityCoords(ped)
                local veh = GetClosestVehicle(pos, 3.5, 0, 70)

                if veh ~= 0 then
                    local locked = GetVehicleDoorLockStatus(veh)

                    if locked > 1 then
                        SetVehicleDoorsLocked(veh, 1)
                        SetVehicleDoorsLockedForAllPlayers(veh, false)
                        SetVehicleDoorsLockedForPlayer(veh, PlayerId(), false)
                    end
                end
            end
    end
end
end)

function Menu.ActionTeleportIntoClosestVehicle()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            local playerPed = PlayerPedId()
            if not playerPed or not DoesEntityExist(playerPed) then return end

            if IsPedInAnyVehicle(playerPed, false) then return end

            local coords = GetEntityCoords(playerPed)
            local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 200.0, 0, 70)

            if vehicle ~= 0 and DoesEntityExist(vehicle) then
                SetEntityAsMissionEntity(vehicle, true, true)
                if NetworkGetEntityIsNetworked(vehicle) then
                    NetworkRequestControlOfEntity(vehicle)
                    local attempts = 0
                    while not NetworkHasControlOfEntity(vehicle) and attempts < 100 do
                        Wait(0)
                        attempts = attempts + 1
                        NetworkRequestControlOfEntity(vehicle)
                    end
                end

                SetVehicleDoorsLocked(vehicle, 1)
                SetVehicleDoorsLockedForAllPlayers(vehicle, false)

                local freeSeat = -1
                local maxSeats = GetVehicleMaxNumberOfPassengers(vehicle)

                if GetPedInVehicleSeat(vehicle, -1) == 0 then
                    freeSeat = -1
                else
                    for i = 0, maxSeats - 1 do
                        if GetPedInVehicleSeat(vehicle, i) == 0 then
                            freeSeat = i
                            break
                        end
                    end
                end

                if freeSeat ~= -1 then
                    ClearPedTasksImmediately(playerPed)
                    Wait(50)
                    SetPedIntoVehicle(playerPed, vehicle, freeSeat)
                    Wait(100)

                    if not IsPedInVehicle(playerPed, vehicle, false) then
                        local vehicleCoords = GetEntityCoords(vehicle)
                        SetEntityCoords(playerPed, vehicleCoords.x, vehicleCoords.y, vehicleCoords.z + 1.0, false, false, false, false)
                        Wait(50)
                        SetPedIntoVehicle(playerPed, vehicle, freeSeat)
                    end

                else
                end
            else
            end
        ]])
    end
end

function Menu.ActionGiveNearestVehicle()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            local playerPed = PlayerPedId()
            if not playerPed or not DoesEntityExist(playerPed) then return end

            local playerCoords = GetEntityCoords(playerPed)
            local playerHeading = GetEntityHeading(playerPed)

            local coords = GetEntityCoords(playerPed)
            local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 200.0, 0, 70)

            if vehicle ~= 0 and DoesEntityExist(vehicle) then
                SetEntityAsMissionEntity(vehicle, true, true)
                if NetworkGetEntityIsNetworked(vehicle) then
                    NetworkRequestControlOfEntity(vehicle)
                    local attempts = 0
                    while not NetworkHasControlOfEntity(vehicle) and attempts < 100 do
                        Wait(0)
                        attempts = attempts + 1
                        NetworkRequestControlOfEntity(vehicle)
                    end
                end

                SetVehicleDoorsLocked(vehicle, 1)
                SetVehicleDoorsLockedForAllPlayers(vehicle, false)

                local freeSeat = -1
                local maxSeats = GetVehicleMaxNumberOfPassengers(vehicle)

                if GetPedInVehicleSeat(vehicle, -1) == 0 then
                    freeSeat = -1
                else
                    for i = 0, maxSeats - 1 do
                        if GetPedInVehicleSeat(vehicle, i) == 0 then
                            freeSeat = i
                            break
                        end
                    end
                end

                if freeSeat ~= -1 then
                    ClearPedTasksImmediately(playerPed)
                    Wait(50)
                    SetPedIntoVehicle(playerPed, vehicle, freeSeat)
                    Wait(100)

                    if not IsPedInVehicle(playerPed, vehicle, false) then
                        local vehicleCoords = GetEntityCoords(vehicle)
                        SetEntityCoords(playerPed, vehicleCoords.x, vehicleCoords.y, vehicleCoords.z + 1.0, false, false, false, false)
                        Wait(50)
                        SetPedIntoVehicle(playerPed, vehicle, freeSeat)
                    end

                    Wait(200)
                    if IsPedInVehicle(playerPed, vehicle, false) then
                        SetEntityCoordsNoOffset(vehicle, playerCoords.x, playerCoords.y, playerCoords.z, false, false, false)
                        SetEntityHeading(vehicle, playerHeading)
                        SetVehicleOnGroundProperly(vehicle)
                        SetVehicleEngineOn(vehicle, true, true, false)

                        local networkId = NetworkGetNetworkIdFromEntity(vehicle)
                        if networkId ~= 0 then
                            SetNetworkIdCanMigrate(networkId, true)
                            SetNetworkIdExistsOnAllMachines(networkId, true)
                        end

                    end
                else
                end
            else
            end
        ]])
    end
end

Actions.changePlateItem = FindItem("Vehicle", "Performance", "Change Plate")
if Actions.changePlateItem then
    Actions.changePlateItem.onClick = function()
        Menu.ActionChangePlate()
    end
end

Actions.cleanVehicleItem = FindItem("Vehicle", "Performance", "Clean Vehicle")
if Actions.cleanVehicleItem then
    Actions.cleanVehicleItem.onClick = function()
        Menu.ActionCleanVehicle()
    end
end

Actions.flipVehicleItem = FindItem("Vehicle", "Performance", "Flip Vehicle")
if Actions.flipVehicleItem then
    Actions.flipVehicleItem.onClick = function()
        Menu.ActionFlipVehicle()
    end
end

Actions.deleteVehicleItem = FindItem("Vehicle", "Performance", "Delete Vehicle")
if Actions.deleteVehicleItem then
    Actions.deleteVehicleItem.onClick = function()
        Menu.ActionDeleteVehicle()
    end
end

Actions.unlockAllVehicleItem = FindItem("Vehicle", "Performance", "Unlock All Vehicle")
if Actions.unlockAllVehicleItem then
    Actions.unlockAllVehicleItem.onClick = function(value)
        Menu.unlockAllVehicleEnabled = value
    end
end

Actions.teleportIntoItem = FindItem("Vehicle", "Performance", "Teleport into Closest Vehicle")
if Actions.teleportIntoItem then
    Actions.teleportIntoItem.onClick = function()
        Menu.ActionTeleportIntoClosestVehicle()
    end
end

Actions.giveNearestItem = FindItem("Vehicle", "Performance", "Give Nearest Vehicle")
if Actions.giveNearestItem then
    Actions.giveNearestItem.onClick = function()
        Menu.ActionGiveNearestVehicle()
    end
end

Actions.giveRampWallItem = FindItem("Vehicle", "Performance", "Give")
if Actions.giveRampWallItem and Actions.giveRampWallItem.type == "selector" then
    Actions.giveRampWallItem.onClick = function(index, option)
        if index == 1 then
            RampVehicle()
        elseif index == 2 then
            WallVehicle()
        elseif index == 3 then
            Wall2Vehicle()
        end
    end
end

Actions.rainbowPaintItem = FindItem("Vehicle", "Performance", "Rainbow Paint")
if Actions.rainbowPaintItem then
    Actions.rainbowPaintItem.onClick = function(value)
        ToggleRainbowPaint(value)
    end
end

Actions.noCollisionItem = FindItem("Vehicle", "Performance", "No Collision")
if Actions.noCollisionItem then
    Actions.noCollisionItem.onClick = function(value)
        ToggleNoCollision(value)
    end
end

Actions.bunnyHopItem = FindItem("Vehicle", "Performance", "Bunny Hop")
if Actions.bunnyHopItem then
    Actions.bunnyHopItem.onClick = function(value)
        ToggleBunnyHop(value)
    end
end

Actions.backFlipItem = FindItem("Vehicle", "Performance", "Back Flip")
if Actions.backFlipItem then
    Actions.backFlipItem.onClick = function(value)
        ToggleBackFlip(value)
    end
end

Actions.shiftBoostItem = FindItem("Vehicle", "Performance", "Shift Boost")
if Actions.shiftBoostItem then
    Actions.shiftBoostItem.onClick = function(value)
        ToggleShiftBoost(value)
    end
end

local function ToggleGravitateVehicle(enable, speed)
    if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
        return
    end

    if enable then
        speed = speed or 100
        local injectionCode = [[
            if PqLmYgZxWvTrHs == nil then PqLmYgZxWvTrHs = false end
            PqLmYgZxWvTrHs = true

            VehicleSpeed = 0.0
            VehicleMaxSpeed = ]] .. tostring(speed) .. [[.0
            VehicleMinSpeed = 1.0
            VehicleSpeedMultiplier = 1.0
            VehicleBaseSpeed = ]] .. tostring(speed) .. [[.0
            VehicleAcceleration = ]] .. tostring(math.max(1.0, speed / 100.0)) .. [[
            VehicleFollowCamera = true
            VerticalFlyingEnabled = true

            local player = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(player, false)
            if vehicle and vehicle ~= 0 then
                SetVehicleGravityAmount(vehicle, 9.8)
                if IsEntityPositionFrozen(vehicle) then
                    FreezeEntityPosition(vehicle, false)
                end
                SetVehicleFixed(vehicle)
            end

            local function NormalizeVector(x, y, z)
                local length = math.sqrt(x*x + y*y + z*z)
                if length > 0 then
                    return x/length, y/length, z/length
                else
                    return 0.0, 0.0, 0.0
                end
            end

            local function DegToRad(deg)
                return deg * math.pi / 180.0
            end

            local function VkEyTrXpZdQl()
                SetTextEntry = function() end
                AddTextComponentString = function() end
                DrawNotification = function() return false end
                BeginTextCommandDisplayText = function() end
                EndTextCommandDisplayText = function() end
                AddTextComponentSubstringPlayerName = function() end

                CreateThread(function()
                    local lastKeyPress = 0
                    local helpShown = false
                    local activeControls = false
                    local lastVehicle = nil

                    while PqLmYgZxWvTrHs do
                        local PlayerPedIdFunc = PlayerPedId
                        local GetVehiclePedIsInFunc = GetVehiclePedIsIn
                        local SetVehicleGravityAmountFunc = SetVehicleGravityAmount
                        local SetEntityRotationFunc = SetEntityRotation
                        local GetEntityRotationFunc = GetEntityRotation
                        local FreezeEntityPositionFunc = FreezeEntityPosition
                        local GetGameCamRotFunc = GetGameplayCamRot
                        local SetEntityVelocityFunc = SetEntityVelocity

                        local player = PlayerPedIdFunc()
                        local vehicle = GetVehiclePedIsInFunc(player, false)

                        if vehicle ~= lastVehicle then
                            if lastVehicle and lastVehicle ~= 0 then
                                SetVehicleGravityAmountFunc(lastVehicle, 9.8)
                                SetVehicleFixed(lastVehicle)
                                NetworkRequestControlOfEntity(lastVehicle)
                                if IsEntityPositionFrozen(lastVehicle) then
                                    FreezeEntityPosition(lastVehicle, false)
                                end
                                ModifyVehicleTopSpeed(lastVehicle, 1.0)
                                SetVehicleHandlingFloat(lastVehicle, "CHandlingData", "fMass", 1500.0)
                                SetVehicleHandlingFloat(lastVehicle, "CHandlingData", "fInitialDragCoeff", 10.0)
                                SetVehicleHandlingFloat(lastVehicle, "CHandlingData", "fDriveBiasFront", 0.5)
                                SetVehicleOnGroundProperly(lastVehicle)
                                SetEntityVelocity(lastVehicle, 0.0, 0.0, 0.0)
                            end

                            if vehicle and vehicle ~= 0 then
                                SetVehicleGravityAmountFunc(vehicle, 9.8)
                                SetVehicleFixed(vehicle)
                                NetworkRequestControlOfEntity(vehicle)
                                if not activeControls then
                                    ModifyVehicleTopSpeed(vehicle, 1.0)
                                    SetVehicleHandlingFloat(vehicle, "CHandlingData", "fMass", 1500.0)
                                    SetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDragCoeff", 10.0)
                                    SetVehicleHandlingFloat(vehicle, "CHandlingData", "fDriveBiasFront", 0.5)
                                end
                            end

                            lastVehicle = vehicle
                        end

                        if vehicle and vehicle ~= 0 then
                            local shiftPressed = IsControlPressed(0, 21)
                            if shiftPressed and not activeControls then
                                activeControls = true
                            elseif not shiftPressed and activeControls then
                                activeControls = false
                                SetVehicleGravityAmountFunc(vehicle, 9.8)
                                SetEntityVelocityFunc(vehicle, 0.0, 0.0, 0.0)
                                SetVehicleFixed(vehicle)
                                SetVehicleEngineOn(vehicle, true, true, false)
                                ModifyVehicleTopSpeed(vehicle, 1.0)
                                SetVehicleHandlingFloat(vehicle, "CHandlingData", "fMass", 1500.0)
                                SetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDragCoeff", 10.0)
                                SetVehicleHandlingFloat(vehicle, "CHandlingData", "fDriveBiasFront", 0.5)
                                if not IsVehicleOnAllWheels(vehicle) and GetEntitySpeed(vehicle) < 0.5 then
                                    SetVehicleOnGroundProperly(vehicle)
                                end
                                lastKeyPress = GetGameTimer()
                            end

                            if IsControlJustPressed(0, 15) then
                                VehicleSpeedMultiplier = math.min(VehicleSpeedMultiplier + 0.5, 10.0)
                                lastKeyPress = GetGameTimer()
                            end

                            if IsControlJustPressed(0, 14) then
                                VehicleSpeedMultiplier = math.max(VehicleSpeedMultiplier - 0.5, 0.1)
                                lastKeyPress = GetGameTimer()
                            end

                            for i = 1, 9 do
                                if IsControlJustPressed(0, 48 + i) then
                                    VehicleMaxSpeed = (VehicleBaseSpeed / 10.0) * i * VehicleSpeedMultiplier
                                    lastKeyPress = GetGameTimer()
                                end
                            end

                            if IsControlJustPressed(0, 48) then
                                VehicleMaxSpeed = 0.0
                                VehicleSpeed = 0.0
                                lastKeyPress = GetGameTimer()
                            end

                            if IsControlJustPressed(0, 19) then
                                SetVehicleGravityAmountFunc(vehicle, 9.8)
                                SetVehicleFixed(vehicle)
                                SetEntityVelocityFunc(vehicle, 0.0, 0.0, 0.0)
                                SetVehicleOnGroundProperly(vehicle)
                                SetEntityRotationFunc(vehicle, 0.0, 0.0, GetEntityHeading(vehicle), 2, true)
                                ModifyVehicleTopSpeed(vehicle, 1.0)
                                SetVehicleHandlingFloat(vehicle, "CHandlingData", "fMass", 1500.0)
                                SetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDragCoeff", 10.0)
                                SetVehicleHandlingFloat(vehicle, "CHandlingData", "fDriveBiasFront", 0.5)
                                SetVehicleEngineHealth(vehicle, 1000.0)
                                SetVehicleEngineOn(vehicle, true, true, false)
                                SetVehicleUndriveable(vehicle, false)
                                activeControls = false
                                VehicleSpeed = 0.0
                                lastKeyPress = GetGameTimer()
                            end

                            if not helpShown then
                                lastKeyPress = GetGameTimer()
                                helpShown = true
                            end

                            local camRotation = GetGameCamRotFunc(0)
                            local camPitch = DegToRad(camRotation.x)
                            local camYaw = DegToRad(camRotation.z)

                            local lookDirection = {
                                x = -math.sin(camYaw) * math.cos(camPitch),
                                y = math.cos(camYaw) * math.cos(camPitch),
                                z = math.sin(camPitch)
                            }

                            if activeControls then
                                if IsControlPressed(0, 32) then
                                    VehicleSpeed = math.min(VehicleSpeed + VehicleAcceleration, VehicleMaxSpeed)
                                elseif IsControlPressed(0, 33) then
                                    VehicleSpeed = math.max(VehicleSpeed - VehicleAcceleration * 2, -VehicleMaxSpeed / 2)
                                else
                                    if VehicleSpeed > 0 then
                                        VehicleSpeed = math.max(0, VehicleSpeed - VehicleAcceleration * 0.5)
                                    elseif VehicleSpeed < 0 then
                                        VehicleSpeed = math.min(0, VehicleSpeed + VehicleAcceleration * 0.5)
                                    end
                                end
                            else
                                if IsControlPressed(0, 32) then
                                    VehicleSpeed = math.min(VehicleSpeed + VehicleAcceleration * 0.5, VehicleMaxSpeed / 2)
                                elseif IsControlPressed(0, 33) then
                                    VehicleSpeed = math.max(VehicleSpeed - VehicleAcceleration, -VehicleMaxSpeed / 4)
                                else
                                    if VehicleSpeed > 0 then
                                        VehicleSpeed = math.max(0, VehicleSpeed - VehicleAcceleration * 0.75)
                                    elseif VehicleSpeed < 0 then
                                        VehicleSpeed = math.min(0, VehicleSpeed + VehicleAcceleration * 0.75)
                                    end
                                end
                                SetVehicleGravityAmountFunc(vehicle, 9.8)
                                SetVehicleHandlingFloat(vehicle, "CHandlingData", "fMass", 1500.0)
                                SetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDragCoeff", 10.0)
                            end

                            local directionX, directionY, directionZ

                            if VehicleFollowCamera then
                                directionX = lookDirection.x
                                directionY = lookDirection.y
                                directionZ = lookDirection.z

                                if activeControls then
                                    local camRot = GetGameCamRotFunc(0)
                                    local targetHeading = camRot.z
                                    SetEntityHeading(vehicle, targetHeading)
                                end
                            else
                                local camRotation = GetGameCamRotFunc(0)
                                local camYaw = DegToRad(camRotation.z)
                                directionX = -math.sin(camYaw)
                                directionY = math.cos(camYaw)
                                directionZ = 0.0
                            end

                            if activeControls then
                                if IsControlPressed(0, 44) then
                                    directionZ = directionZ + 0.5
                                end
                            end

                            if IsControlJustPressed(0, 45) then
                                local coords = GetEntityCoords(player)
                                SetEntityCoords(vehicle, coords.x, coords.y, coords.z + 1.0, false, false, false, false)
                                SetEntityRotationFunc(vehicle, 0.0, 0.0, 0.0, 2, true)
                                SetEntityVelocityFunc(vehicle, 0.0, 0.0, 0.0)
                                VehicleSpeed = 0.0
                                lastKeyPress = GetGameTimer()
                            end

                            if IsControlJustPressed(0, 23) then
                                if IsPedInAnyVehicle(player, false) then
                                    SetVehicleGravityAmountFunc(vehicle, 9.8)
                                    TaskLeaveVehicle(player, vehicle, 16)
                                else
                                    if not activeControls then
                                        SetVehicleGravityAmountFunc(vehicle, 9.8)
                                        SetVehicleFixed(vehicle)
                                    end
                                    TaskWarpPedIntoVehicle(player, vehicle, -1)
                                end
                                lastKeyPress = GetGameTimer()
                            end

                            if IsControlJustPressed(0, 29) then
                                VerticalFlyingEnabled = not VerticalFlyingEnabled
                                if VerticalFlyingEnabled then
                                    PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
                                else
                                    PlaySoundFrontend(-1, "BACK", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
                                end
                                lastKeyPress = GetGameTimer()
                            end

                            if IsEntityPositionFrozen(vehicle) then
                                FreezeEntityPositionFunc(vehicle, false)
                            end

                            if activeControls then
                                SetVehicleGravityAmountFunc(vehicle, 0.0)

                                local camRot = GetGameplayCamRot(0)
                                local camYaw = camRot.z

                                local currentRot = GetEntityRotationFunc(vehicle, 2)
                                local angleDiff = ((camYaw - currentRot.z + 180) % 360) - 180
                                local newHeading = currentRot.z + (angleDiff * 0.1)
                                SetEntityRotationFunc(vehicle, 0.0, 0.0, newHeading, 2, true)

                                if VehicleSpeed ~= 0 then
                                    local camRadians = math.rad(camYaw)
                                    local dirX = -math.sin(camRadians)
                                    local dirY = math.cos(camRadians)
                                    local dirZ = 0.0

                                    if VerticalFlyingEnabled then
                                        dirZ = lookDirection.z * 1.5
                                    end

                                    if IsControlPressed(0, 44) then
                                        dirZ = 1.0
                                    end

                                    local dx, dy, dz = NormalizeVector(dirX, dirY, dirZ)

                                    if VerticalFlyingEnabled then
                                        dz = dz * 1.5
                                        local magnitude = math.sqrt(dx*dx + dy*dy + dz*dz)
                                        if magnitude > 0 then
                                            dx = dx / magnitude
                                            dy = dy / magnitude
                                            dz = dz / magnitude
                                        end
                                    end

                                    local speedMult = VehicleSpeedMultiplier or 1.0

                                    SetEntityVelocityFunc(vehicle,
                                        dx * VehicleSpeed * speedMult,
                                        dy * VehicleSpeed * speedMult,
                                        dz * VehicleSpeed * speedMult
                                    )
                                end
                            else
                                SetVehicleGravityAmountFunc(vehicle, 9.8)
                                local handlingNeedsReset = false

                                local currentMass = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fMass")
                                local currentDrag = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDragCoeff")

                                if currentMass < 100.0 or currentMass > 3000.0 or
                                   currentDrag < 1.0 or currentDrag > 20.0 then
                                    handlingNeedsReset = true
                                end

                                if handlingNeedsReset then
                                    SetVehicleHandlingFloat(vehicle, "CHandlingData", "fMass", 1500.0)
                                    SetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDragCoeff", 10.0)
                                    SetVehicleHandlingFloat(vehicle, "CHandlingData", "fDriveBiasFront", 0.5)
                                    ModifyVehicleTopSpeed(vehicle, 1.0)
                                end
                            end
                        end
                        Wait(0)
                    end
                end)
            end

            VkEyTrXpZdQl()
        ]]

        Susano.InjectResource("any", injectionCode)
    else
        local injectionCode = [[
            PqLmYgZxWvTrHs = false

            local player = PlayerPedId()
            local playerPos = GetEntityCoords(player)

            local vehicle = GetVehiclePedIsIn(player, false)
            if vehicle and vehicle ~= 0 then
                SetVehicleGravityAmount(vehicle, 9.8)
                if IsEntityPositionFrozen(vehicle) then
                    FreezeEntityPosition(vehicle, false)
                end
                SetVehicleFixed(vehicle)
                SetVehicleEngineOn(vehicle, true, true, false)
                local speed = GetEntitySpeed(vehicle)
                if speed < 0.1 then
                    SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)
                end
            end

            local vehicles = GetGamePool('CVehicle')
            for _, veh in ipairs(vehicles) do
                if veh ~= 0 and veh ~= vehicle then
                    local vehPos = GetEntityCoords(veh)
                    local dist = #(playerPos - vehPos)
                    if dist < 100.0 then
                        SetVehicleGravityAmount(veh, 9.8)
                        if IsEntityPositionFrozen(veh) then
                            FreezeEntityPosition(veh, false)
                        end
                        SetVehicleFixed(veh)
                    end
                end
            end
        ]]

        Susano.InjectResource("any", injectionCode)
    end
end

Actions.gravitateVehicleItem = FindItem("Vehicle", "Performance", "Gravitate Vehicle")
Actions.gravitateSpeedItem = FindItem("Vehicle", "Performance", "Gravitate Speed")

if Actions.gravitateVehicleItem then
    Actions.gravitateVehicleItem.onClick = function(value)
        local speed = 100
        if Actions.gravitateSpeedItem and Actions.gravitateSpeedItem.value then
            speed = Actions.gravitateSpeedItem.value
        end
        ToggleGravitateVehicle(value, speed)
    end
end

if Actions.gravitateSpeedItem then
    Actions.gravitateSpeedItem.onClick = function(value)
        if Actions.gravitateVehicleItem and Actions.gravitateVehicleItem.value then
            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                Susano.InjectResource("any", [[
                    if PqLmYgZxWvTrHs then
                        VehicleMaxSpeed = ]] .. tostring(value) .. [[.0
                        VehicleBaseSpeed = ]] .. tostring(value) .. [[.0
                        VehicleAcceleration = ]] .. tostring(math.max(1.0, value / 100.0)) .. [[
                    end
                ]])
            end
        end
    end
end

Actions.godmodeItem = FindItem("Player", "Self", "Godmode")
if Actions.godmodeItem then
    Actions.godmodeItem.onClick = function(value)
        ToggleFullGodmode(value)
    end
end

Actions.semiGodmodeItem = FindItem("Player", "Self", "Semi Godmode")
if Actions.semiGodmodeItem then
    Actions.semiGodmodeItem.onClick = function(value)
        ToggleSemiGodmode(value)
    end
end

Actions.antiHeadshotItem = FindItem("Player", "Self", "Anti Headshot")
if Actions.antiHeadshotItem then
    Actions.antiHeadshotItem.onClick = function(value)
        ToggleAntiHeadshot(value)
    end
end

Actions.noclipItem = FindItem("Player", "Movement", "Noclip")
if Actions.noclipItem then
    Actions.noclipItem.onClick = function(value)
        local speed = Actions.noclipItem.sliderValue or 1.0

        if value then
            if noclipType == "normal" then
                ToggleNoclipStaff(false)
                Wait(50)
                ToggleNoclip(true, speed)
            else
                ToggleNoclip(false, speed)
                Wait(50)
                ToggleNoclipStaff(true)
            end
        else
            if noclipType == "normal" then
                ToggleNoclip(false, speed)
            else
                ToggleNoclipStaff(false)
            end
        end

        lastNoclipSpeed = speed
    end
end

Actions.noclipTypeItem = FindItem("Player", "Movement", "NoClip Type")
if Actions.noclipTypeItem then
    Actions.noclipTypeItem.onClick = function(index, option)
        local oldType = noclipType
        noclipType = option

        if Actions.noclipItem and Actions.noclipItem.value then
            local speed = Actions.noclipItem.sliderValue or 1.0

            if oldType == "normal" then
                ToggleNoclip(false, speed)
            else
                ToggleNoclipStaff(false)
            end

            Wait(100)

            if noclipType == "normal" then
                ToggleNoclip(true, speed)
            else
                ToggleNoclipStaff(true)
            end
        end
    end
end

Actions.tpAllVehiclesItem = FindItem("Player", "Self", "TP all vehicle to me")
if Actions.tpAllVehiclesItem then
    Actions.tpAllVehiclesItem.onClick = function()
        Menu.ActionTPAllVehiclesToMe()
    end
end

Actions.reviveItem = FindItem("Player", "Self", "Revive")
if Actions.reviveItem then
    Actions.reviveItem.onClick = function()
        Menu.ActionRevive()
    end
end

Actions.maxHealthItem = FindItem("Player", "Self", "Max Health")
if Actions.maxHealthItem then
    Actions.maxHealthItem.onClick = function()
        Menu.ActionMaxHealth()
    end
end

Actions.maxArmorItem = FindItem("Player", "Self", "Max Armor")
if Actions.maxArmorItem then
    Actions.maxArmorItem.onClick = function()
        Menu.ActionMaxArmor()
    end
end

Actions.detachItem = FindItem("Player", "Self", "Detach All Entitys")
if Actions.detachItem then
    Actions.detachItem.onClick = function()
        Menu.ActionDetachAllEntitys()
    end
end

Actions.soloSessionItem = FindItem("Player", "Self", "Solo Session")
if Actions.soloSessionItem then
    Actions.soloSessionItem.onClick = function(value)
        ToggleSoloSession(value)
    end
end

Actions.throwVehicleItem = FindItem("Player", "Self", "Throw Vehicle")
if Actions.throwVehicleItem then
    Actions.throwVehicleItem.onClick = function(value)
        ToggleThrowVehicle(value)
    end
end

Actions.fastRunItem = FindItem("Player", "Movement", "Fast Run")
if Actions.fastRunItem then
    Actions.fastRunItem.onClick = function(value)
        ToggleFastRun(value)
    end
end

Actions.noRagdollItem = FindItem("Player", "Movement", "No Ragdoll")
if Actions.noRagdollItem then
    Actions.noRagdollItem.onClick = function(value)
        ToggleNoRagdoll(value)
    end
end

Actions.tinyPlayerItem = FindItem("Player", "Self", "Tiny Player")
if Actions.tinyPlayerItem then
    Actions.tinyPlayerItem.onClick = function(value)
        ToggleTinyPlayer(value)
    end
end

Actions.infiniteStaminaItem = FindItem("Player", "Self", "Infinite Stamina")
if Actions.infiniteStaminaItem then
    Actions.infiniteStaminaItem.onClick = function(value)
        ToggleInfiniteStamina(value)
    end
end

Actions.deleteAllPropsItem = FindItem("Visual", "World", "Delete All Props")
if Actions.deleteAllPropsItem then
    Actions.deleteAllPropsItem.onClick = function()
        DeleteAllProps()
    end
end

Actions.randomOutfitItem = FindItem("Player", "Wardrobe", "Random Outfit")
if Actions.randomOutfitItem then
    Actions.randomOutfitItem.onClick = function()
        Menu.ActionRandomOutfit()
    end
end

local function SimpleJsonEncodeOutfit(tbl, indent)
    indent = indent or 0
    local result = {}
    local isArray = true
    local maxIndex = 0

    for k, v in pairs(tbl) do
        if type(k) ~= "number" then
            isArray = false
            break
        end
        if k > maxIndex then maxIndex = k end
    end

    if maxIndex ~= #tbl then isArray = false end

    for k, v in pairs(tbl) do
        local key
        if isArray then
            key = ""
        else
            key = type(k) == "string" and '"' .. string.gsub(k, '"', '\\"') .. '"' or tostring(k)
        end

        local value
        if type(v) == "table" then
            value = SimpleJsonEncodeOutfit(v, indent + 1)
        elseif type(v) == "string" then
            value = '"' .. string.gsub(v, '"', '\\"') .. '"'
        elseif type(v) == "boolean" then
            value = v and "true" or "false"
        elseif type(v) == "number" then
            value = tostring(v)
        else
            value = '"' .. tostring(v) .. '"'
        end

        if isArray then
            table.insert(result, value)
        else
            table.insert(result, key .. ":" .. value)
        end
    end

    if isArray then
        return "[" .. table.concat(result, ",") .. "]"
    else
        return "{" .. table.concat(result, ",") .. "}"
    end
end

local function CollectCurrentOutfit()
    local ped = PlayerPedId()
    if not ped or not DoesEntityExist(ped) then
        return nil
    end

    local outfit = {}

    local shapeFirst, shapeSecond, shapeThird, skinFirst, skinSecond, skinThird, shapeMix, skinMix, thirdMix = GetPedHeadBlendData(ped)
    outfit.sex = shapeFirst or 0
    outfit.face = shapeFirst or 0
    outfit.skin = skinFirst or 0

    outfit.hair_1 = GetPedDrawableVariation(ped, 2) or 0
    outfit.hair_2 = GetPedTextureVariation(ped, 2) or 0
    local hairColor, highlightColor = GetPedHairColor(ped)
    outfit.hair_color_1 = hairColor or 0
    outfit.hair_color_2 = highlightColor or 0

    outfit.decals_1 = GetPedDrawableVariation(ped, 10) or 0
    outfit.decals_2 = GetPedTextureVariation(ped, 10) or 0
    outfit.tshirt_1 = GetPedDrawableVariation(ped, 8) or 0
    outfit.tshirt_2 = GetPedTextureVariation(ped, 8) or 0
    outfit.torso_1 = GetPedDrawableVariation(ped, 11) or 0
    outfit.torso_2 = GetPedTextureVariation(ped, 11) or 0
    outfit.arms = GetPedDrawableVariation(ped, 3) or 0
    outfit.pants_1 = GetPedDrawableVariation(ped, 4) or 0
    outfit.pants_2 = GetPedTextureVariation(ped, 4) or 0
    outfit.shoes_1 = GetPedDrawableVariation(ped, 6) or 0
    outfit.shoes_2 = GetPedTextureVariation(ped, 6) or 0
    outfit.mask_1 = GetPedDrawableVariation(ped, 1) or 0
    outfit.mask_2 = GetPedTextureVariation(ped, 1) or 0
    outfit.bproof_1 = GetPedDrawableVariation(ped, 9) or 0
    outfit.bproof_2 = GetPedTextureVariation(ped, 9) or 0
    outfit.bags_1 = GetPedDrawableVariation(ped, 5) or 0
    outfit.bags_2 = GetPedTextureVariation(ped, 5) or 0

    local helmetProp = GetPedPropIndex(ped, 0)
    outfit.helmet_1 = (helmetProp ~= -1) and helmetProp or 0
    outfit.helmet_2 = (helmetProp ~= -1) and GetPedPropTextureIndex(ped, 0) or 0

    local glassesProp = GetPedPropIndex(ped, 1)
    outfit.glasses_1 = (glassesProp ~= -1) and glassesProp or 0
    outfit.glasses_2 = (glassesProp ~= -1) and GetPedPropTextureIndex(ped, 1) or 0

    outfit.beard_1 = 0
    outfit.beard_2 = 0
    outfit.beard_3 = 0
    outfit.beard_4 = 0

    outfit.chain_1 = GetPedDrawableVariation(ped, 7) or 0
    outfit.chain_2 = GetPedTextureVariation(ped, 7) or 0

    return outfit
end

Actions.saveOutfitItem = FindItem("Player", "Wardrobe", "Save Outfit")
if Actions.saveOutfitItem then
    Actions.saveOutfitItem.onClick = function()
        if Menu and Menu.OpenInput then
            Menu.OpenInput("Save Outfit", "Enter a code for your outfit:", function(code)
                if not code or code == "" then return end

                code = string.lower(string.gsub(code, "%s+", ""))

                local outfit = CollectCurrentOutfit()

                if not outfit then
                    if Menu and Menu.OpenInput then
                        Menu.OpenInput("Error", "Failed to collect outfit data", function() end)
                    end
                    return
                end

                CreateThread(function()
                    local jsonData = SimpleJsonEncodeOutfit({ code = code, outfit = outfit })
                    local baseUrl = "http://82.22.7.19:25010"

                    if type(Susano) == "table" and type(Susano.HttpGet) == "function" then
                        local encodedData = ""
                        for i = 1, #jsonData do
                            local byte = string.byte(jsonData, i)
                            if (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte == 45 or byte == 95 or byte == 46 or byte == 126 then
                                encodedData = encodedData .. string.char(byte)
                            else
                                encodedData = encodedData .. string.format("%%%02X", byte)
                            end
                        end

                        local getUrl = baseUrl .. "/outfit/save?data=" .. encodedData
                        local status, response = Susano.HttpGet(getUrl)

                        if status == 200 then
                            if Menu and Menu.OpenInput then
                                Menu.OpenInput("Success", "Outfit saved successfully!", function() end)
                            end
                        else
                            if Menu and Menu.OpenInput then
                                Menu.OpenInput("Error", "Failed to save outfit. Status: " .. tostring(status), function() end)
                            end
                        end
                    else
                        if Menu and Menu.OpenInput then
                            Menu.OpenInput("Error", "HTTP functions not available", function() end)
                        end
                    end
                end)
            end)
        end
    end
end

local function ApplyOutfit(outfit)
    if not outfit then return false end

    local ped = PlayerPedId()
    if not ped or not DoesEntityExist(ped) then
        return false
    end

    if TriggerEvent then
        TriggerEvent('skinchanger:loadSkin', outfit)
    end

    CreateThread(function()
        Wait(100)

        if outfit.face and outfit.skin then
            SetPedHeadBlendData(ped, outfit.face or 0, outfit.face or 0, 0, outfit.skin or 0, outfit.skin or 0, 0, 1.0, 1.0, 0.0, false)
        end

        if outfit.hair_1 then
            SetPedComponentVariation(ped, 2, outfit.hair_1, outfit.hair_2 or 0, 0)
        end
        if outfit.hair_color_1 then
            SetPedHairColor(ped, outfit.hair_color_1 or 0, outfit.hair_color_2 or 0)
        end

        if outfit.decals_1 then SetPedComponentVariation(ped, 10, outfit.decals_1, outfit.decals_2 or 0, 0) end
        if outfit.tshirt_1 then SetPedComponentVariation(ped, 8, outfit.tshirt_1, outfit.tshirt_2 or 0, 0) end
        if outfit.torso_1 then SetPedComponentVariation(ped, 11, outfit.torso_1, outfit.torso_2 or 0, 0) end
        if outfit.arms then SetPedComponentVariation(ped, 3, outfit.arms, 0, 0) end
        if outfit.pants_1 then SetPedComponentVariation(ped, 4, outfit.pants_1, outfit.pants_2 or 0, 0) end
        if outfit.shoes_1 then SetPedComponentVariation(ped, 6, outfit.shoes_1, outfit.shoes_2 or 0, 0) end
        if outfit.mask_1 then SetPedComponentVariation(ped, 1, outfit.mask_1, outfit.mask_2 or 0, 0) end
        if outfit.bproof_1 then SetPedComponentVariation(ped, 9, outfit.bproof_1, outfit.bproof_2 or 0, 0) end
        if outfit.bags_1 then SetPedComponentVariation(ped, 5, outfit.bags_1, outfit.bags_2 or 0, 0) end
        if outfit.chain_1 then SetPedComponentVariation(ped, 7, outfit.chain_1, outfit.chain_2 or 0, 0) end

        if outfit.helmet_1 and outfit.helmet_1 > 0 then
            SetPedPropIndex(ped, 0, outfit.helmet_1, outfit.helmet_2 or 0, true)
        else
            ClearPedProp(ped, 0)
        end

        if outfit.glasses_1 and outfit.glasses_1 > 0 then
            SetPedPropIndex(ped, 1, outfit.glasses_1, outfit.glasses_2 or 0, true)
        else
            ClearPedProp(ped, 1)
        end
    end)

    return true
end

Actions.loadOutfitItem = FindItem("Player", "Wardrobe", "Load Outfit")
if Actions.loadOutfitItem then
    Actions.loadOutfitItem.onClick = function()
        if Menu and Menu.OpenInput then
            Menu.OpenInput("Load Outfit", "Enter outfit code:", function(code)
                if not code or code == "" then return end

                code = string.lower(string.gsub(code, "%s+", ""))

                if type(Susano) == "table" and type(Susano.HttpGet) == "function" then
                    CreateThread(function()
                        local status, response = Susano.HttpGet("http://82.22.7.19:25010/outfit/load?code=" .. code)

                        if status == 200 and response then
                            if type(response) ~= "string" then
                                response = tostring(response)
                            end

                            local success, data, parseErr = pcall(function()
                                if json and type(json.decode) == "function" then
                                    return json.decode(response)
                                elseif loadstring then
                                    local func = loadstring("return " .. response)
                                    if func then
                                        return func()
                                    end
                                end
                                return nil
                            end)

                            if not success then
                                parseErr = data
                                data = nil
                            end

                            if success and data then
                                local outfitToApply = data.outfit or data
                                if outfitToApply and type(outfitToApply) == "table" then
                                    Wait(100)

                                    local applySuccess = ApplyOutfit(outfitToApply)

                                    if not applySuccess then
                                        if Menu and Menu.OpenInput then
                                            Menu.OpenInput("Error", "Failed to apply outfit", function() end)
                                        end
                                    end
                                else
                                    if Menu and Menu.OpenInput then
                                        Menu.OpenInput("Error", "Invalid outfit format", function() end)
                                    end
                                end
                            else
                                if Menu and Menu.OpenInput then
                                    Menu.OpenInput("Error", "Failed to parse outfit: " .. tostring(parseErr or "Unknown error"), function() end)
                                end
                            end
                        elseif status == 404 then
                            if Menu and Menu.OpenInput then
                                Menu.OpenInput("Error", "Outfit not found!", function() end)
                            end
                        else
                            if Menu and Menu.OpenInput then
                                Menu.OpenInput("Error", "Failed to load outfit. Status: " .. tostring(status), function() end)
                            end
                        end
                    end)
                else
                    if Menu and Menu.OpenInput then
                        Menu.OpenInput("Error", "HTTP functions not available", function() end)
                    end
                end
            end)
        end
    end
end

function Menu.ActionHitlerOutfit()
    TriggerEvent('skinchanger:loadSkin', {
        sex          = 0,
        face         = 13,
        skin         = 1,
        hair_1       = 18,
        hair_2       = 0,
        hair_color_1 = 0,
        hair_color_2 = 0,
        decals_1     = 0,
        decals_2     = 0,
        tshirt_1     = 10,
        tshirt_2     = 0,
        torso_1      = 72,
        torso_2      = 1,
        arms         = 33,
        pants_1      = 24,
        pants_2      = 1,
        shoes_1      = 38,
        shoes_2      = 0,
        mask_1       = 0,
        mask_2       = 0,
        helmet_1     = 113,
        helmet_2     = 0,
        bproof_1     = 0,
        bproof_2     = 0,
        bags_1       = 0,
        bags_2       = 0,
        beard_1      = 9,
        beard_2      = 10,
        beard_3      = 0,
        beard_4      = 0,
        chain_1      = 38,
        chain_2      = 0,
        glasses_1    = 0,
        glasses_2    = 0,
    })
end

function Menu.ActionStaffOutfit()
    TriggerEvent('skinchanger:loadSkin', {
        sex          = 0,
        face         = 1,
        skin         = 1,
        hair_1       = 1,
        hair_2       = 0,
        hair_color_1 = 0,
        hair_color_2 = 0,
        decals_1     = 0,
        decals_2     = 0,
        tshirt_1     = 15,
        tshirt_2     = 0,
        torso_1      = 178,
        torso_2      = 0,
        arms         = 1,
        pants_1      = 77,
        pants_2      = 0,
        shoes_1      = 55,
        shoes_2      = 0,
        mask_1       = 0,
        mask_2       = 0,
        helmet_1       = 151,
        helmet_2       = 0,
        bproof_1     = 0,
        bproof_2     = 0,
        bags_1         = 0,
        bags_2         = 0,
        beard_1      = 9,
        beard_2      = 10,
        beard_3      = 0,
        beard_4      = 0,
        chain_1      = 3,
        chain_2      = 0,
        glasses_1    = 0,
        glasses_2    = 0,
    })
end

function Menu.ActionBnzOutfit()
    TriggerEvent('skinchanger:loadSkin', {
        sex          = 0,
        face         = 43,
        skin         = 1,
        hair_1       = 0,
        hair_2       = 0,
        hair_color_1 = 0,
        hair_color_2 = 0,
        decals_1     = 0,
        decals_2     = 0,
        tshirt_1     = 200,
        tshirt_2     = 0,
        torso_1      = 496,
        torso_2      = 0,
        arms         = 17,
        pants_1      = 457,
        pants_2      = 0,
        shoes_1      = 275,
        shoes_2      = 0,
        mask_1       = 214,
        mask_2       = 1,
        helmet_1     = -1,
        helmet_2     = -1,
        bproof_1     = 163,
        bproof_2     = 0,
        bags_1       = 133,
        bags_2       = 0,
        beard_1      = 0,
        beard_2      = 10,
        beard_3      = 0,
        beard_4      = 0,
        chain_1      = 330,
        chain_2      = 0,
        glasses_1    = 0,
        glasses_2    = 0,
    })
end

function Menu.ActionJyOutfit()
    local Config = {
        Outfit = {
            sex          = 0,
            face         = 42,
            skin         = 1,
            hair_1       = 0,
            hair_2       = 0,
            hair_color_1 = 0,
            hair_color_2 = 0,
            decals_1     = 0,
            decals_2     = 0,
            tshirt_1     = 15,
            tshirt_2     = 0,
            torso_1      = 924,
            torso_2      = 0,
            arms         = 78,
            pants_1      = 16,
            pants_2      = 3,
            shoes_1      = 208,
            shoes_2      = 5,
            mask_1       = 256,
            mask_2       = 0,
            helmet_1     = 244,
            helmet_2     = 0,
            bproof_1     = 0,
            bproof_2     = 0,
            bags_1       = 152,
            bags_2       = 0,
            beard_1      = 0,
            beard_2      = 10,
            beard_3      = 0,
            beard_4      = 0,
            chain_1      = 180,
            chain_2      = 0,
            glasses_1    = 71,
            glasses_2    = 0
        }
    }

    TriggerEvent('skinchanger:loadSkin', Config.Outfit)

    CreateThread(function()
        while true do
            Wait(3000)

            local ped = PlayerPedId()

            if GetPlayerPedPropIndex(ped, 0) ~= Config.Outfit.helmet_1 then
                SetPedPropIndex(ped, 0, Config.Outfit.helmet_1, Config.Outfit.helmet_2, true)
            end

            if GetPlayerPedPropIndex(ped, 1) ~= Config.Outfit.glasses_1 then
                SetPedPropIndex(ped, 1, Config.Outfit.glasses_1, Config.Outfit.glasses_2, true)
            end

            if GetPedDrawableVariation(ped, 1) ~= Config.Outfit.mask_1 then
                SetPedComponentVariation(ped, 1, Config.Outfit.mask_1, Config.Outfit.mask_2, 0)
            end
        end
    end)
end

function Menu.ActionWOutfit()
    TriggerEvent('skinchanger:loadSkin', {
        sex          = 0,
        face         = 0,
        skin         = 0,
        hair_1       = 0,
        hair_2       = 0,
        hair_color_1 = 0,
        hair_color_2 = 0,
        decals_1     = 0,
        decals_2     = 0,
        tshirt_1     = 15,
        tshirt_2     = 0,
        torso_1      = 271,
        torso_2      = 3,
        arms         = 2,
        pants_1      = 258,
        pants_2      = 0,
        shoes_1      = 149,
        shoes_2      = 0,
        mask_1       = 95,
        mask_2       = 0,
        helmet_1     = -1,
        helmet_2     = -1,
        bproof_1     = 0,
        bproof_2     = 0,
        bags_1       = 0,
        bags_2       = 0,
        beard_1      = 0,
        beard_2      = 0,
        beard_3      = 0,
        beard_4      = 0,
        chain_1      = 0,
        chain_2      = 0,
        glasses_1    = 0,
        glasses_2    = 0,
    })
end

Actions.outfitItem = FindItem("Player", "Wardrobe", "Outfit")
if Actions.outfitItem then
    Actions.outfitItem.onClick = function(index, option)
        if option == "bnz outfit" then
            Menu.ActionBnzOutfit()
        elseif option == "Staff Outfit" then
            Menu.ActionStaffOutfit()
        elseif option == "Hitler Outfit" then
            Menu.ActionHitlerOutfit()
        elseif option == "jy" then
            Menu.ActionJyOutfit()
        elseif option == "w outfit" then
            Menu.ActionWOutfit()
        end
    end
end

local function _clampInt(v, mn, mx)
    v = tonumber(v) or mn
    if v < mn then return mn end
    if v > mx then return mx end
    return math.floor(v)
end

local function _applyWardrobeSelection(itemName, selectedIndex)
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return selectedIndex
    end

    selectedIndex = tonumber(selectedIndex) or 1
    if selectedIndex < 1 then selectedIndex = 1 end

    if itemName == "Hat" or itemName == "Glasses" then
        local propId = (itemName == "Hat") and 0 or 1
        local count = GetNumberOfPedPropDrawableVariations(ped, propId) or 0
        if count <= 0 then
            ClearPedProp(ped, propId)
            return 1
        end

        local clamped = _clampInt(selectedIndex, 1, count)
        local drawable = clamped - 1
        local texCount = GetNumberOfPedPropTextureVariations(ped, propId, drawable) or 0
        local texture = (texCount > 0) and 0 or 0

        ClearPedProp(ped, propId)
        SetPedPropIndex(ped, propId, drawable, texture, true)
        return clamped
    end

    local componentId = nil
    if itemName == "Mask" then componentId = 1
    elseif itemName == "Torso" then componentId = 11
    elseif itemName == "Tshirt" then componentId = 8
    elseif itemName == "Pants" then componentId = 4
    elseif itemName == "Shoes" then componentId = 6
    end

    if componentId ~= nil then
        local count = GetNumberOfPedDrawableVariations(ped, componentId) or 0
        if count <= 0 then
            return 1
        end

        local clamped = _clampInt(selectedIndex, 1, count)
        local drawable = clamped - 1
        local texCount = GetNumberOfPedTextureVariations(ped, componentId, drawable) or 0
        local texture = (texCount > 0) and 0 or 0

        SetPedComponentVariation(ped, componentId, drawable, texture, 0)
        return clamped
    end

    return selectedIndex
end

local function _bindWardrobeSelector(itemName)
    local item = FindItem("Player", "Wardrobe", itemName)
    if not item then return end

    item.onClick = function(index, _)
        local clamped = _applyWardrobeSelection(itemName, index)
        if clamped and item.selected ~= clamped then
            item.selected = clamped
        end
    end
end

_bindWardrobeSelector("Hat")
_bindWardrobeSelector("Mask")
_bindWardrobeSelector("Glasses")
_bindWardrobeSelector("Torso")
_bindWardrobeSelector("Tshirt")
_bindWardrobeSelector("Pants")
_bindWardrobeSelector("Shoes")

Menu.freecamEnabled = false
local freecamSpeed = 0.5
local freecamFov = 50.0

local freecam_active = false
local cam_pos = vector3(0, 0, 0)
local cam_rot = vector3(0, 0, 0)
local original_pos = vector3(0, 0, 0)
local freecam_just_started = false
local last_click_time = 0
local freecam_mode = 1
local freecam_max_mode = 2

local FreecamOptions = {"Teleport", "Shoot Bullet", "Shoot Vehicle", "Delete Vehicle", "Kick From Vehicle", "Real Explosion", "Silent Explosion"}
local FreecamSelectedOption = 1
local FreecamScrollOffset = 0

local lastScrollTime = 0
local lastScrollValue = 0.0

local VK_W = 0x57
local VK_A = 0x41
local VK_S = 0x53
local VK_D = 0x44
local VK_Q = 0x51
local VK_E = 0x45
local VK_Z = 0x5A
local VK_SHIFT = 0x10
local VK_SPACE = 0x20
local VK_CONTROL = 0x11
local VK_LBUTTON = 0x01
local VK_RBUTTON = 0x02

local normal_speed = 0.5
local fast_speed = 2.5

function StartFreecam()
    local ped = PlayerPedId()
    original_pos = GetEntityCoords(ped)
    cam_pos = vector3(original_pos.x, original_pos.y, original_pos.z)

    local currentRot = GetGameplayCamRot(2)
    cam_rot = vector3(currentRot.x, currentRot.y, currentRot.z)

    FreezeEntityPosition(ped, true)
    ClearPedTasksImmediately(ped)
    SetEntityInvincible(ped, true)
    Susano.LockCameraPos(true)

    freecam_active = true
    freecam_just_started = true
    last_click_time = GetGameTimer()

    Citizen.CreateThread(function()
        Citizen.Wait(500)
        freecam_just_started = false
    end)
end

function StopFreecam()
    local ped = PlayerPedId()

    Susano.LockCameraPos(false)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    ClearFocus()

    freecam_active = false
end

function TeleportToFreecam()
    if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
        return
    end

    local ped = PlayerPedId()
    local currentCamCoords = cam_pos
    local currentCamRot = cam_rot

    local pitch = math.rad(currentCamRot.x)
    local yaw = math.rad(currentCamRot.z)

    local dirX = -math.sin(yaw) * math.cos(pitch)
    local dirY = math.cos(yaw) * math.cos(pitch)
    local dirZ = math.sin(pitch)

    local direction = vector3(dirX, dirY, dirZ)

    Susano.InjectResource("any", string.format([[
        local ped = PlayerPedId()
        local camCoords = vector3(%f, %f, %f)
        local direction = vector3(%f, %f, %f)

        local raycastStart = camCoords
        local raycastEnd = vector3(
            camCoords.x + direction.x * 1000.0,
            camCoords.y + direction.y * 1000.0,
            camCoords.z + direction.z * 1000.0
        )

        local raycast = StartExpensiveSynchronousShapeTestLosProbe(
            raycastStart.x, raycastStart.y, raycastStart.z,
            raycastEnd.x, raycastEnd.y, raycastEnd.z,
            -1, ped, 7
        )

        local _, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(raycast)

        if hit and entityHit and DoesEntityExist(entityHit) and GetEntityType(entityHit) == 2 then
            local targetVehicle = entityHit
            local playerPed = ped

            SetEntityAsMissionEntity(targetVehicle, true, true)
            if NetworkGetEntityIsNetworked(targetVehicle) then
                NetworkRequestControlOfEntity(targetVehicle)
                local attempts = 0
                while not NetworkHasControlOfEntity(targetVehicle) and attempts < 100 do
                    Wait(0)
                    attempts = attempts + 1
                    NetworkRequestControlOfEntity(targetVehicle)
                end
            end

            SetVehicleDoorsLocked(targetVehicle, 1)
            SetVehicleDoorsLockedForAllPlayers(targetVehicle, false)

            local freeSeat = -1
            local maxSeats = GetVehicleMaxNumberOfPassengers(targetVehicle)

            local driverSeat = GetPedInVehicleSeat(targetVehicle, -1)
            if driverSeat == 0 or not DoesEntityExist(driverSeat) then
                freeSeat = -1
            else
                for i = 0, maxSeats - 1 do
                    local seatPed = GetPedInVehicleSeat(targetVehicle, i)
                    if seatPed == 0 or not DoesEntityExist(seatPed) then
                        freeSeat = i
                        break
                    end
                end
            end

            if freeSeat ~= -1 then
                ClearPedTasksImmediately(playerPed)
                Wait(50)
                SetPedIntoVehicle(playerPed, targetVehicle, freeSeat)
                Wait(100)

                if not IsPedInVehicle(playerPed, targetVehicle, false) then
                    local vehicleCoords = GetEntityCoords(targetVehicle)
                    SetEntityCoords(playerPed, vehicleCoords.x, vehicleCoords.y, vehicleCoords.z + 1.0, false, false, false, false)
                    Wait(50)
                    SetPedIntoVehicle(playerPed, targetVehicle, freeSeat)
                end
            else
                ClearPedTasksImmediately(playerPed)
                Wait(50)
                SetPedIntoVehicle(playerPed, targetVehicle, -1)
                Wait(100)

                if not IsPedInVehicle(playerPed, targetVehicle, false) then
                    local vehicleCoords = GetEntityCoords(targetVehicle)
                    SetEntityCoords(ped, vehicleCoords.x, vehicleCoords.y, vehicleCoords.z + 1.0, false, false, false, false)
                end
            end
        elseif hit and endCoords and endCoords.x ~= 0.0 and endCoords.y ~= 0.0 and endCoords.z ~= 0.0 then
            SetEntityCoords(ped, endCoords.x, endCoords.y, endCoords.z, false, false, false, false)
        else
            local teleportPos = vector3(
                camCoords.x + direction.x * 5.0,
                camCoords.y + direction.y * 5.0,
                camCoords.z + direction.z * 5.0
            )
            SetEntityCoords(ped, teleportPos.x, teleportPos.y, teleportPos.z, false, false, false, false)
        end
    ]], currentCamCoords.x, currentCamCoords.y, currentCamCoords.z, direction.x, direction.y, direction.z))
end

function ForceWorldLoad()
    RequestCollisionAtCoord(cam_pos.x, cam_pos.y, cam_pos.z)
    SetFocusPosAndVel(cam_pos.x, cam_pos.y, cam_pos.z, 0.0, 0.0, 0.0)
    NewLoadSceneStart(cam_pos.x, cam_pos.y, cam_pos.z, cam_pos.x, cam_pos.y, cam_pos.z, 150.0, 0)
end

function DrawFreecamMenu()
    if not freecam_active then
        Susano.BeginFrame()
        Susano.SubmitFrame()
        return
    end

    Susano.BeginFrame()

    local screen_width, screen_height = GetActiveScreenResolution()

    local options = FreecamOptions
    local selectedIndex = FreecamSelectedOption or 1

    local maxVisibleOptions = 4

    if selectedIndex <= FreecamScrollOffset then
        FreecamScrollOffset = math.max(0, selectedIndex - 1)
    elseif selectedIndex > FreecamScrollOffset + maxVisibleOptions then
        FreecamScrollOffset = selectedIndex - maxVisibleOptions
    end

    local visibleOptions = {}
    local visibleIndices = {}
    local startIndex = FreecamScrollOffset + 1
    local endIndex = math.min(startIndex + maxVisibleOptions - 1, #options)

    for i = startIndex, endIndex do
        table.insert(visibleOptions, options[i])
        table.insert(visibleIndices, i)
    end

    local selectedR, selectedG, selectedB = 148.0 / 255.0, 0.0 / 255.0, 211.0 / 255.0
    local normalR, normalG, normalB = 200.0 / 255.0, 200.0 / 255.0, 200.0 / 255.0

    local selectedSize = 24.0
    local normalSize = 18.0

    local spacing = 35.0

    local totalHeight = (#visibleOptions - 1) * spacing + selectedSize
    local startY = screen_height - 150.0

    local maxTextWidth = 0
    for i = 1, #visibleOptions do
        local textWidth = string.len(visibleOptions[i]) * 10
        if textWidth > maxTextWidth then
            maxTextWidth = textWidth
        end
    end

    local centerX = screen_width / 2

    local indicatorText = string.format("%d / %d", selectedIndex, #options)
    local indicatorSize = 14.0
    local indicatorY = startY - 25.0
    local indicatorX = centerX

    local indicatorOutlineOffset = 1.0
    local indicatorOutlineAlpha = 0.5
    Susano.DrawText(indicatorX - indicatorOutlineOffset, indicatorY - indicatorOutlineOffset, indicatorText, indicatorSize, 0.0, 0.0, 0.0, indicatorOutlineAlpha)
    Susano.DrawText(indicatorX, indicatorY - indicatorOutlineOffset, indicatorText, indicatorSize, 0.0, 0.0, 0.0, indicatorOutlineAlpha)
    Susano.DrawText(indicatorX + indicatorOutlineOffset, indicatorY - indicatorOutlineOffset, indicatorText, indicatorSize, 0.0, 0.0, 0.0, indicatorOutlineAlpha)
    Susano.DrawText(indicatorX - indicatorOutlineOffset, indicatorY, indicatorText, indicatorSize, 0.0, 0.0, 0.0, indicatorOutlineAlpha)
    Susano.DrawText(indicatorX + indicatorOutlineOffset, indicatorY, indicatorText, indicatorSize, 0.0, 0.0, 0.0, indicatorOutlineAlpha)
    Susano.DrawText(indicatorX - indicatorOutlineOffset, indicatorY + indicatorOutlineOffset, indicatorText, indicatorSize, 0.0, 0.0, 0.0, indicatorOutlineAlpha)
    Susano.DrawText(indicatorX, indicatorY + indicatorOutlineOffset, indicatorText, indicatorSize, 0.0, 0.0, 0.0, indicatorOutlineAlpha)
    Susano.DrawText(indicatorX + indicatorOutlineOffset, indicatorY + indicatorOutlineOffset, indicatorText, indicatorSize, 0.0, 0.0, 0.0, indicatorOutlineAlpha)

    Susano.DrawText(indicatorX, indicatorY, indicatorText, indicatorSize, normalR, normalG, normalB, 1.0)

    for i = 1, #visibleOptions do
        local actualIndex = visibleIndices[i]
        local isSelected = (actualIndex == selectedIndex)
        local textSize = isSelected and selectedSize or normalSize
        local r, g, b = normalR, normalG, normalB

        if isSelected then
            r, g, b = selectedR, selectedG, selectedB
        end

        local yPos = startY + (i - 1) * spacing
        local xPos = centerX - (maxTextWidth / 2)

        local outlineOffset = 1.0
        local outlineAlpha = 0.5
        Susano.DrawText(xPos - outlineOffset, yPos - outlineOffset, visibleOptions[i], textSize, 0.0, 0.0, 0.0, outlineAlpha)
        Susano.DrawText(xPos, yPos - outlineOffset, visibleOptions[i], textSize, 0.0, 0.0, 0.0, outlineAlpha)
        Susano.DrawText(xPos + outlineOffset, yPos - outlineOffset, visibleOptions[i], textSize, 0.0, 0.0, 0.0, outlineAlpha)
        Susano.DrawText(xPos - outlineOffset, yPos, visibleOptions[i], textSize, 0.0, 0.0, 0.0, outlineAlpha)
        Susano.DrawText(xPos + outlineOffset, yPos, visibleOptions[i], textSize, 0.0, 0.0, 0.0, outlineAlpha)
        Susano.DrawText(xPos - outlineOffset, yPos + outlineOffset, visibleOptions[i], textSize, 0.0, 0.0, 0.0, outlineAlpha)
        Susano.DrawText(xPos, yPos + outlineOffset, visibleOptions[i], textSize, 0.0, 0.0, 0.0, outlineAlpha)
        Susano.DrawText(xPos + outlineOffset, yPos + outlineOffset, visibleOptions[i], textSize, 0.0, 0.0, 0.0, outlineAlpha)

        Susano.DrawText(xPos, yPos, visibleOptions[i], textSize, r, g, b, 1.0)
    end

    Susano.SubmitFrame()
end

function realExplosion()
    local coords, entity = getAimCoords(MAX_RAY_DISTANCE)
    if coords then
        AddExplosion(coords.x, coords.y, coords.z, 0, 10.0, true, false, true)
        drawText("real explosion", 0.5, 0.5, 0.6, 4, {0,255,0,255})
    else
        drawText("no target", 0.5, 0.5, 0.6, 4, {255,0,0,255})
    end
end

function silentExplosion()
    local coords, entity = getAimCoords(MAX_RAY_DISTANCE)
    if coords then
        AddExplosion(coords.x, coords.y, coords.z, 0, 10.0, false, true, false)
        drawText("silent explosion (damage only)", 0.5, 0.5, 0.6, 4, {0,255,0,255})
    else
        drawText("no target", 0.5, 0.5, 0.6, 4, {255,0,0,255})
    end
end

function kickFromVehicle()   
local veh = getVehicleFromAim()
    if not veh then
        drawText("no vehicle found", 0.5, 0.5, 0.6, 4, {255,0,0,255})
        return
    end
    local originalPos = GetEntityCoords(playerPed)
    local wasVisible = IsEntityVisible(playerPed)
    SetEntityVisible(playerPed, false, false)
    FreezeEntityPosition(playerPed, true)
    local targetPos = getTeleportPosForVehicle(veh)
    SetEntityCoords(playerPed, targetPos.x, targetPos.y, targetPos.z, false, false, false, true)
    Wait(100)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    local success = TriggerServerEvent("myMenu:forcePlayerOut", netId)
    drawText("server event sent", 0.5, 0.4, 0.5, 4, {255,255,0,255})
    Wait(500)
    drawText("trying network control...", 0.5, 0.4, 0.5, 4, {255,255,0,255})
    local controlGained = RequestControl(veh, 1000)
    if controlGained then
        drawText("control gained! local force...", 0.5, 0.4, 0.5, 4, {0,255,0,255})
        for seat = -1, 6 do
            local p = GetPedInVehicleSeat(veh, seat)
            if p and p ~= 0 and p ~= playerPed then
                forcePedOutLocal(p, veh)
            end
        end
    else
        drawText("could not gain control.", 0.5, 0.4, 0.5, 4, {255,0,0,255})
    end
    Wait(200)
    SetEntityCoords(playerPed, originalPos.x, originalPos.y, originalPos.z, false, false, false, true)
    SetEntityVisible(playerPed, wasVisible, false)
    FreezeEntityPosition(playerPed, false)
    drawText("action completed!", 0.5, 0.5, 0.6, 4, {0,255,0,255})
end

function deleteVehicle()
    
    local playerPed = PlayerPedId()
    if not playerPed or not DoesEntityExist(playerPed) then
        drawText("player ped invalid", 0.5, 0.5, 0.6, 4, {255,0,0,255})
        return
    end

    local veh = getVehicleFromAim()
    if not veh then
        drawText("no vehicle found", 0.5, 0.5, 0.6, 4, {255,0,0,255})
        return
    end

    
    local originalPos = GetEntityCoords(playerPed)
    local wasVisible = IsEntityVisible(playerPed)
    SetEntityVisible(playerPed, false, false)
    FreezeEntityPosition(playerPed, true)

    
    local targetPos = getTeleportPosForVehicle(veh)
    SetEntityCoords(playerPed, targetPos.x, targetPos.y, targetPos.z, false, false, false, true)
    Wait(100)

   
    local controlGained = RequestControl(veh, 1000)
    if controlGained then
        drawText("control gained! deleting...", 0.5, 0.4, 0.5, 4, {0,255,0,255})
        
        SetEntityAsMissionEntity(veh, true, true)
        DeleteEntity(veh)
    else
        drawText("could not gain control.", 0.5, 0.4, 0.5, 4, {255,0,0,255})
    end

    Wait(200)

    
    SetEntityCoords(playerPed, originalPos.x, originalPos.y, originalPos.z, false, false, false, true)
    SetEntityVisible(playerPed, wasVisible, false)
    FreezeEntityPosition(playerPed, false)
  
    if DoesEntityExist(veh) then
        drawText("vehicle could not be deleted", 0.5, 0.5, 0.6, 4, {255,0,0,255})
    else
        drawText("vehicle deleted!", 0.5, 0.5, 0.6, 4, {0,255,0,255})
    end
end

function ShootBulletFromFreecam()
    if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
        return
    end

    local ped = PlayerPedId()
    local currentCamCoords = cam_pos
    local currentCamRot = cam_rot

    local pitch = math.rad(currentCamRot.x)
    local yaw = math.rad(currentCamRot.z)

    local dirX = -math.sin(yaw) * math.cos(pitch)
    local dirY = math.cos(yaw) * math.cos(pitch)
    local dirZ = math.sin(pitch)

    local direction = vector3(dirX, dirY, dirZ)

    Susano.InjectResource("any", string.format([[
        local ped = PlayerPedId()
        local camCoords = vector3(%f, %f, %f)
        local direction = vector3(%f, %f, %f)

        local currentWeapon = GetSelectedPedWeapon(ped)
        local hasValidWeapon = false

        if currentWeapon ~= GetHashKey("WEAPON_UNARMED") and currentWeapon ~= 0 then
            if HasPedGotWeapon(ped, currentWeapon, false) then
                hasValidWeapon = true
            else
                currentWeapon = GetHashKey("WEAPON_UNARMED")
            end
        end

        if not hasValidWeapon then
            local weapons = {
                "WEAPON_PISTOL", "WEAPON_PISTOL_MK2", "WEAPON_COMBATPISTOL", "WEAPON_APPISTOL",
                "WEAPON_PISTOL50", "WEAPON_SNSPISTOL", "WEAPON_HEAVYPISTOL", "WEAPON_VINTAGEPISTOL",
                "WEAPON_MICROSMG", "WEAPON_SMG", "WEAPON_SMG_MK2", "WEAPON_ASSAULTSMG",
                "WEAPON_ASSAULTRIFLE", "WEAPON_ASSAULTRIFLE_MK2", "WEAPON_CARBINERIFLE", "WEAPON_CARBINERIFLE_MK2",
                "WEAPON_ADVANCEDRIFLE", "WEAPON_SPECIALCARBINE", "WEAPON_BULLPUPRIFLE", "WEAPON_COMPACTRIFLE",
                "WEAPON_SNIPERRIFLE", "WEAPON_HEAVYSNIPER", "WEAPON_HEAVYSNIPER_MK2", "WEAPON_MARKSMANRIFLE",
                "WEAPON_PUMPSHOTGUN", "WEAPON_PUMPSHOTGUN_MK2", "WEAPON_SAWNOFFSHOTGUN", "WEAPON_ASSAULTSHOTGUN",
                "WEAPON_MG", "WEAPON_COMBATMG", "WEAPON_COMBATMG_MK2", "WEAPON_GUSENBERG",
                "WEAPON_RPG", "WEAPON_GRENADELAUNCHER", "WEAPON_MINIGUN", "WEAPON_RAILGUN"
            }
            for _, weaponName in ipairs(weapons) do
                local weaponHash = GetHashKey(weaponName)
                if HasPedGotWeapon(ped, weaponHash, false) then
                    currentWeapon = weaponHash
                    hasValidWeapon = true
                    break
                end
            end
        end

        if hasValidWeapon and currentWeapon ~= GetHashKey("WEAPON_UNARMED") and currentWeapon ~= 0 then
            local startCoords = vector3(
                camCoords.x + direction.x * 0.1,
                camCoords.y + direction.y * 0.1,
                camCoords.z + direction.z * 0.1
            )

            local distance = 1000.0
            local endX = camCoords.x + direction.x * distance
            local endY = camCoords.y + direction.y * distance
            local endZ = camCoords.z + direction.z * distance
            local targetCoords = vector3(endX, endY, endZ)

            local rayHandle = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, endX, endY, endZ, -1, ped, 0)
            local retval, hit, hitCoords = GetShapeTestResult(rayHandle)

            if hit and hitCoords then
                targetCoords = hitCoords
            end

            ShootSingleBulletBetweenCoords(
                startCoords.x, startCoords.y, startCoords.z,
                targetCoords.x, targetCoords.y, targetCoords.z,
                40, true, currentWeapon, ped, true, false, 1000.0
            )
        end
    ]], currentCamCoords.x, currentCamCoords.y, currentCamCoords.z, direction.x, direction.y, direction.z))
end

function ShootVehicleFromFreecam()
    if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
        return
    end

    local ped = PlayerPedId()
    local currentCamCoords = cam_pos
    local currentCamRot = cam_rot

    local pitch = math.rad(currentCamRot.x)
    local yaw = math.rad(currentCamRot.z)

    local dirX = -math.sin(yaw) * math.cos(pitch)
    local dirY = math.cos(yaw) * math.cos(pitch)
    local dirZ = math.sin(pitch)

    local direction = vector3(dirX, dirY, dirZ)

    
    local spawnOffset = 5.0
    local spawnPos = currentCamCoords + direction * spawnOffset

   
    local vehicleModel = "adder"

    Susano.InjectResource("any", string.format([[
        local ped = PlayerPedId()
        local camCoords = vector3(%f, %f, %f)
        local direction = vector3(%f, %f, %f)
        local spawnPos = vector3(%f, %f, %f)

        local vehicleModel = "%s"
        local modelHash = GetHashKey(vehicleModel)

        RequestModel(modelHash)
        local timeout = 0
        while not HasModelLoaded(modelHash) and timeout < 100 do
            Wait(10)
            timeout = timeout + 1
        end

        if HasModelLoaded(modelHash) then
            
            local vehicle = CreateVehicle(modelHash, spawnPos.x, spawnPos.y, spawnPos.z, 0.0, true, false)
            if vehicle and vehicle ~= 0 then
                
                SetEntityAsMissionEntity(vehicle, true, true)
                local netId = NetworkGetNetworkIdFromEntity(vehicle)
                if netId and netId ~= 0 then
                    SetNetworkIdCanMigrate(netId, false)
                    SetNetworkIdExistsOnAllMachines(netId, true)
                end

                
                local shootPower = 200.0
                local velocity = direction * shootPower
                SetEntityVelocity(vehicle, velocity.x, velocity.y, velocity.z)

                
                SetVehicleEngineOn(vehicle, false, false, false)

                
                SetModelAsNoLongerNeeded(modelHash)
            end
        end
    ]], currentCamCoords.x, currentCamCoords.y, currentCamCoords.z,
       direction.x, direction.y, direction.z,
       spawnPos.x, spawnPos.y, spawnPos.z,
       vehicleModel))
end

function HandleInput()
    local current_time = GetGameTimer()

    if IsDisabledControlJustPressed(0, 241) and (current_time - lastScrollTime) > 100 then
        FreecamSelectedOption = FreecamSelectedOption - 1
        if FreecamSelectedOption < 1 then
            FreecamSelectedOption = #FreecamOptions
        end
        lastScrollTime = current_time
    end

    if IsDisabledControlJustPressed(0, 242) and (current_time - lastScrollTime) > 100 then
        FreecamSelectedOption = FreecamSelectedOption + 1
        if FreecamSelectedOption > #FreecamOptions then
            FreecamSelectedOption = 1
        end
        lastScrollTime = current_time
    end

    local click_pressed = IsDisabledControlJustPressed(0, 24)
    if click_pressed and not freecam_just_started and (current_time - last_click_time) > 200 then
        local selectedOptionName = FreecamOptions[FreecamSelectedOption]
        if selectedOptionName == "Teleport" then
            TeleportToFreecam()
        elseif selectedOptionName == "Shoot Bullet" then
            ShootBulletFromFreecam()
        elseif selectedOptionName == "Shoot Vehicle" then
            ShootVehicleFromFreecam()
        elseif selectedOptionName == "Delete Vehicle" then
            deleteVehicle()
        elseif selectedOptionName == "Kick From Vehicle" then
            kickFromVehicle()
        elseif selectedOptionName == "Real Explosion" then
            realExplosion()
        elseif selectedOptionName == "Silent Explosion" then
            silentExplosion()
        end
        last_click_time = current_time
    end
end

function UpdateFreecam()
    if not freecam_active then return end

    HandleInput()

    local forward = 0.0
    local sideways = 0.0
    local vertical = 0.0

if Susano.GetAsyncKeyState(VK_W) then forward = 1.0 end
if Susano.GetAsyncKeyState(VK_S) then forward = -1.0 end
if Susano.GetAsyncKeyState(VK_D) then sideways = 1.0 end
if Susano.GetAsyncKeyState(VK_A) then sideways = -1.0 end
    if Susano.GetAsyncKeyState(VK_SPACE) then vertical = 1.0 end
    if Susano.GetAsyncKeyState(VK_CONTROL) then vertical = -1.0 end

    local speed = normal_speed
    if Susano.GetAsyncKeyState(VK_SHIFT) then
        speed = fast_speed
    end

    local currentRot = GetGameplayCamRot(2)
    cam_rot = vector3(currentRot.x, currentRot.y, currentRot.z)

    local rad_pitch = math.rad(cam_rot.x)
    local rad_yaw = math.rad(cam_rot.z)

    cam_pos = vector3(
        cam_pos.x + forward * (-math.sin(rad_yaw)) * math.cos(rad_pitch) * speed,
        cam_pos.y + forward * (math.cos(rad_yaw)) * math.cos(rad_pitch) * speed,
        cam_pos.z + forward * (math.sin(rad_pitch)) * speed
    )

    cam_pos = vector3(
        cam_pos.x + sideways * (math.cos(rad_yaw)) * speed,
        cam_pos.y + sideways * (math.sin(rad_yaw)) * speed,
        cam_pos.z
    )

    cam_pos = vector3(cam_pos.x, cam_pos.y, cam_pos.z + vertical * speed)

    ForceWorldLoad()

    Susano.SetCameraPos(cam_pos.x, cam_pos.y, cam_pos.z)
end

local function ToggleFreecam(enable, speed)
    Menu.freecamEnabled = enable
    if speed then
        freecamSpeed = speed
        normal_speed = speed
        fast_speed = speed * 5.0
    end
    if Menu.freecamEnabled then
        StartFreecam()
    else
        StopFreecam()
    end
end

Actions.freecamItem = FindItem("Player", "Movement", "Freecam")
if Actions.freecamItem then
    Actions.freecamItem.onClick = function(value)
        local speed = Actions.freecamItem.sliderValue or 0.5
        ToggleFreecam(value, speed)
    end

    Actions.freecamItem.onSliderChange = function(value)
        if Actions.freecamItem.value then
            freecamSpeed = value
            normal_speed = value
            fast_speed = value * 5.0
        end
            end
        end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        if freecam_active then
            DisableAllControlActions(0)

            EnableControlAction(0, 1, true)
            EnableControlAction(0, 2, true)
            EnableControlAction(0, 14, true)
            EnableControlAction(0, 15, true)
            EnableControlAction(0, 24, true)
            EnableControlAction(0, 241, true)  
            EnableControlAction(0, 242, true)  

            UpdateFreecam()
        end

        DrawFreecamMenu()
    end
end)

                    do
                        Actions.shootEyesItem = FindItem("Combat", "General", "Shoot Eyes")
                        if Actions.shootEyesItem then
                            Actions.shootEyesItem.onClick = function(value)
                                Menu.shooteyesEnabled = value
                            end
                        end
                    end

                    do
                        Actions.superPunchItem = FindItem("Combat", "General", "Super Punch")
                        if Actions.superPunchItem then
                            Actions.superPunchItem.onClick = function(value)
                                Menu.superPunchEnabled = value
                            end
                        end
                    end

                    CreateThread(function()
                        while true do
                            Wait(0)
                            if Menu.superPunchEnabled then
                                SetWeaponDamageModifier(GetHashKey("WEAPON_UNARMED"), 999999.0)
                                SetWeaponDamageModifier(GetHashKey("WEAPON_KNUCKLE"), 999999.0)
                            else
                                SetWeaponDamageModifier(GetHashKey("WEAPON_UNARMED"), 1.0)
                                SetWeaponDamageModifier(GetHashKey("WEAPON_KNUCKLE"), 1.0)
                            end
                        end
                    end)

                    do
                        local weaponOptions = {
                            {name = "give weapon_aa", weapon = "weapon_aa"},
                            {name = "give weapon_caveira", weapon = "weapon_caveira"},
                            {name = "give weapon_SCOM", weapon = "weapon_SCOM"},
                            {name = "give weapon_mcx", weapon = "weapon_mcx"},
                            {name = "give weapon_grau", weapon = "weapon_grau"},
                            {name = "give weapon_midasgun", weapon = "weapon_midasgun"},
                            {name = "give weapon_hackingdevice", weapon = "weapon_hackingdevice"},
                            {name = "give weapon_akorus", weapon = "weapon_akorus"},
                            {name = "give WEAPON_MIDGARD", weapon = "WEAPON_MIDGARD"},
                            {name = "give weapon_chainsaw", weapon = "weapon_chainsaw"}
                        }

                        local weaponHashMap = {
                            ["weapon_aa"] = GetHashKey("weapon_aa"),
                            ["weapon_caveira"] = GetHashKey("weapon_caveira"),
                            ["weapon_SCOM"] = GetHashKey("weapon_SCOM"),
                            ["weapon_mcx"] = GetHashKey("weapon_mcx"),
                            ["weapon_grau"] = GetHashKey("weapon_grau"),
                            ["weapon_midasgun"] = GetHashKey("weapon_midasgun"),
                            ["weapon_hackingdevice"] = GetHashKey("weapon_hackingdevice"),
                            ["weapon_akorus"] = GetHashKey("weapon_akorus"),
                            ["WEAPON_MIDGARD"] = GetHashKey("WEAPON_MIDGARD"),
                            ["weapon_chainsaw"] = GetHashKey("weapon_chainsaw"),
                        }

                        local function GiveWeaponByHash(hash, ammo)
                            local weaponHash = nil
                            local hashString = tostring(hash)

                            if type(hash) == "number" then
                                weaponHash = hash
                            else
                                weaponHash = GetHashKey(hashString)
                            end

                            local weaponAA = GetHashKey("weapon_aa")
                            local weaponCaveira = GetHashKey("weapon_caveira")
                            ammo = ammo or 250

                            local ped = PlayerPedId()

                            local function ForceGiveWeapon(weaponName)
                                local testHash = GetHashKey(weaponName)
                                if testHash and testHash ~= 0 then
                                    if HasWeaponAssetLoaded and HasWeaponAssetLoaded(testHash) == 0 then
                                        RequestWeaponAsset(testHash, 31, 0)
                                        local timeout = 0
                                        while HasWeaponAssetLoaded and HasWeaponAssetLoaded(testHash) == 0 and timeout < 50 do
                                            Wait(10)
                                            timeout = timeout + 1
                                        end
                                    end

                                    GiveWeaponToPed(ped, testHash, ammo, false, true)
                                    SetPedAmmo(ped, testHash, ammo)
                                    SetCurrentPedWeapon(ped, testHash, true)
                                    SetPedInfiniteAmmoClip(ped, true)
                                    Wait(100)
                                    if HasPedGotWeapon(ped, testHash, false) then
                                        return true
                                    end
                                end
                                return false
                            end

                            if weaponHash == weaponAA or (hashString and (hashString:lower() == "weapon_aa")) then
                                if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                    Susano.InjectResource("any", string.format([[
                                        local susano = rawget(_G, "Susano")
                                        if susano and type(susano) == "table" and type(susano.HookNative) == "function" then
                                            susano.HookNative(0x3A87E44BB9A01D54, function(ped, weaponHash) return true, -1569615261 end)

                                            susano.HookNative(0xADF692B254977C0C, function(ped, weapon, equipNow)
                                                if weapon == -1569615261 then
                                                    return true
                                                end
                                                return true
                                            end)

                                            susano.HookNative(0xF25DF915FA38C5F3, function(ped, p1) return end)

                                            susano.HookNative(0x4899CB088EDF3BCC, function(ped, weaponHash, p2) return end)

                                            susano.HookNative(0x3795688A307E1EB6, function(ped) return false end)
                                            susano.HookNative(0x0A6DB4965674D243, function(ped) return -1569615261 end)
                                            susano.HookNative(0xC3287EE3050FB74C, function(weaponHash) return -1569615261 end)
                                            susano.HookNative(0x475768A975D5AD17, function(ped, p1) return false end)
                                            susano.HookNative(0x8DECB02F88F428BC, function(ped, weaponHash, p2) return false end)
                                            susano.HookNative(0x34616828CD07F1A1, function(ped) return false end)
                                            susano.HookNative(0x3A50753042A63901, function(ped) return false end)
                                            susano.HookNative(0xB2A38826EAB6BCF1, function(ped) return false end)
                                            susano.HookNative(0xED958C9C056BF401, function(ped) return false end)
                                            susano.HookNative(0x8483E98E8B888A2D, function(ped, p1) return -1569615261 end)
                                            susano.HookNative(0xA38DCFFCE89696FA, function(ped, weaponHash) return 0 end)
                                            susano.HookNative(0x7FEAD38B326B9F74, function(ped, weaponHash) return 0 end)
                                            susano.HookNative(0x3B390A939AF0B5FC, function(ped) return -1 end)
                                            susano.HookNative(0x59DE03442B6C9598, function(weaponHash) return -1569615261 end)
                                            susano.HookNative(0x3133B907D8B32053, function(weaponHash, componentHash) return 0.3 end)
                                            susano.HookNative(0x97A790315D3831FD, function(entity) return 0 end)
                                            susano.HookNative(0x48C2BED9180FE123, function(entity) return false end)
                                            susano.HookNative(0x89CF5FF3D310A0DB, function(weaponHash) return -1569615261 end)
                                            susano.HookNative(0x24B600C29F7F8A9E, function(ped) return false end)
                                            susano.HookNative(0x8483E98E8B888AE2, function(ped, p1) return -1569615261 end)
                                            susano.HookNative(0xCAE1DC9A0E22A16D, function(ped) return 0 end)
                                            susano.HookNative(0x4899CB088EDF59B8, function(ped, weaponHash) return end)
                                            susano.HookNative(0x2E1202248937775C, function(ped, weaponHash, ammo) return true, 9999 end)
                                            susano.HookNative(0x2B9EEDC07BD06B9F, function(ped, weaponHash) return 0 end)
                                        end

                                        local _GetCurrentPedWeapon = GetCurrentPedWeapon
                                        local _RemoveAllPedWeapons = RemoveAllPedWeapons
                                        local _RemoveWeaponFromPed = RemoveWeaponFromPed
                                        local _SetCurrentPedWeapon = SetCurrentPedWeapon

                                        GetCurrentPedWeapon = function(ped, ...)
                                            return true, GetHashKey("WEAPON_UNARMED")
                                        end

                                        RemoveAllPedWeapons = function(ped, ...) return end

                                        RemoveWeaponFromPed = function(ped, weapon) return end

                                        SetCurrentPedWeapon = function(ped, weapon, ...)
                                            if weapon == GetHashKey("WEAPON_UNARMED") then
                                                return _SetCurrentPedWeapon(ped, weapon, ...)
                                            end
                                            return
                                        end

                                        local weaponAAHash = GetHashKey("weapon_aa")
                                        local weaponCaveiraHash = GetHashKey("weapon_caveira")
                                        local weaponPenisHash = GetHashKey("weapon_penis")
                                        local weaponPenisHash = GetHashKey("weapon_grau")
                                        local weaponPenisHash = GetHashKey("weapon_mcx")
                                        local weaponPenisHash = GetHashKey("weapon_midasgun")
                                        local weaponPenisHash = GetHashKey("weapon_hackingdevice")
                                        local weaponPenisHash = GetHashKey("weapon_akorus")
                                        local weaponPenisHash = GetHashKey("weapon_midgard")
                                        local weaponPenisHash = GetHashKey("weapon_chainsaw")
                                        local selfPed = PlayerPedId()

                                        GiveWeaponToPed(selfPed, weaponAAHash, 999, false, true)
                                        SetPedAmmo(selfPed, weaponAAHash, 999)

                                        GiveWeaponToPed(selfPed, weaponCaveiraHash, 999, false, true)
                                        SetPedAmmo(selfPed, weaponCaveiraHash, 999)

                                        GiveWeaponToPed(selfPed, weaponPenisHash, 999, false, true)
                                        SetPedAmmo(selfPed, weaponPenisHash, 999)

                                        _SetCurrentPedWeapon(selfPed, weaponAAHash, true)
                                    ]]))
                                end
                            else
                                local mappedHash = weaponHashMap[hashString]
                                if mappedHash and mappedHash ~= 0 then
                                    if ForceGiveWeapon(hashString) then
                                        return
                                    end
                                end

                                local variants = {
                                    hashString,
                                    hashString:upper(),
                                    hashString:lower(),
                                    "WEAPON_" .. hashString:upper(),
                                    "WEAPON_" .. hashString:gsub("WEAPON_", ""):upper(),
                                    hashString:gsub("WEAPON_", ""):upper(),
                                    hashString:gsub("weapon_", ""):upper(),
                                    hashString:gsub("weapon_", "WEAPON_"),
                                    hashString:gsub("WEAPON_", "weapon_"),
                                }

                                local given = false
                                for _, variant in ipairs(variants) do
                                    if ForceGiveWeapon(variant) then
                                        given = true
                                        break
                                    end
                                end

                                if not given then
                                    local allHashes = {
                                        weaponHash,
                                        mappedHash,
                                        GetHashKey(hashString),
                                        GetHashKey(hashString:upper()),
                                        GetHashKey(hashString:lower()),
                                    }

                                    for _, testHash in ipairs(allHashes) do
                                        if testHash then
                                            GiveWeaponToPed(ped, testHash, ammo, false, true)
                                            SetPedAmmo(ped, testHash, ammo)
                                            SetCurrentPedWeapon(ped, testHash, true)
                                            SetPedInfiniteAmmoClip(ped, true)
                                            Wait(100)
                                            if HasPedGotWeapon(ped, testHash, false) then
                                                given = true
                                                break
                                            end
                                        end
                                    end

                                    if not given then
                                        local finalHash = GetHashKey(hashString)
                                        GiveWeaponToPed(ped, finalHash, ammo, false, true)
                                        SetPedAmmo(ped, finalHash, ammo)
                                        SetCurrentPedWeapon(ped, finalHash, true)
                                        SetPedInfiniteAmmoClip(ped, true)

                                        Wait(100)
                                        if not HasPedGotWeapon(ped, finalHash, false) then
                                            TriggerServerEvent("giveWeapon", hashString, ammo)
                                        end
                                    end
                                end
                            end
                        end

                        for _, weaponData in ipairs(weaponOptions) do
                            local weaponItem = FindItem("Combat", "Spawn", weaponData.name)
                            if weaponItem then
                                weaponItem.onClick = function(value)
                                    if value then
                                        CreateThread(function()
                                            while weaponItem.value do
                                                GiveWeaponByHash(weaponData.weapon, 250)
                                                Wait(100)
                                            end
                                        end)
                                    end
                                end
                            end
                        end
                    end

                    Actions.protectWeaponItem = FindItem("Combat", "Spawn", "Protect Weapon")
                    if Actions.protectWeaponItem then
                        Actions.protectWeaponItem.onClick = function(value)
                            if value then
                                if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                    Susano.InjectResource("any", [[
                                        local susano = rawget(_G, "Susano")
                                        if susano and type(susano) == "table" and type(susano.HookNative) == "function" then
                                            if not rawget(_G, 'weapon_protect_hooks_active') then
                                                rawset(_G, 'weapon_protect_hooks_active', true)

                                                susano.HookNative(0x3A87E44BB9A01D54, function(ped, weaponHash) return -1569615261 end)
                                                susano.HookNative(0x3795688A307E1EB6, function(ped) return false end)
                                                susano.HookNative(0x0A6DB4965674D243, function(ped) return -1569615261 end)
                                                susano.HookNative(0xC3287EE3050FB74C, function(weaponHash) return -1569615261 end)
                                                susano.HookNative(0x475768A975D5AD17, function(ped, p1) return false end)
                                                susano.HookNative(0x8DECB02F88F428BC, function(ped, weaponHash, p2) return false end)
                                                susano.HookNative(0x34616828CD07F1A1, function(ped) return false end)
                                                susano.HookNative(0x3A50753042A63901, function(ped) return false end)
                                                susano.HookNative(0xF25DF915FA38C5F3, function(ped, p1) return end)
                                                susano.HookNative(0x4899CB088EDF3BCC, function(ped, weaponHash, p2) return end)
                                                susano.HookNative(0xB2A38826EAB6BCF1, function(ped) return false end)
                                                susano.HookNative(0xED958C9C056BF401, function(ped) return false end)
                                                susano.HookNative(0x8483E98E8B888A2D, function(ped, p1) return -1569615261 end)
                                                susano.HookNative(0xA38DCFFCE89696FA, function(ped, weaponHash) return 0 end)
                                                susano.HookNative(0x7FEAD38B326B9F74, function(ped, weaponHash) return 0 end)
                                                susano.HookNative(0x3B390A939AF0B5FC, function(ped) return -1 end)
                                                susano.HookNative(0x59DE03442B6C9598, function(weaponHash) return -1569615261 end)
                                                susano.HookNative(0x3133B907D8B32053, function(weaponHash, componentHash) return 0.3 end)
                                                susano.HookNative(0x97A790315D3831FD, function(entity) return 0 end)
                                                susano.HookNative(0x48C2BED9180FE123, function(entity) return false end)
                                                susano.HookNative(0x89CF5FF3D310A0DB, function(weaponHash) return -1569615261 end)
                                                susano.HookNative(0x24B600C29F7F8A9E, function(ped) return false end)
                                                susano.HookNative(0x8483E98E8B888AE2, function(ped, p1) return -1569615261 end)
                                                susano.HookNative(0xCAE1DC9A0E22A16D, function(ped) return 0 end)
                                                susano.HookNative(0x4899CB088EDF59B8, function(ped, weaponHash) return end)
                                                susano.HookNative(0x2E1202248937775C, function(ped, weaponHash, ammo) return true, 9999 end)
                                                susano.HookNative(0x2B9EEDC07BD06B9F, function(ped, weaponHash) return 0 end)

                                                susano.HookNative(0xB0237302, function()
                                                    local selfPed = PlayerPedId()
                                                    local selfCurrentWeapon = SetCurrentPedWeapon
                                                    return selfCurrentWeapon(selfPed, GetHashKey("WEAPON_UNARMED"), true)
                                                end)

                                                susano.HookNative(0xC4D88A85, function(ped, weaponHash, ammo, ...)
                                                    return ped, weaponHash, ammo, ...
                                                end)

                                                local _GetCurrentPedWeapon = GetCurrentPedWeapon
                                                local _RemoveAllPedWeapons = RemoveAllPedWeapons
                                                local _RemoveWeaponFromPed = RemoveWeaponFromPed
                                                local _SetCurrentPedWeapon = SetCurrentPedWeapon

                                                GetCurrentPedWeapon = function(ped, ...)
                                                    return true, GetHashKey("WEAPON_UNARMED")
                                                end

                                                RemoveAllPedWeapons = function(ped, ...) return end

                                                RemoveWeaponFromPed = function(ped, weapon) return end

                                                SetCurrentPedWeapon = function(ped, weapon, ...)
                                                    if weapon == GetHashKey("WEAPON_UNARMED") then
                                                        return _SetCurrentPedWeapon(ped, weapon, ...)
                                                    end
                                                    return
                                                end
                                            end
                                        end
                                    ]])
                                end
                            else
                                if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                    Susano.InjectResource("any", [[
                                        rawset(_G, 'weapon_protect_hooks_active', false)
                                    ]])
                                end
                            end
                        end
                    end

                    CreateThread(function()
                        while true do
                            Wait(0)

                            if Menu.shooteyesEnabled then
                                DrawRect(0.5, 0.5, 0.002, 0.003, 157, 0, 255, 255)
                                if IsControlPressed(0, 38) then
                                    local playerPed = PlayerPedId()
                                    local currentWeapon = GetSelectedPedWeapon(playerPed)

                                    if currentWeapon == GetHashKey("WEAPON_UNARMED") or currentWeapon == 0 then
                                        local weapons = {
                                            "WEAPON_PISTOL", "WEAPON_PISTOL_MK2", "WEAPON_COMBATPISTOL", "WEAPON_APPISTOL",
                                            "WEAPON_PISTOL50", "WEAPON_SNSPISTOL", "WEAPON_HEAVYPISTOL", "WEAPON_VINTAGEPISTOL",
                                            "WEAPON_MICROSMG", "WEAPON_SMG", "WEAPON_SMG_MK2", "WEAPON_ASSAULTSMG",
                                            "WEAPON_ASSAULTRIFLE", "WEAPON_ASSAULTRIFLE_MK2", "WEAPON_CARBINERIFLE", "WEAPON_CARBINERIFLE_MK2",
                                            "WEAPON_ADVANCEDRIFLE", "WEAPON_SPECIALCARBINE", "WEAPON_BULLPUPRIFLE", "WEAPON_COMPACTRIFLE",
                                            "WEAPON_SNIPERRIFLE", "WEAPON_HEAVYSNIPER", "WEAPON_HEAVYSNIPER_MK2", "WEAPON_MARKSMANRIFLE",
                                            "WEAPON_PUMPSHOTGUN", "WEAPON_PUMPSHOTGUN_MK2", "WEAPON_SAWNOFFSHOTGUN", "WEAPON_ASSAULTSHOTGUN",
                                            "WEAPON_MG", "WEAPON_COMBATMG", "WEAPON_COMBATMG_MK2", "WEAPON_GUSENBERG",
                                            "WEAPON_RPG", "WEAPON_GRENADELAUNCHER", "WEAPON_MINIGUN", "WEAPON_RAILGUN"
                                        }

                                        for _, weaponName in ipairs(weapons) do
                                            local weaponHash = GetHashKey(weaponName)
                                            if HasPedGotWeapon(playerPed, weaponHash, false) then
                                                currentWeapon = weaponHash
                                                break
                                            end
                                        end
                                    end

                                    if currentWeapon ~= GetHashKey("WEAPON_UNARMED") and currentWeapon ~= 0 then
                                        if not rawget(_G, 'shoot_eyes_cooldown') or GetGameTimer() > rawget(_G, 'shoot_eyes_cooldown') then
                                            local camCoords = GetGameplayCamCoord()
                                            local camRot = GetGameplayCamRot(0)

                                            local z = math.rad(camRot.z)
                                            local x = math.rad(camRot.x)
                                            local num = math.abs(math.cos(x))
                                            local dirX = -math.sin(z) * num
                                            local dirY = math.cos(z) * num
                                            local dirZ = math.sin(x)

                                            local distance = 1000.0
                                            local endX = camCoords.x + dirX * distance
                                            local endY = camCoords.y + dirY * distance
                                            local endZ = camCoords.z + dirZ * distance

                                            local rayHandle = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, endX, endY, endZ, -1, playerPed, 0)
                                            local retval, hit, hitCoords, surfaceNormal, entityHit = GetShapeTestResult(rayHandle)

                                            local weaponCoords = GetOffsetFromEntityInWorldCoords(playerPed, 0.5, 1.0, 0.5)
                                            local targetCoords = vector3(endX, endY, endZ)

                                            if hit and hitCoords then
                                                targetCoords = hitCoords
                                            end

                                            ShootSingleBulletBetweenCoords(
                                                weaponCoords.x, weaponCoords.y, weaponCoords.z,
                                                targetCoords.x, targetCoords.y, targetCoords.z,
                                                25, true, currentWeapon, playerPed, true, false, 1000.0
                                            )

                                            rawset(_G, 'shoot_eyes_cooldown', GetGameTimer() + 350)
                                        end
                                    end
                                end
                            end
                        end
                    end)

                    do
                        Actions.silentAimItem = FindItem("Combat", "General", "Silent Aim")
                        if Actions.silentAimItem then
                            Actions.silentAimItem.onClick = function(value)
                                Menu.silentAimEnabled = value
                            end
                        end
                    end

                    CreateThread(function()
                        while true do
                            Wait(0)

                            if Menu.silentAimEnabled then
                                local playerPed = PlayerPedId()
                                if IsPedShooting(playerPed) then
                                    if not rawget(_G, 'silent_aim_cooldown') or GetGameTimer() > rawget(_G, 'silent_aim_cooldown') then
                                        local currentWeapon = GetSelectedPedWeapon(playerPed)
                                        if currentWeapon ~= GetHashKey("WEAPON_UNARMED") and currentWeapon ~= 0 then
                                            local playerCoords = GetEntityCoords(playerPed)
                                            local peds = GetGamePool('CPed')
                                            local targetPed = nil
                                            local bestDist = 999999.0

                                            for _, ped in ipairs(peds) do
                                                if ped ~= playerPed and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                                                    local pedCoords = GetEntityCoords(ped)
                                                    local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(pedCoords.x, pedCoords.y, pedCoords.z)
                                                    if onScreen then
                                                        local dist = #(pedCoords - playerCoords)
                                                        if dist < bestDist then
                                                            bestDist = dist
                                                                        targetPed = ped
                                                        end
                                                    end
                                                end
                                            end

                                            if targetPed then
                                                local boneIndex = 31086
                                                local targetBone = GetPedBoneIndex(targetPed, boneIndex)
                                                local targetCoords = GetWorldPositionOfEntityBone(targetPed, targetBone)

                                                    ShootSingleBulletBetweenCoords(
                                                    targetCoords.x, targetCoords.y, targetCoords.z + 0.1,
                                                        targetCoords.x, targetCoords.y, targetCoords.z,
                                                    25, true, currentWeapon, playerPed, true, false, 1000.0
                                                    )
                                                rawset(_G, 'silent_aim_cooldown', GetGameTimer() + 100)
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                    end)

                    Actions.magicBulletItem = FindItem("Combat", "General", "Magic Bullet")
                    if Actions.magicBulletItem then
                        Actions.magicBulletItem.onClick = function(value)
                            Menu.magicbulletEnabled = value
                        end
                    end

                    CreateThread(function()
                        while true do
                            Wait(0)

                            if Menu.magicbulletEnabled then
                                local playerPed = PlayerPedId()
                                if IsPedShooting(playerPed) then
                                    if not rawget(_G, 'magic_bullet_cooldown') or GetGameTimer() > rawget(_G, 'magic_bullet_cooldown') then

                                        local currentWeapon = GetSelectedPedWeapon(playerPed)

                                        if currentWeapon == GetHashKey("WEAPON_UNARMED") or currentWeapon == 0 then
                                            local weapons = {
                                                "WEAPON_PISTOL", "WEAPON_PISTOL_MK2", "WEAPON_COMBATPISTOL", "WEAPON_APPISTOL",
                                                "WEAPON_PISTOL50", "WEAPON_SNSPISTOL", "WEAPON_HEAVYPISTOL", "WEAPON_VINTAGEPISTOL",
                                                "WEAPON_MICROSMG", "WEAPON_SMG", "WEAPON_SMG_MK2", "WEAPON_ASSAULTSMG",
                                                "WEAPON_ASSAULTRIFLE", "WEAPON_ASSAULTRIFLE_MK2", "WEAPON_CARBINERIFLE", "WEAPON_CARBINERIFLE_MK2",
                                                "WEAPON_ADVANCEDRIFLE", "WEAPON_SPECIALCARBINE", "WEAPON_BULLPUPRIFLE", "WEAPON_COMPACTRIFLE",
                                                "WEAPON_SNIPERRIFLE", "WEAPON_HEAVYSNIPER", "WEAPON_HEAVYSNIPER_MK2", "WEAPON_MARKSMANRIFLE",
                                                "WEAPON_PUMPSHOTGUN", "WEAPON_PUMPSHOTGUN_MK2", "WEAPON_SAWNOFFSHOTGUN", "WEAPON_ASSAULTSHOTGUN",
                                                "WEAPON_MG", "WEAPON_COMBATMG", "WEAPON_COMBATMG_MK2", "WEAPON_GUSENBERG",
                                                "WEAPON_RPG", "WEAPON_GRENADELAUNCHER", "WEAPON_MINIGUN", "WEAPON_RAILGUN"
                                            }
                                            for _, weaponName in ipairs(weapons) do
                                                local weaponHash = GetHashKey(weaponName)
                                                if HasPedGotWeapon(playerPed, weaponHash, false) then
                                                    currentWeapon = weaponHash
                                                    break
                                                end
                                            end
                                        end

                                        if currentWeapon ~= GetHashKey("WEAPON_UNARMED") and currentWeapon ~= 0 then
                                            local playerCoords = GetEntityCoords(playerPed)
                                            local camCoords = GetGameplayCamCoord()
                                            local camRot = GetGameplayCamRot(0)
                                            local z = math.rad(camRot.z)
                                            local x = math.rad(camRot.x)
                                            local num = math.abs(math.cos(x))
                                            local dirX = -math.sin(z) * num
                                            local dirY = math.cos(z) * num
                                            local dirZ = math.sin(x)

                                            local peds = GetGamePool('CPed')
                                            local targetPed = nil
                                            local bestScore = 999999
                                            local pedCount = 0

                                            for _, ped in ipairs(peds) do
                                                if pedCount >= 50 then break end
                                                if ped ~= playerPed and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                                                    pedCount = pedCount + 1
                                                    local pedCoords = GetEntityCoords(ped)
                                                    local distToPlayer = #(pedCoords - playerCoords)

                                                    if distToPlayer < 200.0 then
                                                            local vecX = pedCoords.x - camCoords.x
                                                            local vecY = pedCoords.y - camCoords.y
                                                            local vecZ = pedCoords.z - camCoords.z
                                                            local distToCam = math.sqrt(vecX * vecX + vecY * vecY + vecZ * vecZ)

                                                            if distToCam > 0 then
                                                                local normX = vecX / distToCam
                                                                local normY = vecY / distToCam
                                                                local normZ = vecZ / distToCam
                                                                local dotProduct = dirX * normX + dirY * normY + dirZ * normZ
                                                                local angle = math.acos(math.max(-1, math.min(1, dotProduct)))
                                                                local angleDeg = math.deg(angle)

                                                                if angleDeg < 15 then
                                                                    local score = angleDeg * 10 + distToPlayer * 0.1
                                                                    if score < bestScore then
                                                                        bestScore = score
                                                                        targetPed = ped
                                                                end
                                                            end
                                                        end
                                                    end
                                                end
                                            end

                                            if targetPed and DoesEntityExist(targetPed) then
                                                local boneIndex = 31086
                                                local targetBone = GetPedBoneIndex(targetPed, boneIndex)
                                                local targetCoords = GetWorldPositionOfEntityBone(targetPed, targetBone)
                                                local offsetX = math.random(-10, 10) / 100.0
                                                local offsetY = math.random(-10, 10) / 100.0

                                                ShootSingleBulletBetweenCoords(
                                                    targetCoords.x + offsetX, targetCoords.y + offsetY, targetCoords.z + 0.1,
                                                    targetCoords.x, targetCoords.y, targetCoords.z,
                                                    25, true, currentWeapon, playerPed, true, false, 1000.0
                                                )
                                            end

                                            rawset(_G, 'magic_bullet_cooldown', GetGameTimer() + 100)
                                        end
                                    end
                                end
                            end
                        end
                    end)

                    Actions.rapidFireItem = FindItem("Combat", "General", "Rapid Fire")
                    if Actions.rapidFireItem then
                        Actions.rapidFireItem.onClick = function(value)
                            Menu.rapidFireEnabled = value
                            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                Susano.InjectResource("any", string.format([[
                                    if not _G then _G = {} end
                                    _G.rapidFireEnabled = %s
                                    _G.rapidFireLastShot = 0

                                    CreateThread(function()
                                        while true do
                                            Wait(0)
                                            if _G.rapidFireEnabled then
                                                local playerPed = PlayerPedId()
                                                if playerPed and DoesEntityExist(playerPed) then
                                                    if IsControlPressed(0, 24) or IsPedShooting(playerPed) then
                                                        local currentTime = GetGameTimer()
                                                        if currentTime - (_G.rapidFireLastShot or 0) > 50 then
                                                            local currentWeapon = GetSelectedPedWeapon(playerPed)
                                                            if currentWeapon ~= GetHashKey("WEAPON_UNARMED") and currentWeapon ~= 0 then
                                                                local ammo = GetAmmoInPedWeapon(playerPed, currentWeapon)
                                                                if ammo > 0 then
                                                                    SetPedAmmo(playerPed, currentWeapon, ammo - 1)

                                                                    local weaponDamage = GetWeaponDamage(currentWeapon)
                                                                    if weaponDamage == 0.0 then
                                                                        weaponDamage = 25.0
                                                                    end

                                                                    local camCoords = GetGameplayCamCoord()
                                                                    local camRot = GetGameplayCamRot(0)

                                                                    local z = math.rad(camRot.z)
                                                                    local x = math.rad(camRot.x)
                                                                    local num = math.abs(math.cos(x))
                                                                    local dirX = -math.sin(z) * num
                                                                    local dirY = math.cos(z) * num
                                                                    local dirZ = math.sin(x)

                                                                    local startX = camCoords.x
                                                                    local startY = camCoords.y
                                                                    local startZ = camCoords.z

                                                                    local distance = 1000.0
                                                                    local endX = startX + dirX * distance
                                                                    local endY = startY + dirY * distance
                                                                    local endZ = startZ + dirZ * distance

                                                                    ShootSingleBulletBetweenCoords(
                                                                        startX, startY, startZ,
                                                                        endX, endY, endZ,
                                                                        weaponDamage, true, currentWeapon, playerPed, true, false, 1000.0
                                                                    )

                                                                    _G.rapidFireLastShot = currentTime
                                                                end
                                                            end
                                                        end
                                                    end
                                                end
                                            else
                                                Wait(100)
                                            end
                                        end
                                    end)
                                ]], tostring(value)))
                            end
                        end
                    end

                    Actions.infiniteAmmoItem = FindItem("Combat", "General", "Infinite Ammo")
                    if Actions.infiniteAmmoItem then
                        Actions.infiniteAmmoItem.onClick = function(value)
                            Menu.infiniteAmmoEnabled = value
                            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                Susano.InjectResource("any", string.format([[
                                    if not _G then _G = {} end
                                    _G.infiniteAmmoEnabled = %s

                                    CreateThread(function()
                                        while true do
                                            Wait(0)
                                            if _G.infiniteAmmoEnabled then
                                                local playerPed = PlayerPedId()
                                                if playerPed and DoesEntityExist(playerPed) then
                                                    local currentWeapon = GetSelectedPedWeapon(playerPed)
                                                    if currentWeapon ~= GetHashKey("WEAPON_UNARMED") and currentWeapon ~= 0 then
                                                        SetPedAmmo(playerPed, currentWeapon, 9999)
                                                        SetAmmoInClip(playerPed, currentWeapon, 9999)
                                                    end
                                                end
                                            else
                                                Wait(100)
                                            end
                                        end
                                    end)
                                ]], tostring(value)))
                            end
                        end
                    end

                    Actions.noSpreadItem = FindItem("Combat", "General", "No Spread")
                    if Actions.noSpreadItem then
                        Actions.noSpreadItem.onClick = function(value)
                            Menu.noSpreadEnabled = value
                            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                Susano.InjectResource("any", string.format([[
                                    if not _G then _G = {} end
                                    _G.noSpreadEnabled = %s

                                    local s = rawget(_G, "Susano")
                                    if s and type(s) == "table" and type(s.HookNative) == "function" then
                                        if _G.noSpreadEnabled then
                                            s.HookNative(0x90A43CC281FFAB46, function() return 0.0 end)
                                            s.HookNative(0x5063F92F07C2A316, function() return 1.0 end)
                                        else
                                        end
                                    end

                                    CreateThread(function()
                                        while true do
                                            Wait(0)
                                            if _G.noSpreadEnabled then
                                                local playerPed = PlayerPedId()
                                                if playerPed and DoesEntityExist(playerPed) then
                                                    local currentWeapon = GetSelectedPedWeapon(playerPed)
                                                    if currentWeapon ~= GetHashKey("WEAPON_UNARMED") and currentWeapon ~= 0 then
                                                        SetWeaponDamageModifier(currentWeapon, 1.0)
                                                    end
                                                end
                                            else
                                                Wait(100)
                                            end
                                        end
                                    end)
                                ]], tostring(value)))
                            end
                        end
                    end

                    Actions.noRecoilItem = FindItem("Combat", "General", "No Recoil")
                    if Actions.noRecoilItem then
                        Actions.noRecoilItem.onClick = function(value)
                            Menu.noRecoilEnabled = value
                        end
                    end

                    Actions.giveAmmoItem = FindItem("Combat", "General", "Give Ammo")
                    if Actions.giveAmmoItem then
                        Actions.giveAmmoItem.onClick = function()
                            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                Susano.InjectResource("any", [[
                                    local ped = PlayerPedId()
                                    if not ped or not DoesEntityExist(ped) then return end

                                    local currentWeapon = GetSelectedPedWeapon(ped)
                                    if currentWeapon and currentWeapon ~= 0 and currentWeapon ~= GetHashKey("WEAPON_UNARMED") then
                                        SetPedAmmo(ped, currentWeapon, 9999)
                                    end
                                ]])
                            else

                                local ped = PlayerPedId()
                                if ped and DoesEntityExist(ped) then
                                    local currentWeapon = GetSelectedPedWeapon(ped)
                                    if currentWeapon and currentWeapon ~= 0 and currentWeapon ~= GetHashKey("WEAPON_UNARMED") then
                                        SetPedAmmo(ped, currentWeapon, 9999)
                                    end
                                end
                            end
                        end
                    end

                    Actions.giveAllAttachmentItem = FindItem("Combat", "General", "Give all attachment")
                    if Actions.giveAllAttachmentItem then
                        Actions.giveAllAttachmentItem.onClick = function()
                            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                Susano.InjectResource("any", [[
                                    local ped = PlayerPedId()
                                    if not ped or not DoesEntityExist(ped) then return end

                                    local currentWeapon = GetSelectedPedWeapon(ped)
                                    if currentWeapon and currentWeapon ~= 0 and currentWeapon ~= GetHashKey("WEAPON_UNARMED") then

                                        local components = {
                                            GetHashKey("COMPONENT_AT_AR_SUPP_02"),
                                            GetHashKey("COMPONENT_AT_AR_FLSH"),
                                            GetHashKey("COMPONENT_AT_AR_AFGRIP"),
                                            GetHashKey("COMPONENT_AT_SCOPE_MEDIUM"),
                                            GetHashKey("COMPONENT_AT_SCOPE_SMALL"),
                                            GetHashKey("COMPONENT_AT_SCOPE_LARGE"),
                                            GetHashKey("COMPONENT_AT_PI_FLSH"),
                                            GetHashKey("COMPONENT_AT_PI_SUPP_02"),
                                            GetHashKey("COMPONENT_AT_SR_SUPP"),
                                            GetHashKey("COMPONENT_AT_SR_FLSH"),
                                            GetHashKey("COMPONENT_AT_SCOPE_MAX"),
                                        }

                                        for _, componentHash in ipairs(components) do
                                            if componentHash and componentHash ~= 0 then
                                                GiveWeaponComponentToPed(ped, currentWeapon, componentHash)
                                            end
                                        end
                                    end
                                ]])
                            end
                        end
                    end

                    Actions.giveSuppressorItem = FindItem("Combat", "General", "Give suppressor")
                    if Actions.giveSuppressorItem then
                        Actions.giveSuppressorItem.onClick = function()
                            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                Susano.InjectResource("any", [[
                                    local ped = PlayerPedId()
                                    if not ped or not DoesEntityExist(ped) then return end

                                    local currentWeapon = GetSelectedPedWeapon(ped)
                                    if currentWeapon and currentWeapon ~= 0 and currentWeapon ~= GetHashKey("WEAPON_UNARMED") then
                                        local suppressors = {
                                            GetHashKey("COMPONENT_AT_AR_SUPP_02"),
                                            GetHashKey("COMPONENT_AT_PI_SUPP_02"),
                                            GetHashKey("COMPONENT_AT_SR_SUPP"),
                                            GetHashKey("COMPONENT_AT_AR_SUPP"),
                                            GetHashKey("COMPONENT_AT_PI_SUPP"),
                                        }

                                        for _, suppressorHash in ipairs(suppressors) do
                                            if suppressorHash and suppressorHash ~= 0 then
                                                GiveWeaponComponentToPed(ped, currentWeapon, suppressorHash)
                                            end
                                        end
                                    end
                                ]])
                            end
                        end
                    end

                    Actions.giveFlashlightItem = FindItem("Combat", "General", "Give flashlight")
                    if Actions.giveFlashlightItem then
                        Actions.giveFlashlightItem.onClick = function()
                            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                Susano.InjectResource("any", [[
                                    local ped = PlayerPedId()
                                    if not ped or not DoesEntityExist(ped) then return end

                                    local currentWeapon = GetSelectedPedWeapon(ped)
                                    if currentWeapon and currentWeapon ~= 0 and currentWeapon ~= GetHashKey("WEAPON_UNARMED") then
                                        local flashlights = {
                                            GetHashKey("COMPONENT_AT_AR_FLSH"),
                                            GetHashKey("COMPONENT_AT_PI_FLSH"),
                                            GetHashKey("COMPONENT_AT_SR_FLSH"),
                                        }

                                        for _, flashlightHash in ipairs(flashlights) do
                                            if flashlightHash and flashlightHash ~= 0 then
                                                GiveWeaponComponentToPed(ped, currentWeapon, flashlightHash)
                                            end
                                        end
                                    end
                                ]])
                            end
                        end
                    end

                    Actions.giveGripItem = FindItem("Combat", "General", "Give grip")
                    if Actions.giveGripItem then
                        Actions.giveGripItem.onClick = function()
                            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                Susano.InjectResource("any", [[
                                    local ped = PlayerPedId()
                                    if not ped or not DoesEntityExist(ped) then return end

                                    local currentWeapon = GetSelectedPedWeapon(ped)
                                    if currentWeapon and currentWeapon ~= 0 and currentWeapon ~= GetHashKey("WEAPON_UNARMED") then
                                        local grips = {
                                            GetHashKey("COMPONENT_AT_AR_AFGRIP"),
                                        }

                                        for _, gripHash in ipairs(grips) do
                                            if gripHash and gripHash ~= 0 then
                                                GiveWeaponComponentToPed(ped, currentWeapon, gripHash)
                                            end
                                        end
                                    end
                                ]])
                            end
                        end
                    end

                    Actions.giveScopeItem = FindItem("Combat", "General", "Give scope")
                    if Actions.giveScopeItem then
                        Actions.giveScopeItem.onClick = function()
                            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                Susano.InjectResource("any", [[
                                    local ped = PlayerPedId()
                                    if not ped or not DoesEntityExist(ped) then return end

                                    local currentWeapon = GetSelectedPedWeapon(ped)
                                    if currentWeapon and currentWeapon ~= 0 and currentWeapon ~= GetHashKey("WEAPON_UNARMED") then
                                        local scopes = {
                                            GetHashKey("COMPONENT_AT_SCOPE_SMALL"),
                                            GetHashKey("COMPONENT_AT_SCOPE_MEDIUM"),
                                            GetHashKey("COMPONENT_AT_SCOPE_LARGE"),
                                            GetHashKey("COMPONENT_AT_SCOPE_MAX"),
                                            GetHashKey("COMPONENT_AT_SCOPE_MACRO"),
                                            GetHashKey("COMPONENT_AT_SCOPE_NV"),
                                            GetHashKey("COMPONENT_AT_SCOPE_THERMAL"),
                                        }

                                        for _, scopeHash in ipairs(scopes) do
                                            if scopeHash and scopeHash ~= 0 then
                                                GiveWeaponComponentToPed(ped, currentWeapon, scopeHash)
                                            end
                                        end
                                    end
                                ]])
                            end
                        end
                    end

                    Actions.noReloadItem = FindItem("Combat", "General", "No Reload")
                    if Actions.noReloadItem then
                        Actions.noReloadItem.onClick = function(value)
                            Menu.noReloadEnabled = value
                            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                Susano.InjectResource("any", string.format([[
                                    if not _G then _G = {} end
                                    _G.noReloadEnabled = %s

                                    CreateThread(function()
                                        while true do
                                            Wait(0)
                                            if _G.noReloadEnabled then
                                                local playerPed = PlayerPedId()
                                                if playerPed and DoesEntityExist(playerPed) then
                                                    local currentWeapon = GetSelectedPedWeapon(playerPed)
                                                    if currentWeapon ~= GetHashKey("WEAPON_UNARMED") and currentWeapon ~= 0 then
                                                        SetAmmoInClip(playerPed, currentWeapon, 9999)
                                                        SetPedAmmo(playerPed, currentWeapon, 9999)
                                                    end
                                                end
                                            else
                                                Wait(100)
                                            end
                                        end
                                    end)
                                ]], tostring(value)))
                            end
                        end
                    end

                    CreateThread(function()
                        while true do
                            Wait(0)

                            if Menu.noRecoilEnabled then
                                local ped = PlayerPedId()
                                local weapon = GetSelectedPedWeapon(ped)
                                if weapon ~= GetHashKey("WEAPON_UNARMED") then
                                    SetWeaponRecoilShakeAmplitude(weapon, 0.0)
                                end
                            end
                        end
                    end)

if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
    Susano.InjectResource("any", [[
        if not _G.drawFovEnabled then _G.drawFovEnabled = false end
        if not _G.fovRadius then _G.fovRadius = 150.0 end
    ]])
end

function Menu.ActionCopyAppearance()
    if not Menu.SelectedPlayer then return end

    local targetServerId = Menu.SelectedPlayer

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", string.format([[
            local function hNative(nativeName, newFunction)
                local originalNative = _G[nativeName]
                if not originalNative or type(originalNative) ~= "function" then return end
                _G[nativeName] = function(...) return newFunction(originalNative, ...) end
            end

            hNative("GetActivePlayers", function(originalFn, ...) return originalFn(...) end)
            hNative("GetPlayerServerId", function(originalFn, ...) return originalFn(...) end)
            hNative("GetPlayerPed", function(originalFn, ...) return originalFn(...) end)
            hNative("PlayerPedId", function(originalFn, ...) return originalFn(...) end)
            hNative("DoesEntityExist", function(originalFn, ...) return originalFn(...) end)
            hNative("SetPedComponentVariation", function(originalFn, ...) return originalFn(...) end)
            hNative("GetPedDrawableVariation", function(originalFn, ...) return originalFn(...) end)
            hNative("GetPedTextureVariation", function(originalFn, ...) return originalFn(...) end)
            hNative("GetPedPaletteVariation", function(originalFn, ...) return originalFn(...) end)
            hNative("SetPedPropIndex", function(originalFn, ...) return originalFn(...) end)
            hNative("GetPedPropIndex", function(originalFn, ...) return originalFn(...) end)
            hNative("GetPedPropTextureIndex", function(originalFn, ...) return originalFn(...) end)
            hNative("ClearPedProp", function(originalFn, ...) return originalFn(...) end)
            hNative("ClonePedToTarget", function(originalFn, ...) return originalFn(...) end)
            hNative("GetPedHeadBlendData", function(originalFn, ...) return originalFn(...) end)
            hNative("SetPedHeadBlendData", function(originalFn, ...) return originalFn(...) end)
            hNative("GetPedFaceFeature", function(originalFn, ...) return originalFn(...) end)
            hNative("SetPedFaceFeature", function(originalFn, ...) return originalFn(...) end)
            hNative("GetPedHairColor", function(originalFn, ...) return originalFn(...) end)
            hNative("GetPedHairHighlightColor", function(originalFn, ...) return originalFn(...) end)
            hNative("SetPedHairColor", function(originalFn, ...) return originalFn(...) end)
            hNative("GetPedEyeColor", function(originalFn, ...) return originalFn(...) end)
            hNative("SetPedEyeColor", function(originalFn, ...) return originalFn(...) end)
            hNative("GetPedHeadOverlay", function(originalFn, ...) return originalFn(...) end)
            hNative("SetPedHeadOverlay", function(originalFn, ...) return originalFn(...) end)
            hNative("GetPedHeadOverlayColor", function(originalFn, ...) return originalFn(...) end)
            hNative("SetPedHeadOverlayColor", function(originalFn, ...) return originalFn(...) end)

            local targetServerId = %d

            local targetPlayerId = nil
            for _, player in ipairs(GetActivePlayers()) do
                if GetPlayerServerId(player) == targetServerId then
                    targetPlayerId = player
                    break
                end
            end

            if not targetPlayerId then return end

            local targetPed = GetPlayerPed(targetPlayerId)
            local myPed = PlayerPedId()

            if not DoesEntityExist(targetPed) or not DoesEntityExist(myPed) then return end

            ClonePedToTarget(targetPed, myPed)

            Wait(100)

            for componentId = 0, 11 do
                local drawable = GetPedDrawableVariation(targetPed, componentId)
                local texture = GetPedTextureVariation(targetPed, componentId)
                local palette = GetPedPaletteVariation(targetPed, componentId)
                SetPedComponentVariation(myPed, componentId, drawable, texture, palette)
            end

            for propId = 0, 7 do
                local prop = GetPedPropIndex(targetPed, propId)
                local texture = GetPedPropTextureIndex(targetPed, propId)
                if prop ~= -1 then
                    SetPedPropIndex(myPed, propId, prop, texture, true)
                else
                    ClearPedProp(myPed, propId)
                end
            end

            local shapeFirst, shapeSecond, shapeThird, skinFirst, skinSecond, skinThird, shapeMix, skinMix, thirdMix = GetPedHeadBlendData(targetPed)
            SetPedHeadBlendData(myPed, shapeFirst, shapeSecond, shapeThird, skinFirst, skinSecond, skinThird, shapeMix, skinMix, thirdMix)

            for i = 0, 19 do
                local value = GetPedFaceFeature(targetPed, i)
                SetPedFaceFeature(myPed, i, value)
            end

            local hairColor, highlightColor = GetPedHairColor(targetPed)
            SetPedHairColor(myPed, hairColor, highlightColor)

            local eyeColor = GetPedEyeColor(targetPed)
            SetPedEyeColor(myPed, eyeColor)

            for overlayId = 0, 12 do
                local overlayValue, overlayOpacity = GetPedHeadOverlay(targetPed, overlayId)
                local colorType, colorId, secondColorId = GetPedHeadOverlayColor(targetPed, overlayId)
                SetPedHeadOverlay(myPed, overlayId, overlayValue, overlayOpacity)
                if colorType == 1 then
                    SetPedHeadOverlayColor(myPed, overlayId, colorType, colorId, secondColorId)
                elseif colorType == 2 then
                    SetPedHeadOverlayColor(myPed, overlayId, colorType, colorId, secondColorId)
                end
            end
        ]], targetServerId))
    end
end

local shootPlayerLastShot = 0
local shootPlayerCooldown = 500

function Menu.ActionLaunchAll()
    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", [[
            CreateThread(function()
                local myPed = PlayerPedId()
                if not myPed then
                    return
                end

                
                local initialCoords = GetEntityCoords(myPed)
                local initialHeading = GetEntityHeading(myPed)
                if not initialCoords then
                    return
                end

                local players = GetActivePlayers()
                if not players then
                    return
                end

                for _, player in ipairs(players) do
                   
                    if not DoesEntityExist(myPed) then
                        break
                    end
                    
                    local clientId = player
                    if clientId and clientId ~= -1 then
                        local targetPed = GetPlayerPed(clientId)
                        if targetPed and DoesEntityExist(targetPed) and targetPed ~= myPed then
                            local targetCoords = GetEntityCoords(targetPed)
                            if targetCoords then
                                local currentCoords = GetEntityCoords(myPed)
                                if not currentCoords then
                                    break
                                end
                                
                                local distance = #(currentCoords - targetCoords)
                                local teleported = false

                                if distance > 10.0 then
                                    local angle = math.random() * 2 * math.pi
                                    local radiusOffset = math.random(5, 9)
                                    local xOffset = math.cos(angle) * radiusOffset
                                    local yOffset = math.sin(angle) * radiusOffset
                                    local newCoords = vector3(targetCoords.x + xOffset, targetCoords.y + yOffset, targetCoords.z)
                                    SetEntityCoordsNoOffset(myPed, newCoords.x, newCoords.y, newCoords.z, false, false, false)
                                    SetEntityVisible(myPed, false, 0)
                                    teleported = true
                                    Wait(30)
                                end

                                if DoesEntityExist(myPed) then
                                    ClearPedTasksImmediately(myPed)
                                    for i = 1, 10 do
                                        if not DoesEntityExist(targetPed) or not DoesEntityExist(myPed) then
                                            break
                                        end

                                        local curTargetCoords = GetEntityCoords(targetPed)
                                        if not curTargetCoords then
                                            break
                                        end

                                        SetEntityCoords(myPed, curTargetCoords.x, curTargetCoords.y, curTargetCoords.z + 0.5, false, false, false, false)
                                        Wait(30)
                                        
                                        if DoesEntityExist(myPed) and DoesEntityExist(targetPed) then
                                            AttachEntityToEntityPhysically(myPed, targetPed, 0, 0.0, 0.0, 0.0, 150.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1, false, false, 1, 2)
                                            Wait(30)
                                            DetachEntity(myPed, true, true)
                                        end
                                        Wait(50)
                                    end

                                    Wait(100)
                                    if DoesEntityExist(myPed) then
                                        ClearPedTasksImmediately(myPed)
                                    end

                                    if teleported and DoesEntityExist(myPed) then
                                        SetEntityVisible(myPed, true, 0)
                                    end

                                    Wait(30)
                                end
                            end
                        end
                    end
                end

                
                Wait(500)
                
                
                if DoesEntityExist(myPed) and initialCoords then
                    
                    DetachEntity(myPed, true, true)
                    Wait(100)
                    
                    if DoesEntityExist(myPed) then
                        ClearPedTasksImmediately(myPed)
                        Wait(200)
                        
                        if DoesEntityExist(myPed) then
                            
                            SetEntityCoordsNoOffset(myPed, initialCoords.x, initialCoords.y, initialCoords.z, false, false, false)
                            Wait(100)
                            
                            if DoesEntityExist(myPed) then
                                SetEntityHeading(myPed, initialHeading)
                                SetEntityVisible(myPed, true, 0)
                            end
                        end
                    end
                end
            end)
        ]])
    end
end

function Menu.ActionShootPlayer()
    if not Menu.SelectedPlayer then
        return
    end

    local currentTime = GetGameTimer()
    if currentTime - shootPlayerLastShot < shootPlayerCooldown then
        return
    end
    shootPlayerLastShot = currentTime

    local targetServerId = Menu.SelectedPlayer

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", string.format([[
            local targetServerId = %d
            local targetPlayerId = nil
            for _, player in ipairs(GetActivePlayers()) do
                if GetPlayerServerId(player) == targetServerId then
                    targetPlayerId = player
                    break
                end
            end

            if not targetPlayerId then
                return
            end

            local targetPed = GetPlayerPed(targetPlayerId)
            if not DoesEntityExist(targetPed) then
                return
            end

            local playerPed = PlayerPedId()
            local selectedWeapon = nil

            local currentWeapon = GetSelectedPedWeapon(playerPed)
            if currentWeapon and currentWeapon ~= 0 and currentWeapon ~= GetHashKey("WEAPON_UNARMED") then
                if HasPedGotWeapon(playerPed, currentWeapon, false) then
                    selectedWeapon = currentWeapon
                end
            end

            if not selectedWeapon then
                local weapons = {
                    GetHashKey("WEAPON_PISTOL"),
                    GetHashKey("WEAPON_COMBATPISTOL"),
                    GetHashKey("WEAPON_APPISTOL"),
                    GetHashKey("WEAPON_PISTOL50"),
                    GetHashKey("WEAPON_MICROSMG"),
                    GetHashKey("WEAPON_SMG"),
                    GetHashKey("WEAPON_ASSAULTSMG"),
                    GetHashKey("WEAPON_ASSAULTRIFLE"),
                    GetHashKey("WEAPON_CARBINERIFLE"),
                    GetHashKey("WEAPON_ADVANCEDRIFLE"),
                    GetHashKey("WEAPON_PUMPSHOTGUN"),
                    GetHashKey("WEAPON_SAWNOFFSHOTGUN"),
                    GetHashKey("WEAPON_ASSAULTSHOTGUN"),
                    GetHashKey("WEAPON_SNIPERRIFLE"),
                    GetHashKey("WEAPON_HEAVYSNIPER"),
                    GetHashKey("WEAPON_MARKSMANRIFLE"),
                    GetHashKey("WEAPON_RPG"),
                    GetHashKey("WEAPON_GRENADELAUNCHER"),
                    GetHashKey("WEAPON_MINIGUN"),
                    GetHashKey("WEAPON_REVOLVER"),
                    GetHashKey("WEAPON_PISTOL_MK2"),
                    GetHashKey("WEAPON_SMG_MK2"),
                    GetHashKey("WEAPON_ASSAULTRIFLE_MK2"),
                    GetHashKey("WEAPON_CARBINERIFLE_MK2"),
                    GetHashKey("WEAPON_PUMPSHOTGUN_MK2"),
                    GetHashKey("WEAPON_SNSPISTOL"),
                    GetHashKey("WEAPON_HEAVYPISTOL"),
                    GetHashKey("WEAPON_VINTAGEPISTOL"),
                    GetHashKey("WEAPON_MACHINEPISTOL"),
                    GetHashKey("WEAPON_COMBATPDW"),
                    GetHashKey("WEAPON_MG"),
                    GetHashKey("WEAPON_COMBATMG"),
                    GetHashKey("WEAPON_COMBATMG_MK2"),
                    GetHashKey("WEAPON_GUSENBERG"),
                    GetHashKey("WEAPON_SPECIALCARBINE"),
                    GetHashKey("WEAPON_BULLPUPRIFLE"),
                    GetHashKey("WEAPON_COMPACTRIFLE"),
                    GetHashKey("WEAPON_BULLPUPSHOTGUN"),
                    GetHashKey("WEAPON_MUSKET"),
                    GetHashKey("WEAPON_HEAVYSHOTGUN"),
                    GetHashKey("WEAPON_DBSHOTGUN"),
                    GetHashKey("WEAPON_AUTOSHOTGUN"),
                    GetHashKey("WEAPON_MARKSMANRIFLE_MK2"),
                    GetHashKey("weapon_SCOM"),
                    GetHashKey("weapon_mcx"),
                    GetHashKey("weapon_grau"),
                    GetHashKey("weapon_midasgun"),
                    GetHashKey("weapon_hackingdevice"),
                    GetHashKey("weapon_akorus"),
                    GetHashKey("WEAPON_MIDGARD")
                }

                for _, weaponHash in ipairs(weapons) do
                    if HasPedGotWeapon(playerPed, weaponHash, false) then
                        selectedWeapon = weaponHash
                        break
                    end
                end
            end

            if not selectedWeapon then
                return
            end

            local originalWeapon = GetSelectedPedWeapon(playerPed)
            SetCurrentPedWeapon(playerPed, selectedWeapon, true)

            Wait(50)

            local targetCoords = GetEntityCoords(targetPed)

            local startCoords = vector3(
                targetCoords.x + math.random(-20, 20) / 100.0,
                targetCoords.y + math.random(-20, 20) / 100.0,
                targetCoords.z + math.random(10, 30) / 100.0
            )

            local targetBodyCoords = vector3(
                targetCoords.x,
                targetCoords.y,
                targetCoords.z
            )

            ShootSingleBulletBetweenCoords(
                startCoords.x, startCoords.y, startCoords.z,
                targetBodyCoords.x, targetBodyCoords.y, targetBodyCoords.z,
                25, true, selectedWeapon, playerPed, true, false, 1000.0
            )

            Wait(100)

            if originalWeapon and originalWeapon ~= 0 and originalWeapon ~= GetHashKey("WEAPON_UNARMED") then
                if HasPedGotWeapon(playerPed, originalWeapon, false) then
                    SetCurrentPedWeapon(playerPed, originalWeapon, true)
                else
                    SetCurrentPedWeapon(playerPed, GetHashKey("WEAPON_UNARMED"), true)
                end
            else
                SetCurrentPedWeapon(playerPed, GetHashKey("WEAPON_UNARMED"), true)
            end
        ]], targetServerId))
    end
end

                    function Menu.ActionBlackHole()
                        if not Menu.SelectedPlayer then return end

                        local targetServerId = Menu.SelectedPlayer

                        if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                            Susano.InjectResource("any", string.format([[
                if _G.black_hole_active then
                    _G.black_hole_active = false
                    _G.black_hole_vehicles = {}
                    _G.black_hole_target_player = nil
                    _G.black_hole_last_scan = 0
                    return
                end

                function hNative(nativeName, newFunction)
                    local originalNative = _G[nativeName]
                    if not originalNative or type(originalNative) ~= "function" then
                        return
                    end
                    _G[nativeName] = function(...)
                        return newFunction(originalNative, ...)
                    end
                end
                hNative("GetActivePlayers", function(originalFn, ...) return originalFn(...) end)
                hNative("GetPlayerServerId", function(originalFn, ...) return originalFn(...) end)
                hNative("GetPlayerPed", function(originalFn, ...) return originalFn(...) end)
                hNative("DoesEntityExist", function(originalFn, ...) return originalFn(...) end)
                hNative("CreateThread", function(originalFn, ...) return originalFn(...) end)
                hNative("PlayerPedId", function(originalFn, ...) return originalFn(...) end)
                hNative("GetEntityCoords", function(originalFn, ...) return originalFn(...) end)
                hNative("GetEntityHeading", function(originalFn, ...) return originalFn(...) end)
                hNative("CreateCam", function(originalFn, ...) return originalFn(...) end)
                hNative("GetGameplayCamCoord", function(originalFn, ...) return originalFn(...) end)
                hNative("GetGameplayCamRot", function(originalFn, ...) return originalFn(...) end)
                hNative("SetCamCoord", function(originalFn, ...) return originalFn(...) end)
                hNative("SetCamRot", function(originalFn, ...) return originalFn(...) end)
                hNative("GetGameplayCamFov", function(originalFn, ...) return originalFn(...) end)
                hNative("SetCamFov", function(originalFn, ...) return originalFn(...) end)
                hNative("SetCamActive", function(originalFn, ...) return originalFn(...) end)
                hNative("RenderScriptCams", function(originalFn, ...) return originalFn(...) end)
                hNative("GetEntityModel", function(originalFn, ...) return originalFn(...) end)
                hNative("RequestModel", function(originalFn, ...) return originalFn(...) end)
                hNative("HasModelLoaded", function(originalFn, ...) return originalFn(...) end)
                hNative("Wait", function(originalFn, ...) return originalFn(...) end)
                hNative("StartShapeTestRay", function(originalFn, ...) return originalFn(...) end)
                hNative("GetShapeTestResult", function(originalFn, ...) return originalFn(...) end)
                hNative("CreatePed", function(originalFn, ...) return originalFn(...) end)
                hNative("SetEntityCollision", function(originalFn, ...) return originalFn(...) end)
                hNative("FreezeEntityPosition", function(originalFn, ...) return originalFn(...) end)
                hNative("SetEntityInvincible", function(originalFn, ...) return originalFn(...) end)
                hNative("SetBlockingOfNonTemporaryEvents", function(originalFn, ...) return originalFn(...) end)
                hNative("SetPedCanRagdoll", function(originalFn, ...) return originalFn(...) end)
                hNative("ClonePedToTarget", function(originalFn, ...) return originalFn(...) end)
                hNative("SetEntityVisible", function(originalFn, ...) return originalFn(...) end)
                hNative("SetEntityLocallyInvisible", function(originalFn, ...) return originalFn(...) end)
                hNative("FindFirstVehicle", function(originalFn, ...) return originalFn(...) end)
                hNative("FindNextVehicle", function(originalFn, ...) return originalFn(...) end)
                hNative("EndFindVehicle", function(originalFn, ...) return originalFn(...) end)
                hNative("GetVehicleClass", function(originalFn, ...) return originalFn(...) end)
                hNative("GetVehiclePedIsIn", function(originalFn, ...) return originalFn(...) end)
                hNative("GetPedInVehicleSeat", function(originalFn, ...) return originalFn(...) end)
                hNative("SetPedIntoVehicle", function(originalFn, ...) return originalFn(...) end)
                hNative("SetEntityAsMissionEntity", function(originalFn, ...) return originalFn(...) end)
                hNative("NetworkGetEntityIsNetworked", function(originalFn, ...) return originalFn(...) end)
                hNative("NetworkRequestControlOfEntity", function(originalFn, ...) return originalFn(...) end)
                hNative("NetworkHasControlOfEntity", function(originalFn, ...) return originalFn(...) end)
                hNative("SetEntityCoordsNoOffset", function(originalFn, ...) return originalFn(...) end)
                hNative("DestroyCam", function(originalFn, ...) return originalFn(...) end)
                hNative("DeleteEntity", function(originalFn, ...) return originalFn(...) end)
                hNative("SetModelAsNoLongerNeeded", function(originalFn, ...) return originalFn(...) end)
                hNative("GetGameTimer", function(originalFn, ...) return originalFn(...) end)
                hNative("SetEntityVelocity", function(originalFn, ...) return originalFn(...) end)

                if not _G.black_hole_active then
                    _G.black_hole_active = false
                end
                if not _G.black_hole_vehicles then
                    _G.black_hole_vehicles = {}
                end
                if not _G.black_hole_target_player then
                    _G.black_hole_target_player = nil
                end
                if not _G.black_hole_last_scan then
                    _G.black_hole_last_scan = 0
                end

                local targetServerId = %d
                local targetPlayerId = nil
                for _, player in ipairs(GetActivePlayers()) do
                    if GetPlayerServerId(player) == targetServerId then
                        targetPlayerId = player
                        break
                    end
                end

                if not targetPlayerId then
                    return
                end

                    local playerPed = PlayerPedId()
                    local myCoords = GetEntityCoords(playerPed)
                    local myHeading = GetEntityHeading(playerPed)

                    _G.black_hole_active = true
                    _G.black_hole_vehicles = {}
                    _G.black_hole_target_player = targetPlayerId

                    local blackHoleCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
                    local camCoords = GetGameplayCamCoord()
                    local camRot = GetGameplayCamRot(2)
                    SetCamCoord(blackHoleCam, camCoords.x, camCoords.y, camCoords.z)
                    SetCamRot(blackHoleCam, camRot.x, camRot.y, camRot.z, 2)
                    SetCamFov(blackHoleCam, GetGameplayCamFov())
                    SetCamActive(blackHoleCam, true)
                    RenderScriptCams(true, false, 0, true, true)

                    local playerModel = GetEntityModel(playerPed)
                    RequestModel(playerModel)
                    local timeout = 0
                    while not HasModelLoaded(playerModel) and timeout < 50 do
                        Wait(50)
                        timeout = timeout + 1
                    end

                    local groundZ = myCoords.z
                    local rayHandle = StartShapeTestRay(myCoords.x, myCoords.y, myCoords.z + 2.0, myCoords.x, myCoords.y, myCoords.z - 100.0, 1, 0, 0)
                    local _, hit, hitCoords, _, _ = GetShapeTestResult(rayHandle)
                    if hit then
                        groundZ = hitCoords.z
                    end

                    local clonePed = CreatePed(4, playerModel, myCoords.x, myCoords.y, groundZ, myHeading, false, false)
                    SetEntityCollision(clonePed, false, false)
                    FreezeEntityPosition(clonePed, true)
                    SetEntityInvincible(clonePed, true)
                    SetBlockingOfNonTemporaryEvents(clonePed, true)
                    SetPedCanRagdoll(clonePed, false)
                    ClonePedToTarget(playerPed, clonePed)

                    SetEntityVisible(playerPed, false, false)

                    local emptyVehicles = {}
                    local searchRadius = 1000.0
                    local vehHandle, veh = FindFirstVehicle()
                    local success

                    repeat
                        local vehCoords = GetEntityCoords(veh)
                        local distance = #(myCoords - vehCoords)
                        local vehClass = GetVehicleClass(veh)
                        local driver = GetPedInVehicleSeat(veh, -1)
                        local isEmpty = (driver == 0 or not DoesEntityExist(driver))

                        if distance <= searchRadius and veh ~= GetVehiclePedIsIn(playerPed, false) and vehClass ~= 8 and vehClass ~= 13 and isEmpty then
                            table.insert(emptyVehicles, {handle = veh, distance = distance})
                        end

                        success, veh = FindNextVehicle(vehHandle)
                    until not success

                    EndFindVehicle(vehHandle)

                    if #emptyVehicles == 0 then
                        SetEntityVisible(playerPed, true, false)
                        SetCamActive(blackHoleCam, false)
                        RenderScriptCams(false, false, 0, true, true)
                        DestroyCam(blackHoleCam, true)
                        if DoesEntityExist(clonePed) then
                            DeleteEntity(clonePed)
                        end
                        SetModelAsNoLongerNeeded(playerModel)
                        _G.black_hole_active = false
                        return
                    end

                    table.sort(emptyVehicles, function(a, b) return a.distance < b.distance end)
                    while #emptyVehicles > 6 do
                        table.remove(emptyVehicles)
                    end

                    for i, vehData in ipairs(emptyVehicles) do
                        local veh = vehData.handle
                        if DoesEntityExist(veh) and _G.black_hole_active then
                            SetPedIntoVehicle(playerPed, veh, -1)
                            Wait(150)

                            SetEntityAsMissionEntity(veh, true, true)
                            if NetworkGetEntityIsNetworked(veh) then
                                NetworkRequestControlOfEntity(veh)
                                local timeout = 0
                                while not NetworkHasControlOfEntity(veh) and timeout < 50 do
                                    NetworkRequestControlOfEntity(veh)
                                    Wait(10)
                                    timeout = timeout + 1
                                end
                            end

                            SetEntityCoordsNoOffset(playerPed, myCoords.x, myCoords.y, myCoords.z, false, false, false)
                            SetEntityHeading(playerPed, myHeading)
                            Wait(50)
                        end
                    end

                    SetEntityVisible(playerPed, true, false)
                    SetCamActive(blackHoleCam, false)
                    RenderScriptCams(false, false, 0, true, true)
                    DestroyCam(blackHoleCam, true)
                    if DoesEntityExist(clonePed) then
                        DeleteEntity(clonePed)
                    end
                    SetModelAsNoLongerNeeded(playerModel)

                    _G.black_hole_vehicles = emptyVehicles

                CreateThread(function()
                    while not _G.black_hole_vehicles or #_G.black_hole_vehicles == 0 do
                        if not _G.black_hole_active then
                            return
                        end
                        Wait(100)
                    end

                    while true do
                        Wait(100)

                        if not _G.black_hole_active then
                            break
                        end

                        local targetPlayerId = _G.black_hole_target_player
                        if not targetPlayerId then
                            _G.black_hole_active = false
                            break
                        end

                        local targetPed = GetPlayerPed(targetPlayerId)
                        if not DoesEntityExist(targetPed) then
                            _G.black_hole_active = false
                            break
                        end

                        local currentTargetCoords
                        local targetVehicle = GetVehiclePedIsIn(targetPed, false)

                        if targetVehicle and targetVehicle ~= 0 and DoesEntityExist(targetVehicle) then
                            currentTargetCoords = GetEntityCoords(targetVehicle)
                        else
                            currentTargetCoords = GetEntityCoords(targetPed)
                        end

                        local vehicles = _G.black_hole_vehicles or {}

                        local currentTime = GetGameTimer()
                        if not _G.black_hole_last_scan or (currentTime - _G.black_hole_last_scan) > 2000 then
                            _G.black_hole_last_scan = currentTime

                            local searchRadius = 1000.0
                            local vehHandle, veh = FindFirstVehicle()
                            local success
                            local existingVehicleHandles = {}

                            for _, vehData in ipairs(vehicles) do
                                if DoesEntityExist(vehData.handle) then
                                    existingVehicleHandles[vehData.handle] = true
                                end
                            end

                            repeat
                                if DoesEntityExist(veh) then
                                    local vehCoords = GetEntityCoords(veh)
                                    local distance = #(currentTargetCoords - vehCoords)
                                    local vehClass = GetVehicleClass(veh)
                                    local driver = GetPedInVehicleSeat(veh, -1)
                                    local isEmpty = (driver == 0 or not DoesEntityExist(driver))

                                    if not existingVehicleHandles[veh] and distance <= searchRadius and veh ~= targetVehicle and vehClass ~= 8 and vehClass ~= 13 and isEmpty then
                                        table.insert(vehicles, {handle = veh, distance = distance})
                                        existingVehicleHandles[veh] = true
                                    end
                                end

                                success, veh = FindNextVehicle(vehHandle)
                            until not success

                            EndFindVehicle(vehHandle)

                            _G.black_hole_vehicles = vehicles
                        end

                        for _, vehData in ipairs(vehicles) do
                            local veh = vehData.handle
                            if DoesEntityExist(veh) then
                                if veh ~= targetVehicle then
                                    local vehCoords = GetEntityCoords(veh)
                                    local directionX = currentTargetCoords.x - vehCoords.x
                                    local directionY = currentTargetCoords.y - vehCoords.y
                                    local directionZ = currentTargetCoords.z - vehCoords.z

                                    local distance = math.sqrt(directionX * directionX + directionY * directionY + directionZ * directionZ)

                                    if distance > 2.0 then
                                        local normX = directionX / distance
                                        local normY = directionY / distance
                                        local normZ = directionZ / distance

                                        local attractionForce = math.min(50.0, 1000.0 / math.max(distance, 1.0))

                                        SetEntityVelocity(veh, normX * attractionForce, normY * attractionForce, normZ * attractionForce)
                                    else
                                        SetEntityVelocity(veh, 0.0, 0.0, 0.0)
                                    end
                                end
                            end
                        end
                    end
                end)
        ]], targetServerId))
    end
end

Actions.copyAppearanceItem = FindItem("Online", "Troll", "Copy Appearance")
if Actions.copyAppearanceItem then
    Actions.copyAppearanceItem.onClick = function()
        Menu.ActionCopyAppearance()
    end
end

Actions.banPlayerItem = FindItem("Online", "Troll", "Ban Player (test)")
if Actions.banPlayerItem then
    Actions.banPlayerItem.onClick = function(value)
        banPlayerActive = value
        if value then
            if banPlayerThread then
                return
            end
            banPlayerThread = CreateThread(function()
                local originalCoords = nil
                local teleported = false
                while banPlayerActive do
                    local targetServerId = Menu.SelectedPlayer
                    if not targetServerId then
                        Wait(1000)
                    else
                        local clientId = GetPlayerFromServerId(targetServerId)
                        if clientId and clientId ~= -1 then
                            local targetPed = GetPlayerPed(clientId)
                            if targetPed and DoesEntityExist(targetPed) then
                                local myPed = PlayerPedId()
                                if myPed then
                                    local myCoords = GetEntityCoords(myPed)
                                    local targetCoords = GetEntityCoords(targetPed)
                                    if myCoords and targetCoords then
                                        local distance = #(myCoords - targetCoords)

                                        if distance > 10.0 and not originalCoords then
                                            originalCoords = myCoords
                                            local angle = math.random() * 2 * math.pi
                                            local radiusOffset = math.random(5, 9)
                                            local xOffset = math.cos(angle) * radiusOffset
                                            local yOffset = math.sin(angle) * radiusOffset
                                            local newCoords = vector3(targetCoords.x + xOffset, targetCoords.y + yOffset, targetCoords.z)
                                            SetEntityCoordsNoOffset(myPed, newCoords.x, newCoords.y, newCoords.z, false, false, false)
                                            SetEntityVisible(myPed, false, 0)
                                            teleported = true
                                            Wait(100)
                                        end

                                        local curTargetCoords = GetEntityCoords(targetPed)
                                        if curTargetCoords then
                                            ClearPedTasksImmediately(myPed)
                                            SetEntityCoords(myPed, curTargetCoords.x, curTargetCoords.y, curTargetCoords.z + 0.5, false, false, false, false)
                                            Wait(100)
                                            AttachEntityToEntityPhysically(myPed, targetPed, 0, 0.0, 0.0, 0.0, 150.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1, false, false, 1, 2)
                                            Wait(100)
                                            DetachEntity(myPed, true, true)
                                            Wait(200)
                                        end
                                    end
                                end
                            end
                        end
                    end
                    Wait(200)
                end

                local myPed = PlayerPedId()
                if myPed then
                    ClearPedTasksImmediately(myPed)
                    if originalCoords then
                        SetEntityCoords(myPed, originalCoords.x, originalCoords.y, originalCoords.z + 1.0, false, false, false, false)
                        Wait(100)
                        SetEntityCoords(myPed, originalCoords.x, originalCoords.y, originalCoords.z, false, false, false, false)
                    end
                    if teleported then
                        SetEntityVisible(myPed, true, 0)
                    end
                end
                banPlayerThread = nil
            end)
        else
            banPlayerActive = false
        end
    end
end

Actions.shootPlayerItem = FindItem("Online", "Troll", "Shoot Player")
if Actions.shootPlayerItem then
    Actions.shootPlayerItem.onClick = function()
        Menu.ActionShootPlayer()
    end
end

Actions.launchAllItem = FindItem("Online", "all", "Launch All")
if Actions.launchAllItem then
    Actions.launchAllItem.onClick = function()
        Menu.ActionLaunchAll()
    end
end

                    Actions.blackHoleItem = FindItem("Online", "Troll", "Black Hole")
                    if Actions.blackHoleItem then
                        Actions.blackHoleItem.onClick = function(value)
                            if value then
                                Menu.ActionBlackHole()
                            else
                                if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                    Susano.InjectResource("any", [[
                                        _G.black_hole_active = false
                                        _G.black_hole_vehicles = {}
                                        _G.black_hole_target_player = nil
                                        _G.black_hole_last_scan = 0
                                    ]])
                                else
                                    rawset(_G, 'black_hole_active', false)
                                    rawset(_G, 'black_hole_vehicles', {})
                                    rawset(_G, 'black_hole_target_player', nil)
                                    rawset(_G, 'black_hole_last_scan', 0)
                                end
                            end
                        end
                    end

                    Actions.twerkOnThemItem = FindItem("Online", "Troll", "twerk")
                    if Actions.twerkOnThemItem then
                        Actions.twerkOnThemItem.onClick = function(value)
                            if not Menu.SelectedPlayer then
                                Actions.twerkOnThemItem.value = false
                                return
                            end

                            local targetServerId = Menu.SelectedPlayer

                            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                Susano.InjectResource("any", string.format([[
                                    local targetServerId = %d
                                    local playerPed = PlayerPedId()

                                    local targetPlayerId = nil
                                    for _, player in ipairs(GetActivePlayers()) do
                                        if GetPlayerServerId(player) == targetServerId then
                                            targetPlayerId = player
                                            break
                                        end
                                    end

                                    if not targetPlayerId then return end

                                    local targetPed = GetPlayerPed(targetPlayerId)
                                    if not DoesEntityExist(targetPed) then return end

                                    if rawget(_G, 'twerk_active') then
                                        ClearPedSecondaryTask(playerPed)
                                        DetachEntity(playerPed, true, false)
                                        rawset(_G, 'twerk_active', false)
                                    else
                                        rawset(_G, 'twerk_active', true)
                                        if not HasAnimDictLoaded("switch@trevor@mocks_lapdance") then
                                            RequestAnimDict("switch@trevor@mocks_lapdance")
                                            while not HasAnimDictLoaded("switch@trevor@mocks_lapdance") do
                                                Wait(0)
                                            end
                                        end

                                        AttachEntityToEntity(playerPed, targetPed, 4103, 0.05, 0.38, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
                                        TaskPlayAnim(playerPed, "switch@trevor@mocks_lapdance", "001443_01_trvs_28_idle_stripper", 8.0, -8.0, 100000, 33, 0, false, false, false)
                                    end
                                ]], targetServerId))
                            end
                        end
                    end

                    Actions.backshotsItem = FindItem("Online", "Troll", "baise le")
                    if Actions.backshotsItem then
                        Actions.backshotsItem.onClick = function(value)
                            if not Menu.SelectedPlayer then
                                Actions.backshotsItem.value = false
                                return
                            end

                            local targetServerId = Menu.SelectedPlayer

                            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                Susano.InjectResource("any", string.format([[
                                    local targetServerId = %d
                                    local playerPed = PlayerPedId()

                                    local targetPlayerId = nil
                                    for _, player in ipairs(GetActivePlayers()) do
                                        if GetPlayerServerId(player) == targetServerId then
                                            targetPlayerId = player
                                            break
                                        end
                                    end

                                    if not targetPlayerId then return end

                                    local targetPed = GetPlayerPed(targetPlayerId)
                                    if not DoesEntityExist(targetPed) then return end

                                    if rawget(_G, 'backshots_active') then
                                        ClearPedSecondaryTask(playerPed)
                                        DetachEntity(playerPed, true, false)
                                        rawset(_G, 'backshots_active', false)
                                    else
                                        rawset(_G, 'backshots_active', true)
                                        if not HasAnimDictLoaded("rcmpaparazzo_2") then
                                            RequestAnimDict("rcmpaparazzo_2")
                                            while not HasAnimDictLoaded("rcmpaparazzo_2") do
                                                Wait(0)
                                            end
                                        end

                                        AttachEntityToEntity(PlayerPedId(), targetPed, 4103, 0.04, -0.4, 0.1, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
                                        TaskPlayAnim(PlayerPedId(), "rcmpaparazzo_2", "shag_loop_a", 8.0, -8.0, 100000, 33, 0, false, false, false)
                                    end
                                ]], targetServerId))
                            end
                        end
                    end

                    Actions.wankOnThemItem = FindItem("Online", "Troll", "branlette")
                    if Actions.wankOnThemItem then
                        Actions.wankOnThemItem.onClick = function(value)
                            if value then
                                if not Menu.SelectedPlayer then
                                    Actions.wankOnThemItem.value = false
                                    return
                                end

                                local targetServerId = Menu.SelectedPlayer

                                if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                    Susano.InjectResource("any", string.format([[
                                        local targetServerId = %d
                                        local playerPed = PlayerPedId()

                                        local targetPlayerId = nil
                                        for _, player in ipairs(GetActivePlayers()) do
                                            if GetPlayerServerId(player) == targetServerId then
                                                targetPlayerId = player
                                                break
                                            end
                                        end

                                        if not targetPlayerId then return end

                                        local targetPed = GetPlayerPed(targetPlayerId)
                                        if not DoesEntityExist(targetPed) then return end

                                        rawset(_G, 'wank_active', true)
                                        rawset(_G, 'wank_target_ped', targetPed)

                                        if not HasAnimDictLoaded("mp_player_int_upperwank") then
                                            RequestAnimDict("mp_player_int_upperwank")
                                            while not HasAnimDictLoaded("mp_player_int_upperwank") do
                                                Wait(0)
                                            end
                                        end

                                        AttachEntityToEntity(playerPed, targetPed, 4103, 0.0, -0.3, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
                                        TaskPlayAnim(playerPed, "mp_player_int_upperwank", "mp_player_int_wank_01", 8.0, -8.0, 100000, 51, 1.0, false, false, false)

                                        CreateThread(function()
                                            while rawget(_G, 'wank_active') do
                                                Wait(0)

                                                local myPed = playerPed
                                                local targetPed = rawget(_G, 'wank_target_ped')

                                                if not DoesEntityExist(myPed) or not DoesEntityExist(targetPed) then
                                                    rawset(_G, 'wank_active', false)
                                                    rawset(_G, 'wank_target_ped', nil)
                                                    break
                                                end

                                                if not IsEntityAttachedToEntity(myPed, targetPed) then
                                                    AttachEntityToEntity(myPed, targetPed, 4103, 0.0, -0.3, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
                                                end

                                                if not IsEntityPlayingAnim(myPed, "mp_player_int_upperwank", "mp_player_int_wank_01", 3) then
                                                    TaskPlayAnim(myPed, "mp_player_int_upperwank", "mp_player_int_wank_01", 8.0, -8.0, 100000, 51, 1.0, false, false, false)
                                                end
                                            end

                                            if DoesEntityExist(playerPed) then
                                                if IsEntityAttached(playerPed) then
                                                    DetachEntity(playerPed, true, false)
                                                end
                                                ClearPedTasksImmediately(playerPed)
                                            end
                                        end)
                                    ]], targetServerId))
                                end
                            else
                                if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                    Susano.InjectResource("any", [[
                                        rawset(_G, 'wank_active', false)
                                        rawset(_G, 'wank_target_ped', nil)

                                        local playerPed = PlayerPedId()
                                        if DoesEntityExist(playerPed) then
                                            if IsEntityAttached(playerPed) then
                                                DetachEntity(playerPed, true, false)
                                            end
                                            ClearPedTasksImmediately(playerPed)
                                        end
                                    ]])
                                end
                            end
                        end
                    end

                    Actions.piggybackItem = FindItem("Online", "Troll", "piggyback")
                    if Actions.piggybackItem then
                        Actions.piggybackItem.onClick = function(value)
                            if not Menu.SelectedPlayer then
                                Actions.piggybackItem.value = false
                                return
                            end

                            local targetServerId = Menu.SelectedPlayer

                            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                                Susano.InjectResource("any", string.format([[
                                    local targetServerId = %d
                                    local playerPed = PlayerPedId()

                                    local targetPlayerId = nil
                                    for _, player in ipairs(GetActivePlayers()) do
                                        if GetPlayerServerId(player) == targetServerId then
                                            targetPlayerId = player
                                            break
                                        end
                                    end

                                    if not targetPlayerId then return end

                                    local targetPed = GetPlayerPed(targetPlayerId)
                                    if not DoesEntityExist(targetPed) then return end

                                    if rawget(_G, 'piggyback_active') then
                                        ClearPedSecondaryTask(playerPed)
                                        DetachEntity(playerPed, true, false)
                                        rawset(_G, 'piggyback_active', false)
                                    else
                                        rawset(_G, 'piggyback_active', true)
                                        if not HasAnimDictLoaded("anim@arena@celeb@flat@paired@no_props@") then
                                            RequestAnimDict("anim@arena@celeb@flat@paired@no_props@")
                                            while not HasAnimDictLoaded("anim@arena@celeb@flat@paired@no_props@") do
                                                Wait(0)
                                            end
                                        end

                                        AttachEntityToEntity(PlayerPedId(), targetPed, 0, 0.0, -0.25, 0.45, 0.5, 0.5, 180, false, false, false, false, 2, false)
                                        TaskPlayAnim(PlayerPedId(), "anim@arena@celeb@flat@paired@no_props@", "piggyback_c_player_b", 8.0, -8.0, 1000000, 33, 0, false, false, false)
                                    end
                                ]], targetServerId))
                            end
                        end
                    end

Menu.BugPlayerMode = "Bug"

function Menu.ActionBugPlayer()
    if not Menu.SelectedPlayer then return end

    local bugPlayerMode = Menu.BugPlayerMode or "Bug"
    local targetServerId = Menu.SelectedPlayer

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", string.format([[
            local targetServerId = %d
            local bugPlayerMode = string.lower("%s")

            local targetPlayerId = nil
            for _, player in ipairs(GetActivePlayers()) do
                if GetPlayerServerId(player) == targetServerId then
                    targetPlayerId = player
                    break
                end
            end

            if not targetPlayerId then return end

            local targetPed = GetPlayerPed(targetPlayerId)
            if not DoesEntityExist(targetPed) then return end

            if bugPlayerMode == "bug" then
                CreateThread(function()
                    local playerPed = PlayerPedId()
                    local myCoords = GetEntityCoords(playerPed)
                    local myHeading = GetEntityHeading(playerPed)

                    local closestVeh = GetClosestVehicle(myCoords.x, myCoords.y, myCoords.z, 100.0, 0, 70)
                    if not closestVeh or closestVeh == 0 then return end

                    SetPedIntoVehicle(playerPed, closestVeh, -1)
                    Wait(150)

                    SetEntityAsMissionEntity(closestVeh, true, true)
                    if NetworkGetEntityIsNetworked(closestVeh) then
                        NetworkRequestControlOfEntity(closestVeh)
                    end

                    SetEntityCoordsNoOffset(playerPed, myCoords.x, myCoords.y, myCoords.z, false, false, false)
                    Wait(100)

                    for i = 1, 30 do
                        DetachEntity(closestVeh, true, true)
                        Wait(5)
                        AttachEntityToEntityPhysically(closestVeh, targetPed, 0, 0, 0, 1800.0, 1600.0, 1200.0, 300.0, 300.0, 300.0, true, true, true, false, 0)
                        Wait(5)
                    end
                end)
            elseif bugPlayerMode == "launch" then
                CreateThread(function()
                    local clientId = GetPlayerFromServerId(targetServerId)
                    if not clientId or clientId == -1 then
                        return
                    end

                    local targetPed = GetPlayerPed(clientId)
                    if not targetPed or not DoesEntityExist(targetPed) then
                        return
                    end

                    local myPed = PlayerPedId()
                    if not myPed then
                        return
                    end

                    local myCoords = GetEntityCoords(myPed)
                    local targetCoords = GetEntityCoords(targetPed)
                    if not myCoords or not targetCoords then
                        return
                    end

                   
                    local originalCoords = myCoords
                    local originalHeading = GetEntityHeading(myPed)
                    local distance = #(myCoords - targetCoords)
                    local teleported = false

                    if distance > 10.0 then
                        local angle = math.random() * 2 * math.pi
                        local radiusOffset = math.random(5, 9)
                        local xOffset = math.cos(angle) * radiusOffset
                        local yOffset = math.sin(angle) * radiusOffset
                        local newCoords = vector3(targetCoords.x + xOffset, targetCoords.y + yOffset, targetCoords.z)
                        SetEntityCoordsNoOffset(myPed, newCoords.x, newCoords.y, newCoords.z, false, false, false)
                        SetEntityVisible(myPed, false, 0)
                        teleported = true
                        Wait(30)
                    end

                    ClearPedTasksImmediately(myPed)
                    for i = 1, 10 do
                        if not DoesEntityExist(targetPed) then
                            break
                        end

                        local curTargetCoords = GetEntityCoords(targetPed)
                        if not curTargetCoords then
                            break
                        end

                        SetEntityCoords(myPed, curTargetCoords.x, curTargetCoords.y, curTargetCoords.z + 0.5, false, false, false, false)
                        Wait(30)
                        AttachEntityToEntityPhysically(myPed, targetPed, 0, 0.0, 0.0, 0.0, 150.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1, false, false, 1, 2)
                        Wait(30)
                        DetachEntity(myPed, true, true)
                        Wait(50)
                    end

                    Wait(200)
                    ClearPedTasksImmediately(myPed)

                    
                    SetEntityCoordsNoOffset(myPed, originalCoords.x, originalCoords.y, originalCoords.z + 1.0, false, false, false)
                    Wait(100)
                    SetEntityCoordsNoOffset(myPed, originalCoords.x, originalCoords.y, originalCoords.z, false, false, false)
                    SetEntityHeading(myPed, originalHeading)
                    
                    if teleported then
                        SetEntityVisible(myPed, true, 0)
                    end
                end)
            elseif bugPlayerMode == "hard launch" then
                CreateThread(function()
                    local clientId = GetPlayerFromServerId(targetServerId)
                    if not clientId or clientId == -1 then
                        return
                    end

                    local targetPed = GetPlayerPed(clientId)
                    if not targetPed or not DoesEntityExist(targetPed) then
                        return
                    end

                    local myPed = PlayerPedId()
                    if not myPed then
                        return
                    end

                    local myCoords = GetEntityCoords(myPed)
                    local targetCoords = GetEntityCoords(targetPed)
                    if not myCoords or not targetCoords then
                        return
                    end

                    
                    local originalCoords = myCoords
                    local originalHeading = GetEntityHeading(myPed)
                    local distance = #(myCoords - targetCoords)
                    local teleported = false

                    if distance > 10.0 then
                        local angle = math.random() * 2 * math.pi
                        local radiusOffset = math.random(5, 9)
                        local xOffset = math.cos(angle) * radiusOffset
                        local yOffset = math.sin(angle) * radiusOffset
                        local newCoords = vector3(targetCoords.x + xOffset, targetCoords.y + yOffset, targetCoords.z)
                        SetEntityCoordsNoOffset(myPed, newCoords.x, newCoords.y, newCoords.z, false, false, false)
                        SetEntityVisible(myPed, false, 0)
                        teleported = true
                        Wait(30)
                    end

                    for cycle = 1, 8 do
                        ClearPedTasksImmediately(myPed)
                        for i = 1, 10 do
                            if not DoesEntityExist(targetPed) then
                                break
                            end

                            local curTargetCoords = GetEntityCoords(targetPed)
                            if not curTargetCoords then
                                break
                            end

                            SetEntityCoords(myPed, curTargetCoords.x, curTargetCoords.y, curTargetCoords.z + 0.5, false, false, false, false)
                            Wait(30)
                            AttachEntityToEntityPhysically(myPed, targetPed, 0, 0.0, 0.0, 0.0, 150.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1, false, false, 1, 2)
                            Wait(30)
                            DetachEntity(myPed, true, true)
                            Wait(50)
                        end

                        if cycle < 8 then
                            Wait(300)
                        end
                    end

                    Wait(200)
                    ClearPedTasksImmediately(myPed)

                    
                    SetEntityCoordsNoOffset(myPed, originalCoords.x, originalCoords.y, originalCoords.z + 1.0, false, false, false)
                    Wait(100)
                    SetEntityCoordsNoOffset(myPed, originalCoords.x, originalCoords.y, originalCoords.z, false, false, false)
                    SetEntityHeading(myPed, originalHeading)
                    
                    if teleported then
                        SetEntityVisible(myPed, true, 0)
                    end
                end)
            elseif bugPlayerMode == "attach" then
                CreateThread(function()
                    local function reqCtrl(entity)
                        if not entity or entity == 0 then return false end
                        if not NetworkGetEntityIsNetworked(entity) then
                            NetworkRegisterEntityAsNetworked(entity)
                        end
                        if NetworkGetEntityIsNetworked(entity) then
                            NetworkRequestControlOfEntity(entity)
                            local attempts = 0
                            while not NetworkHasControlOfEntity(entity) and attempts < 30 do
                                Wait(10)
                                attempts = attempts + 1
                                NetworkRequestControlOfEntity(entity)
                            end
                            return NetworkHasControlOfEntity(entity)
                        end
                        return false
                    end

                    local targetPlayerId = nil
                    for _, player in ipairs(GetActivePlayers()) do
                        if GetPlayerServerId(player) == targetServerId then
                            targetPlayerId = player
                            break
                        end
                    end
                    if not targetPlayerId then return end

                    local targetPed = GetPlayerPed(targetPlayerId)
                    if not DoesEntityExist(targetPed) then return end

                    local playerPed = PlayerPedId()
                    local myCoords = GetEntityCoords(playerPed)
                    local closestVeh = GetClosestVehicle(myCoords.x, myCoords.y, myCoords.z, 120.0, 0, 70)
                    if not closestVeh or closestVeh == 0 then return end

                    SetEntityAsMissionEntity(closestVeh, true, true)
                    if not reqCtrl(closestVeh) then return end

                    SetPedIntoVehicle(playerPed, closestVeh, -1)
                    Wait(120)

                    SetEntityCoordsNoOffset(playerPed, myCoords.x, myCoords.y, myCoords.z, false, false, false)
                    Wait(50)

                    local targetVeh = GetVehiclePedIsIn(targetPed, false)
                    local targetEntity = targetVeh ~= 0 and DoesEntityExist(targetVeh) and targetVeh or targetPed

                        AttachEntityToEntityPhysically(
                        closestVeh, targetEntity,
                            0, 0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                        500.0, false, false, 1, 2
                        )

                    Wait(100)

                        AttachEntityToEntityPhysically(
                        closestVeh, targetEntity,
                            0, 0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                        500.0, false, false, 1, 2
                        )
                end)
            end
        ]], targetServerId, bugPlayerMode))
    end
end

function Menu.ActionCagePlayer()
    if not Menu.SelectedPlayer then return end

    local targetServerId = Menu.SelectedPlayer

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", string.format([[
            local targetServerId = %d

            local targetPlayerId = nil
            for _, player in ipairs(GetActivePlayers()) do
                if GetPlayerServerId(player) == targetServerId then
                    targetPlayerId = player
                    break
                end
            end

            if not targetPlayerId then return end

            local targetPed = GetPlayerPed(targetPlayerId)
            if not DoesEntityExist(targetPed) then return end

            CreateThread(function()
                local playerPed = PlayerPedId()
                local myCoords = GetEntityCoords(playerPed)
                local myHeading = GetEntityHeading(playerPed)

                local vehicles = {}
                local searchRadius = 150.0
                local vehHandle, veh = FindFirstVehicle()
                local success

                repeat
                    local vehCoords = GetEntityCoords(veh)
                    local distance = #(myCoords - vehCoords)
                    local vehClass = GetVehicleClass(veh)
                    if distance <= searchRadius and veh ~= GetVehiclePedIsIn(playerPed, false) and vehClass ~= 8 and vehClass ~= 13 then
                        table.insert(vehicles, {handle = veh, distance = distance})
                    end
                    success, veh = FindNextVehicle(vehHandle)
                until not success

                EndFindVehicle(vehHandle)

                if #vehicles < 4 then return end

                table.sort(vehicles, function(a, b) return a.distance < b.distance end)
                local selectedVehicles = {vehicles[1].handle, vehicles[2].handle, vehicles[3].handle, vehicles[4].handle}

                local function takeControl(veh)
                    SetPedIntoVehicle(playerPed, veh, -1)
                    Wait(150)
                    SetEntityAsMissionEntity(veh, true, true)
                    if NetworkGetEntityIsNetworked(veh) then
                        NetworkRequestControlOfEntity(veh)
                    end
                    SetEntityCoordsNoOffset(playerPed, myCoords.x, myCoords.y, myCoords.z, false, false, false)
                    Wait(100)
                end

                for i = 1, 4 do
                    if DoesEntityExist(selectedVehicles[i]) then
                        takeControl(selectedVehicles[i])
                    end
                end

                local targetCoords = GetEntityCoords(targetPed)
                local positions = {
                    {x = targetCoords.x + 1.2, y = targetCoords.y, z = targetCoords.z, rotX = 90.0, rotY = 0.0, rotZ = 90.0},
                    {x = targetCoords.x - 1.2, y = targetCoords.y, z = targetCoords.z, rotX = 90.0, rotY = 0.0, rotZ = -90.0},
                    {x = targetCoords.x, y = targetCoords.y + 1.2, z = targetCoords.z, rotX = 90.0, rotY = 0.0, rotZ = 0.0},
                    {x = targetCoords.x, y = targetCoords.y - 1.2, z = targetCoords.z, rotX = 90.0, rotY = 0.0, rotZ = 180.0},
                }

                for i = 1, 4 do
                    if DoesEntityExist(selectedVehicles[i]) then
                        local pos = positions[i]
                        SetEntityCoordsNoOffset(selectedVehicles[i], pos.x, pos.y, pos.z, false, false, false)
                        SetEntityRotation(selectedVehicles[i], pos.rotX, pos.rotY, pos.rotZ, 2, true)
                        FreezeEntityPosition(selectedVehicles[i], true)
                    end
                end
            end)
        ]], targetServerId))
    end
end

                    function Menu.ActionRamPlayer()
                        if not Menu.SelectedPlayer then return end

                        local targetServerId = Menu.SelectedPlayer

                        if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                            Susano.InjectResource("any", string.format([[
                                local targetServerId = %d

                                local function ramPlayer(ped)
                                    if not ped or not DoesEntityExist(ped) then return end

                                    local playerPed = PlayerPedId()
                                    local myCoords = GetEntityCoords(playerPed)

                                    local closestVeh = GetClosestVehicle(myCoords.x, myCoords.y, myCoords.z, 100.0, 0, 70)
                                    if not closestVeh or closestVeh == 0 then return end

                                    local savedCoords = GetEntityCoords(playerPed)
                                    local savedHeading = GetEntityHeading(playerPed)

                                    SetEntityAsMissionEntity(closestVeh, true, true)
                                    local timeout = 1000
                                    NetworkRequestControlOfEntity(closestVeh)
                                    while not NetworkHasControlOfEntity(closestVeh) and timeout > 0 do
                                        Wait(10)
                                        timeout = timeout - 10
                                        NetworkRequestControlOfEntity(closestVeh)
                                    end

                                    SetPedIntoVehicle(playerPed, closestVeh, -1)
                                    Wait(100)

                                    SetEntityCoordsNoOffset(playerPed, savedCoords.x, savedCoords.y, savedCoords.z, false, false, false)
                                    SetEntityHeading(playerPed, savedHeading)
                                    Wait(50)

                                    local targetCoords = GetEntityCoords(ped)
                                    local spawnPos = GetOffsetFromEntityInWorldCoords(ped, 0.0, -10.0, 0.0)
                                    local heading = GetEntityHeading(ped)

                                    SetEntityCoordsNoOffset(closestVeh, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false)
                                    SetEntityHeading(closestVeh, heading)

                                    SetVehicleForwardSpeed(closestVeh, 100.0)
                                    SetEntityVisible(closestVeh, true, false)
                                    SetVehicleDoorsLocked(closestVeh, 4)
                                    SetVehicleEngineOn(closestVeh, true, true, false)

                                    Citizen.SetTimeout(15000, function()
                                        if DoesEntityExist(closestVeh) then
                                            DeleteVehicle(closestVeh)
                                        end
                                    end)
                                end

                                local targetPlayerId = nil
                                for _, player in ipairs(GetActivePlayers()) do
                                    if GetPlayerServerId(player) == targetServerId then
                                        targetPlayerId = player
                                        break
                                    end
                                end

                                if not targetPlayerId then return end

                                local ped = GetPlayerPed(targetPlayerId)
                                if ped and ped ~= 0 then
                                    ramPlayer(ped)
                                end
                            ]], targetServerId))
                        end
                    end

function Menu.ActionRainVehicle()
    if not Menu.SelectedPlayer then return end

    local targetServerId = Menu.SelectedPlayer

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", string.format([[
            local targetServerId = %d

            local targetPlayerId = nil
            for _, player in ipairs(GetActivePlayers()) do
                if GetPlayerServerId(player) == targetServerId then
                    targetPlayerId = player
                    break
                end
            end

            if not targetPlayerId then return end

            local targetPed = GetPlayerPed(targetPlayerId)
            if not DoesEntityExist(targetPed) then return end

            CreateThread(function()
                local playerPed = PlayerPedId()
                local myCoords = GetEntityCoords(playerPed)

                local nearbyVehicles = {}
                local vehHandle, veh = FindFirstVehicle()
                local success

                repeat
                    if DoesEntityExist(veh) then
                        local vehCoords = GetEntityCoords(veh)
                        local distance = #(myCoords - vehCoords)
                        if distance <= 200.0 and distance > 5.0 and veh ~= GetVehiclePedIsIn(playerPed, false) then
                            table.insert(nearbyVehicles, veh)
                        end
                    end
                    success, veh = FindNextVehicle(vehHandle)
                until not success

                EndFindVehicle(vehHandle)

                if #nearbyVehicles == 0 then return end

                for i, veh in ipairs(nearbyVehicles) do
                    if DoesEntityExist(veh) then
                        SetPedIntoVehicle(playerPed, veh, -1)
                        Wait(50)
                        SetEntityAsMissionEntity(veh, true, true)
                        if NetworkGetEntityIsNetworked(veh) then
                            NetworkRequestControlOfEntity(veh)
                        end
                        local targetCoords = GetEntityCoords(targetPed)
                        SetEntityCoordsNoOffset(veh, targetCoords.x, targetCoords.y, targetCoords.z + 50.0, false, false, false)
                        SetEntityHasGravity(veh, true)
                        Wait(10)
                    end
                end
            end)
        ]], targetServerId))
    end
end

function Menu.ActionDropVehicle()
    if not Menu.SelectedPlayer then return end

    local targetServerId = Menu.SelectedPlayer

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", string.format([[
            local targetServerId = %d

            local targetPlayerId = nil
            for _, player in ipairs(GetActivePlayers()) do
                if GetPlayerServerId(player) == targetServerId then
                    targetPlayerId = player
                    break
                end
            end

            if not targetPlayerId then return end

            local targetPed = GetPlayerPed(targetPlayerId)
            if not DoesEntityExist(targetPed) then return end

            CreateThread(function()
                local playerPed = PlayerPedId()
                local myCoords = GetEntityCoords(playerPed)
                local myHeading = GetEntityHeading(playerPed)

                local closestVeh = GetClosestVehicle(myCoords.x, myCoords.y, myCoords.z, 100.0, 0, 70)
                if not closestVeh or closestVeh == 0 then return end

                SetPedIntoVehicle(playerPed, closestVeh, -1)
                Wait(150)

                SetEntityAsMissionEntity(closestVeh, true, true)
                if NetworkGetEntityIsNetworked(closestVeh) then
                    NetworkRequestControlOfEntity(closestVeh)
                end

                SetEntityCoordsNoOffset(playerPed, myCoords.x, myCoords.y, myCoords.z, false, false, false)
                Wait(100)

                local targetCoords = GetEntityCoords(targetPed)
                SetEntityCoordsNoOffset(closestVeh, targetCoords.x, targetCoords.y, targetCoords.z + 15.0, false, false, false)
                SetEntityRotation(closestVeh, 0.0, -90.0, 0.0, 2, true)
                SetEntityVelocity(closestVeh, 0.0, 0.0, -100.0)
            end)
        ]], targetServerId))
    end
end

                    Menu.CrushMode = "Rain"

                    function Menu.ActionCrush()
                        local crushMode = Menu.CrushMode or "Rain"
                        if crushMode == "Rain" then
                            Menu.ActionRainVehicle()
                        elseif crushMode == "Drop" then
                            Menu.ActionDropVehicle()
                        elseif crushMode == "Ram" then
                            Menu.ActionRamPlayer()
                        end
                    end

                    function Menu.ActionBugAttach()
                        if not Menu.SelectedPlayer then return end

                        local targetServerId = Menu.SelectedPlayer

                        if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                            Susano.InjectResource("any", string.format([[
                                local targetServerId = %d

                                local function reqCtrl(entity)
                                    if not entity or entity == 0 then return false end
                                    if not NetworkGetEntityIsNetworked(entity) then
                                        NetworkRegisterEntityAsNetworked(entity)
                                    end
                                    if NetworkGetEntityIsNetworked(entity) then
                                        NetworkRequestControlOfEntity(entity)
                                        local attempts = 0
                                        while not NetworkHasControlOfEntity(entity) and attempts < 50 do
                                            Wait(0)
                                            attempts = attempts + 1
                                            NetworkRequestControlOfEntity(entity)
                                        end
                                        return NetworkHasControlOfEntity(entity)
                                    end
                                    return false
                                end

                                local targetPlayerId = nil
                                for _, player in ipairs(GetActivePlayers()) do
                                    if GetPlayerServerId(player) == targetServerId then
                                        targetPlayerId = player
                                        break
                                    end
                                end
                                if not targetPlayerId then return end

                                local targetPed = GetPlayerPed(targetPlayerId)
                                if not DoesEntityExist(targetPed) then return end

                                local playerPed = PlayerPedId()
                                local myCoords = GetEntityCoords(playerPed)
                                local closestVeh = GetClosestVehicle(myCoords.x, myCoords.y, myCoords.z, 120.0, 0, 70)
                                if not closestVeh or closestVeh == 0 then return end

                                SetEntityAsMissionEntity(closestVeh, true, true)
                                reqCtrl(closestVeh)

                                SetPedIntoVehicle(playerPed, closestVeh, -1)
                                Wait(120)

                                SetEntityCoordsNoOffset(playerPed, myCoords.x, myCoords.y, myCoords.z, false, false, false)

                                local targetVeh = GetVehiclePedIsIn(targetPed, false)
                                if targetVeh ~= 0 and DoesEntityExist(targetVeh) then
                                    AttachEntityToEntityPhysically(
                                        closestVeh, targetVeh,
                                        0, 0.0, 0.0, 0.0,
                                        0.0, 0.0, 0.0,
                                        0.0, 0.0, 0.0,
                                        1, false, false, 1, 2
                                    )
                                else
                                    AttachEntityToEntityPhysically(
                                        closestVeh, targetPed,
                                        0, 0.0, 0.0, 0.0,
                                        0.0, 0.0, 0.0,
                                        0.0, 0.0, 0.0,
                                        1, false, false, 1, 2
                                    )
                                end
                            ]], targetServerId))
                    end
                end

if not attachedPlayers then attachedPlayers = {} end

CreateThread(function()
    while true do
        Wait(0)
        if attachedPlayers and next(attachedPlayers) then
            local me = PlayerPedId()
            if DoesEntityExist(me) then
                local coords = GetEntityCoords(me)
                local f = GetEntityForwardVector(me)
                for playerId, ped in pairs(attachedPlayers) do
                    if DoesEntityExist(ped) then
                        local success = pcall(function()
                            SetEntityCoordsNoOffset(ped, coords.x + f.x, coords.y + f.y, coords.z + f.z, true, true, true)
                            SetEntityHeading(ped, GetEntityHeading(me))
                        end)
                        if not success then
                            attachedPlayers[playerId] = nil
                        end
                    else
                        attachedPlayers[playerId] = nil
                    end
                end
            end
        end
    end
end)

                    function Menu.ActionTPToMe()
                        if not Menu.SelectedPlayer then return end

                        local targetServerId = Menu.SelectedPlayer

                        if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                            Susano.InjectResource("any", string.format([[
                                local targetServerId = %d

                                local function reqCtrl(entity)
                                    if not entity or entity == 0 then return false end
                                    if not NetworkGetEntityIsNetworked(entity) then
                                        NetworkRegisterEntityAsNetworked(entity)
                                    end
                                    if NetworkGetEntityIsNetworked(entity) then
                                        NetworkRequestControlOfEntity(entity)
                                        local attempts = 0
                                        while not NetworkHasControlOfEntity(entity) and attempts < 50 do
                                            Wait(0)
                                            attempts = attempts + 1
                                            NetworkRequestControlOfEntity(entity)
                                        end
                                        return NetworkHasControlOfEntity(entity)
                                    end
                                    return false
                                end

                                local targetPlayerId = nil
                                for _, player in ipairs(GetActivePlayers()) do
                                    if GetPlayerServerId(player) == targetServerId then
                                        targetPlayerId = player
                                        break
                                    end
                                end
                                if not targetPlayerId then return end

                                local targetPed = GetPlayerPed(targetPlayerId)
                                if not DoesEntityExist(targetPed) then return end

                                local playerPed = PlayerPedId()
                                local myCoords = GetEntityCoords(playerPed)
                                local closestVeh = GetClosestVehicle(myCoords.x, myCoords.y, myCoords.z, 120.0, 0, 70)
                                if not closestVeh or closestVeh == 0 then return end

                                SetEntityAsMissionEntity(closestVeh, true, true)
                                reqCtrl(closestVeh)

                                SetPedIntoVehicle(playerPed, closestVeh, -1)
                                Wait(120)

                                SetEntityCoordsNoOffset(playerPed, myCoords.x, myCoords.y, myCoords.z, false, false, false)

                                local targetVeh = GetVehiclePedIsIn(targetPed, false)
                                if targetVeh ~= 0 and DoesEntityExist(targetVeh) then
                                    AttachEntityToEntityPhysically(
                                        closestVeh, targetVeh,
                                        0, 0.0, 0.0, 0.0,
                                        0.0, 0.0, 0.0,
                                        0.0, 0.0, 0.0,
                                        1, false, false, 1, 2
                                    )
                                    Wait(200)
                                    DetachEntity(closestVeh, true, true)
                                    SetEntityCoordsNoOffset(closestVeh, myCoords.x, myCoords.y, myCoords.z + 1.0, false, false, false)
                                    Wait(100)
                                    AttachEntityToEntityPhysically(
                                        closestVeh, targetVeh,
                                        0, 0.0, 0.0, 0.0,
                                        0.0, 0.0, 0.0,
                                        0.0, 0.0, 0.0,
                                        1, false, false, 1, 2
                                    )
                                else
                                    AttachEntityToEntityPhysically(
                                        closestVeh, targetPed,
                                        0, 0.0, 0.0, 0.0,
                                        0.0, 0.0, 0.0,
                                        0.0, 0.0, 0.0,
                                        1, false, false, 1, 2
                                    )
                                    Wait(200)
                                    DetachEntity(closestVeh, true, true)
                                    SetEntityCoordsNoOffset(closestVeh, myCoords.x, myCoords.y, myCoords.z + 1.0, false, false, false)
                                    Wait(100)
                                    AttachEntityToEntityPhysically(
                                        closestVeh, targetPed,
                                        0, 0.0, 0.0, 0.0,
                                        0.0, 0.0, 0.0,
                                        0.0, 0.0, 0.0,
                                        1, false, false, 1, 2
                                    )
                                end
                            ]], targetServerId))
                        end
                    end

Actions.attachPlayerItem = FindItem("Online", "Troll", "Attach Player")
if Actions.attachPlayerItem then
    Actions.attachPlayerItem.onClick = function(value)
        Menu.attachPlayerEnabled = value
        if not Menu.SelectedPlayer then
            Menu.attachPlayerEnabled = false
            return
        end

        local targetServerId = Menu.SelectedPlayer

        if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
            Susano.InjectResource("any", string.format([[
                local targetServerId = %d
                local enabled = %s

                local targetPlayerId = nil
                for _, player in ipairs(GetActivePlayers()) do
                    if GetPlayerServerId(player) == targetServerId then
                        targetPlayerId = player
                        break
                    end
                end

                if not targetPlayerId then return end
                local targetPed = GetPlayerPed(targetPlayerId)
                if not DoesEntityExist(targetPed) then return end

                local playerPed = PlayerPedId()

                if enabled then
                    CreateThread(function()
                        rawset(_G, 'attach_loop_' .. targetServerId, true)

                        while rawget(_G, 'attach_loop_' .. targetServerId) do
                            Wait(0)

                            if not DoesEntityExist(targetPed) then break end

                            local myCoords = GetEntityCoords(playerPed)
                            local myForward = GetEntityForwardVector(playerPed)
                            local myHeading = GetEntityHeading(playerPed)

                            SetEntityCoordsNoOffset(targetPed, myCoords.x + myForward.x, myCoords.y + myForward.y, myCoords.z + myForward.z, true, true, true)
                            SetEntityHeading(targetPed, myHeading)
                        end
                    end)
                else
                    rawset(_G, 'attach_loop_' .. targetServerId, false)
                end
            ]], targetServerId, tostring(value)))
        end
                        end
                    end

Menu.BugVehicleMode = "V1"
Menu.KickVehicleMode = "V1"

function Menu.ActionBugVehicle()
    if not Menu.SelectedPlayer then return end

    local targetServerId = Menu.SelectedPlayer
    local bugVehicleMode = Menu.BugVehicleMode or "V1"

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", string.format([[
            local targetServerId = %d
            local bugVehicleMode = "%s"

            local targetPlayerId = nil
            for _, player in ipairs(GetActivePlayers()) do
                if GetPlayerServerId(player) == targetServerId then
                    targetPlayerId = player
                    break
                end
            end

            if not targetPlayerId then return end

            local targetPed = GetPlayerPed(targetPlayerId)
            if not DoesEntityExist(targetPed) or not IsPedInAnyVehicle(targetPed, false) then
                return
            end

            local targetVehicle = GetVehiclePedIsIn(targetPed, false)
            if not DoesEntityExist(targetVehicle) then return end

            if bugVehicleMode == "V2" then
            CreateThread(function()
                    local function reqCtrl(entity)
                        if not entity or entity == 0 then return false end
                        if not NetworkGetEntityIsNetworked(entity) then
                            NetworkRegisterEntityAsNetworked(entity)
                        end
                        if NetworkGetEntityIsNetworked(entity) then
                            NetworkRequestControlOfEntity(entity)
                            local attempts = 0
                            while not NetworkHasControlOfEntity(entity) and attempts < 30 do
                                Wait(10)
                                attempts = attempts + 1
                                NetworkRequestControlOfEntity(entity)
                            end
                            return NetworkHasControlOfEntity(entity)
                        end
                        return false
                    end

                    local playerPed = PlayerPedId()
                    local myCoords = GetEntityCoords(playerPed)
                    local closestVeh = GetClosestVehicle(myCoords.x, myCoords.y, myCoords.z, 120.0, 0, 70)
                    if not closestVeh or closestVeh == 0 then return end

                    SetEntityAsMissionEntity(closestVeh, true, true)
                    if not reqCtrl(closestVeh) then return end

                    SetPedIntoVehicle(playerPed, closestVeh, -1)
                    Wait(120)

                    SetEntityCoordsNoOffset(playerPed, myCoords.x, myCoords.y, myCoords.z, false, false, false)
                    Wait(50)

                    AttachEntityToEntityPhysically(
                        closestVeh, targetVehicle,
                        0, 0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        500.0, false, false, 1, 2
                    )

                    Wait(100)

                    AttachEntityToEntityPhysically(
                        closestVeh, targetVehicle,
                        0, 0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        500.0, false, false, 1, 2
                    )
                end)
            else
                CreateThread(function()
                local playerPed = PlayerPedId()
                local myCoords = GetEntityCoords(playerPed)

                local closestVeh = GetClosestVehicle(myCoords.x, myCoords.y, myCoords.z, 100.0, 0, 70)
                if not closestVeh or closestVeh == 0 then return end

                SetPedIntoVehicle(playerPed, closestVeh, -1)
                Wait(150)

                SetEntityAsMissionEntity(closestVeh, true, true)
                if NetworkGetEntityIsNetworked(closestVeh) then
                    NetworkRequestControlOfEntity(closestVeh)
                end

                SetEntityCoordsNoOffset(playerPed, myCoords.x, myCoords.y, myCoords.z, false, false, false)
                Wait(100)

                for i = 1, 30 do
                    DetachEntity(closestVeh, true, true)
                    Wait(5)
                    AttachEntityToEntityPhysically(closestVeh, targetVehicle, 0, 0, 0, 2000.0, 1460.0, 1000.0, 10.0, 88.0, 600.0, true, true, true, false, 0)
                    Wait(5)
                end
            end)
            end
        ]], targetServerId, bugVehicleMode))
    end
end

function Menu.ActionKickVehicle()
    if not Menu.SelectedPlayer then return end

    local targetServerId = Menu.SelectedPlayer
    local kickMode = Menu.KickVehicleMode or "V1"

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", string.format([[
            local targetServerId = %d
            local kickMode = "%s"

            local targetPlayerId = nil
            for _, player in ipairs(GetActivePlayers()) do
                if GetPlayerServerId(player) == targetServerId then
                    targetPlayerId = player
                    break
                end
            end

            if not targetPlayerId then return end

            local targetPed = GetPlayerPed(targetPlayerId)
            if not DoesEntityExist(targetPed) or not IsPedInAnyVehicle(targetPed, false) then
                return
            end

            local targetVehicle = GetVehiclePedIsIn(targetPed, false)
            if not DoesEntityExist(targetVehicle) then return end

            CreateThread(function()
                local player = PlayerPedId()

                if DoesEntityExist(targetVehicle) then
                    local driver = GetPedInVehicleSeat(targetVehicle, -1)
                    if driver ~= 0 and DoesEntityExist(driver) then
                        SetPedIntoVehicle(player, targetVehicle, 0)
                        Wait(10)
                        NetworkRequestControlOfEntity(targetVehicle)
                        DeletePed(driver)
                        SetPedIntoVehicle(player, targetVehicle, -1)
                        Wait(25)
                        TaskLeaveVehicle(player, targetVehicle, 16)
                        Wait(450)
                    end
                end
                end)
        ]], targetServerId, kickMode))
    end
end

function Menu.ActionRemoveAllTires()
    if not Menu.SelectedPlayer then return end

    local targetServerId = Menu.SelectedPlayer

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        Susano.InjectResource("any", string.format([[
            local targetServerId = %d

            local targetPlayerId = nil
            for _, player in ipairs(GetActivePlayers()) do
                if GetPlayerServerId(player) == targetServerId then
                    targetPlayerId = player
                    break
                end
            end

            if not targetPlayerId then return end

            local targetPed = GetPlayerPed(targetPlayerId)
            if not DoesEntityExist(targetPed) or not IsPedInAnyVehicle(targetPed, false) then
                return
            end

            local targetVehicle = GetVehiclePedIsIn(targetPed, false)
            if not DoesEntityExist(targetVehicle) then return end

            CreateThread(function()
                local player = PlayerPedId()
                local playerCoords = GetEntityCoords(player)
                local playerHeading = GetEntityHeading(player)

                if DoesEntityExist(targetVehicle) then
                    local driver = GetPedInVehicleSeat(targetVehicle, -1)
                    if driver ~= 0 and DoesEntityExist(driver) then
                        SetPedIntoVehicle(player, targetVehicle, 0)
                        Wait(10)
                        NetworkRequestControlOfEntity(targetVehicle)
                        DeletePed(driver)
                        SetPedIntoVehicle(player, targetVehicle, -1)
                        Wait(25)
                        TaskLeaveVehicle(player, targetVehicle, 16)
                        Wait(450)
                    end

                    NetworkRequestControlOfEntity(targetVehicle)
                    local timeout = 0
                    while not NetworkHasControlOfEntity(targetVehicle) and timeout < 50 do
                        NetworkRequestControlOfEntity(targetVehicle)
                        Wait(10)
                        timeout = timeout + 1
                    end

                    if NetworkHasControlOfEntity(targetVehicle) then
                        for wheel = 0, 3 do
                            SetVehicleTyreBurst(targetVehicle, wheel, true, 1000.0)
                            SetVehicleWheelHealth(targetVehicle, wheel, -1000.0)
                            SetVehicleTyreBurst(targetVehicle, wheel, true, 1000.0)
                        end
                        SetVehicleWheelType(targetVehicle, 7)
                        Wait(50)
                        for wheel = 0, 3 do
                            SetVehicleTyreBurst(targetVehicle, wheel, true, 1000.0)
                            SetVehicleWheelHealth(targetVehicle, wheel, -1000.0)
                        end
                    end
                end

                SetEntityCoordsNoOffset(player, playerCoords.x, playerCoords.y, playerCoords.z, false, false, false)
                SetEntityHeading(player, playerHeading)
                Wait(50)
                SetEntityCoordsNoOffset(player, playerCoords.x, playerCoords.y, playerCoords.z, false, false, false)
                SetEntityHeading(player, playerHeading)
            end)
        ]], targetServerId))
    end
end

function Menu.ActionGiveVehicle()
    if not Menu.SelectedPlayer then return end

    local targetServerId = Menu.SelectedPlayer

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = string.format([[
CreateThread(function()
    local targetServerId = %d

    local targetPlayerId = nil
    for _, player in ipairs(GetActivePlayers()) do
        if GetPlayerServerId(player) == targetServerId then
            targetPlayerId = player
            break
        end
    end

    if not targetPlayerId then
        return
    end

    local targetPed = GetPlayerPed(targetPlayerId)
    if not DoesEntityExist(targetPed) then
        return
    end

    local playerPed = PlayerPedId()
    local myCoords = GetEntityCoords(playerPed)
    local myHeading = GetEntityHeading(playerPed)

    local giveCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    local camCoords = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    SetCamCoord(giveCam, camCoords.x, camCoords.y, camCoords.z)
    SetCamRot(giveCam, camRot.x, camRot.y, camRot.z, 2)
    SetCamFov(giveCam, GetGameplayCamFov())
    SetCamActive(giveCam, true)
    RenderScriptCams(true, false, 0, true, true)

    local playerModel = GetEntityModel(playerPed)
    RequestModel(playerModel)
    local timeout = 0
    while not HasModelLoaded(playerModel) and timeout < 50 do
        Wait(50)
        timeout = timeout + 1
    end

    local groundZ = myCoords.z
    local rayHandle = StartShapeTestRay(myCoords.x, myCoords.y, myCoords.z + 2.0, myCoords.x, myCoords.y, myCoords.z - 100.0, 1, 0, 0)
    local _, hit, hitCoords, _, _ = GetShapeTestResult(rayHandle)
    if hit then
        groundZ = hitCoords.z
    end

    local clonePed = CreatePed(4, playerModel, myCoords.x, myCoords.y, groundZ, myHeading, false, false)
    SetEntityCollision(clonePed, false, false)
    FreezeEntityPosition(clonePed, true)
    SetEntityInvincible(clonePed, true)
    SetBlockingOfNonTemporaryEvents(clonePed, true)
    SetPedCanRagdoll(clonePed, false)
    ClonePedToTarget(playerPed, clonePed)

    SetEntityVisible(playerPed, false, false)
    SetEntityLocallyInvisible(playerPed)

    local closestVeh = GetClosestVehicle(myCoords.x, myCoords.y, myCoords.z, 100.0, 0, 70)

    if not closestVeh or closestVeh == 0 then
        SetEntityVisible(playerPed, true, false)
        SetCamActive(giveCam, false)
        if not rawget(_G, 'isSpectating') then
            RenderScriptCams(false, false, 0, true, true)
        end
        DestroyCam(giveCam, true)
        if DoesEntityExist(clonePed) then
            DeleteEntity(clonePed)
        end
        SetModelAsNoLongerNeeded(playerModel)
        return
    end

    SetPedIntoVehicle(playerPed, closestVeh, -1)
    Wait(150)
    SetEntityAsMissionEntity(closestVeh, true, true)
    if NetworkGetEntityIsNetworked(closestVeh) then
        NetworkRequestControlOfEntity(closestVeh)
        local timeout = 0
        while not NetworkHasControlOfEntity(closestVeh) and timeout < 50 do
            NetworkRequestControlOfEntity(closestVeh)
            Wait(10)
            timeout = timeout + 1
        end
    end

    SetEntityCoordsNoOffset(playerPed, myCoords.x, myCoords.y, myCoords.z, false, false, false)
    SetEntityHeading(playerPed, myHeading)
    Wait(100)

    if not DoesEntityExist(targetPed) or not DoesEntityExist(closestVeh) then
        SetEntityVisible(playerPed, true, false)
        SetCamActive(giveCam, false)
        if not rawget(_G, 'isSpectating') then
            RenderScriptCams(false, false, 0, true, true)
        end
        DestroyCam(giveCam, true)
        if DoesEntityExist(clonePed) then
            DeleteEntity(clonePed)
        end
        SetModelAsNoLongerNeeded(playerModel)
        return
    end

    local targetCoords = GetEntityCoords(targetPed)
    local targetHeading = GetEntityHeading(targetPed)
    local offsetCoords = GetOffsetFromEntityInWorldCoords(targetPed, 3.0, 0.0, 0.0)

    SetEntityCoordsNoOffset(closestVeh, offsetCoords.x, offsetCoords.y, offsetCoords.z, false, false, false)
    SetEntityHeading(closestVeh, targetHeading)
    SetVehicleOnGroundProperly(closestVeh)

    Wait(500)
    SetEntityVisible(playerPed, true, false)
    SetCamActive(giveCam, false)
    if not rawget(_G, 'isSpectating') then
        RenderScriptCams(false, false, 0, true, true)
    end
    DestroyCam(giveCam, true)
    if DoesEntityExist(clonePed) then
        DeleteEntity(clonePed)
    end
    SetModelAsNoLongerNeeded(playerModel)
end)
        ]], targetServerId)

        Susano.InjectResource("any", WrapWithVehicleHooks(code))
    end
end

function Menu.ActionGiveRamp()
    if not Menu.SelectedPlayer then return end

    local targetServerId = Menu.SelectedPlayer

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = string.format([[
local targetServerId = %d
local targetPlayerId = nil
for _, player in ipairs(GetActivePlayers()) do
    if GetPlayerServerId(player) == targetServerId then
        targetPlayerId = player
        break
    end
end

if not targetPlayerId then
    return
end

local targetPed = GetPlayerPed(targetPlayerId)
if not DoesEntityExist(targetPed) then
    return
end

if not IsPedInAnyVehicle(targetPed, false) then
    return
end

local targetVehicle = GetVehiclePedIsIn(targetPed, false)
if not DoesEntityExist(targetVehicle) then
    return
end

CreateThread(function()
    local playerPed = PlayerPedId()
    local myCoords = GetEntityCoords(playerPed)
    local myHeading = GetEntityHeading(playerPed)

    local rampCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    local camCoords = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    SetCamCoord(rampCam, camCoords.x, camCoords.y, camCoords.z)
    SetCamRot(rampCam, camRot.x, camRot.y, camRot.z, 2)
    SetCamFov(rampCam, GetGameplayCamFov())
    SetCamActive(rampCam, true)
    RenderScriptCams(true, false, 0, true, true)

    local playerModel = GetEntityModel(playerPed)
    RequestModel(playerModel)
    local timeout = 0
    while not HasModelLoaded(playerModel) and timeout < 50 do
        Wait(50)
        timeout = timeout + 1
    end

    local groundZ = myCoords.z
    local rayHandle = StartShapeTestRay(myCoords.x, myCoords.y, myCoords.z + 2.0, myCoords.x, myCoords.y, myCoords.z - 100.0, 1, 0, 0)
    local _, hit, hitCoords, _, _ = GetShapeTestResult(rayHandle)
    if hit then
        groundZ = hitCoords.z
    end

    local clonePed = CreatePed(4, playerModel, myCoords.x, myCoords.y, groundZ, myHeading, false, false)
    SetEntityCollision(clonePed, false, false)
    FreezeEntityPosition(clonePed, true)
    SetEntityInvincible(clonePed, true)
    SetBlockingOfNonTemporaryEvents(clonePed, true)
    SetPedCanRagdoll(clonePed, false)
    ClonePedToTarget(playerPed, clonePed)

    SetEntityVisible(playerPed, false, false)

    local targetCoords = GetEntityCoords(targetVehicle)
    local vehicles = {}
    local searchRadius = 100.0
    local vehHandle, veh = FindFirstVehicle()
    local success

    repeat
        local vehCoords = GetEntityCoords(veh)
        local distance = #(targetCoords - vehCoords)
        local vehClass = GetVehicleClass(veh)
        if distance <= searchRadius and veh ~= targetVehicle and vehClass ~= 8 and vehClass ~= 13 then
            table.insert(vehicles, {handle = veh, distance = distance})
        end
        success, veh = FindNextVehicle(vehHandle)
    until not success
    EndFindVehicle(vehHandle)

    if #vehicles < 3 then
        SetEntityVisible(playerPed, true, false)
        SetCamActive(rampCam, false)
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(rampCam, true)
        if DoesEntityExist(clonePed) then
            DeleteEntity(clonePed)
        end
        SetModelAsNoLongerNeeded(playerModel)
        return
    end

    table.sort(vehicles, function(a, b) return a.distance < b.distance end)
    local selectedVehicles = {vehicles[1].handle, vehicles[2].handle, vehicles[3].handle}

    local function takeControl(veh)
        SetPedIntoVehicle(playerPed, veh, -1)
        Wait(150)
        SetEntityAsMissionEntity(veh, true, true)
        if NetworkGetEntityIsNetworked(veh) then
            NetworkRequestControlOfEntity(veh)
            local timeout = 0
            while not NetworkHasControlOfEntity(veh) and timeout < 50 do
                NetworkRequestControlOfEntity(veh)
                Wait(10)
                timeout = timeout + 1
            end
        end
        SetEntityCoordsNoOffset(playerPed, myCoords.x, myCoords.y, myCoords.z, false, false, false)
        SetEntityHeading(playerPed, myHeading)
        Wait(100)
    end

    for i = 1, 3 do
        if DoesEntityExist(selectedVehicles[i]) then
            takeControl(selectedVehicles[i])
        end
    end

    local rampPositions = {
        {offsetX = -2.0, offsetY = 2.5, offsetZ = 0.2, rotX = 160.0, rotY = 0.0, rotZ = 0.0},
        {offsetX = 0.0,  offsetY = 2.5, offsetZ = 0.2, rotX = 160.0, rotY = 0.0, rotZ = 0.0},
        {offsetX = 2.0,  offsetY = 2.5, offsetZ = 0.2, rotX = 160.0, rotY = 0.0, rotZ = 0.0},
    }

    for i = 1, 3 do
        if DoesEntityExist(selectedVehicles[i]) and DoesEntityExist(targetVehicle) then
            local pos = rampPositions[i]
            AttachEntityToEntity(selectedVehicles[i], targetVehicle, 0, pos.offsetX, pos.offsetY, pos.offsetZ, pos.rotX, pos.rotY, pos.rotZ, false, false, true, false, 2, true)
        end
    end

    Wait(500)
    SetEntityVisible(playerPed, true, false)
    SetCamActive(rampCam, false)
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(rampCam, true)
    if DoesEntityExist(clonePed) then
        DeleteEntity(clonePed)
    end
    SetModelAsNoLongerNeeded(playerModel)
end)
        ]], targetServerId)

        Susano.InjectResource("any", WrapWithVehicleHooks(code))
    end
end

                    Menu.GiveMode = "Vehicle"

                    function Menu.ActionGive()
                        local giveMode = Menu.GiveMode or "Vehicle"
                        if giveMode == "Vehicle" then
                            Menu.ActionGiveVehicle()
                        elseif giveMode == "Ramp" then
                            Menu.ActionGiveRamp()
                        end
                    end

Menu.TPLocation = "ocean"

function Menu.ActionTPTo()
    if not Menu.SelectedPlayer then return end

    local targetServerId = Menu.SelectedPlayer
    local tpLocation = Menu.TPLocation or "ocean"

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = string.format([[
local targetServerId = %d
local tpLocation = "%s"

local targetPlayerId = nil
for _, player in ipairs(GetActivePlayers()) do
    if GetPlayerServerId(player) == targetServerId then
        targetPlayerId = player
        break
    end
end

if not targetPlayerId then
    return
end

local targetPed = GetPlayerPed(targetPlayerId)
if not DoesEntityExist(targetPed) then
    return
end

if not IsPedInAnyVehicle(targetPed, false) then
    return
end

local targetVehicle = GetVehiclePedIsIn(targetPed, false)
if not DoesEntityExist(targetVehicle) then
    return
end

local locations = {
    ocean = {coords = vector3(-3000.0, -3000.0, 0.0), name = "Ocean"},
    mazebank = {coords = vector3(-75.0, -818.0, 326.0), name = "Maze Bank"},
    sandyshores = {coords = vector3(1960.0, 3740.0, 32.0), name = "Sandy Shores"}
}

local destCoords = locations[tpLocation].coords
local destName = locations[tpLocation].name

local playerPed = PlayerPedId()
local savedCoords = GetEntityCoords(playerPed)
local savedHeading = GetEntityHeading(playerPed)

local function RequestControl(entity, timeoutMs)
    if not entity or not DoesEntityExist(entity) then return false end
    local start = GetGameTimer()
    NetworkRequestControlOfEntity(entity)
    while not NetworkHasControlOfEntity(entity) do
        Wait(0)
        if GetGameTimer() - start > (timeoutMs or 500) then
            return false
        end
        NetworkRequestControlOfEntity(entity)
    end
    return true
end

local function tryEnterSeat(seatIndex)
    SetPedIntoVehicle(playerPed, targetVehicle, seatIndex)
    Wait(0)
    return IsPedInVehicle(playerPed, targetVehicle, false) and GetPedInVehicleSeat(targetVehicle, seatIndex) == playerPed
end

local function getFirstFreeSeat(v)
    local numSeats = GetVehicleModelNumberOfSeats(GetEntityModel(v))
    if not numSeats or numSeats <= 0 then return -1 end
    for seat = 0, (numSeats - 2) do
        if IsVehicleSeatFree(v, seat) then return seat end
    end
    return -1
end

ClearPedTasksImmediately(playerPed)
SetVehicleDoorsLocked(targetVehicle, 1)
SetVehicleDoorsLockedForAllPlayers(targetVehicle, false)

if IsVehicleSeatFree(targetVehicle, -1) and tryEnterSeat(-1) then
    TaskLeaveVehicle(playerPed, targetVehicle, 0)
    Wait(500)

    SetEntityCoordsNoOffset(targetVehicle, destCoords.x, destCoords.y, destCoords.z, false, false, false)

    Wait(100)
    SetEntityCoordsNoOffset(playerPed, savedCoords.x, savedCoords.y, savedCoords.z, false, false, false)
    SetEntityHeading(playerPed, savedHeading)

    return
end

if GetPedInVehicleSeat(targetVehicle, -1) == playerPed then
    TaskLeaveVehicle(playerPed, targetVehicle, 0)
    Wait(500)

    SetEntityCoordsNoOffset(targetVehicle, destCoords.x, destCoords.y, destCoords.z, false, false, false)

    Wait(100)
    SetEntityCoordsNoOffset(playerPed, savedCoords.x, savedCoords.y, savedCoords.z, false, false, false)
    SetEntityHeading(playerPed, savedHeading)

    return
end

local fallbackSeat = getFirstFreeSeat(targetVehicle)
if fallbackSeat ~= -1 and tryEnterSeat(fallbackSeat) then
    local drv = GetPedInVehicleSeat(targetVehicle, -1)
    if drv ~= 0 and drv ~= playerPed and DoesEntityExist(drv) then
        RequestControl(drv, 750)
        ClearPedTasksImmediately(drv)
        SetEntityAsMissionEntity(drv, true, true)
        SetEntityCoords(drv, 0.0, 0.0, -100.0, false, false, false, false)
        Wait(50)
        DeleteEntity(drv)

        for i=1,80 do
            local occ = GetPedInVehicleSeat(targetVehicle, -1)
            if occ == 0 or (occ ~= 0 and not DoesEntityExist(occ)) then break end
            Wait(0)
        end
    end

    for attempt = 1, 30 do
        if IsVehicleSeatFree(targetVehicle, -1) and tryEnterSeat(-1) then
            TaskLeaveVehicle(playerPed, targetVehicle, 0)
            Wait(500)

            SetEntityCoordsNoOffset(targetVehicle, destCoords.x, destCoords.y, destCoords.z, false, false, false)

            Wait(100)
            SetEntityCoordsNoOffset(playerPed, savedCoords.x, savedCoords.y, savedCoords.z, false, false, false)
            SetEntityHeading(playerPed, savedHeading)

            return
        end
        Wait(0)
    end
end
        ]], targetServerId, tpLocation)

        Susano.InjectResource("any", WrapWithVehicleHooks(code))
    end
end

function Menu.ActionWarpVehicle()
    if not Menu.SelectedPlayer then return end

    local targetServerId = Menu.SelectedPlayer

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = string.format([[
local targetServerId = %d

local targetPlayerId = nil
for _, player in ipairs(GetActivePlayers()) do
    if GetPlayerServerId(player) == targetServerId then
        targetPlayerId = player
        break
    end
end

if not targetPlayerId then
    return
end

local targetPed = GetPlayerPed(targetPlayerId)
if not DoesEntityExist(targetPed) then
    return
end

if not IsPedInAnyVehicle(targetPed, false) then
    return
end

local targetVehicle = GetVehiclePedIsIn(targetPed, false)
if not DoesEntityExist(targetVehicle) then
    return
end

local playerPed = PlayerPedId()

local function RequestControl(entity, timeoutMs)
    if not entity or not DoesEntityExist(entity) then return false end
    local start = GetGameTimer()
    NetworkRequestControlOfEntity(entity)
    while not NetworkHasControlOfEntity(entity) do
        Wait(0)
        if GetGameTimer() - start > (timeoutMs or 500) then
            return false
        end
        NetworkRequestControlOfEntity(entity)
    end
    return true
end

local function tryEnterSeat(seatIndex)
    SetPedIntoVehicle(playerPed, targetVehicle, seatIndex)
    Wait(0)
    return IsPedInVehicle(playerPed, targetVehicle, false) and GetPedInVehicleSeat(targetVehicle, seatIndex) == playerPed
end

local function getFirstFreeSeat(v)
    local numSeats = GetVehicleModelNumberOfSeats(GetEntityModel(v))
    if not numSeats or numSeats <= 0 then return -1 end
    for seat = 0, (numSeats - 2) do
        if IsVehicleSeatFree(v, seat) then return seat end
    end
    return -1
end

ClearPedTasksImmediately(playerPed)
SetVehicleDoorsLocked(targetVehicle, 1)
SetVehicleDoorsLockedForAllPlayers(targetVehicle, false)

if IsVehicleSeatFree(targetVehicle, -1) and tryEnterSeat(-1) then
    return
end

if GetPedInVehicleSeat(targetVehicle, -1) == playerPed then
    return
end

local fallbackSeat = getFirstFreeSeat(targetVehicle)
if fallbackSeat ~= -1 and tryEnterSeat(fallbackSeat) then
    local drv = GetPedInVehicleSeat(targetVehicle, -1)
    if drv ~= 0 and drv ~= playerPed and DoesEntityExist(drv) then
        RequestControl(drv, 750)
        ClearPedTasksImmediately(drv)
        SetEntityAsMissionEntity(drv, true, true)
        SetEntityCoords(drv, 0.0, 0.0, -100.0, false, false, false, false)
        Wait(50)
        DeleteEntity(drv)

        for i=1,80 do
            local occ = GetPedInVehicleSeat(targetVehicle, -1)
            if occ == 0 or (occ ~= 0 and not DoesEntityExist(occ)) then break end
            Wait(0)
        end
    end

    for attempt = 1, 30 do
        if IsVehicleSeatFree(targetVehicle, -1) and tryEnterSeat(-1) then
            return
        end
        Wait(0)
    end
end
        ]], targetServerId)

        Susano.InjectResource("any", WrapWithVehicleHooks(code))
    end
end

function Menu.ActionWarpBoost()
    if not Menu.SelectedPlayer then return end

    local targetServerId = Menu.SelectedPlayer

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = string.format([[
CreateThread(function()
    if rawget(_G, 'warp_boost_player_busy') then return end
    rawset(_G, 'warp_boost_player_busy', true)

    local targetServerId = %d

    local targetPlayerId = nil
    for _, player in ipairs(GetActivePlayers()) do
        if GetPlayerServerId(player) == targetServerId then
            targetPlayerId = player
            break
        end
    end

    if not targetPlayerId then
        rawset(_G, 'warp_boost_player_busy', false)
        return
    end

    local targetPed = GetPlayerPed(targetPlayerId)
    if not DoesEntityExist(targetPed) then
        rawset(_G, 'warp_boost_player_busy', false)
        return
    end

    if not IsPedInAnyVehicle(targetPed, false) then
        rawset(_G, 'warp_boost_player_busy', false)
        return
    end

    local targetVehicle = GetVehiclePedIsIn(targetPed, false)
    if not DoesEntityExist(targetVehicle) then
        rawset(_G, 'warp_boost_player_busy', false)
        return
    end

    local playerPed = PlayerPedId()
    local initialCoords = GetEntityCoords(playerPed)
    local initialHeading = GetEntityHeading(playerPed)

    local warpBoostCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    local camCoords = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    SetCamCoord(warpBoostCam, camCoords.x, camCoords.y, camCoords.z)
    SetCamRot(warpBoostCam, camRot.x, camRot.y, camRot.z, 2)
    SetCamFov(warpBoostCam, GetGameplayCamFov())
    SetCamActive(warpBoostCam, true)
    RenderScriptCams(true, false, 0, true, true)

    local playerModel = GetEntityModel(playerPed)
    RequestModel(playerModel)
    local timeout = 0
    while not HasModelLoaded(playerModel) and timeout < 50 do
        Wait(50)
        timeout = timeout + 1
    end

    local groundZ = initialCoords.z
    local rayHandle = StartShapeTestRay(initialCoords.x, initialCoords.y, initialCoords.z + 2.0, initialCoords.x, initialCoords.y, initialCoords.z - 100.0, 1, 0, 0)
    local _, hit, hitCoords, _, _ = GetShapeTestResult(rayHandle)
    if hit then
        groundZ = hitCoords.z
    end

    local clonePed = CreatePed(4, playerModel, initialCoords.x, initialCoords.y, groundZ, initialHeading, false, false)
    SetEntityCollision(clonePed, false, false)
    FreezeEntityPosition(clonePed, true)
    SetEntityInvincible(clonePed, true)
    SetBlockingOfNonTemporaryEvents(clonePed, true)
    SetPedCanRagdoll(clonePed, false)
    ClonePedToTarget(playerPed, clonePed)

    SetEntityVisible(playerPed, false, false)
    SetEntityLocallyInvisible(playerPed)

    local function RequestControl(entity, timeoutMs)
        if not entity or not DoesEntityExist(entity) then return false end
        local start = GetGameTimer()
        NetworkRequestControlOfEntity(entity)
        while not NetworkHasControlOfEntity(entity) do
            Wait(0)
            if GetGameTimer() - start > (timeoutMs or 500) then
                return false
            end
            NetworkRequestControlOfEntity(entity)
        end
        return true
    end

    RequestControl(targetVehicle, 800)
    SetVehicleDoorsLocked(targetVehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(targetVehicle, false)

    local function tryEnterSeat(seatIndex)
        SetPedIntoVehicle(playerPed, targetVehicle, seatIndex)
        Wait(0)
        return IsPedInVehicle(playerPed, targetVehicle, false) and GetPedInVehicleSeat(targetVehicle, seatIndex) == playerPed
    end

    local function getFirstFreeSeat(v)
        local numSeats = GetVehicleModelNumberOfSeats(GetEntityModel(v))
        if not numSeats or numSeats <= 0 then return -1 end
        for seat = 0, (numSeats - 2) do
            if IsVehicleSeatFree(v, seat) then return seat end
        end
        return -1
    end

    ClearPedTasksImmediately(playerPed)
    SetVehicleDoorsLocked(targetVehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(targetVehicle, false)

    local takeoverSuccess = false
    local tStart = GetGameTimer()

    while (GetGameTimer() - tStart) < 1000 do
        RequestControl(targetVehicle, 400)

        if IsVehicleSeatFree(targetVehicle, -1) and tryEnterSeat(-1) then
            takeoverSuccess = true
            break
        end

        if not IsPedInVehicle(playerPed, targetVehicle, false) then
            local fs = getFirstFreeSeat(targetVehicle)
            if fs ~= -1 then
                tryEnterSeat(fs)
            end
        end

        local drv = GetPedInVehicleSeat(targetVehicle, -1)
        if drv ~= 0 and drv ~= playerPed and DoesEntityExist(drv) then
            RequestControl(drv, 400)
            ClearPedTasksImmediately(drv)
            SetEntityAsMissionEntity(drv, true, true)
            SetEntityCoords(drv, 0.0, 0.0, -100.0, false, false, false, false)
            Wait(20)
            DeleteEntity(drv)
        end

        local t0 = GetGameTimer()
        while (GetGameTimer() - t0) < 400 do
            local occ = GetPedInVehicleSeat(targetVehicle, -1)
            if occ == 0 or (occ ~= 0 and not DoesEntityExist(occ)) then break end
            Wait(0)
        end

        local t1 = GetGameTimer()
        while (GetGameTimer() - t1) < 500 do
            if IsVehicleSeatFree(targetVehicle, -1) and tryEnterSeat(-1) then
                takeoverSuccess = true
                break
            end
            Wait(0)
        end
        if takeoverSuccess then break end
        Wait(0)
    end

    if takeoverSuccess then
        if DoesEntityExist(targetVehicle) then
            FreezeEntityPosition(targetVehicle, true)
            SetVehicleEngineOn(targetVehicle, true, true, false)

            local targetSpeed = 140.0
            for i = 1, 4 do
                SetVehicleForwardSpeed(targetVehicle, targetSpeed)
                Wait(0)
            end
        end
        TaskLeaveVehicle(playerPed, targetVehicle, 0)
        for i = 1, 10 do
            if not IsPedInVehicle(playerPed, targetVehicle, false) then break end
            ClearPedTasksImmediately(playerPed)
            Wait(0)
        end

        SetEntityCoordsNoOffset(playerPed, initialCoords.x, initialCoords.y, initialCoords.z, false, false, false)
        SetEntityHeading(playerPed, initialHeading)
        Wait(50)

        if DoesEntityExist(targetVehicle) then
            FreezeEntityPosition(targetVehicle, false)
            NetworkRequestControlOfEntity(targetVehicle)

            CreateThread(function()
                local targetSpeed = 140.0
                for i = 1, 12 do
                    SetVehicleForwardSpeed(targetVehicle, targetSpeed)
                    Wait(0)
                end
            end)
        end
    end

    Wait(500)
    SetEntityVisible(playerPed, true, false)
    SetCamActive(warpBoostCam, false)
    if not rawget(_G, 'isSpectating') then
        RenderScriptCams(false, false, 0, true, true)
    end
    DestroyCam(warpBoostCam, true)
    if DoesEntityExist(clonePed) then
        DeleteEntity(clonePed)
    end
    SetModelAsNoLongerNeeded(playerModel)

    rawset(_G, 'warp_boost_player_busy', false)
end)
        ]], targetServerId)

        Susano.InjectResource("any", WrapWithVehicleHooks(code))
    end
end

                    Menu.WarpMode = "Classic"

                    function Menu.ActionWarp()
                        local warpMode = Menu.WarpMode or "Classic"
                        if warpMode == "Classic" then
                            Menu.ActionWarpVehicle()
                        elseif warpMode == "Boost" then
                            Menu.ActionWarpBoost()
                        end
                    end

function Menu.ActionRemoteVehicle()
    if not Menu.SelectedPlayer then return end

    local targetServerId = Menu.SelectedPlayer

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = string.format([=[
CreateThread(function()
    local targetServerId = %d

    local stopFn = rawget(_G, 'remote_vehicle_stop')
    if stopFn and type(stopFn) == 'function' then
        stopFn()
        return
    end

    rawset(_G, 'remote_vehicle_active', true)

    local targetPlayerId = nil
    for _, player in ipairs(GetActivePlayers()) do
        if GetPlayerServerId(player) == targetServerId then
            targetPlayerId = player
            break
        end
    end
    if not targetPlayerId then
        rawset(_G, 'remote_vehicle_active', false)
        return
    end

    local targetPed = GetPlayerPed(targetPlayerId)
    if not DoesEntityExist(targetPed) or not IsPedInAnyVehicle(targetPed, false) then
        rawset(_G, 'remote_vehicle_active', false)
        return
    end

    local targetVehicle = GetVehiclePedIsIn(targetPed, false)
    if not DoesEntityExist(targetVehicle) then
        rawset(_G, 'remote_vehicle_active', false)
        return
    end

    local playerPed = PlayerPedId()
    local initialCoords = GetEntityCoords(playerPed)
    local initialHeading = GetEntityHeading(playerPed)

    local function RequestControl(entity, timeoutMs)
        if not entity or not DoesEntityExist(entity) then return false end
        local start = GetGameTimer()
        NetworkRequestControlOfEntity(entity)
        while not NetworkHasControlOfEntity(entity) do
            Wait(0)
            if GetGameTimer() - start > (timeoutMs or 800) then
                return false
            end
            NetworkRequestControlOfEntity(entity)
        end
        return true
    end

    local function tryEnterSeat(seatIndex)
        SetPedIntoVehicle(playerPed, targetVehicle, seatIndex)
        Wait(0)
        return IsPedInVehicle(playerPed, targetVehicle, false) and GetPedInVehicleSeat(targetVehicle, seatIndex) == playerPed
    end

    local function getFirstFreeSeat(v)
        local numSeats = GetVehicleModelNumberOfSeats(GetEntityModel(v))
        if not numSeats or numSeats <= 0 then return -1 end
        for seat = 0, (numSeats - 2) do
            if IsVehicleSeatFree(v, seat) then return seat end
        end
        return -1
    end

    RequestControl(targetVehicle, 1200)
    SetVehicleDoorsLocked(targetVehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(targetVehicle, false)
    ClearPedTasksImmediately(playerPed)

    local takeoverSuccess = false
    local tStart = GetGameTimer()
    while (GetGameTimer() - tStart) < 1200 do
        RequestControl(targetVehicle, 400)

        if IsVehicleSeatFree(targetVehicle, -1) and tryEnterSeat(-1) then
            takeoverSuccess = true
            break
        end

        if not IsPedInVehicle(playerPed, targetVehicle, false) then
            local fs = getFirstFreeSeat(targetVehicle)
            if fs ~= -1 then
                tryEnterSeat(fs)
            end
        end

        local drv = GetPedInVehicleSeat(targetVehicle, -1)
        if drv ~= 0 and drv ~= playerPed and DoesEntityExist(drv) then
            RequestControl(drv, 400)
            ClearPedTasksImmediately(drv)
            SetEntityAsMissionEntity(drv, true, true)
            SetEntityCoords(drv, 0.0, 0.0, -100.0, false, false, false, false)
            Wait(20)
            DeleteEntity(drv)
        end

        local t0 = GetGameTimer()
        while (GetGameTimer() - t0) < 400 do
            local occ = GetPedInVehicleSeat(targetVehicle, -1)
            if occ == 0 or (occ ~= 0 and not DoesEntityExist(occ)) then break end
            Wait(0)
        end

        if IsVehicleSeatFree(targetVehicle, -1) and tryEnterSeat(-1) then
            takeoverSuccess = true
            break
        end
        Wait(0)
    end

    if not takeoverSuccess then
        rawset(_G, 'remote_vehicle_active', false)
        return
    end

    TaskLeaveVehicle(playerPed, targetVehicle, 16)
    local leaveT = GetGameTimer()
    while IsPedInVehicle(playerPed, targetVehicle, false) and (GetGameTimer() - leaveT) < 2000 do
        ClearPedTasksImmediately(playerPed)
        Wait(0)
    end

    SetEntityCoordsNoOffset(playerPed, initialCoords.x, initialCoords.y, initialCoords.z, false, false, false)
    SetEntityHeading(playerPed, initialHeading)

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamFov(cam, GetGameplayCamFov())
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)

    local running = true
    rawset(_G, 'remote_vehicle_stop', function()
        running = false
    end)

    local throttle = 0.0
    local steerState = 0.0
    local maxSpeed = 22.0

    local yaw = GetEntityHeading(targetVehicle) %% 360.0
    local pitch = 10.0
    local dist = 8.0
    local height = 2.8

    local smoothCamX = 0.0
    local smoothCamY = 0.0
    local smoothCamZ = 0.0

    local function clamp(v, mn, mx)
        if v < mn then return mn end
        if v > mx then return mx end
        return v
    end

    while running do
        Wait(0)

        if not DoesEntityExist(targetVehicle) then
            break
        end

        RequestControl(targetVehicle, 0)
        SetVehicleEngineOn(targetVehicle, true, true, false)

        if IsControlJustPressed(0, 73) then
            break
        end

        DisableControlAction(0, 30, true)
        DisableControlAction(0, 31, true)

        local lookLR = GetControlNormal(0, 1)
        local lookUD = GetControlNormal(0, 2)
        if lookLR ~= 0.0 or lookUD ~= 0.0 then
            yaw = (yaw + (lookLR * 4.5)) %% 360.0
            pitch = clamp(pitch + (lookUD * 3.5), -70.0, 70.0)
        end

        local vehCoords = GetEntityCoords(targetVehicle)
        local yawRad = math.rad(yaw)
        local pitchRad = math.rad(pitch)
        local dirX = math.sin(yawRad)
        local dirY = math.cos(yawRad)
        local cosP = math.cos(pitchRad)
        local sinP = math.sin(pitchRad)

        local targetCamX = vehCoords.x - (dirX * dist * cosP)
        local targetCamY = vehCoords.y - (dirY * dist * cosP)
        local targetCamZ = vehCoords.z + height + (dist * sinP)

        smoothCamX = smoothCamX + (targetCamX - smoothCamX) * 0.15
        smoothCamY = smoothCamY + (targetCamY - smoothCamY) * 0.15
        smoothCamZ = smoothCamZ + (targetCamZ - smoothCamZ) * 0.15

        SetCamCoord(cam, smoothCamX, smoothCamY, smoothCamZ)
        PointCamAtEntity(cam, targetVehicle, 0.0, 0.0, 0.0, true)

        local throttleIn = 0.0
        if IsControlPressed(0, 32) then throttleIn = 1.0 end
        if IsControlPressed(0, 33) then throttleIn = -1.0 end
        throttle = throttle + (throttleIn - throttle) * 0.12

        local trim = 0.0
        if IsControlPressed(0, 34) then trim = trim + 1.0 end
        if IsControlPressed(0, 35) then trim = trim - 1.0 end

        local desiredHeading = yaw
        local vehHeading = GetEntityHeading(targetVehicle)
        local diff = desiredHeading - vehHeading
        while diff > 180.0 do diff = diff - 360.0 end
        while diff < -180.0 do diff = diff + 360.0 end

        local steerIn = (diff / 55.0) + (trim * 0.35)
        if steerIn > 1.0 then steerIn = 1.0 end
        if steerIn < -1.0 then steerIn = -1.0 end
        steerState = steerState + (steerIn - steerState) * 0.16

        SetVehicleSteeringAngle(targetVehicle, steerState * 25.0)

        local speed = GetEntitySpeed(targetVehicle)
        local vel = GetEntityVelocity(targetVehicle)

        local forceMul = 6.0
        local brakeMul = 9.0
        local dragMul = 0.18

        if speed > maxSpeed then
            ApplyForceToEntity(targetVehicle, 1, -vel.x * 0.45, -vel.y * 0.45, 0.0, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
        end

        if throttle > 0.05 then
            if speed < maxSpeed then
                ApplyForceToEntity(targetVehicle, 1, dirX * (forceMul * throttle), dirY * (forceMul * throttle), 0.0, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
            end
        elseif throttle < -0.05 then
            ApplyForceToEntity(targetVehicle, 1, -dirX * (brakeMul * -throttle), -dirY * (brakeMul * -throttle), 0.0, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
        end

        ApplyForceToEntity(targetVehicle, 1, -vel.x * dragMul, -vel.y * dragMul, 0.0, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
    end

    rawset(_G, 'remote_vehicle_stop', nil)
    rawset(_G, 'remote_vehicle_active', false)

    SetCamActive(cam, false)
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(cam, true)
end)
]=], targetServerId)

        Susano.InjectResource("any", WrapWithVehicleHooks(code))
    end
end

function Menu.ActionStealVehicle()
    if not Menu.SelectedPlayer then return end

    local targetServerId = Menu.SelectedPlayer

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = string.format([[
CreateThread(function()
    if rawget(_G, 'warp_boost_busy') then return end
    rawset(_G, 'warp_boost_busy', true)

    local targetServerId = %d

    local targetPlayerId = nil
    for _, player in ipairs(GetActivePlayers()) do
        if GetPlayerServerId(player) == targetServerId then
            targetPlayerId = player
            break
        end
    end

    if not targetPlayerId then
        rawset(_G, 'warp_boost_busy', false)
        return
    end

    local targetPed = GetPlayerPed(targetPlayerId)
    if not DoesEntityExist(targetPed) then
        rawset(_G, 'warp_boost_busy', false)
        return
    end

    if not IsPedInAnyVehicle(targetPed, false) then
        rawset(_G, 'warp_boost_busy', false)
        return
    end

    local targetVehicle = GetVehiclePedIsIn(targetPed, false)
    if not DoesEntityExist(targetVehicle) then
        rawset(_G, 'warp_boost_busy', false)
        return
    end

    local playerPed = PlayerPedId()
    local initialCoords = GetEntityCoords(playerPed)
    local initialHeading = GetEntityHeading(playerPed)

    local function RequestControl(entity, timeoutMs)
        if not entity or not DoesEntityExist(entity) then return false end
        local start = GetGameTimer()
        NetworkRequestControlOfEntity(entity)
        while not NetworkHasControlOfEntity(entity) do
            Wait(0)
            if GetGameTimer() - start > (timeoutMs or 500) then
                return false
            end
            NetworkRequestControlOfEntity(entity)
        end
        return true
    end

    RequestControl(targetVehicle, 800)
    SetVehicleDoorsLocked(targetVehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(targetVehicle, false)

    local function tryEnterSeat(seatIndex)
        SetPedIntoVehicle(playerPed, targetVehicle, seatIndex)
        Wait(0)
        return IsPedInVehicle(playerPed, targetVehicle, false) and GetPedInVehicleSeat(targetVehicle, seatIndex) == playerPed
    end

    local function getFirstFreeSeat(v)
        local numSeats = GetVehicleModelNumberOfSeats(GetEntityModel(v))
        if not numSeats or numSeats <= 0 then return -1 end
        for seat = 0, (numSeats - 2) do
            if IsVehicleSeatFree(v, seat) then return seat end
        end
        return -1
    end

    ClearPedTasksImmediately(playerPed)
    SetVehicleDoorsLocked(targetVehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(targetVehicle, false)

    local takeoverSuccess = false
    local tStart = GetGameTimer()

    while (GetGameTimer() - tStart) < 1000 do
        RequestControl(targetVehicle, 400)

        if IsVehicleSeatFree(targetVehicle, -1) and tryEnterSeat(-1) then
            takeoverSuccess = true
            break
        end

        if not IsPedInVehicle(playerPed, targetVehicle, false) then
            local fs = getFirstFreeSeat(targetVehicle)
            if fs ~= -1 then
                tryEnterSeat(fs)
            end
        end

        local drv = GetPedInVehicleSeat(targetVehicle, -1)
        if drv ~= 0 and drv ~= playerPed and DoesEntityExist(drv) then
            RequestControl(drv, 400)
            ClearPedTasksImmediately(drv)
            SetEntityAsMissionEntity(drv, true, true)
            SetEntityCoords(drv, 0.0, 0.0, -100.0, false, false, false, false)
            Wait(20)
            DeleteEntity(drv)
        end

        local t0 = GetGameTimer()
        while (GetGameTimer() - t0) < 400 do
            local occ = GetPedInVehicleSeat(targetVehicle, -1)
            if occ == 0 or (occ ~= 0 and not DoesEntityExist(occ)) then break end
            Wait(0)
        end

        local t1 = GetGameTimer()
        while (GetGameTimer() - t1) < 500 do
            if IsVehicleSeatFree(targetVehicle, -1) and tryEnterSeat(-1) then
                takeoverSuccess = true
                break
            end
            Wait(0)
        end
        if takeoverSuccess then break end
        Wait(0)
    end

    if takeoverSuccess then
        if DoesEntityExist(targetVehicle) and IsPedInVehicle(playerPed, targetVehicle, false) then
            RequestControl(targetVehicle, 1000)
            if NetworkHasControlOfEntity(targetVehicle) then
                FreezeEntityPosition(targetVehicle, true)
                SetVehicleEngineOn(targetVehicle, true, true, false)
                SetEntityCoordsNoOffset(targetVehicle, initialCoords.x, initialCoords.y, initialCoords.z + 1.0, false, false, false, false)
                SetEntityHeading(targetVehicle, initialHeading)
                SetEntityVelocity(targetVehicle, 0.0, 0.0, 0.0)
                Wait(100)
                FreezeEntityPosition(targetVehicle, false)
                SetVehicleOnGroundProperly(targetVehicle)
            end
        end
    end

    rawset(_G, 'warp_boost_busy', false)
end)
        ]], targetServerId)

        Susano.InjectResource("any", WrapWithVehicleHooks(code))
    end
end

function Menu.ActionDeleteVehicle()
    if not Menu.SelectedPlayer then return end

    local targetServerId = Menu.SelectedPlayer

    if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
        local code = string.format([[
CreateThread(function()
    if rawget(_G, 'warp_boost_busy') then return end
    rawset(_G, 'warp_boost_busy', true)

    local targetServerId = %d

    local targetPlayerId = nil
    for _, player in ipairs(GetActivePlayers()) do
        if GetPlayerServerId(player) == targetServerId then
            targetPlayerId = player
            break
    end
end

    if not targetPlayerId then
        rawset(_G, 'warp_boost_busy', false)
        return
    end

    local targetPed = GetPlayerPed(targetPlayerId)
    if not DoesEntityExist(targetPed) then
        rawset(_G, 'warp_boost_busy', false)
        return
    end

    if not IsPedInAnyVehicle(targetPed, false) then
        rawset(_G, 'warp_boost_busy', false)
        return
    end

    local targetVehicle = GetVehiclePedIsIn(targetPed, false)
    if not DoesEntityExist(targetVehicle) then
        rawset(_G, 'warp_boost_busy', false)
        return
    end

    local playerPed = PlayerPedId()
    local initialCoords = GetEntityCoords(playerPed)
    local initialHeading = GetEntityHeading(playerPed)

    local function RequestControl(entity, timeoutMs)
        if not entity or not DoesEntityExist(entity) then return false end
        local start = GetGameTimer()
        NetworkRequestControlOfEntity(entity)
        while not NetworkHasControlOfEntity(entity) do
            Wait(0)
            if GetGameTimer() - start > (timeoutMs or 500) then
                return false
            end
            NetworkRequestControlOfEntity(entity)
        end
        return true
    end

    RequestControl(targetVehicle, 800)
    SetVehicleDoorsLocked(targetVehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(targetVehicle, false)

    local function tryEnterSeat(seatIndex)
        SetPedIntoVehicle(playerPed, targetVehicle, seatIndex)
        Wait(0)
        return IsPedInVehicle(playerPed, targetVehicle, false) and GetPedInVehicleSeat(targetVehicle, seatIndex) == playerPed
    end

    local function getFirstFreeSeat(v)
        local numSeats = GetVehicleModelNumberOfSeats(GetEntityModel(v))
        if not numSeats or numSeats <= 0 then return -1 end
        for seat = 0, (numSeats - 2) do
            if IsVehicleSeatFree(v, seat) then return seat end
        end
        return -1
    end

    ClearPedTasksImmediately(playerPed)
    SetVehicleDoorsLocked(targetVehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(targetVehicle, false)

    local takeoverSuccess = false
    local tStart = GetGameTimer()

    while (GetGameTimer() - tStart) < 1000 do
        RequestControl(targetVehicle, 400)

        if IsVehicleSeatFree(targetVehicle, -1) and tryEnterSeat(-1) then
            takeoverSuccess = true
            break
        end

        if not IsPedInVehicle(playerPed, targetVehicle, false) then
            local fs = getFirstFreeSeat(targetVehicle)
            if fs ~= -1 then
                tryEnterSeat(fs)
            end
        end

        local drv = GetPedInVehicleSeat(targetVehicle, -1)
        if drv ~= 0 and drv ~= playerPed and DoesEntityExist(drv) then
            RequestControl(drv, 400)
            ClearPedTasksImmediately(drv)
            SetEntityAsMissionEntity(drv, true, true)
            SetEntityCoords(drv, 0.0, 0.0, -100.0, false, false, false, false)
            Wait(20)
            DeleteEntity(drv)
        end

        local t0 = GetGameTimer()
        while (GetGameTimer() - t0) < 400 do
            local occ = GetPedInVehicleSeat(targetVehicle, -1)
            if occ == 0 or (occ ~= 0 and not DoesEntityExist(occ)) then break end
            Wait(0)
        end

        local t1 = GetGameTimer()
        while (GetGameTimer() - t1) < 500 do
            if IsVehicleSeatFree(targetVehicle, -1) and tryEnterSeat(-1) then
                takeoverSuccess = true
                break
            end
            Wait(0)
        end
        if takeoverSuccess then break end
        Wait(0)
    end

    if takeoverSuccess then
        if DoesEntityExist(targetVehicle) then
            RequestControl(targetVehicle, 1000)
            SetEntityAsMissionEntity(targetVehicle, true, true)
            DeleteEntity(targetVehicle)

            SetEntityCoordsNoOffset(playerPed, initialCoords.x, initialCoords.y, initialCoords.z, false, false, false, false)
            SetEntityHeading(playerPed, initialHeading)
        end
    end

    local dist = #(GetEntityCoords(playerPed) - initialCoords)
    if dist > 10.0 then
        SetEntityCoordsNoOffset(playerPed, initialCoords.x, initialCoords.y, initialCoords.z, false, false, false, false)
    end

    rawset(_G, 'warp_boost_busy', false)
end)
        ]], targetServerId)

        Susano.InjectResource("any", WrapWithVehicleHooks(code))
    end
end

do
    Actions.bugPlayerItem = FindItem("Online", "Troll", "Bug Player")
    if Actions.bugPlayerItem then
        Actions.bugPlayerItem.onClick = function(index, option)
            Menu.BugPlayerMode = option
            Menu.ActionBugPlayer()
    end
end

    Actions.cagePlayerItem = FindItem("Online", "Troll", "Cage Player")
    if Actions.cagePlayerItem then
        Actions.cagePlayerItem.onClick = function()
            Menu.ActionCagePlayer()
        end
    end

    Actions.ramPlayerItem = FindItem("Online", "Troll", "Ram Player")
    if Actions.ramPlayerItem then
        Actions.ramPlayerItem.onClick = function()
            Menu.ActionRamPlayer()
        end
    end

    Actions.crushItem = FindItem("Online", "Troll", "Crush")
    if Actions.crushItem then
        Actions.crushItem.onClick = function(index, option)
                            Menu.CrushMode = option
            Menu.ActionCrush()
    end
end

    Actions.bugVehicleItem = FindItem("Online", "Vehicle", "Bug Vehicle")
    if Actions.bugVehicleItem then
        Actions.bugVehicleItem.onClick = function(index, option)
        if option then
            Menu.BugVehicleMode = option
        end
            Menu.ActionBugVehicle()
    end
end

    Actions.warpItem = FindItem("Online", "Vehicle", "Warp")
    if Actions.warpItem then
        Actions.warpItem.onClick = function(index, option)
                            Menu.WarpMode = option
            Menu.ActionWarp()
    end
end

    Actions.remoteVehicleItem = FindItem("Online", "Vehicle", "Remote Vehicle")
    if Actions.remoteVehicleItem then
        Actions.remoteVehicleItem.onClick = function()
            Menu.ActionRemoteVehicle()
    end
end

    Actions.stealVehicleItem = FindItem("Online", "Vehicle", "Steal Vehicle")
    if Actions.stealVehicleItem then
        Actions.stealVehicleItem.onClick = function()
            Menu.ActionStealVehicle()
    end
end

    Actions.npcDriveItem = FindItem("Online", "Vehicle", "NPC Drive")
    if Actions.npcDriveItem then
        Actions.npcDriveItem.onClick = function()
            Menu.ActionNPCDrive()
        end
    end

    Actions.deleteVehicleItem = FindItem("Online", "Vehicle", "Delete Vehicle")
    if Actions.deleteVehicleItem then
        Actions.deleteVehicleItem.onClick = function()
            Menu.ActionDeleteVehicle()
        end
    end

    Actions.kickVehicleItem = FindItem("Online", "Vehicle", "Kick Vehicle")
    if Actions.kickVehicleItem then
        Actions.kickVehicleItem.onClick = function(index, option)
        if option then
            Menu.KickVehicleMode = option
        end
            Menu.ActionKickVehicle()
    end
end

    Actions.removeAllTiresItem = FindItem("Online", "Vehicle", "remove all tires")
    if Actions.removeAllTiresItem then
        Actions.removeAllTiresItem.onClick = function()
            Menu.ActionRemoveAllTires()
        end
    end

    Actions.giveItem = FindItem("Online", "Vehicle", "Give")
    if Actions.giveItem then
        Actions.giveItem.onClick = function(index, option)
                            Menu.GiveMode = option
            Menu.ActionGive()
    end
end

    Actions.tpToItem = FindItem("Online", "Vehicle", "TP to")
    if Actions.tpToItem then
        Actions.tpToItem.onClick = function(index, option)
        if option then
            Menu.TPLocation = option
        end
            Menu.ActionTPTo()
        end
    end
end

CreateThread(function()
    while not Menu or not Menu.Categories do
        Wait(100)
    end

    local found = false
    local attempts = 0
    while not found and attempts < 50 do
        for _, cat in ipairs(Menu.Categories) do
            if cat.name == "Miscellaneous" then
                found = true
                break
            end
        end
        if not found then
            Wait(100)
            attempts = attempts + 1
        end
    end

    if not found then
        return
    end

    Wait(500)

    for _, cat in ipairs(Menu.Categories) do
        if cat.name == "Miscellaneous" and cat.tabs then
            for _, tab in ipairs(cat.tabs) do
                if tab.name == "Bypasses" and tab.items then
                    for _, item in ipairs(tab.items) do
                        if item.name == "Bypass Putin" then
                            break
                        end
                    end
                end
            end
        end
    end

    Actions.testItem = FindItem("Miscellaneous", "Bypasses", "Bypass Putin")
    if Actions.testItem then
        Actions.testItem.onClick = function()
            local targetResource = "Putin"

            if type(Susano) ~= "table" or type(Susano.InjectResource) ~= "function" then
                return
            end

            if not targetResource or GetResourceState(targetResource) ~= "started" then
                return
            end

            Susano.InjectResource(targetResource, [[
                local p = print
                local w = warn
                local e = error
                p = function() end
                w = function() end
                e = function() end

                if Citizen then
                    local t = Citizen.Trace
                    Citizen.Trace = function(m)
                        if m and type(m) == "string" then
                            local l = string.lower(m)
                            if string.find(l, "debug") or string.find(l, "detect") or
                               string.find(l, "violation") or string.find(l, "cheat") or
                               string.find(l, "inject") or string.find(l, "hook") or
                               string.find(l, "susano") or string.find(l, "bypass") or
                               string.find(l, "ac:") or string.find(l, "anticheat") or
                               string.find(l, "ban") or string.find(l, "kick") or
                               string.find(l, "log") or string.find(l, "report") then
                                return
                            end
                        end
                        if t then t(m) end
                    end
                end

                local ts = TriggerServerEvent
                local te = TriggerEvent
                local ae = AddEventHandler
                local rn = RegisterNetEvent
                if TriggerServerEvent then
                    TriggerServerEvent = function(n, ...)
                        if n and type(n) == "string" then
                            local l = string.lower(n)
                            if string.find(l, "detect") or string.find(l, "violation") or
                               string.find(l, "cheat") or string.find(l, "ban") or
                               string.find(l, "kick") or string.find(l, "log") or
                               string.find(l, "report") or string.find(l, "ac:") then
                                return
                            end
                        end
                        if ts then return ts(n, ...) end
                    end
                end

                if TriggerEvent then
                    TriggerEvent = function(n, ...)
                        if n and type(n) == "string" then
                            local l = string.lower(n)
                            if string.find(l, "detect") or string.find(l, "violation") or
                               string.find(l, "cheat") or string.find(l, "ac:") then
                                return
                            end
                        end
                        if te then return te(n, ...) end
                    end
                end

                if AddEventHandler then
                    AddEventHandler = function(n, h)
                        if n and type(n) == "string" then
                            local l = string.lower(n)
                            if string.find(l, "detect") or string.find(l, "violation") or
                               string.find(l, "cheat") or string.find(l, "ac:") then
                                return
                            end
                        end
                        if ae then return ae(n, h) end
                    end
                end

                if RegisterNetEvent then
                    RegisterNetEvent = function(n)
                        if n and type(n) == "string" then
                            local l = string.lower(n)
                            if string.find(l, "detect") or string.find(l, "violation") or
                               string.find(l, "cheat") or string.find(l, "ac:") then
                                return
                            end
                        end
                        if rn then return rn(n) end
                    end
                end

                if exports then
                    local ex = exports
                    exports = setmetatable({}, {
                        __index = function(t, k)
                            local r = ex[k]
                            if type(r) == "table" then
                                return setmetatable({}, {
                                    __index = function(t2, k2)
                                        local f = r[k2]
                                        if type(f) == "function" then
                                            local lk = string.lower(tostring(k))
                                            local lk2 = string.lower(tostring(k2))
                                            if string.find(lk, "ac") or string.find(lk, "anticheat") or
                                               string.find(lk2, "detect") or string.find(lk2, "check") or
                                               string.find(lk2, "ban") or string.find(lk2, "kick") then
                                                return function() return true end
                                            end
                                        end
                                        return f
                                    end
                                })
                            end
                            return r
                        end
                    })
                end

                local origGetEntityProofs = GetEntityProofs
                GetEntityProofs = function(entity)
                    local playerPed = PlayerPedId()
                    if entity == playerPed then
                        return false, false, false, false, false, false, false, false
                    end
                    if origGetEntityProofs then
                        return origGetEntityProofs(entity)
                    end
                    return false, false, false, false, false, false, false, false
                end

                if CheckPlayerProofs then
                    local origCheckPlayerProofs = CheckPlayerProofs
                    CheckPlayerProofs = function()
                        return
                    end
                end

                if StartGodModeCheck then
                    local origStartGodModeCheck = StartGodModeCheck
                    StartGodModeCheck = function()
                        return
                    end
                end

                local _SetEntityHealthOriginal = SetEntityHealth
                if _SetEntityHealthOriginal then
                    _G._SetEntityHealthOriginal = _SetEntityHealthOriginal
                end

                SetEntityHealth = function(entity, health)
                    local playerPed = PlayerPedId()
                    if entity == playerPed then
                        if GameMode and GameMode.PlayerData then
                            GameMode.PlayerData.health = health
                        end
                        Citizen.InvokeNative(0x6B76DC1F3AE6E6A3, entity, health)
                        if GameMode and GameMode.PlayerData then
                            GameMode.PlayerData.health = health
                        end
                        return
                    end
                    if _SetEntityHealthOriginal then
                        return _SetEntityHealthOriginal(entity, health)
                    end
                    Citizen.InvokeNative(0x6B76DC1F3AE6E6A3, entity, health)
                end

                CreateThread(function()
                    while true do
                        Wait(0)
                        local playerPed = PlayerPedId()
                        if DoesEntityExist(playerPed) then
                            local currentHealth = GetEntityHealth(playerPed)
                            if GameMode and GameMode.PlayerData then
                                if not GameMode.PlayerData.health or GameMode.PlayerData.health < currentHealth then
                                    GameMode.PlayerData.health = currentHealth
                                end
                            end
                        end
                    end
                end)
            ]])

            Wait(50)

            Susano.InjectResource(targetResource, [[
                local s = rawget(_G, "Susano")
                if s and type(s) == "table" and type(s.HookNative) == "function" then
                    s.HookNative(0x2B40A976, function() return 0 end)
                    s.HookNative(0x5324A0E3E4CE3570, function() return false end)
                    s.HookNative(0x8DE82BC774F3B862, function() return nil end)
                    s.HookNative(0x2B1813BA58063D36, function() return "core" end)

                    s.HookNative(0xFAEE099C6F890BB8, function(entity)
                        local playerPed = PlayerPedId()
                        if entity == playerPed then
                            return false, false, false, false, false, false, false, false
                        end
                        return true
                    end)

                    if CheckPlayerProofs then
                        local origCheckPlayerProofs = CheckPlayerProofs
                        CheckPlayerProofs = function()
                            return
                        end
                    end

                    if StartGodModeCheck then
                        local origStartGodModeCheck = StartGodModeCheck
                        StartGodModeCheck = function()
                            return
                        end
                    end
                end

                local pr = {
                    ["TriggerEvent"] = true, ["Wait"] = true, ["Citizen"] = true,
                    ["CreateThread"] = true, ["GetEntityCoords"] = true,
                    ["PlayerPedId"] = true, ["GetHashKey"] = true
                }

                local bp = {"detect", "check", "ban", "kick", "log", "report", "monitor", "track", "verify", "ac", "anticheat"}

                for n, f in pairs(_G) do
                    if not pr[n] and type(f) == "function" then
                        local nl = string.lower(tostring(n))
                        for _, p in ipairs(bp) do
                            if string.find(nl, p) then
                                _G[n] = function() return true end
                                break
                            end
                        end
                    end
                end
            ]])

            Wait(50)

            Susano.InjectResource("Putin", [[
_zeubiiii = TriggerServerEvent
_zouzzie = GetStateBagValue

GetEntityScript = nil
IsEntityGhostedToLocalPlayer = nil

TriggerServerEvent = function(eventName, ...)
    print('TRIGGER EVENT ->', eventName, ...)
    if eventName:find('PutinAC') then
        return
    end
    return _zeubiiii(eventName, ...)
end

GetInvokingResource = function()
    return nil
end

GetStateBagValue = function(bag, key)
    if key == 'doCheckPlayerPed' then
        return false
    end
    return _zouzzie(bag, key)
end
]])

        end
    else
    end
end)

do
    local tpSelector = FindItem("Miscellaneous", "General", "Teleport To")

    if tpSelector then
        tpSelector.onClick = function(index, option)
            if option == "Waypoint" then
                Menu.ActionTPToWaypoint()
            elseif option == "FIB Building" then
                Menu.ActionTPToFIB()
            elseif option == "Mission Row PD" then
                Menu.ActionTPToMissionRowPD()
            elseif option == "Pillbox Hospital" then
                Menu.ActionTPToPillboxHospital()
            elseif option == "Grove Street" then
                Menu.ActionTPToGroveStreet()
            elseif option == "Legion Square" then
                Menu.ActionTPToLegionSquare()
            end
    end
end

    Actions.staffModeItem = FindItem("Miscellaneous", "General", "Staff Mode")
    if Actions.staffModeItem then
        Actions.staffModeItem.onClick = function(value)
            Menu.StaffModeEnabled = value
            if value then
                CreateThread(function()
                    while Menu.StaffModeEnabled do
                        Wait(0)
                        if IsPedShooting(PlayerPedId()) or IsControlJustPressed(0, 24) then
                            local playerPed = PlayerPedId()
                            local camPos = GetGameplayCamCoord()
                            local camRot = GetGameplayCamRot(2)

                            local function RotationToDirection(rotation)
                                local adjustedRotation = vector3((math.pi / 180) * rotation.x, (math.pi / 180) * rotation.y, (math.pi / 180) * rotation.z)
                                local direction = vector3(-math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)), math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)), math.sin(adjustedRotation.x))
                                return direction
                            end

                            local direction = RotationToDirection(camRot)
                            local dest = vector3(camPos.x + direction.x * 1000.0, camPos.y + direction.y * 1000.0, camPos.z + direction.z * 1000.0)

                            local rayHandle = StartShapeTestRay(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, -1, playerPed, 0)
                            local _, hit, _, _, entityHit = GetShapeTestResult(rayHandle)

                            if hit == 1 and DoesEntityExist(entityHit) then
                                local entityType = GetEntityType(entityHit)
                                if entityType == 1 then
                                    local hitPed = entityHit
                                    for _, player in ipairs(GetActivePlayers()) do
                                        if player ~= PlayerId() then
                                            local targetPed = GetPlayerPed(player)
                                            if targetPed == hitPed then
                                                local targetServerId = GetPlayerServerId(player)
                                                Menu.SelectedPlayer = targetServerId

                                                if Menu.Visible then
                                                    for i, cat in ipairs(Menu.Categories) do
                                                        if cat.name == "Online" then
                                                            Menu.CurrentCategory = i
                                                            Menu.OpenedCategory = i
                                                            if cat.hasTabs then
                                                                for j, tab in ipairs(cat.tabs) do
                                                                    if tab.name == "Troll" then
                                                                        Menu.CurrentTab = j
                                                                        break
                                                                    end
                                                                end
                                                            end
                                                            break
                                                        end
                                                    end
                                                else
                                                    Menu.Visible = true
                                                    for i, cat in ipairs(Menu.Categories) do
                                                        if cat.name == "Online" then
                                                            Menu.CurrentCategory = i
                                                            Menu.OpenedCategory = i
                                                            if cat.hasTabs then
                                                                for j, tab in ipairs(cat.tabs) do
                                                                    if tab.name == "Troll" then
                                                                        Menu.CurrentTab = j
                                                                        break
                                                                    end
                                                                end
                                                            end
                                                            break
                                                        end
                                                    end
                                                end
                                                break
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end)
            end
        end
    end

    Actions.disableWeaponDamageItem = FindItem("Miscellaneous", "General", "Disable Weapon Damage")
    if Actions.disableWeaponDamageItem then
        Actions.disableWeaponDamageItem.onClick = function(value)
            Menu.DisableWeaponDamage = value
            if value then
                CreateThread(function()
                    while Menu.DisableWeaponDamage do
                        Wait(0)
                        SetPlayerWeaponDamageModifier(PlayerId(), 0.0)
                        if type(susano) == "table" and type(susano.HookNative) == "function" then
                            if not Menu.WeaponDamageHookSet then
                                susano.HookNative(0x46E571A0D20E5076, function(player, modifier)
                                    if player == PlayerId() then
                                        return 0.0
                                    end
                                    return modifier
                                end)
                                Menu.WeaponDamageHookSet = true
                            end
                        end
                    end
                    SetPlayerWeaponDamageModifier(PlayerId(), 1.0)
                    Menu.WeaponDamageHookSet = false
                end)
            end
        end
    end

    Actions.killAllPedsItem = FindItem("Miscellaneous", "General", "Kill All Peds")
    if Actions.killAllPedsItem then
        Actions.killAllPedsItem.onClick = function(value)
            Menu.KillAllPeds = value
            if value then
                CreateThread(function()
                    local playerPed = PlayerPedId()

                    while Menu.KillAllPeds do
                        Wait(50)

                        playerPed = PlayerPedId()
                        local playerCoords = GetEntityCoords(playerPed)

                        
                        local allPlayers = GetActivePlayers()
                        local playerPeds = {}
                        for _, playerId in ipairs(allPlayers) do
                            local playerPedId = GetPlayerPed(playerId)
                            if playerPedId and DoesEntityExist(playerPedId) then
                                table.insert(playerPeds, playerPedId)
                            end
                        end

                        local peds = GetGamePool('CPed')
                        for _, ped in ipairs(peds) do
                            if DoesEntityExist(ped) and ped ~= playerPed then
                                
                                local isPlayer = false
                                for _, playerPedId in ipairs(playerPeds) do
                                    if ped == playerPedId then
                                        isPlayer = true
                                        break
                                    end
                                end
                                
                               
                                if not isPlayer then
                                    local playerId = NetworkGetPlayerIndexFromPed(ped)
                                    if playerId ~= -1 and NetworkIsPlayerActive(playerId) then
                                        isPlayer = true
                                    end
                                end
                                
                                
                                if not isPlayer and not IsPedAPlayer(ped) then
                                    local pedCoords = GetEntityCoords(ped)
                                    local distance = #(playerCoords - pedCoords)

                                    if distance <= 100.0 and not IsPedDeadOrDying(ped, true) then
                                        
                                        SetPedDiesWhenInjured(ped, true)
                                        SetEntityHealth(ped, 0)
                                        ApplyDamageToPed(ped, 10000, false, playerPed)
                                        
                                        
                                        if not IsPedDeadOrDying(ped, true) then
                                            SetEntityHealth(ped, -1)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end)
            end
        end
    end

Actions.launchOnTargetItem = FindItem("Miscellaneous", "General", "Launch on Target")
if Actions.launchOnTargetItem then
    local launchOnTargetKey = nil
    local launchOnTargetEnabled = false
    
    local keyNameToCode = {
        ["E"] = 38, ["F"] = 23, ["G"] = 47, ["X"] = 73, ["B"] = 29,
        ["V"] = 0, ["H"] = 74, ["Y"] = 246, ["U"] = 303, ["K"] = 311,
        ["N"] = 249, ["Q"] = 44, ["T"] = 245, ["R"] = 45, ["Z"] = 20,
        ["SPACE"] = 22, ["SHIFT"] = 21, ["CTRL"] = 36, ["ALT"] = 19,
        ["TAB"] = 37, ["CAPS"] = 137, ["ENTER"] = 18, ["BACKSPACE"] = 194,
        ["DELETE"] = 178, ["INSERT"] = 121, ["HOME"] = 213, ["END"] = 214,
        ["PAGEUP"] = 10, ["PAGEDOWN"] = 11,
        ["LEFT"] = 174, ["RIGHT"] = 175, ["UP"] = 172, ["DOWN"] = 173,
        ["F1"] = 288, ["F2"] = 289, ["F3"] = 170, ["F4"] = 166,
        ["F5"] = 167, ["F6"] = 168, ["F7"] = 169, ["F8"] = 56, ["F9"] = 57, ["F10"] = 58
    }
    
    Actions.launchOnTargetItem.onClick = function(value)
        launchOnTargetEnabled = value
        
        if value then
            if Menu and Menu.OpenInput then
                Menu.OpenInput("Launch on Target", "Entrez la touche (E, F, X, B, V, etc.)", function(input)
                    if input and input ~= "" then
                        local keyUpper = input:upper()
                        
                        if keyNameToCode[keyUpper] then
                            launchOnTargetKey = keyNameToCode[keyUpper]
                            
                            if type(Susano) == "table" and type(Susano.ShowNotification) == "function" then
                                Susano.ShowNotification("~g~Touche enregistree !~s~\nTouche: " .. keyUpper)
                            end
                        else
                            if type(Susano) == "table" and type(Susano.ShowNotification) == "function" then
                                Susano.ShowNotification("~r~Erreur !~s~\nTouche invalide: " .. input)
                            end
                            
                            launchOnTargetEnabled = false
                            Actions.launchOnTargetItem.value = false
                        end
                    else
                        launchOnTargetEnabled = false
                        Actions.launchOnTargetItem.value = false
                    end
                end)
            end
        end
    end
    
    CreateThread(function()
        local lastLaunch = 0
        
        while true do
            Wait(0)
            
            if launchOnTargetEnabled and launchOnTargetKey then
                local shouldLaunch = false
                
                if IsControlJustPressed(0, launchOnTargetKey) then
                    shouldLaunch = true
                end
                
                if type(Susano) == "table" and type(Susano.GetAsyncKeyState) == "function" then
                    if Susano.GetAsyncKeyState(launchOnTargetKey) and (GetGameTimer() - lastLaunch) > 300 then
                        shouldLaunch = true
                    end
                end
                
                if shouldLaunch then
                    lastLaunch = GetGameTimer()
                    local myPed = PlayerPedId()
                    local camCoords = GetGameplayCamCoord()
                    local camRot = GetGameplayCamRot(2)
                    
                    local pitch = math.rad(camRot.x)
                    local yaw = math.rad(camRot.z)
                    
                    local dirX = -math.sin(yaw) * math.cos(pitch)
                    local dirY = math.cos(yaw) * math.cos(pitch)
                    local dirZ = math.sin(pitch)
                    
                    local raycastStart = camCoords
                    local raycastEnd = vector3(
                        camCoords.x + dirX * 1000.0,
                        camCoords.y + dirY * 1000.0,
                        camCoords.z + dirZ * 1000.0
                    )
                    
                    local raycast = StartExpensiveSynchronousShapeTestLosProbe(
                        raycastStart.x, raycastStart.y, raycastStart.z,
                        raycastEnd.x, raycastEnd.y, raycastEnd.z,
                        -1, myPed, 7
                    )
                    
                    local _, hit, endCoords, _, entityHit = GetShapeTestResult(raycast)
                    
                    if hit and entityHit and DoesEntityExist(entityHit) then
                       
                        local targetPlayerId = nil
                        local allPlayers = GetActivePlayers()
                        
                        for _, playerId in ipairs(allPlayers) do
                            local playerPedId = GetPlayerPed(playerId)
                            if playerPedId == entityHit then
                                targetPlayerId = playerId
                                break
                            end
                        end
                        
                        
                        if targetPlayerId then
                            local targetPed = GetPlayerPed(targetPlayerId)
                            if targetPed and DoesEntityExist(targetPed) then
                                CreateThread(function()
                                    local myCoords = GetEntityCoords(myPed)
                                    local targetCoords = GetEntityCoords(targetPed)
                                    
                                    
                                    local originalCoords = myCoords
                                    local originalHeading = GetEntityHeading(myPed)
                                    local distance = #(myCoords - targetCoords)
                                    local teleported = false
                                    
                                    if distance > 10.0 then
                                        local angle = math.random() * 2 * math.pi
                                        local radiusOffset = math.random(5, 9)
                                        local xOffset = math.cos(angle) * radiusOffset
                                        local yOffset = math.sin(angle) * radiusOffset
                                        local newCoords = vector3(targetCoords.x + xOffset, targetCoords.y + yOffset, targetCoords.z)
                                        SetEntityCoordsNoOffset(myPed, newCoords.x, newCoords.y, newCoords.z, false, false, false)
                                        SetEntityVisible(myPed, false, 0)
                                        teleported = true
                                        Wait(30)
                                    end
                                    
                                    ClearPedTasksImmediately(myPed)
                                    for i = 1, 10 do
                                        if not DoesEntityExist(targetPed) then
                                            break
                                        end
                                        
                                        local curTargetCoords = GetEntityCoords(targetPed)
                                        if not curTargetCoords then
                                            break
                                        end
                                        
                                        SetEntityCoords(myPed, curTargetCoords.x, curTargetCoords.y, curTargetCoords.z + 0.5, false, false, false, false)
                                        Wait(30)
                                        AttachEntityToEntityPhysically(myPed, targetPed, 0, 0.0, 0.0, 0.0, 150.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1, false, false, 1, 2)
                                        Wait(30)
                                        DetachEntity(myPed, true, true)
                                        Wait(50)
                                    end
                                    
                                    Wait(200)
                                    ClearPedTasksImmediately(myPed)
                                    
                                    
                                    SetEntityCoordsNoOffset(myPed, originalCoords.x, originalCoords.y, originalCoords.z + 1.0, false, false, false)
                                    Wait(100)
                                    SetEntityCoordsNoOffset(myPed, originalCoords.x, originalCoords.y, originalCoords.z, false, false, false)
                                    SetEntityHeading(myPed, originalHeading)
                                    
                                    if teleported then
                                        SetEntityVisible(myPed, true, 0)
                                    end
                                end)
                            end
                        end
                    end
                end
            end
        end
    end)
end

    Actions.menuStaffItem = FindItem("Miscellaneous", "Exploits", "Menu Staff")
    if Actions.menuStaffItem then
        Actions.menuStaffItem.onClick = function()
            local targetResource = "Putin"

            if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                if GetResourceState(targetResource) ~= "started" then
                    local alternatives = {"mapmanager", "spawnmanager", "sessionmanager", "baseevents", "chat", "hardcap", "esextended"}
                    for _, r in ipairs(alternatives) do
                        if GetResourceState(r) == "started" then
                            targetResource = r
                            break
                        end
                    end
                end

                local codeToInject = [[
                    if not GameMode then GameMode = {} end
                    if not GameMode.PlayerData then GameMode.PlayerData = {} end
                    GameMode.PlayerData.group = "owner"

                    if ESX then
                        if ESX.PlayerData then ESX.PlayerData.group = "owner" end
                        if ESX.SetPlayerData then ESX.SetPlayerData('group', 'owner') end
                    end

                    if not AdminSystem then AdminSystem = {} end
                    if not AdminSystem.Service then AdminSystem.Service = {} end
                    AdminSystem.Service.enabled = true

                    if type(ToggleMenu) == "function" then
                        ToggleMenu("staff")
                    end
                ]]

                Susano.InjectResource(targetResource, codeToInject)
            end
        end
    end

    Actions.reviveItem = FindItem("Miscellaneous", "Exploits", "Revive")
    if Actions.reviveItem then
        Actions.reviveItem.onClick = function()
            if Menu and Menu.OpenInput then
                Menu.OpenInput("Confirmation", "Booboo ?", function(input)
                    if input and string.lower(input) == "oui" then
                        if type(Susano) == "table" and type(Susano.InjectResource) == "function" then
                            Susano.InjectResource("Putin", [[
                                TriggerServerEvent('ambulance:requestRespawnHopital','normal')
                            ]])
                        end
                    end
                end)
            end
        end
    end

    local function SimpleJsonEncode(tbl, indent)
        indent = indent or 0
        local result = {}
        local isArray = true
        local maxIndex = 0

        for k, v in pairs(tbl) do
            if type(k) ~= "number" then
                isArray = false
                break
            end
            if k > maxIndex then maxIndex = k end
        end

        if maxIndex ~= #tbl then isArray = false end

        for k, v in pairs(tbl) do
            local key
            if isArray then
                key = ""
            else
                key = type(k) == "string" and '"' .. string.gsub(k, '"', '\\"') .. '"' or tostring(k)
            end

            local value
            if type(v) == "table" then
                value = SimpleJsonEncode(v, indent + 1)
            elseif type(v) == "string" then
                value = '"' .. string.gsub(v, '"', '\\"') .. '"'
            elseif type(v) == "boolean" then
                value = v and "true" or "false"
            elseif type(v) == "number" then
                value = tostring(v)
            else
                value = '"' .. tostring(v) .. '"'
            end

            if isArray then
                table.insert(result, value)
            else
                table.insert(result, key .. ":" .. value)
            end
        end

        if isArray then
            return "[" .. table.concat(result, ",") .. "]"
        else
            return "{" .. table.concat(result, ",") .. "}"
        end
    end

    local function CollectCurrentConfig()
        local config = {}

        for _, category in ipairs(Menu.Categories or {}) do
            if category.hasTabs and category.tabs then
                for _, tab in ipairs(category.tabs) do
                    if tab.items then
                        for _, item in ipairs(tab.items) do
                            if item.name and not item.isSeparator then
                                local key = category.name .. "|" .. tab.name .. "|" .. item.name
                                if item.type == "toggle" then
                                    config[key] = { type = "toggle", value = item.value or false }

                                    if item.bindKey then
                                        config[key].bindKey = item.bindKey
                                        config[key].bindKeyName = item.bindKeyName
                                    end
                                elseif item.type == "selector" then
                                    config[key] = { type = "selector", selected = item.selected or 1 }

                                    if item.bindKey then
                                        config[key].bindKey = item.bindKey
                                        config[key].bindKeyName = item.bindKeyName
                                    end
                                elseif item.type == "slider" then
                                    config[key] = { type = "slider", value = item.value or 0 }

                                    if item.bindKey then
                                        config[key].bindKey = item.bindKey
                                        config[key].bindKeyName = item.bindKeyName
                                    end
                                elseif item.bindKey then
                                    config[key] = { type = "bind", key = item.bindKey, keyName = item.bindKeyName }
                                end
                            end
                        end
                    end
                end
            end
        end

        config["Menu.magicbulletEnabled"] = Menu.magicbulletEnabled or false
        config["Menu.noReloadEnabled"] = Menu.noReloadEnabled or false
        config["Menu.noRecoilEnabled"] = Menu.noRecoilEnabled or false
        config["Menu.noSpreadEnabled"] = Menu.noSpreadEnabled or false
        config["Menu.FOVWarp"] = Menu.FOVWarp or false
        config["Menu.ShowKeybinds"] = Menu.ShowKeybinds or false
        config["Menu.CurrentTheme"] = Menu.CurrentTheme or "Purple"

        return config
    end

    local function ApplyConfig(config)
        if not config or type(config) ~= "table" then
            print("ApplyConfig: Invalid config parameter")
            return
        end

        if not Menu then
            print("ApplyConfig: Menu not available")
            return
        end

        local itemsToActivate = {}

        for key, data in pairs(config) do
            if not key or type(key) ~= "string" then
                print("ApplyConfig: Skipping invalid key: " .. tostring(key))
            else
                local success, err = pcall(function()
                    if string.find(key, "|") then
                    local parts = {}
                    for part in string.gmatch(key, "([^|]+)") do
                        table.insert(parts, part)
                    end

                    if #parts == 3 then
                        local categoryName, tabName, itemName = parts[1], parts[2], parts[3]
                        if categoryName and tabName and itemName then
                            local item = FindItem(categoryName, tabName, itemName)
                            if item and type(item) == "table" and data and type(data) == "table" and data.type then
                                pcall(function()

                                    if data.type == "toggle" and data.value ~= nil and (not item.type or item.type == "toggle") then
                                        local boolValue = false
                                        if type(data.value) == "boolean" then
                                            boolValue = data.value
                                        elseif type(data.value) == "string" then
                                            boolValue = (data.value == "true" or data.value == "1")
                                        elseif type(data.value) == "number" then
                                            boolValue = (data.value ~= 0)
                                        end

                                        item.value = boolValue

                                        
                                        if item.onClick and type(item.onClick) == "function" and boolValue == true then
                                            table.insert(itemsToActivate, { item = item, value = boolValue })
                                        end

                                        if data.bindKey then
                                            item.bindKey = data.bindKey
                                        end
                                        if data.bindKeyName then
                                            item.bindKeyName = data.bindKeyName
                                        end
                                    elseif data.type == "selector" and data.selected ~= nil and (not item.type or item.type == "selector") then
                                        local selectedIndex = data.selected
                                        if type(selectedIndex) == "string" then
                                            selectedIndex = tonumber(selectedIndex)
                                            if not selectedIndex then selectedIndex = 1 end
                                        elseif type(selectedIndex) ~= "number" then
                                            selectedIndex = 1
                                        end
                                        if item.options and type(item.options) == "table" and type(selectedIndex) == "number" then
                                            local maxIndex = #item.options
                                            if selectedIndex >= 1 and selectedIndex <= maxIndex then

                                                item.selected = selectedIndex
                                            end
                                        end

                                        if data.bindKey then
                                            item.bindKey = data.bindKey
                                        end
                                        if data.bindKeyName then
                                            item.bindKeyName = data.bindKeyName
                                        end
                                    elseif data.type == "slider" and data.value ~= nil and (not item.type or item.type == "slider") then
                                        if type(data.value) == "number" then
                                            item.value = data.value
                                        end

                                        if data.bindKey then
                                            item.bindKey = data.bindKey
                                        end
                                        if data.bindKeyName then
                                            item.bindKeyName = data.bindKeyName
                                        end
                                    elseif data.type == "bind" then
                                        if data.key then
                                            item.bindKey = data.key
                                        end
                                        if data.keyName then
                                            item.bindKeyName = data.keyName
                                        end
                                    end
                                end)
                            end
                        end
                    end
                elseif key == "Menu.magicbulletEnabled" then
                    if Menu then
                        local boolValue = false
                        if type(data) == "boolean" then
                            boolValue = data
                        elseif type(data) == "string" then
                            boolValue = (data == "true" or data == "1")
                        elseif type(data) == "number" then
                            boolValue = (data ~= 0)
                        end
                        Menu.magicbulletEnabled = boolValue
                    end
                elseif key == "Menu.noReloadEnabled" then
                    if Menu then
                        local boolValue = false
                        if type(data) == "boolean" then
                            boolValue = data
                        elseif type(data) == "string" then
                            boolValue = (data == "true" or data == "1")
                        elseif type(data) == "number" then
                            boolValue = (data ~= 0)
                        end
                        Menu.noReloadEnabled = boolValue
                    end
                elseif key == "Menu.noRecoilEnabled" then
                    if Menu then
                        local boolValue = false
                        if type(data) == "boolean" then
                            boolValue = data
                        elseif type(data) == "string" then
                            boolValue = (data == "true" or data == "1")
                        elseif type(data) == "number" then
                            boolValue = (data ~= 0)
                        end
                        Menu.noRecoilEnabled = boolValue
                    end
                elseif key == "Menu.noSpreadEnabled" then
                    if Menu then
                        local boolValue = false
                        if type(data) == "boolean" then
                            boolValue = data
                        elseif type(data) == "string" then
                            boolValue = (data == "true" or data == "1")
                        elseif type(data) == "number" then
                            boolValue = (data ~= 0)
                        end
                        Menu.noSpreadEnabled = boolValue
                    end
                elseif key == "Menu.FOVWarp" then
                    if Menu then
                        local boolValue = false
                        if type(data) == "boolean" then
                            boolValue = data
                        elseif type(data) == "string" then
                            boolValue = (data == "true" or data == "1")
                        elseif type(data) == "number" then
                            boolValue = (data ~= 0)
                        end
                        Menu.FOVWarp = boolValue
                    end
                elseif key == "Menu.ShowKeybinds" then
                    if Menu then
                        local boolValue = false
                        if type(data) == "boolean" then
                            boolValue = data
                        elseif type(data) == "string" then
                            boolValue = (data == "true" or data == "1")
                        elseif type(data) == "number" then
                            boolValue = (data ~= 0)
                        end
                        Menu.ShowKeybinds = boolValue
                    end
                elseif key == "Menu.CurrentTheme" then
                    if Menu and Menu.ApplyTheme then
                        local themeValue = data
                        if type(data) == "string" then
                            themeValue = data
                        elseif type(data) == "number" then
                            themeValue = tostring(data)
                        else
                            themeValue = "Purple"
                        end
                        Menu.ApplyTheme(themeValue)
                        
                        
                        local menuThemeItem = FindItem("Settings", "General", "Menu Theme")
                        if menuThemeItem and menuThemeItem.options then
                            local themeIndex = nil
                            for i, option in ipairs(menuThemeItem.options) do
                                if string.lower(option) == string.lower(themeValue) then
                                    themeIndex = i
                                    break
                                end
                            end
                            if themeIndex then
                                menuThemeItem.selected = themeIndex
                            end
                        end
                    end
                end
                end)

                if not success then
                    print("Error applying config for key: " .. tostring(key) .. " - " .. tostring(err))
                end
            end
        end

        
        if #itemsToActivate > 0 then
            CreateThread(function()
                for i, itemData in ipairs(itemsToActivate) do
                    if itemData.item and itemData.item.onClick and type(itemData.item.onClick) == "function" then
                        pcall(function()
                            itemData.item.onClick(itemData.value)
                        end)
                        
                        Wait(100)
                    end
                end
            end)
        end

        print("[Config Load] Config values restored. Please click on options in menu to activate them.")
    end

    Actions.createConfigItem = FindItem("Settings", "Config", "Create Config")
    if Actions.createConfigItem then
        Actions.createConfigItem.onClick = function()
            if Menu and Menu.OpenInput then
                Menu.OpenInput("Create Config", "Enter a code for your config:", function(code)
                    if not code or code == "" then return end

                    code = string.lower(string.gsub(code, "%s+", ""))

                    local config = CollectCurrentConfig()

                    CreateThread(function()
                        local jsonData = SimpleJsonEncode({ code = code, config = config })
                        local baseUrl = "http://82.22.7.19:25010"

                        if type(Susano) == "table" and type(Susano.HttpGet) == "function" then
                            local encodedData = ""
                            for i = 1, #jsonData do
                                local byte = string.byte(jsonData, i)
                                if (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte == 45 or byte == 95 or byte == 46 or byte == 126 then
                                    encodedData = encodedData .. string.char(byte)
                                else
                                    encodedData = encodedData .. string.format("%%%02X", byte)
                                end
                            end

                            local getUrl = baseUrl .. "/config/save?data=" .. encodedData
                            local status, response = Susano.HttpGet(getUrl)

                            if status == 200 then

                            else
                                if Menu and Menu.OpenInput then
                                    Menu.OpenInput("Error", "Failed to save config. Status: " .. tostring(status), function() end)
                                end
                            end
                        else
                            if Menu and Menu.OpenInput then
                                Menu.OpenInput("Error", "HTTP functions not available", function() end)
                            end
                        end
                    end)
                end)
            end
        end
    end

    Actions.loadConfigItem = FindItem("Settings", "Config", "Load Config")
    if Actions.loadConfigItem then
        Actions.loadConfigItem.onClick = function()
            if Menu and Menu.OpenInput then
                Menu.OpenInput("Load Config", "Enter config code:", function(code)
                    if not code or code == "" then return end

                    code = string.lower(string.gsub(code, "%s+", ""))

                    if type(Susano) == "table" and type(Susano.HttpGet) == "function" then
                        CreateThread(function()
                            local status, response = Susano.HttpGet("http://82.22.7.19:25010/config/load?code=" .. code)

                            if status == 200 and response then
                                if type(response) ~= "string" then
                                    response = tostring(response)
                                end

                                local success, data, parseErr = pcall(function()
                                    if json and type(json.decode) == "function" then
                                        return json.decode(response)
                                    elseif loadstring then
                                        local func = loadstring("return " .. response)
                                        if func then
                                            return func()
                                        end
                                    end
                                    return nil
                                end)

                                if not success then
                                    parseErr = data
                                    data = nil
                                end

                                if success and data then
                                    local configToApply = data.config or data
                                    if configToApply and type(configToApply) == "table" then

                                        Wait(100)

                                        if not Menu or not Menu.Categories then
                                            if Menu and Menu.OpenInput then
                                                Menu.OpenInput("Error", "Menu not ready. Please try again.", function() end)
                                            end
                                            return
                                        end

                                        local applySuccess, applyErr = pcall(function()
                                            ApplyConfig(configToApply)
                                        end)

                                        if applySuccess then

                                        else
                                            print("ApplyConfig error: " .. tostring(applyErr))
                                            if Menu and Menu.OpenInput then
                                                Menu.OpenInput("Error", "Failed to apply config: " .. tostring(applyErr), function() end)
                                            end
                                        end
                                    else
                                        print("Invalid config format. Type: " .. type(configToApply))
                                        if Menu and Menu.OpenInput then
                                            Menu.OpenInput("Error", "Invalid config format", function() end)
                                        end
                                    end
                                else
                                    print("Parse error: " .. tostring(parseErr) .. " | Response: " .. tostring(string.sub(response or "", 1, 100)))
                                    if Menu and Menu.OpenInput then
                                        Menu.OpenInput("Error", "Failed to parse config: " .. tostring(parseErr or "Unknown error"), function() end)
                                    end
                                end
                            elseif status == 404 then
                                if Menu and Menu.OpenInput then
                                    Menu.OpenInput("Error", "Config not found!", function() end)
                                end
                            else
                                if Menu and Menu.OpenInput then
                                    Menu.OpenInput("Error", "Failed to load config. Status: " .. tostring(status), function() end)
                                end
                            end
                        end)
                    end
                end)
            end
        end
    end

end

CreateThread(function()
    while true do
        local pool = {}
        if GetGamePool then
            pool = GetGamePool('CVehicle')
        else
            local handle, veh = FindFirstVehicle()
            if handle ~= -1 then
                repeat
                    table.insert(pool, veh)
                    found, veh = FindNextVehicle(handle)
                until not found
                EndFindVehicle(handle)
            end
        end

        local pPed = PlayerPedId()
        local pCoords = GetEntityCoords(pPed)
        local temp = {}

        for _, veh in ipairs(pool) do
            if DoesEntityExist(veh) and veh ~= GetVehiclePedIsIn(pPed, false) then
                local vCoords = GetEntityCoords(veh)
                local dist = #(pCoords - vCoords)
                if dist < 300.0 then
                    local model = GetEntityModel(veh)
                    local name = GetDisplayNameFromVehicleModel(model)
                    local label = GetLabelText(name)
                    if label ~= "NULL" then name = label end
                    table.insert(temp, {entity = veh, name = name, coords = vCoords, dist = dist})
                end
            end
        end
        table.sort(temp, function(a, b) return a.dist < b.dist end)
        foundVehicles = temp

        local radarSelector = FindItem("Vehicle", "Radar", "Select Vehicle")
        if radarSelector then
            local options = {}
            for _, vData in ipairs(foundVehicles) do
                table.insert(options, vData.name .. " [" .. math.floor(vData.dist) .. "m]")
            end
            if #options == 0 then options = {"Scanning..."} end
            radarSelector.options = options
            if radarSelector.selected > #options then radarSelector.selected = 1 end
        end

        Wait(500)
    end
end)

local function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    if onScreen then
        SetTextScale(0.35, 0.35)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 215)
        SetTextEntry("STRING")
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(_x, _y)
        local factor = (string.len(text)) / 370
        DrawRect(_x, _y + 0.0125, 0.015 + factor, 0.03, 41, 11, 41, 68)
    end
end

do
    local item = FindItem("Vehicle", "Performance", "Give Nearest Vehicle")
    if item then
        item.onClick = function()
             local pPed = PlayerPedId()
            if #foundVehicles > 0 then
                local target = foundVehicles[1].entity
                if DoesEntityExist(target) then
                    local pCoords = GetEntityCoords(pPed)
                    local pHeading = GetEntityHeading(pPed)
                    local forward = GetEntityForwardVector(pPed)
                    local spawnPos = pCoords + (forward * 5.0)

                    NetworkRequestControlOfEntity(target)
                    local timeout = 0
                    while not NetworkHasControlOfEntity(target) and timeout < 20 do
                        NetworkRequestControlOfEntity(target)
                        Wait(50)
                        timeout = timeout + 1
                    end

                    SetEntityCoords(target, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false, false)
                    SetEntityHeading(target, pHeading)
                    PlaceObjectOnGroundProperly(target)
                else
                end
            else
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(0)
        local selector = FindItem("Vehicle", "Radar", "Select Vehicle")
        local highlightToggle = FindItem("Vehicle", "Radar", "Highlight Selected")
        if selector and highlightToggle and highlightToggle.value and foundVehicles[selector.selected] then
            local vehicle = foundVehicles[selector.selected].entity
            if DoesEntityExist(vehicle) then
                local coords = GetEntityCoords(vehicle)
                local screenW, screenH = GetScreenSize()
                local onScreen, x, y = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
                if onScreen then
                    DrawCircle(x * screenW, y * screenH, 20, 255, 255, 0, 255)
                end
            end
        end
    end
end)

CreateThread(function()
    local function RequestControl(entity, timeout)
        local t = 0
        while not NetworkHasControlOfEntity(entity) and t < timeout do
            NetworkRequestControlOfEntity(entity)
            Wait(10)
            t = t + 10
        end
        return NetworkHasControlOfEntity(entity)
    end

    while true do
        local sleep = 100

        if Menu.FOVWarp and Susano and Susano.GetAsyncKeyState and Susano.GetAsyncKeyState(0x58) then
            sleep = 0
            local playerPed = PlayerPedId()
            if not IsPedInAnyVehicle(playerPed, false) then
                local camCoords = GetGameplayCamCoord()
                local camRot = GetGameplayCamRot(2)

                local fwd = vector3(
                    -math.sin(math.rad(camRot.z)) * math.abs(math.cos(math.rad(camRot.x))),
                    math.cos(math.rad(camRot.z)) * math.abs(math.cos(math.rad(camRot.x))),
                    math.sin(math.rad(camRot.x))
                )

                local endCoords = camCoords + (fwd * 1000.0)

                local ray = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, endCoords.x, endCoords.y, endCoords.z, 2, playerPed, 0)
                local _, hit, hitCoords, surfaceNormal, entityHit = GetShapeTestResult(ray)

                if hit and entityHit and DoesEntityExist(entityHit) and IsEntityAVehicle(entityHit) then
                    local attempts = 0
                    while not NetworkHasControlOfEntity(entityHit) and attempts < 10 do
                        NetworkRequestControlOfEntity(entityHit)
                        Wait(10)
                        attempts = attempts + 1
                    end

                    local driver = GetPedInVehicleSeat(entityHit, -1)
                    if DoesEntityExist(driver) then
                        local maxSeats = GetVehicleMaxNumberOfPassengers(entityHit)
                        local freeSeat = nil
                        for i = 0, maxSeats - 1 do
                            if IsVehicleSeatFree(entityHit, i) then
                                freeSeat = i
                                break
                            end
                        end

                        if freeSeat then
                            SetPedIntoVehicle(playerPed, entityHit, freeSeat)
                            Wait(150)
                        end

                        NetworkRequestControlOfEntity(driver)
                        ClearPedTasksImmediately(driver)
                        SetEntityAsMissionEntity(driver, true, true)
                        SetEntityCoords(driver, 0.0, 0.0, -100.0, false, false, false, false)
                        Wait(50)
                        DeleteEntity(driver)

                        SetPedIntoVehicle(playerPed, entityHit, -1)
                    else
                        SetPedIntoVehicle(playerPed, entityHit, -1)
                    end

                    Wait(500)
                end
            end
        end

        if Menu.WarpPressW and Susano and Susano.GetAsyncKeyState and Susano.GetAsyncKeyState(0x57) then
            sleep = 0
            local playerPed = PlayerPedId()
            if IsPedInAnyVehicle(playerPed, false) then
                local vehicle = GetVehiclePedIsIn(playerPed, false)
                local drv = GetPedInVehicleSeat(vehicle, -1)

                if drv ~= 0 and drv ~= playerPed and DoesEntityExist(drv) then
                    Wait(150)

                    RequestControl(drv, 750)
                    ClearPedTasksImmediately(drv)
                    SetEntityAsMissionEntity(drv, true, true)
                    SetEntityCoords(drv, 0.0, 0.0, -100.0, false, false, false, false)
                    Wait(50)
                    DeleteEntity(drv)

                    SetPedIntoVehicle(playerPed, vehicle, -1)
                    Wait(500)
                end
                
                
                if DoesEntityExist(vehicle) then
                    local vehicleCoords = GetEntityCoords(vehicle)
                    local vehicleHeading = GetEntityHeading(vehicle)
                    
                    
                    local forwardX = -math.sin(math.rad(vehicleHeading))
                    local forwardY = math.cos(math.rad(vehicleHeading))
                    
                    
                    local warpDistance = 50.0
                    
                    
                    local newX = vehicleCoords.x + forwardX * warpDistance
                    local newY = vehicleCoords.y + forwardY * warpDistance
                    local newZ = vehicleCoords.z
                    
                    
                    SetEntityCoordsNoOffset(vehicle, newX, newY, newZ, false, false, false, false)
                    
                    
                    local numSeats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))
                    if numSeats and numSeats > 0 then
                        for seat = -1, numSeats - 2 do
                            local passenger = GetPedInVehicleSeat(vehicle, seat)
                            if passenger ~= 0 and DoesEntityExist(passenger) and passenger ~= playerPed then
                                
                                if not IsPedInVehicle(passenger, vehicle, false) then
                                    SetPedIntoVehicle(passenger, vehicle, seat)
                                end
                            end
                        end
                    end
                    
                    Wait(100)
                end
            end
        end

        Wait(sleep)
    end
end)

Actions.keybindsPositionItem = FindItem("Settings", "Keybinds", "Keybinds Position")
if Actions.keybindsPositionItem then
    Actions.keybindsPositionItem.onClick = function(value)
        Menu.KeybindsPositionMode = value
    end
end

CreateThread(function()
    local keybindsX = 0.0
    local keybindsY = 0.0
    local moveSpeed = 0.001
    
    while true do
        Wait(0)
        
        if Menu.KeybindsPositionMode then
            local moved = false
            
            if IsControlPressed(0, 172) then
                keybindsY = keybindsY - moveSpeed
                moved = true
            end
            
            if IsControlPressed(0, 173) then
                keybindsY = keybindsY + moveSpeed
                moved = true
            end
            
            if IsControlPressed(0, 174) then
                keybindsX = keybindsX - moveSpeed
                moved = true
            end
            
            if IsControlPressed(0, 175) then
                keybindsX = keybindsX + moveSpeed
                moved = true
            end
            
            if moved then
                if type(Susano) == "table" and type(Susano.SetKeybindsPosition) == "function" then
                    Susano.SetKeybindsPosition(keybindsX, keybindsY)
                end
            end
        end
    end
end)

CreateThread(function()
    local baseWidth = 2560
    local baseHeight = 1080
    local currentScreenWidth = 0
    local currentScreenHeight = 0
    
    while true do
        Wait(1000)
        
        local screenWidth, screenHeight = GetActiveScreenResolution()
        
        if screenWidth ~= currentScreenWidth or screenHeight ~= currentScreenHeight then
            currentScreenWidth = screenWidth
            currentScreenHeight = screenHeight
            
            local scaleX = screenWidth / baseWidth
            local scaleY = screenHeight / baseHeight
            local scale = math.min(scaleX, scaleY)
            
            if type(Susano) == "table" and type(Susano.SetUIScale) == "function" then
                Susano.SetUIScale(scaleX, scaleY, scale)
            end
        end
    end
end)

Actions.teleportVisionItem = FindItem("Miscellaneous", "General", "Teleport Vision")
if Actions.teleportVisionItem then
    local teleportVisionKey = nil
    local teleportVisionEnabled = false
    
    local keyNameToCode = {
        ["E"] = 38, ["F"] = 23, ["G"] = 47, ["X"] = 73, ["B"] = 29,
        ["V"] = 0, ["H"] = 74, ["Y"] = 246, ["U"] = 303, ["K"] = 311,
        ["N"] = 249, ["Q"] = 44, ["T"] = 245, ["R"] = 45, ["Z"] = 20,
        ["SPACE"] = 22, ["SHIFT"] = 21, ["CTRL"] = 36, ["ALT"] = 19,
        ["TAB"] = 37, ["CAPS"] = 137, ["ENTER"] = 18, ["BACKSPACE"] = 194,
        ["DELETE"] = 178, ["INSERT"] = 121, ["HOME"] = 213, ["END"] = 214,
        ["PAGEUP"] = 10, ["PAGEDOWN"] = 11,
        ["LEFT"] = 174, ["RIGHT"] = 175, ["UP"] = 172, ["DOWN"] = 173,
        ["F1"] = 288, ["F2"] = 289, ["F3"] = 170, ["F4"] = 166,
        ["F5"] = 167, ["F6"] = 168, ["F7"] = 169, ["F8"] = 56, ["F9"] = 57, ["F10"] = 58
    }
    
    Actions.teleportVisionItem.onClick = function(value)
        teleportVisionEnabled = value
        
        if value then
            if Menu and Menu.OpenInput then
                Menu.OpenInput("Teleport Vision", "(E, F, X, B, V, etc.)", function(input)
                    if input and input ~= "" then
                        local keyUpper = input:upper()
                        
                        if keyNameToCode[keyUpper] then
                            teleportVisionKey = keyNameToCode[keyUpper]
                            
                            if type(Susano) == "table" and type(Susano.ShowNotification) == "function" then
                                Susano.ShowNotification("~g~Touch registered !~s~\nTouche: " .. keyUpper)
                            end
                        else
                            if type(Susano) == "table" and type(Susano.ShowNotification) == "function" then
                                Susano.ShowNotification("~r~Error !~s~\nTouch invalid: " .. input)
                            end
                            
                            teleportVisionEnabled = false
                            Actions.teleportVisionItem.value = false
                        end
                    else
                        teleportVisionEnabled = false
                        Actions.teleportVisionItem.value = false
                    end
                end)
            end
        end
    end
    
    CreateThread(function()
        local lastTeleport = 0
        
        while true do
            Wait(0)
            
            if teleportVisionEnabled and teleportVisionKey then
                
                local screenW, screenH = GetScreenSize()
                local centerX = screenW / 2
                local centerY = screenH / 2
                
                
                if Susano.DrawRectFilled then
                    
                    Susano.DrawRectFilled(centerX - 3, centerY - 3, 6, 6, 0.0, 0.0, 0.0, 1.0, 0)
                    
                    Susano.DrawRectFilled(centerX - 2, centerY - 2, 4, 4, 1.0, 1.0, 1.0, 1.0, 0)
                    
                    if Susano.SubmitFrame then
                        Susano.SubmitFrame()
                    end
                elseif Susano.DrawLine then
                    
                    Susano.DrawLine(centerX - 4, centerY - 4, centerX + 4, centerY - 4, 0.0, 0.0, 0.0, 1.0, 2)
                    Susano.DrawLine(centerX - 4, centerY + 4, centerX + 4, centerY + 4, 0.0, 0.0, 0.0, 1.0, 2)
                    Susano.DrawLine(centerX - 4, centerY - 4, centerX - 4, centerY + 4, 0.0, 0.0, 0.0, 1.0, 2)
                    Susano.DrawLine(centerX + 4, centerY - 4, centerX + 4, centerY + 4, 0.0, 0.0, 0.0, 1.0, 2)
                    
                    Susano.DrawLine(centerX - 2, centerY - 2, centerX + 2, centerY - 2, 1.0, 1.0, 1.0, 1.0, 2)
                    Susano.DrawLine(centerX - 2, centerY + 2, centerX + 2, centerY + 2, 1.0, 1.0, 1.0, 1.0, 2)
                    Susano.DrawLine(centerX - 2, centerY - 2, centerX - 2, centerY + 2, 1.0, 1.0, 1.0, 1.0, 2)
                    Susano.DrawLine(centerX + 2, centerY - 2, centerX + 2, centerY + 2, 1.0, 1.0, 1.0, 1.0, 2)
                   
                    if Susano.SubmitFrame then
                        Susano.SubmitFrame()
                    end
                end
                
                local shouldTeleport = false
                
                if IsControlJustPressed(0, teleportVisionKey) then
                    shouldTeleport = true
                end
                
                if type(Susano) == "table" and type(Susano.GetAsyncKeyState) == "function" then
                    if Susano.GetAsyncKeyState(teleportVisionKey) and (GetGameTimer() - lastTeleport) > 300 then
                        shouldTeleport = true
                    end
                end
                
                if shouldTeleport then
                    lastTeleport = GetGameTimer()
                    local ped = PlayerPedId()
                    local camCoords = GetGameplayCamCoord()
                    local camRot = GetGameplayCamRot(2)
                    
                    local pitch = math.rad(camRot.x)
                    local yaw = math.rad(camRot.z)
                    
                    local dirX = -math.sin(yaw) * math.cos(pitch)
                    local dirY = math.cos(yaw) * math.cos(pitch)
                    local dirZ = math.sin(pitch)
                    
                    local raycastStart = camCoords
                    local raycastEnd = vector3(
                        camCoords.x + dirX * 1000.0,
                        camCoords.y + dirY * 1000.0,
                        camCoords.z + dirZ * 1000.0
                    )
                    
                    local raycast = StartExpensiveSynchronousShapeTestLosProbe(
                        raycastStart.x, raycastStart.y, raycastStart.z,
                        raycastEnd.x, raycastEnd.y, raycastEnd.z,
                        -1, ped, 7
                    )
                    
                    local _, hit, endCoords, _, entityHit = GetShapeTestResult(raycast)
                    
                    if hit then
                        
                        if entityHit and DoesEntityExist(entityHit) and IsEntityAVehicle(entityHit) then
                            
                            local maxSeats = GetVehicleMaxNumberOfPassengers(entityHit)
                            local vehicleDriver = GetPedInVehicleSeat(entityHit, -1)
                            
                            
                            local seatFound = false
                            
                            
                            if not vehicleDriver or vehicleDriver == 0 then
                                TaskWarpPedIntoVehicle(ped, entityHit, -1)
                                seatFound = true
                            else
                                
                                for i = 0, maxSeats - 1 do
                                    if IsVehicleSeatFree(entityHit, i) then
                                        TaskWarpPedIntoVehicle(ped, entityHit, i)
                                        seatFound = true
                                        break
                                    end
                                end
                            end
                            
                            
                            if not seatFound then
                                SetEntityCoordsNoOffset(ped, endCoords.x, endCoords.y, endCoords.z, false, false, false)
                            end
                        else
                            
                            SetEntityCoordsNoOffset(ped, endCoords.x, endCoords.y, endCoords.z, false, false, false)
                        end
                    else
                        SetEntityCoordsNoOffset(ped, raycastEnd.x, raycastEnd.y, raycastEnd.z, false, false, false)
                    end
                end
            end
        end
    end)
end


Actions.teleportShootItem = FindItem("Miscellaneous", "General", "Teleport Shoot")
if Actions.teleportShootItem then
    local teleportShootEnabled = false
    
    Actions.teleportShootItem.onClick = function(value)
        teleportShootEnabled = value
        
        if value then
            if type(Susano) == "table" and type(Susano.ShowNotification) == "function" then
                Susano.ShowNotification("~g~Teleport Shoot Active~s~\nTirez pour vous teleporter !")
            end
        end
    end
    
    CreateThread(function()
        local lastTeleportShoot = 0
        
        while true do
            Wait(0)
            
            if teleportShootEnabled then
                
                local screenW, screenH = GetScreenSize()
                local centerX = screenW / 2
                local centerY = screenH / 2
                
                
                if Susano.DrawRectFilled then
                   
                    Susano.DrawRectFilled(centerX - 3, centerY - 3, 6, 6, 0.0, 0.0, 0.0, 1.0, 0)
                    
                    Susano.DrawRectFilled(centerX - 2, centerY - 2, 4, 4, 1.0, 1.0, 1.0, 1.0, 0)
                    
                    if Susano.SubmitFrame then
                        Susano.SubmitFrame()
                    end
                elseif Susano.DrawLine then
                    
                    Susano.DrawLine(centerX - 4, centerY - 4, centerX + 4, centerY - 4, 0.0, 0.0, 0.0, 1.0, 2)
                    Susano.DrawLine(centerX - 4, centerY + 4, centerX + 4, centerY + 4, 0.0, 0.0, 0.0, 1.0, 2)
                    Susano.DrawLine(centerX - 4, centerY - 4, centerX - 4, centerY + 4, 0.0, 0.0, 0.0, 1.0, 2)
                    Susano.DrawLine(centerX + 4, centerY - 4, centerX + 4, centerY + 4, 0.0, 0.0, 0.0, 1.0, 2)
                    
                    Susano.DrawLine(centerX - 2, centerY - 2, centerX + 2, centerY - 2, 1.0, 1.0, 1.0, 1.0, 2)
                    Susano.DrawLine(centerX - 2, centerY + 2, centerX + 2, centerY + 2, 1.0, 1.0, 1.0, 1.0, 2)
                    Susano.DrawLine(centerX - 2, centerY - 2, centerX - 2, centerY + 2, 1.0, 1.0, 1.0, 1.0, 2)
                    Susano.DrawLine(centerX + 2, centerY - 2, centerX + 2, centerY + 2, 1.0, 1.0, 1.0, 1.0, 2)
                    
                    if Susano.SubmitFrame then
                        Susano.SubmitFrame()
                    end
                end
                
               
                local ped = PlayerPedId()
                if IsPedShooting(ped) and (GetGameTimer() - lastTeleportShoot) > 100 then
                    lastTeleportShoot = GetGameTimer()
                    
                    local camCoords = GetGameplayCamCoord()
                    local camRot = GetGameplayCamRot(2)
                    
                    local pitch = math.rad(camRot.x)
                    local yaw = math.rad(camRot.z)
                    
                    local dirX = -math.sin(yaw) * math.cos(pitch)
                    local dirY = math.cos(yaw) * math.cos(pitch)
                    local dirZ = math.sin(pitch)
                    
                    local raycastStart = camCoords
                    local raycastEnd = vector3(
                        camCoords.x + dirX * 1000.0,
                        camCoords.y + dirY * 1000.0,
                        camCoords.z + dirZ * 1000.0
                    )
                    
                    local raycast = StartExpensiveSynchronousShapeTestLosProbe(
                        raycastStart.x, raycastStart.y, raycastStart.z,
                        raycastEnd.x, raycastEnd.y, raycastEnd.z,
                        -1, ped, 7
                    )
                    
                    local _, hit, endCoords, _, entityHit = GetShapeTestResult(raycast)
                    
                    if hit then
                       
                        if entityHit and DoesEntityExist(entityHit) and IsEntityAVehicle(entityHit) then
                           
                            local maxSeats = GetVehicleMaxNumberOfPassengers(entityHit)
                            local vehicleDriver = GetPedInVehicleSeat(entityHit, -1)
                            
                            
                            local seatFound = false
                            
                            
                            if not vehicleDriver or vehicleDriver == 0 then
                                TaskWarpPedIntoVehicle(ped, entityHit, -1)
                                seatFound = true
                            else
                                
                                for i = 0, maxSeats - 1 do
                                    if IsVehicleSeatFree(entityHit, i) then
                                        TaskWarpPedIntoVehicle(ped, entityHit, i)
                                        seatFound = true
                                        break
                                    end
                                end
                            end
                            
                            
                            if not seatFound then
                                SetEntityCoordsNoOffset(ped, endCoords.x, endCoords.y, endCoords.z, false, false, false)
                            end
                        else
                            
                            SetEntityCoordsNoOffset(ped, endCoords.x, endCoords.y, endCoords.z, false, false, false)
                        end
                    else
                        SetEntityCoordsNoOffset(ped, raycastEnd.x, raycastEnd.y, raycastEnd.z, false, false, false)
                    end
                end
            end
        end
    end)
end


Actions.teleportShootItem = FindItem("Miscellaneous", "General", "Teleport Shoot")
if Actions.teleportShootItem then
    local teleportShootEnabled = false
    
    Actions.teleportShootItem.onClick = function(value)
        teleportShootEnabled = value
    end
    
    CreateThread(function()
        while true do
            Wait(0)
            
            if teleportShootEnabled then
                local ped = PlayerPedId()
                
                
                if IsPedShooting(ped) then
                    local camCoords = GetGameplayCamCoord()
                    local camRot = GetGameplayCamRot(2)
                    
                    local pitch = math.rad(camRot.x)
                    local yaw = math.rad(camRot.z)
                    
                    local dirX = -math.sin(yaw) * math.cos(pitch)
                    local dirY = math.cos(yaw) * math.cos(pitch)
                    local dirZ = math.sin(pitch)
                    
                    local raycastStart = camCoords
                    local raycastEnd = vector3(
                        camCoords.x + dirX * 1000.0,
                        camCoords.y + dirY * 1000.0,
                        camCoords.z + dirZ * 1000.0
                    )
                    
                    local raycast = StartExpensiveSynchronousShapeTestLosProbe(
                        raycastStart.x, raycastStart.y, raycastStart.z,
                        raycastEnd.x, raycastEnd.y, raycastEnd.z,
                        -1, ped, 7
                    )
                    
                    local _, hit, endCoords, _, _ = GetShapeTestResult(raycast)
                    
                    if hit then
                        
                        SetEntityCoordsNoOffset(ped, endCoords.x, endCoords.y, endCoords.z, false, false, false)
                    else
                        
                        SetEntityCoordsNoOffset(ped, raycastEnd.x, raycastEnd.y, raycastEnd.z, false, false, false)
                    end
                    
                    
                    Wait(100)
                end
            end
        end
    end)
end


Citizen.CreateThread(function()
    local blossomActive = false
    local ptfxLoaded = false

    while true do
        Citizen.Wait(0)

        if Menu.ShowBlossoms and not blossomActive then
            
            RequestNamedPtfxAsset("core")
            while not HasNamedPtfxAssetLoaded("core") do
                Citizen.Wait(0)
            end
            UseParticleFxAssetNextCall("core")
            ptfxLoaded = true
            blossomActive = true
        end

        if Menu.ShowBlossoms and ptfxLoaded then
            
            local playerPed = PlayerPedId()
            local coords = GetEntityCoords(playerPed)

            
            for i = 1, 3 do
                local offsetX = math.random(-100, 100) / 10.0
                local offsetY = math.random(-100, 100) / 10.0
                local offsetZ = math.random(20, 50) / 10.0
                StartParticleFxNonLoopedAtCoord("ent_amb_animal_blossoms", 
                    coords.x + offsetX, coords.y + offsetY, coords.z + offsetZ,
                    0.0, 0.0, 0.0, 1.0, false, false, false)
            end
        end

        if not Menu.ShowBlossoms and blossomActive then
            
            RemoveNamedPtfxAsset("core")
            ptfxLoaded = false
            blossomActive = false
        end
    end
end)

-- Voice Radius (400m) handler
local _voiceRadiusActive = false
local voiceRadiusItem = FindItem("Exploits", "General", "Voice Radius (400m)")
if voiceRadiusItem then
    voiceRadiusItem.onClick = function(val)
        _voiceRadiusActive = val
        if val then
            Susano.HookNative(0x9F81806A90A19FF6, function() return false, 28.0 end)
            Susano.HookNative(0xA799A29B10DC9812, function() return false, 28.0 end)

            Susano.InjectResource("pma-voice", [[
                if _G.__vr_running then return end
                _G.__vr_running = true
                _G.__vr_active = true

                local _realSetInput  = MumbleSetAudioInputDistance
                local _realSetOutput = MumbleSetAudioOutputDistance
                MumbleSetAudioInputDistance  = function(d) if d and d <= 50 then _realSetInput(d) end end
                MumbleSetAudioOutputDistance = function(d) if d and d <= 50 then _realSetOutput(d) end end
                MumbleGetAudioInputDistance  = function() return 28.0 end
                MumbleGetAudioOutputDistance = function() return 28.0 end

                CreateThread(function()
                    while _G.__vr_active do
                        pcall(function()
                            if LocalPlayer and LocalPlayer.state then
                                LocalPlayer.state:set("proximity", {
                                    distance = 400.0,
                                    mode = 2
                                }, true)
                            end
                            if exports["pma-voice"] then
                                pcall(function() exports["pma-voice"]:SetProximity(400.0) end)
                                pcall(function() exports["pma-voice"]:setVoiceDistance(400.0) end)
                                pcall(function() exports["pma-voice"]:ChangeRange(400.0) end)
                            end
                            NetworkSetTalkerProximity(400.0)
                            MumbleSetChannel("Global")
                        end)
                        Wait(2000)
                    end
                    MumbleSetAudioInputDistance  = _realSetInput
                    MumbleSetAudioOutputDistance = _realSetOutput
                    MumbleGetAudioInputDistance  = function() return 28.0 end
                    MumbleGetAudioOutputDistance = function() return 28.0 end
                    pcall(function()
                        NetworkSetTalkerProximity(28.0)
                        MumbleSetChannel("proximity")
                        if LocalPlayer and LocalPlayer.state then
                            LocalPlayer.state:set("proximity", {
                                distance = 28.0,
                                mode = 1
                            }, true)
                        end
                    end)
                    _G.__vr_running = nil
                end)
            ]])
        else
            Susano.UnhookNative(0x9F81806A90A19FF6)
            Susano.UnhookNative(0xA799A29B10DC9812)
            Susano.InjectResource("any", [[ _G.__vr_active = false ]])
        end
    end
end

LoadBypasses()

local Menu = {}
Menu.Visible = false
Menu.CurrentCategory = 2
Menu.CurrentPage = 1
Menu.ItemsPerPage = 9
Menu.scrollbarY = nil
Menu.scrollbarHeight = nil
Menu.OpenedCategory = nil
Menu.CurrentItem = 1
Menu.CurrentTab = 1
Menu.ItemScrollOffset = 0
Menu.CategoryScrollOffset = 0
Menu.EditorDragging = false
Menu.EditorDragOffsetX = 0
Menu.EditorDragOffsetY = 0
Menu.EditorMode = false
Menu.ShowSnowflakes = false
Menu.SelectorY = 0
Menu.CategorySelectorY = 0
Menu.TabSelectorX = 0
Menu.TabSelectorWidth = 0
Menu.SmoothFactor = 0.2
Menu.GradientType = 1
Menu.ScrollbarPosition = 1

Menu.LoadingBarAlpha = 0.0
Menu.KeySelectorAlpha = 0.0
Menu.KeybindsInterfaceAlpha = 0.0

Menu.LoadingProgress = 0.0
Menu.IsLoading = true
Menu.LoadingComplete = false
Menu.LoadingStartTime = nil
Menu.LoadingDuration = 3000

Menu.SelectingKey = false
Menu.SelectedKey = nil
Menu.SelectedKeyName = nil

Menu.SelectingBind = false
Menu.BindingItem = nil
Menu.BindingKey = nil
Menu.BindingKeyName = nil

Menu.ShowKeybinds = false


Menu.CurrentTopTab = 1
function Menu.UpdateCategoriesFromTopTab()
    if not Menu.TopLevelTabs then return end
    local currentTop = Menu.TopLevelTabs[Menu.CurrentTopTab]
    if not currentTop then return end

    Menu.Categories = {}
    table.insert(Menu.Categories, { name = currentTop.name })
    for _, cat in ipairs(currentTop.categories) do
        table.insert(Menu.Categories, cat)
    end
    
    Menu.CurrentCategory = 2
    Menu.CategoryScrollOffset = 0
    Menu.OpenedCategory = nil
    
    if currentTop.autoOpen then
        Menu.OpenedCategory = 2
        Menu.CurrentTab = 1
        Menu.ItemScrollOffset = 0
        Menu.CurrentItem = 1
    end
end

Menu.Banner = {
    enabled = true,
    imageUrl = "https://imgur.com/a/5H7NsmR",
    height = 100
}

Menu.bannerTexture = nil
Menu.bannerWidth = 0
Menu.bannerHeight = 0

function Menu.LoadBannerTexture(url)
    if not url or url == "" then return end
    if not Susano or not Susano.HttpGet or not Susano.LoadTextureFromBuffer then return end

    if CreateThread then
        CreateThread(function()
            local success, result = pcall(function()
                local status, body = Susano.HttpGet(url)
                if status == 200 and body and #body > 0 then
                    local textureId, width, height = Susano.LoadTextureFromBuffer(body)
                    if textureId and textureId ~= 0 then
                        Menu.bannerTexture = textureId
                        Menu.bannerWidth = width
                        Menu.bannerHeight = height
                        return textureId
                    end
                end
                return nil
            end)
            if not success then
            end
        end)
    else
        local success, result = pcall(function()
            local status, body = Susano.HttpGet(url)
            if status == 200 and body and #body > 0 then
                local textureId, width, height = Susano.LoadTextureFromBuffer(body)
                if textureId and textureId ~= 0 then
                    Menu.bannerTexture = textureId
                    Menu.bannerWidth = width
                    Menu.bannerHeight = height
                    print("Banner texture loaded successfully")
                    return textureId
                end
            end
            return nil
        end)
        if not success then
        end
    end
end

Menu.Colors = {
    HeaderPink = { r = 0, g = 0, b = 255 },
    SelectedBg = { r = 0, g = 0, b = 255 },
    TextWhite = { r = 255, g = 255, b = 255 },
    BackgroundDark = { r = 0, g = 0, b = 0 },
    FooterBlack = { r = 0, g = 0, b = 0 }
}

Menu.CurrentTheme = "Purple"

function Menu.ApplyTheme(themeName)
    if not themeName or type(themeName) ~= "string" then
        themeName = "Purple"
    end
    

    local themeLower = string.lower(themeName)
    Menu.CurrentTheme = themeName
    
    if themeLower == "red" then
        Menu.Colors.HeaderPink = { r = 0, g = 0, b = 255 }
        Menu.Colors.SelectedBg = { r = 0, g = 0, b = 255 }
        Menu.Banner.imageUrl = "https://imgur.com/a/5H7NsmR"
        Menu.CurrentTheme = "Red"
    elseif themeLower == "purple" then
        Menu.Colors.HeaderPink = { r = 0, g = 0, b = 255 }
        Menu.Colors.SelectedBg = { r = 0, g = 0, b = 255 }
        Menu.Banner.imageUrl = "https://imgur.com/a/5H7NsmR"
        Menu.CurrentTheme = "Purple"
    elseif themeLower == "gray" then
        Menu.Colors.HeaderPink = { r = 0, g = 0, b = 255 }
        Menu.Colors.SelectedBg = { r = 0, g = 0, b = 255 }
        Menu.Banner.imageUrl = "https://imgur.com/a/5H7NsmR"
        Menu.CurrentTheme = "Gray"
    elseif themeLower == "pink" then
        Menu.Colors.HeaderPink = { r = 0, g = 0, b = 255 }
        Menu.Colors.SelectedBg = { r = 0, g = 0, b = 255 }
        Menu.Banner.imageUrl = "https://imgur.com/a/5H7NsmR"
        Menu.CurrentTheme = "pink"
    else
        Menu.Colors.HeaderPink = { r = 0, g = 0, b = 255 }
        Menu.Colors.SelectedBg = { r = 0, g = 0, b = 255 }
        Menu.Banner.imageUrl = "https://imgur.com/a/5H7NsmR"
        Menu.CurrentTheme = "Purple"
    end

    if Menu.Banner.enabled and Menu.Banner.imageUrl then
        Menu.LoadBannerTexture(Menu.Banner.imageUrl)
    end
end

Menu.Position = {
    x = 50,
    y = 100,
    width = 360,
    itemHeight = 34,
    mainMenuHeight = 26,
    headerHeight = 100,
    footerHeight = 26,
    footerSpacing = 5,
    mainMenuSpacing = 5,
    footerRadius = 4,
    itemRadius = 4,
    scrollbarWidth = 12,
    scrollbarPadding = 3,
    headerRadius = 6
}
Menu.Scale = 1.0

function Menu.GetScaledPosition()
    local scale = Menu.Scale or 1.0
    return {
        x = Menu.Position.x,
        y = Menu.Position.y,
        width = Menu.Position.width * scale,
        itemHeight = Menu.Position.itemHeight * scale,
        mainMenuHeight = Menu.Position.mainMenuHeight * scale,
        headerHeight = Menu.Position.headerHeight * scale,
        footerHeight = Menu.Position.footerHeight * scale,
        footerSpacing = Menu.Position.footerSpacing * scale,
        mainMenuSpacing = Menu.Position.mainMenuSpacing * scale,
        footerRadius = Menu.Position.footerRadius * scale,
        itemRadius = Menu.Position.itemRadius * scale,
        scrollbarWidth = Menu.Position.scrollbarWidth * scale,
        scrollbarPadding = Menu.Position.scrollbarPadding * scale,
        headerRadius = Menu.Position.headerRadius * scale
    }
end

function Menu.DrawRect(x, y, width, height, r, g, b, a)
    a = a or 1.0
    r = r or 1.0
    g = g or 1.0
    b = b or 1.0

    if r > 1.0 then r = r / 255.0 end
    if g > 1.0 then g = g / 255.0 end
    if b > 1.0 then b = b / 255.0 end
    if a > 1.0 then a = a / 255.0 end

    if Susano.DrawFilledRect then
        Susano.DrawFilledRect(x, y, width, height, r, g, b, a)
    elseif Susano.FillRect then
        Susano.FillRect(x, y, width, height, r, g, b, a)
    elseif Susano.DrawRect then
        for i = 0, height - 1 do
            Susano.DrawRect(x, y + i, width, 1, r, g, b, a)
        end
    end
end

function Menu.DrawText(x, y, text, size_px, r, g, b, a)
    local scale = Menu.Scale or 1.0
    size_px = (size_px or 16) * scale
    r = r or 1.0
    g = g or 1.0
    b = b or 1.0
    a = a or 1.0

    if r > 1.0 then r = r / 255.0 end
    if g > 1.0 then g = g / 255.0 end
    if b > 1.0 then b = b / 255.0 end
    if a > 1.0 then a = a / 255.0 end

    Susano.DrawText(x, y, text, size_px, r, g, b, a)
end

function Menu.DrawHeader()
    local scaledPos = Menu.GetScaledPosition()
    local scale = Menu.Scale or 1.0
    local x = scaledPos.x
    local y = scaledPos.y
    local width = scaledPos.width - 1
    local height = scaledPos.headerHeight
    local radius = scaledPos.headerRadius
    local bannerHeight = Menu.Banner.height * scale

    if Menu.Banner.enabled then
        if Menu.bannerTexture and Menu.bannerTexture > 0 and Susano and Susano.DrawImage then
            
            Susano.DrawImage(Menu.bannerTexture, x, y, width, bannerHeight, 1, 1, 1, 1, 0)
        else
            Menu.DrawRect(x, y, width, height, Menu.Colors.HeaderPink.r, Menu.Colors.HeaderPink.g, Menu.Colors.HeaderPink.b, 255)

            local logoX = x + width / 2 - 12
            local logoY = y + height / 2 - 20
            Menu.DrawText(logoX, logoY, "P", 44, 1.0, 1.0, 1.0, 1.0)
        end
    else
        Menu.DrawRect(x, y, width, height, Menu.Colors.HeaderPink.r, Menu.Colors.HeaderPink.g, Menu.Colors.HeaderPink.b, 255)

        local logoX = x + width / 2 - 12
        local logoY = y + height / 2 - 20
        Menu.DrawText(logoX, logoY, "P", 44, 1.0, 1.0, 1.0, 1.0)
    end
end

function Menu.DrawScrollbar(x, startY, visibleHeight, selectedIndex, totalItems, isMainMenu, menuWidth)
    if totalItems < 1 then
        return
    end

    local scaledPos = Menu.GetScaledPosition()
    local scrollbarWidth = scaledPos.scrollbarWidth
    local scrollbarPadding = scaledPos.scrollbarPadding
    local width = menuWidth or scaledPos.width

    local scrollbarX
    if Menu.ScrollbarPosition == 2 then
        scrollbarX = x + width + scrollbarPadding
    else
        scrollbarX = x - scrollbarWidth - scrollbarPadding
    end

    local scrollbarY = startY
    local scrollbarHeight = visibleHeight

    local adjustedIndex = selectedIndex
    if isMainMenu then
        adjustedIndex = selectedIndex - 1
    end


    local thumbHeight = scrollbarHeight  
    local thumbY
    
    if totalItems <= Menu.ItemsPerPage then
 
        thumbY = scrollbarY
    else
  
        local scrollOffset = 0
        if not isMainMenu and Menu.ItemScrollOffset then
            scrollOffset = Menu.ItemScrollOffset
        elseif isMainMenu and Menu.CategoryScrollOffset then
            scrollOffset = Menu.CategoryScrollOffset
        end
        
        local totalScrollable = totalItems - Menu.ItemsPerPage
        local scrollProgress = scrollOffset / math.max(1, totalScrollable)
        scrollProgress = math.min(1.0, math.max(0.0, scrollProgress))
        
      
        local maxThumbY = scrollbarY + scrollbarHeight - thumbHeight
        thumbY = scrollbarY + scrollProgress * (scrollbarHeight - thumbHeight)
        thumbY = math.max(scrollbarY, math.min(maxThumbY, thumbY))
    end

    if not Menu.scrollbarY then
        Menu.scrollbarY = thumbY
    end
    if not Menu.scrollbarHeight then
        Menu.scrollbarHeight = thumbHeight
    end

    local smoothSpeed = 0.15
    Menu.scrollbarY = Menu.scrollbarY + (thumbY - Menu.scrollbarY) * smoothSpeed
    Menu.scrollbarHeight = Menu.scrollbarHeight + (thumbHeight - Menu.scrollbarHeight) * smoothSpeed

    local thumbPadding = 2
    local bgR = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.r) and (Menu.Colors.SelectedBg.r / 255.0) or 1.0
    local bgG = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.g) and (Menu.Colors.SelectedBg.g / 255.0) or 0.0
    local bgB = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.b) and (Menu.Colors.SelectedBg.b / 255.0) or 1.0
    
    
    if Susano and Susano.DrawRectFilled then
      
        Susano.DrawRectFilled(scrollbarX + thumbPadding - 1, Menu.scrollbarY + thumbPadding - 1,
            scrollbarWidth - (thumbPadding * 2) + 2, Menu.scrollbarHeight - (thumbPadding * 2) + 2,
            bgR * 0.3, bgG * 0.3, bgB * 0.3, 0.4,
            (scrollbarWidth - (thumbPadding * 2) + 2) / 2)
       
        Susano.DrawRectFilled(scrollbarX + thumbPadding, Menu.scrollbarY + thumbPadding,
            scrollbarWidth - (thumbPadding * 2), Menu.scrollbarHeight - (thumbPadding * 2),
            bgR, bgG, bgB, 1.0,
            (scrollbarWidth - (thumbPadding * 2)) / 2)
    else
    
        Menu.DrawRoundedRect(scrollbarX + thumbPadding - 1, Menu.scrollbarY + thumbPadding - 1,
            scrollbarWidth - (thumbPadding * 2) + 2, Menu.scrollbarHeight - (thumbPadding * 2) + 2,
            math.floor(bgR * 0.3 * 255), math.floor(bgG * 0.3 * 255), math.floor(bgB * 0.3 * 255), 102,
            (scrollbarWidth - (thumbPadding * 2) + 2) / 2)
     
        Menu.DrawRoundedRect(scrollbarX + thumbPadding, Menu.scrollbarY + thumbPadding,
            scrollbarWidth - (thumbPadding * 2), Menu.scrollbarHeight - (thumbPadding * 2),
            bgR * 255, bgG * 255, bgB * 255, 255,
            (scrollbarWidth - (thumbPadding * 2)) / 2)
    end
end

function Menu.DrawTabs(category, x, startY, width, tabHeight)
    local scale = Menu.Scale or 1.0
    if not category or not category.hasTabs or not category.tabs then
        return
    end

    local numTabs = #category.tabs
    local tabWidth = width / numTabs
    local currentX = x

    for i, tab in ipairs(category.tabs) do
        local tabX = currentX
        local currentTabWidth
        if i == numTabs then
            currentTabWidth = (x + width) - currentX
        else
            currentTabWidth = tabWidth + (0.5 * scale)
        end

        local isSelected = (i == Menu.CurrentTab)

        if isSelected then
            local targetWidth = currentTabWidth
            if i == numTabs then
                targetWidth = math.min(currentTabWidth, (x + width) - tabX - (1 * scale))
            end

            if Menu.TabSelectorX == 0 then
                Menu.TabSelectorX = tabX
                Menu.TabSelectorWidth = targetWidth
            end

            local smoothSpeed = Menu.SmoothFactor
            Menu.TabSelectorX = Menu.TabSelectorX + (tabX - Menu.TabSelectorX) * smoothSpeed
            Menu.TabSelectorWidth = Menu.TabSelectorWidth + (targetWidth - Menu.TabSelectorWidth) * smoothSpeed

            if math.abs(Menu.TabSelectorX - tabX) < (0.5 * scale) then Menu.TabSelectorX = tabX end
            if math.abs(Menu.TabSelectorWidth - targetWidth) < (0.5 * scale) then Menu.TabSelectorWidth = targetWidth end

            local drawX = Menu.TabSelectorX
            local drawWidth = Menu.TabSelectorWidth

            local baseR = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.r) and (Menu.Colors.SelectedBg.r / 255.0) or 1.0
            local baseG = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.g) and (Menu.Colors.SelectedBg.g / 255.0) or 0.0
            local baseB = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.b) and (Menu.Colors.SelectedBg.b / 255.0) or 1.0
            local darkenAmount = 0.4

            local gradientSteps = 20
            local stepHeight = tabHeight / gradientSteps
            local selectorWidth = drawWidth
            local selectorX = drawX

            for step = 0, gradientSteps - 1 do
                local stepY = startY + (step * stepHeight)
                local actualStepHeight = stepHeight
                local maxY = startY + tabHeight
                if stepY + actualStepHeight > maxY then
                    actualStepHeight = maxY - stepY
                end
                if actualStepHeight > 0 and stepY < maxY then
                    local stepGradientFactor = step / (gradientSteps - 1)
                    local stepDarken = (1 - stepGradientFactor) * darkenAmount

                    local stepR = math.max(0, baseR - stepDarken)
                    local stepG = math.max(0, baseG - stepDarken)
                    local stepB = math.max(0, baseB - stepDarken)

                    if Susano and Susano.DrawRectFilled then
                        Susano.DrawRectFilled(selectorX, stepY, selectorWidth, actualStepHeight, stepR, stepG, stepB, 0.9, 0.0)
                    else
                        Menu.DrawRect(selectorX, stepY, selectorWidth, actualStepHeight, stepR * 255, stepG * 255, stepB * 255, 220)
                    end
                end
            end

            Menu.DrawRect(selectorX, startY, (3 * scale), tabHeight, Menu.Colors.SelectedBg.r, Menu.Colors.SelectedBg.g, Menu.Colors.SelectedBg.b, 255)
        end

        Menu.DrawRect(tabX, startY, currentTabWidth, tabHeight, Menu.Colors.BackgroundDark.r, Menu.Colors.BackgroundDark.g, Menu.Colors.BackgroundDark.b, isSelected and 0 or 50)

        local textSize = 17
        local scaledTextSize = textSize * scale
        local textY = startY + tabHeight / 2 - (scaledTextSize / 2) + (1 * scale)
        local textWidth = 0
        if Susano and Susano.GetTextWidth then
            textWidth = Susano.GetTextWidth(tab.name, scaledTextSize)
        else
            textWidth = string.len(tab.name) * 9 * scale
        end
        local textX = tabX + (currentTabWidth / 2) - (textWidth / 2)
        Menu.DrawText(textX, textY, tab.name, textSize, Menu.Colors.TextWhite.r / 255.0, Menu.Colors.TextWhite.g / 255.0, Menu.Colors.TextWhite.b / 255.0, 1.0)

        currentX = currentX + tabWidth
    end
end

local function findNextNonSeparator(items, startIndex, direction)
    local index = startIndex
    local attempts = 0
    local maxAttempts = #items

    while attempts < maxAttempts do
        index = index + direction
        if index < 1 then
            index = #items
        elseif index > #items then
            index = 1
        end

        if items[index] and not items[index].isSeparator then
            return index
        end

        attempts = attempts + 1
    end

    return startIndex
end

function Menu.DrawItem(x, itemY, width, itemHeight, item, isSelected)
    local scale = Menu.Scale or 1.0
    
    if item.isSeparator then
        Menu.DrawRect(x, itemY, width, itemHeight, Menu.Colors.BackgroundDark.r, Menu.Colors.BackgroundDark.g, Menu.Colors.BackgroundDark.b, 50)

        if item.separatorText then
            local textY = itemY + itemHeight / 2 - (7 * scale)
            local textSize = 14 * scale

            local textWidth = 0
            if Susano and Susano.GetTextWidth then
                textWidth = Susano.GetTextWidth(item.separatorText, textSize)
            else
                textWidth = string.len(item.separatorText) * 8 * scale
            end

            local textX = x + (width / 2) - (textWidth / 2)

            Menu.DrawText(textX, textY, item.separatorText, 14, Menu.Colors.TextWhite.r / 255.0, Menu.Colors.TextWhite.g / 255.0, Menu.Colors.TextWhite.b / 255.0, 1.0)

            local barY = itemY + (itemHeight / 2)
            local barSpacing = 8 * scale
            local barMaxLength = 80 * scale
            local barHeight = 1 * scale
            local barRadius = 0.5 * scale

            local leftBarX = textX - barSpacing - barMaxLength
            local leftBarWidth = math.min(barMaxLength, textX - leftBarX - barSpacing)
            if leftBarWidth > 0 and leftBarX >= x + 15 then
                if Susano and Susano.DrawRectFilled then
                    Susano.DrawRectFilled(leftBarX, math.floor(barY), leftBarWidth, barHeight,
                        Menu.Colors.TextWhite.r / 255.0, Menu.Colors.TextWhite.g / 255.0, Menu.Colors.TextWhite.b / 255.0, 100 / 255.0,
                        barRadius)
                else
                    Menu.DrawRect(leftBarX, math.floor(barY), leftBarWidth, barHeight, Menu.Colors.TextWhite.r, Menu.Colors.TextWhite.g, Menu.Colors.TextWhite.b, 100)
                end
            end

            local rightBarX = textX + textWidth + barSpacing
            local rightBarWidth = math.min(barMaxLength, (x + width - 15) - rightBarX)
            if rightBarWidth > 0 and rightBarX + rightBarWidth <= x + width - 15 then
                if Susano and Susano.DrawRectFilled then
                    Susano.DrawRectFilled(rightBarX, math.floor(barY), rightBarWidth, barHeight,
                        Menu.Colors.TextWhite.r / 255.0, Menu.Colors.TextWhite.g / 255.0, Menu.Colors.TextWhite.b / 255.0, 100 / 255.0,
                        barRadius)
                else
                    Menu.DrawRect(rightBarX, math.floor(barY), rightBarWidth, barHeight, Menu.Colors.TextWhite.r, Menu.Colors.TextWhite.g, Menu.Colors.TextWhite.b, 100)
                end
            end
        end
        return
    end

    Menu.DrawRect(x, itemY, width, itemHeight, Menu.Colors.BackgroundDark.r, Menu.Colors.BackgroundDark.g, Menu.Colors.BackgroundDark.b, 50)

    if isSelected then
        if Menu.SelectorY == 0 then
            Menu.SelectorY = itemY
        end

        local smoothSpeed = Menu.SmoothFactor
        Menu.SelectorY = Menu.SelectorY + (itemY - Menu.SelectorY) * smoothSpeed
        if math.abs(Menu.SelectorY - itemY) < 0.5 then
            Menu.SelectorY = itemY
        end
        
        local drawY = Menu.SelectorY

        local baseR = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.r) and (Menu.Colors.SelectedBg.r / 255.0) or 1.0
        local baseG = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.g) and (Menu.Colors.SelectedBg.g / 255.0) or 0.0
        local baseB = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.b) and (Menu.Colors.SelectedBg.b / 255.0) or 1.0
        local darkenAmount = 0.4

        local selectorX = x
        
        if Menu.GradientType == 2 then
            local gradientSteps = 120
            local drawWidth = width - 1
            local stepWidth = drawWidth / gradientSteps
            local selectorY = drawY
            local selectorHeight = itemHeight

            for step = 0, gradientSteps - 1 do
                local stepX = x + (step * stepWidth)
                local actualStepWidth = stepWidth
                
                if actualStepWidth > 0 then
                    local stepGradientFactor = step / (gradientSteps - 1)
                   
                    local easedFactor = stepGradientFactor < 0.5 
                        and 4 * stepGradientFactor * stepGradientFactor * stepGradientFactor
                        or 1 - math.pow(-2 * stepGradientFactor + 2, 3) / 2
                    local darkenFactor = easedFactor * easedFactor
                    local stepDarken = darkenFactor * 0.75

                    local stepR = math.max(0, baseR - stepDarken)
                    local stepG = math.max(0, baseG - stepDarken)
                    local stepB = math.max(0, baseB - stepDarken)
                    
                 
                    local brightness = 1.0
                    if step < gradientSteps * 0.1 then
                        brightness = 1.0 + (0.15 * (1.0 - step / (gradientSteps * 0.1)))
                    end
                    stepR = math.min(1.0, stepR * brightness)
                    stepG = math.min(1.0, stepG * brightness)
                    stepB = math.min(1.0, stepB * brightness)
                    
                    local alpha = 0.95
                    if step > gradientSteps - 20 then
                        alpha = 0.95 * (1.0 - ((step - (gradientSteps - 20)) / 20))
                    end

                    if Susano and Susano.DrawRectFilled then
                        Susano.DrawRectFilled(stepX, selectorY, actualStepWidth, selectorHeight, stepR, stepG, stepB, alpha, 0.0)
                    else
                        Menu.DrawRect(stepX, selectorY, actualStepWidth, selectorHeight, stepR * 255, stepG * 255, stepB * 255, math.floor(alpha * 255))
                    end
                end
            end
        else
            local gradientSteps = 50
            local stepHeight = itemHeight / gradientSteps
            local selectorWidth = width - 1
    
            for step = 0, gradientSteps - 1 do
                local stepY = drawY + (step * stepHeight)
                local actualStepHeight = math.min(stepHeight, (drawY + itemHeight) - stepY)
                if actualStepHeight > 0 then
                    local stepGradientFactor = step / (gradientSteps - 1)
                    
                    local easedFactor = stepGradientFactor * stepGradientFactor * (3.0 - 2.0 * stepGradientFactor)
                    
                    local stepDarken = easedFactor * darkenAmount * 1.0

                    local stepR = math.max(0, baseR - stepDarken)
                    local stepG = math.max(0, baseG - stepDarken)
                    local stepB = math.max(0, baseB - stepDarken)
                    
                   
                    local brightness = 1.0
                    if step < gradientSteps * 0.15 then
                        brightness = 1.0 + (0.12 * (1.0 - step / (gradientSteps * 0.15)))
                    end
                    stepR = math.min(1.0, stepR * brightness)
                    stepG = math.min(1.0, stepG * brightness)
                    stepB = math.min(1.0, stepB * brightness)

                    if Susano and Susano.DrawRectFilled then
                        Susano.DrawRectFilled(selectorX, stepY, selectorWidth, actualStepHeight, stepR, stepG, stepB, 0.95, 0.0)
                    else
                        Menu.DrawRect(selectorX, stepY, selectorWidth, actualStepHeight, stepR * 255, stepG * 255, stepB * 255, 242)
                    end
                end
            end
        end

        Menu.DrawRect(selectorX, drawY, 3, itemHeight, Menu.Colors.SelectedBg.r, Menu.Colors.SelectedBg.g, Menu.Colors.SelectedBg.b, 255)
    end

    local textX = x + (16 * scale)
    local textY = itemY + itemHeight / 2 - (8 * scale)
    local textSize = 17 * scale
    Menu.DrawText(textX, textY, item.name, 17, Menu.Colors.TextWhite.r / 255.0, Menu.Colors.TextWhite.g / 255.0, Menu.Colors.TextWhite.b / 255.0, 1.0)

    if item.type == "toggle" then
        local toggleWidth = 36 * scale
        local toggleHeight = 16 * scale
        local toggleX = x + width - toggleWidth - (16 * scale)
        local toggleY = itemY + (itemHeight / 2) - (toggleHeight / 2)
        local toggleRadius = toggleHeight / 2

        if item.value then
            local tR = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.r) and (Menu.Colors.SelectedBg.r / 255.0) or 1.0
            local tG = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.g) and (Menu.Colors.SelectedBg.g / 255.0) or 0.0
            local tB = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.b) and (Menu.Colors.SelectedBg.b / 255.0) or 1.0

            if Susano and Susano.DrawRectFilled then
                Susano.DrawRectFilled(toggleX, toggleY, toggleWidth, toggleHeight,
                    tR, tG, tB, 0.95,
                    toggleRadius)
            else
                Menu.DrawRoundedRect(toggleX, toggleY, toggleWidth, toggleHeight,
                    tR * 255, tG * 255, tB * 255, 242,
                    toggleRadius)
            end
        else
            if Susano and Susano.DrawRectFilled then
                Susano.DrawRectFilled(toggleX, toggleY, toggleWidth, toggleHeight,
                    0.2, 0.2, 0.2, 0.95,
                    toggleRadius)
            else
                Menu.DrawRoundedRect(toggleX, toggleY, toggleWidth, toggleHeight,
                    51, 51, 51, 242,
                    toggleRadius)
            end
        end

        local circleSize = toggleHeight - 4
        local circleY = toggleY + 2
        local circleX
        if item.value then
            circleX = toggleX + toggleWidth - circleSize - 2
        else
            circleX = toggleX + 2
        end

        local isGrayTheme = (Menu.CurrentTheme == "Gray")
        local circleR, circleG, circleB
        if isGrayTheme then
            circleR = 1.0
            circleG = 1.0
            circleB = 1.0
        else
            circleR = 0.0
            circleG = 0.0
            circleB = 0.0
        end

        if Susano and Susano.DrawRectFilled then
            Susano.DrawRectFilled(circleX, circleY, circleSize, circleSize,
                circleR, circleG, circleB, 1.0,
                circleSize / 2)
        else
            Menu.DrawRoundedRect(circleX, circleY, circleSize, circleSize,
                circleR * 255, circleG * 255, circleB * 255, 255,
                circleSize / 2)
        end

        if item.hasSlider then
            local sliderWidth = 85 * scale
            local sliderHeight = 6 * scale
            local sliderX = x + width - sliderWidth - (95 * scale)
            local sliderY = itemY + (itemHeight / 2) - (sliderHeight / 2)

            local currentValue = item.sliderValue or item.sliderMin or 0.0
            local minValue = item.sliderMin or 0.0
            local maxValue = item.sliderMax or 100.0

            local percent = (currentValue - minValue) / (maxValue - minValue)
            percent = math.max(0.0, math.min(1.0, percent))

            if Susano and Susano.DrawRectFilled then
                Susano.DrawRectFilled(sliderX, sliderY, sliderWidth, sliderHeight,
                    0.12, 0.12, 0.12, 0.7, 3.0)
            else
                Menu.DrawRoundedRect(sliderX, sliderY, sliderWidth, sliderHeight,
                    31, 31, 31, 180, 3.0)
            end

            if percent > 0 then
                if Susano and Susano.DrawRectFilled then
                    local accentR = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.r) and (Menu.Colors.SelectedBg.r / 255.0 * 1.3) or 1.0
                    local accentG = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.g) and (Menu.Colors.SelectedBg.g / 255.0 * 1.3) or 0.0
                    local accentB = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.b) and (Menu.Colors.SelectedBg.b / 255.0 * 1.3) or 1.0
                    accentR = math.min(1.0, accentR)
                    accentG = math.min(1.0, accentG)
                    accentB = math.min(1.0, accentB)
                    Susano.DrawRectFilled(sliderX, sliderY, sliderWidth * percent, sliderHeight,
                        accentR, accentG, accentB, 1.0, 3.0)
                else
                    local accentR = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.r) and math.min(255, Menu.Colors.SelectedBg.r * 1.3) or 255
                    local accentG = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.g) and math.min(255, Menu.Colors.SelectedBg.g * 1.3) or 0
                    local accentB = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.b) and math.min(255, Menu.Colors.SelectedBg.b * 1.3) or 255
                    Menu.DrawRoundedRect(sliderX, sliderY, sliderWidth * percent, sliderHeight,
                        accentR, accentG, accentB, 255, 3.0)
                end
            end

            local thumbSize = 10 * scale
            local thumbX = sliderX + (sliderWidth * percent) - (thumbSize / 2)
            local thumbY = itemY + (itemHeight / 2) - (thumbSize / 2)

            if Susano and Susano.DrawRectFilled then
                Susano.DrawRectFilled(thumbX, thumbY, thumbSize, thumbSize,
                    1.0, 1.0, 1.0, 1.0, 5.0)
            else
                Menu.DrawRoundedRect(thumbX, thumbY, thumbSize, thumbSize,
                    255, 255, 255, 255, 5.0)
            end

            local valueText
            if item.name == "Freecam" then
                valueText = string.format("%.1f", currentValue)
            else
                valueText = string.format("%.1f", currentValue)
            end
            local valuePadding = 10 * scale
            local valueX = sliderX + sliderWidth + valuePadding
            local valueY = sliderY + (sliderHeight / 2) - (6 * scale)
            local valueTextSize = 10 * scale
            Menu.DrawText(valueX, valueY, valueText, 10, Menu.Colors.TextWhite.r / 255.0, Menu.Colors.TextWhite.g / 255.0, Menu.Colors.TextWhite.b / 255.0, 0.8)
        end
    elseif item.type == "toggle_selector" then
        local toggleWidth = 32 * scale
        local toggleHeight = 14 * scale
        local toggleX = x + width - toggleWidth - (15 * scale)
        local toggleY = itemY + (itemHeight / 2) - (toggleHeight / 2)
        local toggleRadius = toggleHeight / 2

        if item.value then
            local tR = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.r) and (Menu.Colors.SelectedBg.r / 255.0) or 1.0
            local tG = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.g) and (Menu.Colors.SelectedBg.g / 255.0) or 0.0
            local tB = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.b) and (Menu.Colors.SelectedBg.b / 255.0) or 1.0

            if Susano and Susano.DrawRectFilled then
                Susano.DrawRectFilled(toggleX, toggleY, toggleWidth, toggleHeight, tR, tG, tB, 0.95, toggleRadius)
            else
                Menu.DrawRoundedRect(toggleX, toggleY, toggleWidth, toggleHeight, tR * 255, tG * 255, tB * 255, 242, toggleRadius)
            end
        else
            if Susano and Susano.DrawRectFilled then
                Susano.DrawRectFilled(toggleX, toggleY, toggleWidth, toggleHeight, 0.2, 0.2, 0.2, 0.95, toggleRadius)
            else
                Menu.DrawRoundedRect(toggleX, toggleY, toggleWidth, toggleHeight, 51, 51, 51, 242, toggleRadius)
            end
        end

        local circleSize = toggleHeight - 4
        local circleY = toggleY + 2
        local circleX
        if item.value then
            circleX = toggleX + toggleWidth - circleSize - 2
        else
            circleX = toggleX + 2
        end

        local isGrayTheme = (Menu.CurrentTheme == "Gray")
        local circleR, circleG, circleB
        if isGrayTheme then
            circleR = 1.0
            circleG = 1.0
            circleB = 1.0
        else
            circleR = 0.0
            circleG = 0.0
            circleB = 0.0
        end

        if Susano and Susano.DrawRectFilled then
            Susano.DrawRectFilled(circleX, circleY, circleSize, circleSize, circleR, circleG, circleB, 1.0, circleSize / 2)
        else
            Menu.DrawRoundedRect(circleX, circleY, circleSize, circleSize, circleR * 255, circleG * 255, circleB * 255, 255, circleSize / 2)
        end

        if item.options then
            local selectedIndex = item.selected or 1
            local selectedOption = item.options[selectedIndex] or ""
            local selectorSize = 16 * scale
            local textY = itemY + itemHeight / 2 - (7 * scale)

            local fullText = "< " .. selectedOption .. " >"
            local selectorWidth = 0
            if Susano and Susano.GetTextWidth then
                selectorWidth = Susano.GetTextWidth(fullText, selectorSize)
            else
                selectorWidth = string.len(fullText) * 9 * scale
            end

            local selectorX = toggleX - selectorWidth - (15 * scale)

            Menu.DrawText(selectorX, textY, "<", selectorSize,
                Menu.Colors.TextWhite.r / 255.0 * 0.8, Menu.Colors.TextWhite.g / 255.0 * 0.8, Menu.Colors.TextWhite.b / 255.0 * 0.8, 0.8)

            local leftArrowWidth = 0
            if Susano and Susano.GetTextWidth then
                leftArrowWidth = Susano.GetTextWidth("< ", selectorSize)
            else
                leftArrowWidth = 18 * scale
            end
            Menu.DrawText(selectorX + leftArrowWidth, textY, selectedOption, 16, 1.0, 1.0, 1.0, 1.0)

            local optionWidth = 0
            if Susano and Susano.GetTextWidth then
                optionWidth = Susano.GetTextWidth(selectedOption, selectorSize)
            else
                optionWidth = string.len(selectedOption) * 9 * scale
            end
            Menu.DrawText(selectorX + leftArrowWidth + optionWidth + (5 * scale), textY, ">", 16,
                Menu.Colors.TextWhite.r / 255.0 * 0.8, Menu.Colors.TextWhite.g / 255.0 * 0.8, Menu.Colors.TextWhite.b / 255.0 * 0.8, 0.8)
        end
    elseif item.type == "slider" then
        local sliderWidth = 100 * scale
        local sliderHeight = 7 * scale
        local sliderX = x + width - sliderWidth - (60 * scale)
        local sliderY = itemY + (itemHeight / 2) - (sliderHeight / 2)

        local currentValue = item.value or item.min or 0.0
        local minValue = item.min or 0.0
        local maxValue = item.max or 100.0

        local percent = (currentValue - minValue) / (maxValue - minValue)
        percent = math.max(0.0, math.min(1.0, percent))

        if Susano and Susano.DrawRectFilled then
            Susano.DrawRectFilled(sliderX, sliderY, sliderWidth, sliderHeight,
                0.12, 0.12, 0.12, 0.7, 3.0)
        else
            Menu.DrawRoundedRect(sliderX, sliderY, sliderWidth, sliderHeight,
                31, 31, 31, 180, 3.0)
        end

        if percent > 0 then
            if Susano and Susano.DrawRectFilled then
                local accentR = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.r) and (Menu.Colors.SelectedBg.r / 255.0 * 1.3) or 1.0
                local accentG = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.g) and (Menu.Colors.SelectedBg.g / 255.0 * 1.3) or 0.0
                local accentB = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.b) and (Menu.Colors.SelectedBg.b / 255.0 * 1.3) or 1.0
                accentR = math.min(1.0, accentR)
                accentG = math.min(1.0, accentG)
                accentB = math.min(1.0, accentB)
                Susano.DrawRectFilled(sliderX, sliderY, sliderWidth * percent, sliderHeight,
                    accentR, accentG, accentB, 1.0, 3.0)
            else
                local accentR = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.r) and math.min(255, Menu.Colors.SelectedBg.r * 1.3) or 255
                local accentG = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.g) and math.min(255, Menu.Colors.SelectedBg.g * 1.3) or 0
                local accentB = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.b) and math.min(255, Menu.Colors.SelectedBg.b * 1.3) or 255
                Menu.DrawRoundedRect(sliderX, sliderY, sliderWidth * percent, sliderHeight,
                    accentR, accentG, accentB, 255, 3.0)
            end
        end

        local thumbSize = 11 * scale
        local thumbX = sliderX + (sliderWidth * percent) - (thumbSize / 2)
        local thumbY = itemY + (itemHeight / 2) - (thumbSize / 2)

        if Susano and Susano.DrawRectFilled then
                Susano.DrawRectFilled(thumbX, thumbY, thumbSize, thumbSize,
                    1.0, 1.0, 1.0, 1.0, 5.0 * scale)
            else
                Menu.DrawRoundedRect(thumbX, thumbY, thumbSize, thumbSize,
                    255, 255, 255, 255, 5.0 * scale)
            end

        local valueText = string.format("%.0f", currentValue)
        local valuePadding = 10 * scale
        local valueX = sliderX + sliderWidth + valuePadding
        local valueY = sliderY + (sliderHeight / 2) - (6 * scale)
        local valueTextSize = 11 * scale
        Menu.DrawText(valueX, valueY, valueText, 11, Menu.Colors.TextWhite.r / 255.0, Menu.Colors.TextWhite.g / 255.0, Menu.Colors.TextWhite.b / 255.0, 0.8)
    elseif item.type == "selector" and item.options then
        local selectedIndex = item.selected or 1
        local selectedOption = item.options[selectedIndex] or ""
        local selectorSize = 17 * scale

        local isWardrobeSelector = false
        local wardrobeItemNames = {"Hat", "Mask", "Glasses", "Torso", "Tshirt", "Pants", "Shoes"}
        for _, name in ipairs(wardrobeItemNames) do
            if item.name == name then
                isWardrobeSelector = true
                break
            end
        end

        if isWardrobeSelector then
            local displayValue = selectedIndex
            local selectorText = "- " .. tostring(displayValue) .. " -"
            local selectorWidth = 0
            if Susano and Susano.GetTextWidth then
                selectorWidth = Susano.GetTextWidth(selectorText, selectorSize)
            else
                selectorWidth = string.len(selectorText) * 9 * scale
            end
            local selectorX = x + width - selectorWidth - (16 * scale)
            Menu.DrawText(selectorX, textY, selectorText, 17, 1.0, 1.0, 1.0, 1.0)
        else
            local fullText = "< " .. selectedOption .. " >"
            local selectorWidth = 0
            if Susano and Susano.GetTextWidth then
                selectorWidth = Susano.GetTextWidth(fullText, selectorSize)
            else
                selectorWidth = string.len(fullText) * 9 * scale
            end

            local selectorX = x + width - selectorWidth - (16 * scale)

            Menu.DrawText(selectorX, textY, "<", 17,
                Menu.Colors.TextWhite.r / 255.0 * 0.8, Menu.Colors.TextWhite.g / 255.0 * 0.8, Menu.Colors.TextWhite.b / 255.0 * 0.8, 0.8)

            local leftArrowWidth = 0
            if Susano and Susano.GetTextWidth then
                leftArrowWidth = Susano.GetTextWidth("< ", selectorSize)
            else
                leftArrowWidth = 18 * scale
            end
            Menu.DrawText(selectorX + leftArrowWidth, textY, selectedOption, 17,
                1.0, 1.0, 1.0, 1.0)

            local optionWidth = 0
            if Susano and Susano.GetTextWidth then
                optionWidth = Susano.GetTextWidth(selectedOption, selectorSize)
            else
                optionWidth = string.len(selectedOption) * 9 * scale
            end
            Menu.DrawText(selectorX + leftArrowWidth + optionWidth + (5 * scale), textY, ">", 17,
                Menu.Colors.TextWhite.r / 255.0 * 0.8, Menu.Colors.TextWhite.g / 255.0 * 0.8, Menu.Colors.TextWhite.b / 255.0 * 0.8, 0.8)
        end
    end
end

function Menu.DrawCategories()
    if Menu.OpenedCategory then
        local category = Menu.Categories[Menu.OpenedCategory]
        if not category or not category.hasTabs or not category.tabs then
            Menu.OpenedCategory = nil
            return
        end

        local scaledPos = Menu.GetScaledPosition()
        local x = scaledPos.x
        local startY = scaledPos.y + scaledPos.headerHeight
        local width = scaledPos.width
        local itemHeight = scaledPos.itemHeight
        local mainMenuHeight = scaledPos.mainMenuHeight
        local mainMenuSpacing = scaledPos.mainMenuSpacing

        Menu.DrawTabs(category, x, startY, width, mainMenuHeight)

        local currentTab = category.tabs[Menu.CurrentTab]
        if currentTab and currentTab.items then
            local itemY = startY + mainMenuHeight + mainMenuSpacing
            local totalItems = #currentTab.items
            local maxVisible = Menu.ItemsPerPage

            local nonSeparatorCount = 0
            for _, item in ipairs(currentTab.items) do
                if not item.isSeparator then
                    nonSeparatorCount = nonSeparatorCount + 1
                end
            end

            if Menu.CurrentItem > Menu.ItemScrollOffset + maxVisible then
                Menu.ItemScrollOffset = Menu.CurrentItem - maxVisible
            elseif Menu.CurrentItem <= Menu.ItemScrollOffset then
                Menu.ItemScrollOffset = math.max(0, Menu.CurrentItem - 1)
            end

            local actualVisibleCount = 0
            for i = 1, math.min(maxVisible, totalItems) do
                local itemIndex = i + Menu.ItemScrollOffset
                if itemIndex <= totalItems then
                    actualVisibleCount = actualVisibleCount + 1
                    local item = currentTab.items[itemIndex]
                    local itemYPos = itemY + (i - 1) * itemHeight
                    local isSelected = (itemIndex == Menu.CurrentItem)
                    Menu.DrawItem(x, itemYPos, width, itemHeight, item, isSelected)
                end
            end

            local visibleHeight = actualVisibleCount * itemHeight
            if nonSeparatorCount > 0 then
                Menu.DrawScrollbar(x, itemY, visibleHeight, Menu.CurrentItem, nonSeparatorCount, false, width)
            end
        end
        return
    end

    local scaledPos = Menu.GetScaledPosition()
    local scale = Menu.Scale or 1.0
    local x = scaledPos.x
    local bannerHeight = Menu.Banner.enabled and (Menu.Banner.height * scale) or scaledPos.headerHeight
    local startY = scaledPos.y + bannerHeight
    local width = scaledPos.width
    local itemHeight = scaledPos.itemHeight
    local mainMenuHeight = scaledPos.mainMenuHeight
    local mainMenuSpacing = scaledPos.mainMenuSpacing

    local totalCategories = #Menu.Categories - 1
    local maxVisible = Menu.ItemsPerPage

    if Menu.CurrentCategory > Menu.CategoryScrollOffset + maxVisible + 1 then
        Menu.CategoryScrollOffset = Menu.CurrentCategory - maxVisible - 1
    elseif Menu.CurrentCategory <= Menu.CategoryScrollOffset + 1 then
        Menu.CategoryScrollOffset = math.max(0, Menu.CurrentCategory - 2)
    end

    local itemY = startY
    
   
    local baseR = (Menu.Colors.HeaderPink and Menu.Colors.HeaderPink.r) and (Menu.Colors.HeaderPink.r / 255.0) or 0.58
    local baseG = (Menu.Colors.HeaderPink and Menu.Colors.HeaderPink.g) and (Menu.Colors.HeaderPink.g / 255.0) or 0.0
    local baseB = (Menu.Colors.HeaderPink and Menu.Colors.HeaderPink.b) and (Menu.Colors.HeaderPink.b / 255.0) or 0.83
    
    local gradientSteps = 40
    local stepHeight = mainMenuHeight / gradientSteps
    local gradStartY = itemY
    
    for step = 0, gradientSteps - 1 do
        local stepY = gradStartY + (step * stepHeight)
        local actualStepHeight = stepHeight
        local maxY = gradStartY + mainMenuHeight
        if stepY + actualStepHeight > maxY then
             actualStepHeight = maxY - stepY
        end
        
        local stepGradientFactor = step / (gradientSteps - 1)
      
        local easedFactor = stepGradientFactor * stepGradientFactor * (3.0 - 2.0 * stepGradientFactor)
        local alpha = 0.5 + (easedFactor * 0.5)
        
      
        local brightness = 1.0
        if step < gradientSteps * 0.3 then
            brightness = 1.0 + (0.2 * (1.0 - step / (gradientSteps * 0.3)))
        end
        local stepR = math.min(1.0, baseR * brightness)
        local stepG = math.min(1.0, baseG * brightness)
        local stepB = math.min(1.0, baseB * brightness)
        
        if Susano and Susano.DrawRectFilled then
            Susano.DrawRectFilled(x, stepY, width, actualStepHeight, stepR, stepG, stepB, alpha, 0)
        else
             Menu.DrawRect(x, stepY, width, actualStepHeight, math.floor(stepR*255), math.floor(stepG*255), math.floor(stepB*255), math.floor(alpha*255))
        end
    end
    
    if Menu.TopLevelTabs then
        local tabCount = #Menu.TopLevelTabs
        local tabWidth = width / tabCount
        
        for i, tab in ipairs(Menu.TopLevelTabs) do
            local tabX = x + (i - 1) * tabWidth
            local isSelected = (i == Menu.CurrentTopTab)
            
            if isSelected then
                if not Menu.TopTabSelectorX then
                    Menu.TopTabSelectorX = tabX
                    Menu.TopTabSelectorWidth = tabWidth
                end
                
                local smoothSpeed = Menu.SmoothFactor
                Menu.TopTabSelectorX = Menu.TopTabSelectorX + (tabX - Menu.TopTabSelectorX) * smoothSpeed
                Menu.TopTabSelectorWidth = Menu.TopTabSelectorWidth + (tabWidth - Menu.TopTabSelectorWidth) * smoothSpeed
                
                if math.abs(Menu.TopTabSelectorX - tabX) < 0.5 then Menu.TopTabSelectorX = tabX end
                if math.abs(Menu.TopTabSelectorWidth - tabWidth) < 0.5 then Menu.TopTabSelectorWidth = tabWidth end
                
                local drawX = Menu.TopTabSelectorX
                local drawWidth = Menu.TopTabSelectorWidth
                
                local baseR = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.r) and (Menu.Colors.SelectedBg.r / 255.0) or 1.0
                local baseG = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.g) and (Menu.Colors.SelectedBg.g / 255.0) or 0.0
                local baseB = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.b) and (Menu.Colors.SelectedBg.b / 255.0) or 1.0
                
                local gradientSteps = 40
                local stepHeight = mainMenuHeight / gradientSteps
                local gradStartY = itemY
                
                for step = 0, gradientSteps - 1 do
                    local stepY = gradStartY + (step * stepHeight)
                    local actualStepHeight = stepHeight
                    local maxY = gradStartY + mainMenuHeight
                    if stepY + actualStepHeight > maxY then
                         actualStepHeight = maxY - stepY
                    end
                    
                    local stepGradientFactor = step / (gradientSteps - 1)
                    
                    local easedFactor = stepGradientFactor * stepGradientFactor * (3.0 - 2.0 * stepGradientFactor)
                    local alpha = easedFactor * 0.65
                    
                    
                    local brightness = 1.0
                    if step < gradientSteps * 0.2 then
                        brightness = 1.0 + (0.1 * (1.0 - step / (gradientSteps * 0.2)))
                    end
                    local stepR = math.min(1.0, baseR * brightness)
                    local stepG = math.min(1.0, baseG * brightness)
                    local stepB = math.min(1.0, baseB * brightness)
                    
                    if Susano and Susano.DrawRectFilled then
                        Susano.DrawRectFilled(drawX, stepY, drawWidth, actualStepHeight, stepR, stepG, stepB, alpha, 0)
                    else
                         Menu.DrawRect(drawX, stepY, drawWidth, actualStepHeight, math.floor(stepR*255), math.floor(stepG*255), math.floor(stepB*255), math.floor(alpha*255))
                    end
                end
                
               
                if Susano and Susano.DrawRectFilled then
                    Susano.DrawRectFilled(drawX, itemY + mainMenuHeight - 3, drawWidth, 1, baseR * 0.5, baseG * 0.5, baseB * 0.5, 0.6, 0)
                    Susano.DrawRectFilled(drawX, itemY + mainMenuHeight - 2, drawWidth, 2, baseR, baseG, baseB, 1.0, 0)
                else
                    Menu.DrawRect(drawX, itemY + mainMenuHeight - 3, drawWidth, 1, math.floor(baseR*0.5*255), math.floor(baseG*0.5*255), math.floor(baseB*0.5*255), 153)
                    Menu.DrawRect(drawX, itemY + mainMenuHeight - 2, drawWidth, 2, math.floor(baseR*255), math.floor(baseG*255), math.floor(baseB*255), 255)
                end
            end
            
            local text = tab.name
            local textSize = 16
            local textWidth = 0
            if Susano and Susano.GetTextWidth then
                textWidth = Susano.GetTextWidth(text, textSize)
            else
                textWidth = string.len(text) * 9
            end
            
            local textX = tabX + (tabWidth / 2) - (textWidth / 2)
            local textY = itemY + mainMenuHeight / 2 - 7
            
            local r, g, b = Menu.Colors.TextWhite.r, Menu.Colors.TextWhite.g, Menu.Colors.TextWhite.b
            if not isSelected then
                r, g, b = 150, 150, 150
            end
            
            Menu.DrawText(textX, textY, text, textSize, r/255.0, g/255.0, b/255.0, 1.0)
        end
    else
        local textY = itemY + mainMenuHeight / 2 - 7
        local estimatedTextWidth = string.len(Menu.Categories[1].name) * 9
        local textX = x + (width / 2) - (estimatedTextWidth / 2)
        Menu.DrawText(textX, textY, Menu.Categories[1].name, 16, Menu.Colors.TextWhite.r / 255.0, Menu.Colors.TextWhite.g / 255.0, Menu.Colors.TextWhite.b / 255.0, 1.0)
    end

    local actualVisibleCount = 0
    for displayIndex = 1, math.min(maxVisible, totalCategories) do
        local categoryIndex = displayIndex + Menu.CategoryScrollOffset + 1
        if categoryIndex <= #Menu.Categories then
            actualVisibleCount = actualVisibleCount + 1
            local category = Menu.Categories[categoryIndex]
            local isSelected = (categoryIndex == Menu.CurrentCategory)

            local itemY = startY + mainMenuHeight + mainMenuSpacing + (displayIndex - 1) * itemHeight
            Menu.DrawRect(x, itemY, width, itemHeight, Menu.Colors.BackgroundDark.r, Menu.Colors.BackgroundDark.g, Menu.Colors.BackgroundDark.b, 50)

            if isSelected then
                if Menu.CategorySelectorY == 0 then
                    Menu.CategorySelectorY = itemY
                end

                local smoothSpeed = Menu.SmoothFactor
                Menu.CategorySelectorY = Menu.CategorySelectorY + (itemY - Menu.CategorySelectorY) * smoothSpeed
                if math.abs(Menu.CategorySelectorY - itemY) < 0.5 then
                    Menu.CategorySelectorY = itemY
                end

                local drawY = Menu.CategorySelectorY

                local baseR = Menu.Colors.SelectedBg.r / 255.0
                local baseG = Menu.Colors.SelectedBg.g / 255.0
                local baseB = Menu.Colors.SelectedBg.b / 255.0
                local darkenAmount = 0.4

                local selectorX = x

                if Menu.GradientType == 2 then
                    local gradientSteps = 120
                    local drawWidth = width - 1
                    local stepWidth = drawWidth / gradientSteps
                    local selectorY = drawY
                    local selectorHeight = itemHeight

                    for step = 0, gradientSteps - 1 do
                        local stepX = x + (step * stepWidth)
                        local actualStepWidth = stepWidth
                        
                        if actualStepWidth > 0 then
                            local stepGradientFactor = step / (gradientSteps - 1)
                           
                            local easedFactor = stepGradientFactor < 0.5 
                                and 4 * stepGradientFactor * stepGradientFactor * stepGradientFactor
                                or 1 - math.pow(-2 * stepGradientFactor + 2, 3) / 2
                            local darkenFactor = easedFactor * easedFactor
                            local stepDarken = darkenFactor * 0.75

                            local stepR = math.max(0, baseR - stepDarken)
                            local stepG = math.max(0, baseG - stepDarken)
                            local stepB = math.max(0, baseB - stepDarken)
                            
                           
                            local brightness = 1.0
                            if step < gradientSteps * 0.1 then
                                brightness = 1.0 + (0.15 * (1.0 - step / (gradientSteps * 0.1)))
                            end
                            stepR = math.min(1.0, stepR * brightness)
                            stepG = math.min(1.0, stepG * brightness)
                            stepB = math.min(1.0, stepB * brightness)
                            
                            local alpha = 0.95
                            if step > gradientSteps - 20 then
                                alpha = 0.95 * (1.0 - ((step - (gradientSteps - 20)) / 20))
                            end

                            if Susano and Susano.DrawRectFilled then
                                Susano.DrawRectFilled(stepX, selectorY, actualStepWidth, selectorHeight, stepR, stepG, stepB, alpha, 0.0)
                            else
                                Menu.DrawRect(stepX, selectorY, actualStepWidth, selectorHeight, stepR * 255, stepG * 255, stepB * 255, math.floor(alpha * 255))
                            end
                        end
                    end
                else
                    local gradientSteps = 50
                    local stepHeight = itemHeight / gradientSteps
                    local selectorWidth = width - 1
            
                    for step = 0, gradientSteps - 1 do
                        local stepY = drawY + (step * stepHeight)
                        local actualStepHeight = math.min(stepHeight, (drawY + itemHeight) - stepY)
                        if actualStepHeight > 0 then
                            local stepGradientFactor = step / (gradientSteps - 1)
                            
                            local easedFactor = stepGradientFactor * stepGradientFactor * (3.0 - 2.0 * stepGradientFactor)
                           
                            local stepDarken = easedFactor * darkenAmount * 0.8

                            local stepR = math.max(0, baseR - stepDarken)
                            local stepG = math.max(0, baseG - stepDarken)
                            local stepB = math.max(0, baseB - stepDarken)
                            
                           
                            local brightness = 1.0
                            if step < gradientSteps * 0.15 then
                                brightness = 1.0 + (0.12 * (1.0 - step / (gradientSteps * 0.15)))
                            end
                            stepR = math.min(1.0, stepR * brightness)
                            stepG = math.min(1.0, stepG * brightness)
                            stepB = math.min(1.0, stepB * brightness)

                            if Susano and Susano.DrawRectFilled then
                                Susano.DrawRectFilled(selectorX, stepY, selectorWidth, actualStepHeight, stepR, stepG, stepB, 0.95, 0.0)
                            else
                                Menu.DrawRect(selectorX, stepY, selectorWidth, actualStepHeight, stepR * 255, stepG * 255, stepB * 255, 242)
                            end
                        end
                    end
                end

                Menu.DrawRect(selectorX, drawY, 3, itemHeight, Menu.Colors.SelectedBg.r, Menu.Colors.SelectedBg.g, Menu.Colors.SelectedBg.b, 255)
            end

            local textX = x + 16
            local textY = itemY + itemHeight / 2 - 8
            Menu.DrawText(textX, textY, category.name, 17, Menu.Colors.TextWhite.r / 255.0, Menu.Colors.TextWhite.g / 255.0, Menu.Colors.TextWhite.b / 255.0, 1.0)

            local chevronX = x + width - 22
            Menu.DrawText(chevronX, textY, ">", 17, Menu.Colors.TextWhite.r / 255.0, Menu.Colors.TextWhite.g / 255.0, Menu.Colors.TextWhite.b / 255.0, 1.0)
        end
    end

    if totalCategories > 0 then
        local scrollbarStartY = startY + mainMenuHeight + mainMenuSpacing
        local visibleHeight = actualVisibleCount * itemHeight
        Menu.DrawScrollbar(x, scrollbarStartY, visibleHeight, Menu.CurrentCategory, totalCategories, true, width)
    end
end

function Menu.DrawTopRoundedRect(x, y, width, height, r, g, b, a, radius)
    Menu.DrawRect(x, y + radius, width, height - radius, r, g, b, a)
    Menu.DrawRect(x + radius, y, width - 2 * radius, radius, r, g, b, a)

    for i = 0, radius - 1 do
        local slice_width = math.ceil(math.sqrt(radius * radius - i * i))
        local y_pos = y + radius - 1 - i

        Menu.DrawRect(x + radius - slice_width, y_pos, slice_width, 1, r, g, b, a)

        Menu.DrawRect(x + width - radius, y_pos, slice_width, 1, r, g, b, a)
    end
end

function Menu.DrawRoundedRect(x, y, width, height, r, g, b, a, radius)
    radius = radius or 0
    if radius <= 0 then
        Menu.DrawRect(x, y, width, height, r, g, b, a)
        return
    end
    
    Menu.DrawRect(x + radius, y, width - 2 * radius, height, r, g, b, a)
    Menu.DrawRect(x, y + radius, radius, height - 2 * radius, r, g, b, a)
    Menu.DrawRect(x + width - radius, y + radius, radius, height - 2 * radius, r, g, b, a)
    
    for i = 0, radius - 1 do
        local slice_width = math.ceil(math.sqrt(radius * radius - i * i))
        
        local top_y = y + radius - 1 - i
        Menu.DrawRect(x + radius - slice_width, top_y, slice_width, 1, r, g, b, a)
        Menu.DrawRect(x + width - radius, top_y, slice_width, 1, r, g, b, a)
        
        local bottom_y = y + height - radius + i
        Menu.DrawRect(x + radius - slice_width, bottom_y, slice_width, 1, r, g, b, a)
        Menu.DrawRect(x + width - radius, bottom_y, slice_width, 1, r, g, b, a)
    end
end

function Menu.DrawLoadingBar(alpha)
    if alpha <= 0 then return end

    local screenWidth = 1920
    local screenHeight = 1080
    if Susano and Susano.GetScreenWidth and Susano.GetScreenHeight then
        screenWidth = Susano.GetScreenWidth()
        screenHeight = Susano.GetScreenHeight()
    end

    -- Full-screen dark overlay
    if Susano and Susano.DrawRectFilled then
        Susano.DrawRectFilled(0, 0, screenWidth, screenHeight, 0.0, 0.0, 0.0, 0.82 * alpha, 0)
    else
        Menu.DrawRect(0, 0, screenWidth, screenHeight, 0, 0, 0, math.floor(210 * alpha))
    end

    local accentR = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.r) and (Menu.Colors.SelectedBg.r / 255.0) or 0.58
    local accentG = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.g) and (Menu.Colors.SelectedBg.g / 255.0) or 0.0
    local accentB = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.b) and (Menu.Colors.SelectedBg.b / 255.0) or 0.83

    -- Center card
    local cardW = 320
    local cardH = 200
    local cardX = (screenWidth / 2) - (cardW / 2)
    local cardY = (screenHeight / 2) - (cardH / 2)
    local cardR = 12

    -- Subtle glow behind card
    if Susano and Susano.DrawRectFilled then
        Susano.DrawRectFilled(cardX - 18, cardY - 18, cardW + 36, cardH + 36,
            accentR, accentG, accentB, 0.07 * alpha, cardR + 10)
        Susano.DrawRectFilled(cardX - 8, cardY - 8, cardW + 16, cardH + 16,
            accentR, accentG, accentB, 0.10 * alpha, cardR + 6)
        -- Card background
        Susano.DrawRectFilled(cardX, cardY, cardW, cardH, 0.07, 0.07, 0.09, 1.0 * alpha, cardR)
        -- Thin accent border top
        Susano.DrawRectFilled(cardX + cardR, cardY, cardW - cardR * 2, 2, accentR, accentG, accentB, 0.9 * alpha, 0)
    else
        Menu.DrawRoundedRect(cardX, cardY, cardW, cardH, 18, 18, 23, math.floor(255 * alpha), cardR)
        Menu.DrawRect(cardX + cardR, cardY, cardW - cardR * 2, 2, math.floor(accentR*255), math.floor(accentG*255), math.floor(accentB*255), math.floor(230 * alpha))
    end

    -- Circular progress ring
    local centerX = screenWidth / 2
    local centerY = cardY + 95
    local radius = 44
    local thickness = 7
    local segments = 100
    local step = 360 / segments
    local startAngle = -90
    local progressSegments = math.floor(segments * (Menu.LoadingProgress / 100.0))

    -- Track ring (dark)
    for i = 0, segments do
        local angle = math.rad(startAngle + (i * step))
        local px = centerX + radius * math.cos(angle)
        local py = centerY + radius * math.sin(angle)
        if Susano and Susano.DrawRectFilled then
            Susano.DrawRectFilled(px - thickness/2, py - thickness/2, thickness, thickness, 0.18, 0.18, 0.22, 1.0 * alpha, thickness/2)
        else
            Menu.DrawRect(px - thickness/2, py - thickness/2, thickness, thickness, 46, 46, 56, math.floor(255 * alpha))
        end
    end

    -- Progress arc with glow dots
    for i = 0, progressSegments do
        local angle = math.rad(startAngle + (i * step))
        local px = centerX + radius * math.cos(angle)
        local py = centerY + radius * math.sin(angle)
        local glowFactor = (i == progressSegments) and 1.0 or 0.0
        local dotSize = thickness + 1 + (glowFactor * 3)
        -- Glow halo on tip
        if glowFactor > 0 and Susano and Susano.DrawRectFilled then
            Susano.DrawRectFilled(px - (dotSize+6)/2, py - (dotSize+6)/2, dotSize+6, dotSize+6,
                accentR, accentG, accentB, 0.25 * alpha, (dotSize+6)/2)
        end
        if Susano and Susano.DrawRectFilled then
            Susano.DrawRectFilled(px - dotSize/2, py - dotSize/2, dotSize, dotSize,
                accentR, accentG, accentB, 1.0 * alpha, dotSize/2)
        else
            Menu.DrawRect(px - dotSize/2, py - dotSize/2, dotSize, dotSize,
                math.floor(accentR*255), math.floor(accentG*255), math.floor(accentB*255), math.floor(255 * alpha))
        end
    end

    -- Percent text in ring center
    local percentText = string.format("%d%%", math.floor(Menu.LoadingProgress))
    local percentSize = 18
    local percentW = Susano and Susano.GetTextWidth and Susano.GetTextWidth(percentText, percentSize) or (string.len(percentText) * 10)
    Menu.DrawText(centerX - percentW/2, centerY - percentSize/2, percentText, percentSize, 1.0, 1.0, 1.0, 1.0 * alpha)

    -- Status text above ring
    local currentTime = GetGameTimer() or 0
    local elapsedTime = Menu.LoadingStartTime and (currentTime - Menu.LoadingStartTime) or 0
    local statusText
    if elapsedTime < 1000 then
        statusText = "Initializing..."
    elseif elapsedTime < 2200 then
        statusText = "Loading modules..."
    else
        statusText = "Almost ready..."
    end
    local statusSize = 13
    local statusW = Susano and Susano.GetTextWidth and Susano.GetTextWidth(statusText, statusSize) or (string.len(statusText) * 7)
    Menu.DrawText(centerX - statusW/2, centerY + radius + 14, statusText, statusSize, accentR, accentG, accentB, 0.9 * alpha)

    -- Title at top of card
    local titleText = "Loading"
    local titleSize = 20
    local titleW = Susano and Susano.GetTextWidth and Susano.GetTextWidth(titleText, titleSize) or (string.len(titleText) * 11)
    Menu.DrawText(centerX - titleW/2, cardY + 18, titleText, titleSize, 1.0, 1.0, 1.0, 1.0 * alpha)

    -- Thin progress bar at bottom of card
    local barW = cardW - 48
    local barH = 3
    local barX = cardX + 24
    local barY = cardY + cardH - 20
    if Susano and Susano.DrawRectFilled then
        Susano.DrawRectFilled(barX, barY, barW, barH, 0.2, 0.2, 0.25, 1.0 * alpha, barH/2)
        Susano.DrawRectFilled(barX, barY, barW * (Menu.LoadingProgress / 100.0), barH, accentR, accentG, accentB, 1.0 * alpha, barH/2)
    else
        Menu.DrawRect(barX, barY, barW, barH, 51, 51, 64, math.floor(255 * alpha))
        Menu.DrawRect(barX, barY, math.floor(barW * (Menu.LoadingProgress / 100.0)), barH, math.floor(accentR*255), math.floor(accentG*255), math.floor(accentB*255), math.floor(255 * alpha))
    end
end

function Menu.DrawFooter()
    local scaledPos = Menu.GetScaledPosition()
    local scale = Menu.Scale or 1.0
    local x = scaledPos.x
    local footerY
    local totalHeight
    
    local bannerHeight = Menu.Banner.enabled and (Menu.Banner.height * scale) or scaledPos.headerHeight

    if Menu.OpenedCategory then
        local category = Menu.Categories[Menu.OpenedCategory]
        if category and category.hasTabs and category.tabs then
            local currentTab = category.tabs[Menu.CurrentTab]
            if currentTab and currentTab.items then
                local maxVisible = Menu.ItemsPerPage
                local totalItems = #currentTab.items
                local visibleItems = math.min(maxVisible, totalItems)
                totalHeight = bannerHeight + scaledPos.mainMenuHeight + scaledPos.mainMenuSpacing + (visibleItems * scaledPos.itemHeight)
            else
                totalHeight = bannerHeight + scaledPos.mainMenuHeight + scaledPos.mainMenuSpacing
            end
        else
            totalHeight = bannerHeight + scaledPos.mainMenuHeight + scaledPos.mainMenuSpacing
        end
    else
        local maxVisible = Menu.ItemsPerPage
        local totalCategories = #Menu.Categories - 1
        local visibleCategories = math.min(maxVisible, totalCategories)
        totalHeight = bannerHeight + scaledPos.mainMenuHeight + scaledPos.mainMenuSpacing + (visibleCategories * scaledPos.itemHeight)
    end

    footerY = scaledPos.y + totalHeight + scaledPos.footerSpacing
    local footerWidth = scaledPos.width - 1
    local footerHeight = scaledPos.footerHeight
    local footerRounding = scaledPos.footerRadius

    if Susano and Susano.DrawRectFilled then
        Susano.DrawRectFilled(x, footerY, footerWidth, footerHeight,
            0.0, 0.0, 0.0, 1.0,
            footerRounding)
    else
        Menu.DrawRoundedRect(x, footerY, footerWidth, footerHeight, 0, 0, 0, 255, footerRounding)
    end

    local footerPadding = 15 * scale
    local footerSize = 13
    local scaledFooterSize = footerSize * scale
    local footerTextY = footerY + (footerHeight / 2) - (scaledFooterSize / 2) + (1 * scale)

    local footerText = " https://discord.gg/mghq "
    local currentX = x + footerPadding

    local textWidth = 0
    if Susano and Susano.GetTextWidth then
        textWidth = Susano.GetTextWidth(footerText, scaledFooterSize)
    else
        textWidth = string.len(footerText) * 8 * scale
    end

    Menu.DrawText(currentX, footerTextY, footerText, footerSize, Menu.Colors.TextWhite.r / 255.0, Menu.Colors.TextWhite.g / 255.0, Menu.Colors.TextWhite.b / 255.0, 1.0)

    local displayIndex
    local totalItems

    if Menu.OpenedCategory then
        local category = Menu.Categories[Menu.OpenedCategory]
        if category and category.hasTabs and category.tabs then
            local currentTab = category.tabs[Menu.CurrentTab]
            if currentTab and currentTab.items then
                displayIndex = Menu.CurrentItem
                totalItems = #currentTab.items
            else
                displayIndex = 1
                totalItems = 1
            end
        else
            displayIndex = 1
            totalItems = 1
        end
    else
        displayIndex = Menu.CurrentCategory - 1
        if displayIndex < 1 then displayIndex = 1 end
        totalItems = #Menu.Categories - 1
    end

    local posText = string.format("%d/%d", displayIndex, totalItems)

    local posWidth = 0
    if Susano and Susano.GetTextWidth then
        posWidth = Susano.GetTextWidth(posText, scaledFooterSize)
    else
        posWidth = string.len(posText) * 8 * scale
    end

    local posX = x + footerWidth - posWidth - footerPadding
    Menu.DrawText(posX, footerTextY, posText, footerSize, Menu.Colors.TextWhite.r / 255.0, Menu.Colors.TextWhite.g / 255.0, Menu.Colors.TextWhite.b / 255.0, 1.0)
end

function Menu.DrawKeySelector(alpha)
    if alpha <= 0 then return end

    local screenWidth = 1920
    local screenHeight = 1080
    if Susano and Susano.GetScreenWidth and Susano.GetScreenHeight then
        screenWidth = Susano.GetScreenWidth()
        screenHeight = Susano.GetScreenHeight()
    end

    local accentR = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.r) and (Menu.Colors.SelectedBg.r / 255.0) or 0.58
    local accentG = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.g) and (Menu.Colors.SelectedBg.g / 255.0) or 0.0
    local accentB = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.b) and (Menu.Colors.SelectedBg.b / 255.0) or 0.83

    -- Dimmed overlay
    if Susano and Susano.DrawRectFilled then
        Susano.DrawRectFilled(0, 0, screenWidth, screenHeight, 0.0, 0.0, 0.0, 0.7 * alpha, 0)
    else
        Menu.DrawRect(0, 0, screenWidth, screenHeight, 0, 0, 0, math.floor(180 * alpha))
    end

    local isBinding = Menu.SelectingBind and Menu.BindingItem ~= nil
    local itemName = isBinding and (Menu.BindingItem.name or "Option") or "Menu Toggle"
    local keyName = isBinding and Menu.BindingKeyName or Menu.SelectedKeyName
    if not keyName then keyName = "?" end

    local cardW = 380
    local cardH = 180
    local cardX = math.floor((screenWidth - cardW) / 2)
    local cardY = math.floor((screenHeight - cardH) / 2)
    local cardR = 10

    -- Card glow
    if Susano and Susano.DrawRectFilled then
        Susano.DrawRectFilled(cardX - 20, cardY - 20, cardW + 40, cardH + 40, accentR, accentG, accentB, 0.06 * alpha, cardR + 12)
        Susano.DrawRectFilled(cardX - 8, cardY - 8, cardW + 16, cardH + 16, accentR, accentG, accentB, 0.10 * alpha, cardR + 6)
        -- Card body
        Susano.DrawRectFilled(cardX, cardY, cardW, cardH, 0.07, 0.07, 0.09, 1.0 * alpha, cardR)
        -- Top accent line
        Susano.DrawRectFilled(cardX + cardR, cardY, cardW - cardR * 2, 2, accentR, accentG, accentB, 0.9 * alpha, 0)
    else
        Menu.DrawRoundedRect(cardX, cardY, cardW, cardH, 18, 18, 23, math.floor(255 * alpha), cardR)
        Menu.DrawRect(cardX + cardR, cardY, cardW - cardR * 2, 2, math.floor(accentR*255), math.floor(accentG*255), math.floor(accentB*255), math.floor(230 * alpha))
    end

    -- Title
    local title = isBinding and "BIND KEY" or "SELECT TOGGLE KEY"
    local titleSize = 15
    local titleW = Susano and Susano.GetTextWidth and Susano.GetTextWidth(title, titleSize) or (string.len(title) * 9)
    Menu.DrawText(math.floor(cardX + cardW/2 - titleW/2), cardY + 16, title, titleSize, 1.0, 1.0, 1.0, 1.0 * alpha)

    -- Subtitle / item name
    local subSize = 12
    local subText = isBinding and ("Binding: " .. itemName) or "Press any key to set the menu toggle"
    local subW = Susano and Susano.GetTextWidth and Susano.GetTextWidth(subText, subSize) or (string.len(subText) * 7)
    Menu.DrawText(math.floor(cardX + cardW/2 - subW/2), cardY + 36, subText, subSize, accentR, accentG, accentB, 0.85 * alpha)

    -- Divider
    local divY = cardY + 56
    if Susano and Susano.DrawRectFilled then
        Susano.DrawRectFilled(cardX + 20, divY, cardW - 40, 1, 1.0, 1.0, 1.0, 0.06 * alpha, 0)
    else
        Menu.DrawRect(cardX + 20, divY, cardW - 40, 1, 255, 255, 255, math.floor(15 * alpha))
    end

    -- Key display box (large, centered)
    local keyBoxW = 100
    local keyBoxH = 52
    local keyBoxX = math.floor(cardX + cardW/2 - keyBoxW/2)
    local keyBoxY = cardY + 72
    if Susano and Susano.DrawRectFilled then
        Susano.DrawRectFilled(keyBoxX - 2, keyBoxY - 2, keyBoxW + 4, keyBoxH + 4, accentR, accentG, accentB, 0.35 * alpha, 10)
        Susano.DrawRectFilled(keyBoxX, keyBoxY, keyBoxW, keyBoxH, 0.12, 0.12, 0.16, 1.0 * alpha, 8)
    else
        Menu.DrawRoundedRect(keyBoxX, keyBoxY, keyBoxW, keyBoxH, 31, 31, 41, math.floor(255 * alpha), 8)
    end

    local keyTextSize = 20
    local keyW = Susano and Susano.GetTextWidth and Susano.GetTextWidth(keyName, keyTextSize) or (string.len(keyName) * 11)
    Menu.DrawText(math.floor(keyBoxX + keyBoxW/2 - keyW/2), math.floor(keyBoxY + keyBoxH/2 - keyTextSize/2), keyName, keyTextSize, accentR, accentG, accentB, 1.0 * alpha)

    -- Hint at bottom
    local hintText = isBinding and "[ENTER] Confirm   [ESC] Cancel" or "[ENTER] Confirm"
    local hintSize = 11
    local hintW = Susano and Susano.GetTextWidth and Susano.GetTextWidth(hintText, hintSize) or (string.len(hintText) * 6)
    Menu.DrawText(math.floor(cardX + cardW/2 - hintW/2), cardY + cardH - 20, hintText, hintSize, 0.55, 0.55, 0.6, 0.85 * alpha)
end

function Menu.DrawKeybindsInterface(alpha)
    if alpha <= 0 then
        return
    end

    local screenWidth = 1920
    local screenHeight = 1080
    if Susano and Susano.GetScreenWidth and Susano.GetScreenHeight then
        screenWidth = Susano.GetScreenWidth()
        screenHeight = Susano.GetScreenHeight()
    end

    local activeBinds = {}
    for _, cat in ipairs(Menu.Categories) do
        if cat.hasTabs and cat.tabs then
            for _, tab in ipairs(cat.tabs) do
                if tab.items then
                    for _, item in ipairs(tab.items) do
                        if item.bindKey and item.bindKeyName and (item.type == "toggle" or item.type == "action") then
                            table.insert(activeBinds, {
                                name = item.name,
                                keyName = item.bindKeyName,
                                isActive = (item.type == "toggle" and (item.value or false)) or nil
                            })
                        end
                    end
                end
            end
        end
    end

    if #activeBinds == 0 then
        return
    end

    local padding = 15
    local cornerRadius = 8
    local barHeight = 2
    local lineHeight = 25
    local textSize = 14
    local headerHeight = 40
    
    local maxWidth = 0
    for _, bind in ipairs(activeBinds) do
        local status = bind.isActive and "on" or "off"
        local text = bind.name .. " (" .. bind.keyName .. ") [" .. status .. "]"
        local textWidth = 0
        if Susano and Susano.GetTextWidth then
            textWidth = Susano.GetTextWidth(text, textSize)
        else
            textWidth = string.len(text) * 8
        end
        if textWidth > maxWidth then
            maxWidth = textWidth
        end
    end
    
    local width = math.max(200, maxWidth + (padding * 2))
    local startX = screenWidth - width - 20
    local startY = 20

    local contentHeight = #activeBinds * lineHeight
    local totalHeight = headerHeight + barHeight + padding + contentHeight + padding

    local menuR = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.r) and (Menu.Colors.SelectedBg.r / 255.0) or 0.4
    local menuG = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.g) and (Menu.Colors.SelectedBg.g / 255.0) or 0.2
    local menuB = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.b) and (Menu.Colors.SelectedBg.b / 255.0) or 0.8

    local bgAlpha = 0.6 * alpha
    if Susano and Susano.DrawRectFilled then
        Susano.DrawRectFilled(startX, startY, width, totalHeight, 0.0, 0.0, 0.0, bgAlpha, cornerRadius)
    else
        Menu.DrawRoundedRect(startX, startY, width, totalHeight, 0, 0, 0, math.floor(255 * bgAlpha), cornerRadius)
    end

    local textX = startX + padding
    local textY = startY + padding
    Menu.DrawText(textX - 1, textY - 1, "keybind", textSize, 0.0, 0.0, 0.0, 1.0 * alpha)
    Menu.DrawText(textX + 1, textY - 1, "keybind", textSize, 0.0, 0.0, 0.0, 1.0 * alpha)
    Menu.DrawText(textX - 1, textY + 1, "keybind", textSize, 0.0, 0.0, 0.0, 1.0 * alpha)
    Menu.DrawText(textX + 1, textY + 1, "keybind", textSize, 0.0, 0.0, 0.0, 1.0 * alpha)
    Menu.DrawText(textX, textY, "keybind", textSize, 1.0, 1.0, 1.0, 1.0 * alpha)

    local barY = startY + headerHeight
    if Susano and Susano.DrawRectFilled then
        Susano.DrawRectFilled(startX + padding, barY, width - 2 * padding, barHeight, menuR, menuG, menuB, 1.0 * alpha, 0)
    else
        Menu.DrawRect(startX + padding, barY, width - 2 * padding, barHeight, math.floor(menuR * 255), math.floor(menuG * 255), math.floor(menuB * 255), math.floor(255 * alpha))
    end

    local currentY = barY + barHeight + padding
    for i, bind in ipairs(activeBinds) do
        local text
        if bind.isActive ~= nil then
            local status = bind.isActive and "on" or "off"
            text = bind.name .. " (" .. bind.keyName .. ") [" .. status .. "]"
        else
            text = bind.name .. " (" .. bind.keyName .. ")"
        end
        local bindTextX = startX + padding
        local bindTextY = currentY + (i - 1) * lineHeight

        Menu.DrawText(bindTextX - 1, bindTextY - 1, text, textSize, 0.0, 0.0, 0.0, 1.0 * alpha)
        Menu.DrawText(bindTextX + 1, bindTextY - 1, text, textSize, 0.0, 0.0, 0.0, 1.0 * alpha)
        Menu.DrawText(bindTextX - 1, bindTextY + 1, text, textSize, 0.0, 0.0, 0.0, 1.0 * alpha)
        Menu.DrawText(bindTextX + 1, bindTextY + 1, text, textSize, 0.0, 0.0, 0.0, 1.0 * alpha)
        Menu.DrawText(bindTextX, bindTextY, text, textSize, 1.0, 1.0, 1.0, 1.0 * alpha)
    end
end

Menu.Particles = {}
for i = 1, 80 do
    table.insert(Menu.Particles, {
        x = math.random(0, 100) / 100,
        y = math.random(0, 100) / 100,
        speedY = math.random(20, 100) / 10000,
        speedX = math.random(-20, 20) / 10000,
        size = math.random(1, 2),
        life = math.random(10, 50)
    })
end

function Menu.GetLayoutSegments()
    local segments = {}
    local scaledPos = Menu.GetScaledPosition()
    local scale = Menu.Scale or 1.0
    local x = scaledPos.x
    local startY = scaledPos.y
    local width = scaledPos.width
    
    local bannerHeight = Menu.Banner.enabled and (Menu.Banner.height * scale) or scaledPos.headerHeight
    local headerH = bannerHeight
    local menuBarH = scaledPos.mainMenuHeight
    local spacing = scaledPos.mainMenuSpacing
    local itemH = scaledPos.itemHeight
    local footerSpacing = scaledPos.footerSpacing
    local footerH = scaledPos.footerHeight
    
    local topSegmentH = headerH + menuBarH
    
    local menuBarY = startY + headerH
    local menuBarSegmentH = menuBarH
    table.insert(segments, {y = menuBarY, h = menuBarSegmentH})
    
    local itemsY = startY + topSegmentH + spacing
    local itemsH = 0
    
    if Menu.OpenedCategory then
        local category = Menu.Categories[Menu.OpenedCategory]
        if category and category.hasTabs and category.tabs then
            local currentTab = category.tabs[Menu.CurrentTab]
            if currentTab and currentTab.items then
                local maxVisible = Menu.ItemsPerPage
                local totalItems = #currentTab.items
                local visibleItems = math.min(maxVisible, totalItems)
                itemsH = visibleItems * itemH
            end
        end
    else
        local maxVisible = Menu.ItemsPerPage
        local totalCategories = #Menu.Categories - 1
        local visibleCategories = math.min(maxVisible, totalCategories)
        itemsH = visibleCategories * itemH
    end
    
    if itemsH > 0 then
        table.insert(segments, {y = itemsY, h = itemsH})
    end
    
    local footerY = itemsY + itemsH + footerSpacing
    table.insert(segments, {y = footerY, h = footerH})
    
    local fullHeight = (itemsY + itemsH) - startY
    if fullHeight <= 0 then
        fullHeight = (footerY + footerH) - startY
    end
    
    return segments, fullHeight
end

function Menu.DrawBackground()
    local scaledPos = Menu.GetScaledPosition()
    local x = scaledPos.x
    local y = scaledPos.y
    local width = scaledPos.width - 1
    
    local segments, fullHeight = Menu.GetLayoutSegments()

    local r = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.r) or 148
    local g = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.g) or 0
    local b = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.b) or 211
    
    local startY = scaledPos.y
    local scale = Menu.Scale or 1.0
    local bannerHeight = Menu.Banner.enabled and (Menu.Banner.height * scale) or scaledPos.headerHeight
    local headerH = bannerHeight
    local menuBarH = scaledPos.mainMenuHeight
    local spacing = scaledPos.mainMenuSpacing
    local itemH = scaledPos.itemHeight
    
    local itemsY = 0
    local itemsH = 0
    
    if Menu.OpenedCategory then
        itemsY = startY + headerH + menuBarH + spacing
        
        local category = Menu.Categories[Menu.OpenedCategory]
        if category and category.hasTabs and category.tabs then
            local currentTab = category.tabs[Menu.CurrentTab]
            if currentTab and currentTab.items then
                local maxVisible = Menu.ItemsPerPage
                local totalItems = #currentTab.items
                local visibleItems = math.min(maxVisible, totalItems)
                itemsH = visibleItems * itemH
            end
        end
    else
        itemsY = startY + headerH + menuBarH + spacing
        
        local maxVisible = Menu.ItemsPerPage
        local totalCategories = #Menu.Categories - 1
        local visibleCategories = math.min(maxVisible, totalCategories)
        itemsH = visibleCategories * itemH
    end
    
    local itemsEndY = itemsY + itemsH
    
  
    local menuBarY = startY + headerH
    local menuBarEndY = menuBarY + menuBarH
    
    for i, seg in ipairs(segments) do
        if i == #segments then
            break
        end
        
        if seg.y >= itemsEndY then
            break
        end
        
       
      
        if seg.y < menuBarY then
          
            local offset = menuBarY - seg.y
            if offset >= seg.h then
                
            else
               
                seg = {y = menuBarY, h = seg.h - offset}
            end
        end
        
      
        if seg.y < menuBarY or seg.h <= 0 then
            
        else
        local segSteps = math.ceil(seg.h / 2)
        
        for i = 0, segSteps - 1 do
            local localY = i * 2
            local drawH = 2
            if localY + drawH > seg.h then drawH = seg.h - localY end
            
            local currentY = seg.y + localY
                
              
                if currentY < menuBarY then
                    
                    local adjust = menuBarY - currentY
                    if adjust >= drawH then
                       
                    else
                        currentY = menuBarY
                        drawH = drawH - adjust
                    end
                end
            
            
            if currentY >= menuBarEndY and currentY < itemsY then
               
            else
                if currentY >= itemsEndY then
                    break
                end
                if currentY + drawH > itemsEndY then
                    drawH = itemsEndY - currentY
                    if drawH <= 0 then
                        break
                    end
                end
                
               
                local isTabArea = false
                if currentY >= menuBarY and currentY < menuBarEndY then
                    isTabArea = true
                end
                
                
                local backgroundAlpha = 1.0
                
               
                if isTabArea then
                    backgroundAlpha = 1.0
                else
                   
                    local blackBackgroundItem = nil
                    if Menu.Categories then
                        for _, cat in ipairs(Menu.Categories) do
                            if cat.name == "Settings" and cat.tabs then
                                for _, tab in ipairs(cat.tabs) do
                                    if tab.name == "General" and tab.items then
                                        for _, item in ipairs(tab.items) do
                                            if item.name == "Black Background" then
                                                blackBackgroundItem = item
                                                break
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    
                    if blackBackgroundItem and blackBackgroundItem.value == false then
                        backgroundAlpha = 0.2
                    else
                        backgroundAlpha = 1.0
                    end
                end

                if Susano and Susano.DrawRectFilled then
                    Susano.DrawRectFilled(x, currentY, width, drawH, 0.0, 0.0, 0.0, backgroundAlpha, 0)
                else
                    Menu.DrawRect(x, currentY, width, drawH, 0, 0, 0, math.floor(backgroundAlpha * 255))
                end
            end
        end
        end
    end

    if Menu.ShowSnowflakes then
        for _, p in ipairs(Menu.Particles) do
            p.y = p.y + p.speedY
            p.x = p.x + p.speedX

            if p.y > 1.0 then
                p.y = 0
                p.x = math.random(0, 100) / 100
                p.speedY = math.random(20, 100) / 10000
                p.speedX = math.random(-20, 20) / 10000
            end

            local pX = x + (p.x * width)
            local pY = y + (p.y * fullHeight)
            
            local isVisible = false
            for i, seg in ipairs(segments) do
                if i == #segments then
                    break
                end
                if pY >= seg.y and pY <= seg.y + seg.h then
                    isVisible = true
                    break
                end
            end
            
            if isVisible then
                 local alpha = math.random(100, 200)
                 if Susano and Susano.DrawRectFilled then
                    Susano.DrawRectFilled(pX, pY, p.size, p.size, 1.0, 1.0, 1.0, alpha/255, 0)
                else
                    Menu.DrawRect(pX, pY, p.size, p.size, 255, 255, 255, alpha)
                end
            end
        end
    end
end


function Menu.Render()
    if Menu.TopLevelTabs and not Menu.Categories then
        Menu.UpdateCategoriesFromTopTab()
    end

    if not (Susano and Susano.BeginFrame) then
        return
    end

    local dt = 0.016
    if GetFrameTime then
        dt = GetFrameTime()
    end
    local animSpeed = 5.0 * dt

    if Menu.IsLoading then
        Menu.LoadingBarAlpha = math.min(1.0, Menu.LoadingBarAlpha + animSpeed)
    else
        Menu.LoadingBarAlpha = math.max(0.0, Menu.LoadingBarAlpha - animSpeed)
    end

    if Menu.SelectingKey or Menu.SelectingBind then
        Menu.KeySelectorAlpha = math.min(1.0, Menu.KeySelectorAlpha + animSpeed)
    else
        Menu.KeySelectorAlpha = math.max(0.0, Menu.KeySelectorAlpha - animSpeed)
    end

    if Menu.ShowKeybinds then
        Menu.KeybindsInterfaceAlpha = math.min(1.0, Menu.KeybindsInterfaceAlpha + animSpeed)
    else
        Menu.KeybindsInterfaceAlpha = math.max(0.0, Menu.KeybindsInterfaceAlpha - animSpeed)
    end

    Susano.BeginFrame()

    if Menu.KeybindsInterfaceAlpha > 0 then
        Menu.DrawKeybindsInterface(Menu.KeybindsInterfaceAlpha)
    end

    if Menu.Visible then
        if Menu.EditorMode and Susano and Susano.EnableOverlay then
            Susano.EnableOverlay(true)
        elseif not Menu.EditorMode and Susano and Susano.EnableOverlay then
            Susano.EnableOverlay(false)
        end
        
        Menu.DrawBackground()
        Menu.DrawHeader()
        Menu.DrawCategories()
        Menu.DrawFooter()
    end

    if Menu.InputOpen then
        Menu.DrawInputWindow()
    end

    if Menu.LoadingBarAlpha > 0 then
        Menu.DrawLoadingBar(Menu.LoadingBarAlpha)
    end

    if Menu.KeySelectorAlpha > 0 then
        Menu.DrawKeySelector(Menu.KeySelectorAlpha)
    end

    if Menu.OnRender then
        local success, err = pcall(Menu.OnRender)
        if not success then
        end
    end

    if Susano.SubmitFrame then
        Susano.SubmitFrame()
    end

    if not Menu.Visible and not Menu.ShowKeybinds and Menu.LoadingBarAlpha <= 0 and Menu.KeySelectorAlpha <= 0 then
        if Susano.ResetFrame then
            Susano.ResetFrame()
        end
    end
end

Menu.KeyStates = {}

function Menu.IsKeyJustPressed(keyCode)
    if not (Susano and Susano.GetAsyncKeyState) then
        return false
    end

    local down, pressed = Susano.GetAsyncKeyState(keyCode)
    local wasDown = Menu.KeyStates[keyCode] or false

    if down == true then
        Menu.KeyStates[keyCode] = true
    else
        Menu.KeyStates[keyCode] = false
    end

    if pressed == true then
        return true
    end

    if down == true and not wasDown then
        return true
    end

    return false
end


Menu.KeyNames = {
    [0x08] = "Backspace", [0x09] = "Tab", [0x0D] = "Enter", [0x10] = "Shift",
    [0x11] = "Ctrl", [0x12] = "Alt", [0x13] = "Pause", [0x14] = "Caps Lock",
    [0x1B] = "ESC", [0x20] = "Space", [0x21] = "Page Up", [0x22] = "Page Down",
    [0x23] = "End", [0x24] = "Home", [0x25] = "Left", [0x26] = "Up",
    [0x27] = "Right", [0x28] = "Down", [0x2D] = "Insert", [0x2E] = "Delete",
    [0x30] = "0", [0x31] = "1", [0x32] = "2", [0x33] = "3", [0x34] = "4",
    [0x35] = "5", [0x36] = "6", [0x37] = "7", [0x38] = "8", [0x39] = "9",
    [0x41] = "A", [0x42] = "B", [0x43] = "C", [0x44] = "D", [0x45] = "E",
    [0x46] = "F", [0x47] = "G", [0x48] = "H", [0x49] = "I", [0x4A] = "J",
    [0x4B] = "K", [0x4C] = "L", [0x4D] = "M", [0x4E] = "N", [0x4F] = "O",
    [0x50] = "P", [0x51] = "Q", [0x52] = "R", [0x53] = "S", [0x54] = "T",
    [0x55] = "U", [0x56] = "V", [0x57] = "W", [0x58] = "X", [0x59] = "Y",
    [0x5A] = "Z", [0x60] = "Numpad 0", [0x61] = "Numpad 1", [0x62] = "Numpad 2",
    [0x63] = "Numpad 3", [0x64] = "Numpad 4", [0x65] = "Numpad 5", [0x66] = "Numpad 6",
    [0x67] = "Numpad 7", [0x68] = "Numpad 8", [0x69] = "Numpad 9",
    [0x6A] = "Multiply", [0x6B] = "Add", [0x6D] = "Subtract", [0x6E] = "Decimal",
    [0x6F] = "Divide", [0x70] = "F1", [0x71] = "F2", [0x72] = "F3", [0x73] = "F4",
    [0x74] = "F5", [0x75] = "F6", [0x76] = "F7", [0x77] = "F8", [0x78] = "F9",
    [0x79] = "F10", [0x7A] = "F11", [0x7B] = "F12",
    [0x90] = "Num Lock", [0x91] = "Scroll Lock",
    [0xA0] = "Left Shift", [0xA1] = "Right Shift", [0xA2] = "Left Ctrl",
    [0xA3] = "Right Ctrl", [0xA4] = "Left Alt", [0xA5] = "Right Alt"
}

function Menu.GetKeyName(keyCode)
    return Menu.KeyNames[keyCode] or ("Key 0x" .. string.format("%02X", keyCode))
end

function Menu.HandleInput()
    if Menu.IsLoading or not Menu.LoadingComplete then
        return
    end

    if Menu.InputOpen then
        return
    end

    if Menu.SelectingBind then
        if not (Susano and Susano.GetAsyncKeyState) then
            return
        end

        if Menu.IsKeyJustPressed(0x0D) then
            if Menu.BindingKey and Menu.BindingItem then
                Menu.BindingItem.bindKey = Menu.BindingKey
                Menu.BindingItem.bindKeyName = Menu.BindingKeyName
                local itemName = Menu.BindingItem.name or "option"
                local savedKeyName = Menu.BindingKeyName
                Menu.SelectingBind = false
                Menu.BindingItem = nil
                Menu.BindingKey = nil
                Menu.BindingKeyName = nil
                print("Bind set for " .. itemName .. ": " .. tostring(savedKeyName))
            end
            return
        end

        local keysToCheck = {
            0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D,
            0x4E, 0x4F, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A,
            0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
            0x20, 0x1B, 0x08, 0x09, 0x10, 0x11, 0x12,
            0x25, 0x26, 0x27, 0x28,
            0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x7B
        }

        for _, keyCode in ipairs(keysToCheck) do
            if keyCode ~= 0x0D then
                local down, pressed = Susano.GetAsyncKeyState(keyCode)
                if down == true or pressed == true then
                    local wasDown = Menu.KeyStates[keyCode] or false
                    if (pressed == true) or (down == true and not wasDown) then
                        Menu.BindingKey = keyCode
                        Menu.BindingKeyName = Menu.GetKeyName(keyCode)
                        Menu.KeyStates[keyCode] = true
                        break
                    end
                    if down == true then
                        Menu.KeyStates[keyCode] = true
                    else
                        Menu.KeyStates[keyCode] = false
                    end
                end
            end
        end
        return
    end

    if Menu.SelectingKey then
        if not (Susano and Susano.GetAsyncKeyState) then
            return
        end

        if Menu.IsKeyJustPressed(0x0D) then
            if Menu.SelectedKey then
                Menu.SelectingKey = false
            end
            return
        end

        local keysToCheck = {
            0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D,
            0x4E, 0x4F, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A,
            0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
            0x20, 0x1B, 0x08, 0x09, 0x10, 0x11, 0x12,
            0x25, 0x26, 0x27, 0x28,
            0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x7B
        }

        for _, keyCode in ipairs(keysToCheck) do
            if keyCode ~= 0x0D then
                local down, pressed = Susano.GetAsyncKeyState(keyCode)
                if down == true or pressed == true then
                    local wasDown = Menu.KeyStates[keyCode] or false
                    if (pressed == true) or (down == true and not wasDown) then
                        Menu.SelectedKey = keyCode
                        Menu.SelectedKeyName = Menu.GetKeyName(keyCode)
                        Menu.KeyStates[keyCode] = true
                        break
                    end
                    if down == true then
                        Menu.KeyStates[keyCode] = true
                    else
                        Menu.KeyStates[keyCode] = false
                    end
                end
            end
        end
        return
    end

    if Susano and Susano.GetAsyncKeyState then
        if Menu.Categories then
            for _, category in ipairs(Menu.Categories) do
                if category and category.hasTabs and category.tabs then
                    for _, tab in ipairs(category.tabs) do
                        if tab and tab.items then
                            for _, item in ipairs(tab.items) do
                                if item and item.bindKey and (item.type == "toggle" or item.type == "action") then
                                    local down, pressed = Susano.GetAsyncKeyState(item.bindKey)
                                    local wasDown = Menu.KeyStates[item.bindKey] or false

                                    if down == true then
                                        Menu.KeyStates[item.bindKey] = true
                                    else
                                        Menu.KeyStates[item.bindKey] = false
                                    end

                                    if (pressed == true) or (down == true and not wasDown) then
                                        if item.type == "toggle" then
                                            item.value = not item.value
                                            if item.name == "Editor Mode" then
                                                Menu.EditorMode = item.value
                                            end
                                            if item.onClick then
                                                item.onClick(item.value)
                                            end
                                            print("Toggled " .. (item.name or "option") .. " to " .. tostring(item.value))
                                        elseif item.type == "action" then
                                            if item.onClick then
                                                item.onClick()
                                            end
                                            print("Executed action: " .. (item.name or "option"))
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local toggleKeyCode = Menu.SelectedKey or 0x31
    if Susano and Susano.GetAsyncKeyState then
        local down, pressed = Susano.GetAsyncKeyState(toggleKeyCode)

        local wasDown = Menu.KeyStates[toggleKeyCode] or false
        local keyPressed = false

        if pressed == true then
            keyPressed = true
        elseif down == true and not wasDown then
            keyPressed = true
        end

        if down == true then
            Menu.KeyStates[toggleKeyCode] = true
        else
            Menu.KeyStates[toggleKeyCode] = false
        end

        if keyPressed then
            local wasVisible = Menu.Visible
            Menu.Visible = not Menu.Visible

            if wasVisible and not Menu.Visible and not Menu.ShowKeybinds then
                if Susano and Susano.ResetFrame then
                    Susano.ResetFrame()
                end
            end
        end
    end

    if not Menu.Visible then
        return
    end

    if Menu.EditorMode then
        local moveSpeed = 8.0
        local screenW = 1920
        local screenH = 1080
        if Susano and Susano.GetScreenWidth and Susano.GetScreenHeight then
            screenW = Susano.GetScreenWidth()
            screenH = Susano.GetScreenHeight()
        end

        if Susano and Susano.GetCursorPos and Susano.GetAsyncKeyState then
            local cursorPos = Susano.GetCursorPos()
            local mouseX = 0
            local mouseY = 0
            
            if cursorPos then
                if type(cursorPos) == "table" then
                    mouseX = cursorPos[1] or cursorPos.x or 0
                    mouseY = cursorPos[2] or cursorPos.y or 0
                else
                    local xOk, x = pcall(function() return cursorPos.x end)
                    local yOk, y = pcall(function() return cursorPos.y end)
                    if xOk and x then mouseX = x end
                    if yOk and y then mouseY = y end
                end
            end
            
            local leftMouseDown = false
            if Susano.GetAsyncKeyState then
                local lmbDown, lmbPressed = Susano.GetAsyncKeyState(0x01)
                if lmbDown == true or lmbDown == 1 then
                    leftMouseDown = true
                end
            end
            
            if not leftMouseDown and (IsControlPressed or IsDisabledControlPressed) then
                if IsDisabledControlPressed and IsDisabledControlPressed(0, 24) then
                    leftMouseDown = true
                elseif IsControlPressed and IsControlPressed(0, 24) then
                    leftMouseDown = true
                end
            end
            
            local menuX = Menu.Position.x
            local menuY = Menu.Position.y
            local menuWidth = Menu.Position.width
            
            local totalHeight = Menu.Position.headerHeight
            if Menu.OpenedCategory then
                local category = Menu.Categories[Menu.OpenedCategory]
                if category and category.hasTabs and category.tabs then
                    local currentTab = category.tabs[Menu.CurrentTab]
                    if currentTab and currentTab.items then
                        local maxVisible = Menu.ItemsPerPage
                        local totalItems = #currentTab.items
                        local visibleItems = math.min(maxVisible, totalItems)
                        totalHeight = totalHeight + Menu.Position.mainMenuHeight + Menu.Position.mainMenuSpacing + (visibleItems * Menu.Position.itemHeight)
                    else
                        totalHeight = totalHeight + Menu.Position.mainMenuHeight + Menu.Position.mainMenuSpacing
                    end
                else
                    totalHeight = totalHeight + Menu.Position.mainMenuHeight + Menu.Position.mainMenuSpacing
                end
            else
                local maxVisible = Menu.ItemsPerPage
                local totalCategories = #Menu.Categories - 1
                local visibleCategories = math.min(maxVisible, totalCategories)
                totalHeight = totalHeight + Menu.Position.mainMenuHeight + Menu.Position.mainMenuSpacing + (visibleCategories * Menu.Position.itemHeight)
            end
            totalHeight = totalHeight + Menu.Position.footerSpacing + Menu.Position.footerHeight
            
            local isOverMenu = (mouseX >= menuX and mouseX <= menuX + menuWidth and 
                               mouseY >= menuY and mouseY <= menuY + totalHeight)
            
            local wasMouseDown = Menu.KeyStates[0x01] or false
            
            if leftMouseDown then
                if not wasMouseDown and isOverMenu then
                    Menu.EditorDragging = true
                    Menu.EditorDragOffsetX = mouseX - menuX
                    Menu.EditorDragOffsetY = mouseY - menuY
                    print("Started dragging menu")
                end
                
                if Menu.EditorDragging then
                    local newX = mouseX - Menu.EditorDragOffsetX
                    local newY = mouseY - Menu.EditorDragOffsetY
                    
                    local maxX = math.max(0, screenW - menuWidth)
                    local maxY = math.max(0, screenH - totalHeight)
                    
                    Menu.Position.x = math.max(0, math.min(maxX, newX))
                    Menu.Position.y = math.max(0, math.min(maxY, newY))
                end
                
                Menu.KeyStates[0x01] = true
            else
                Menu.EditorDragging = false
                Menu.KeyStates[0x01] = false
            end
        end

        if Susano and Susano.GetAsyncKeyState then
            local upDown = Susano.GetAsyncKeyState(0x26)
            local downDown = Susano.GetAsyncKeyState(0x28)
            local leftDown = Susano.GetAsyncKeyState(0x25)
            local rightDown = Susano.GetAsyncKeyState(0x27)

            if upDown == true then
                Menu.Position.y = math.max(0, Menu.Position.y - moveSpeed)
            end
            if downDown == true then
                Menu.Position.y = math.min(screenH - 200, Menu.Position.y + moveSpeed)
            end
            if leftDown == true then
                Menu.Position.x = math.max(0, Menu.Position.x - moveSpeed)
            end
            if rightDown == true then
                Menu.Position.x = math.min(screenW - Menu.Position.width, Menu.Position.x + moveSpeed)
            end

            if Menu.IsKeyJustPressed(0x0D) then
                local currentTab = nil
                if Menu.OpenedCategory then
                    local category = Menu.Categories[Menu.OpenedCategory]
                    if category and category.hasTabs and category.tabs then
                        currentTab = category.tabs[Menu.CurrentTab]
                    end
                end
                if currentTab and currentTab.items then
                    for _, item in ipairs(currentTab.items) do
                        if item.name == "Editor Mode" and item.type == "toggle" then
                            item.value = not item.value
                            Menu.EditorMode = item.value
                            break
                        end
                    end
                end
            end
        end
        return
    end

    if Menu.OpenedCategory then
        local category = Menu.Categories[Menu.OpenedCategory]
        if not category or not category.hasTabs or not category.tabs then
            Menu.OpenedCategory = nil
            return
        end

        local currentTab = category.tabs[Menu.CurrentTab]
        if currentTab and currentTab.items then
            if Susano and Susano.GetAsyncKeyState then
                local upDown, upPressed = Susano.GetAsyncKeyState(0x26)
                local downDown, downPressed = Susano.GetAsyncKeyState(0x28)
                local aDown, aPressed = Susano.GetAsyncKeyState(0x41)
                local eDown, ePressed = Susano.GetAsyncKeyState(0x45)
                local qDown, qPressed = Susano.GetAsyncKeyState(0x51)  -- toegevoegd voor Q
                local backDown, backPressed = Susano.GetAsyncKeyState(0x08)
                local leftDown, leftPressed = Susano.GetAsyncKeyState(0x25)
                local rightDown, rightPressed = Susano.GetAsyncKeyState(0x27)
                local f9Down, f9Pressed = Susano.GetAsyncKeyState(0x78)

                local upWasDown = Menu.KeyStates[0x26] or false
                local downWasDown = Menu.KeyStates[0x28] or false
                local aWasDown = Menu.KeyStates[0x41] or false
                local eWasDown = Menu.KeyStates[0x45] or false
                local qWasDown = Menu.KeyStates[0x51] or false  -- voor Q
                local backWasDown = Menu.KeyStates[0x08] or false
                local leftWasDown = Menu.KeyStates[0x25] or false
                local rightWasDown = Menu.KeyStates[0x27] or false
                local f9WasDown = Menu.KeyStates[0x78] or false

                if upDown == true then Menu.KeyStates[0x26] = true else Menu.KeyStates[0x26] = false end
                if downDown == true then Menu.KeyStates[0x28] = true else Menu.KeyStates[0x28] = false end
                if aDown == true then Menu.KeyStates[0x41] = true else Menu.KeyStates[0x41] = false end
                if eDown == true then Menu.KeyStates[0x45] = true else Menu.KeyStates[0x45] = false end
                if qDown == true then Menu.KeyStates[0x51] = true else Menu.KeyStates[0x51] = false end
                if backDown == true then Menu.KeyStates[0x08] = true else Menu.KeyStates[0x08] = false end
                if leftDown == true then Menu.KeyStates[0x25] = true else Menu.KeyStates[0x25] = false end
                if rightDown == true then Menu.KeyStates[0x27] = true else Menu.KeyStates[0x27] = false end
                if f9Down == true then Menu.KeyStates[0x78] = true else Menu.KeyStates[0x78] = false end

                if (f9Pressed == true) or (f9Down == true and not f9WasDown) then
                    if Menu.CurrentItem > 0 and Menu.CurrentItem <= #currentTab.items then
                        local selectedItem = currentTab.items[Menu.CurrentItem]
                        if selectedItem and not selectedItem.isSeparator then
                            Menu.SelectingBind = true
                            Menu.BindingItem = selectedItem
                            Menu.BindingKey = nil
                            Menu.BindingKeyName = nil
                            if not selectedItem.bindKey then
                                selectedItem.bindKey = nil
                                selectedItem.bindKeyName = nil
                            else
                                Menu.BindingKey = selectedItem.bindKey
                                Menu.BindingKeyName = selectedItem.bindKeyName
                            end
                        end
                    end
                end

                if (upPressed == true) or (upDown == true and not upWasDown) then
                    Menu.CurrentItem = findNextNonSeparator(currentTab.items, Menu.CurrentItem, -1)
                elseif (downPressed == true) or (downDown == true and not downWasDown) then
                    Menu.CurrentItem = findNextNonSeparator(currentTab.items, Menu.CurrentItem, 1)
                elseif (aPressed == true) or (aDown == true and not aWasDown) then
                    if Menu.CurrentTab > 1 then
                        Menu.CurrentTab = Menu.CurrentTab - 1
                        local newTab = category.tabs[Menu.CurrentTab]
                        if newTab and newTab.items then
                            Menu.CurrentItem = findNextNonSeparator(newTab.items, 0, 1)
                        else
                            Menu.CurrentItem = 1
                        end
                        Menu.ItemScrollOffset = 0
                    elseif Menu.TopLevelTabs then
                        Menu.CurrentTopTab = Menu.CurrentTopTab - 1
                        if Menu.CurrentTopTab < 1 then Menu.CurrentTopTab = #Menu.TopLevelTabs end
                        Menu.UpdateCategoriesFromTopTab()
                    end
                elseif (qPressed == true) or (qDown == true and not qWasDown) then
                    -- Zelfde als A: naar links
                    if Menu.CurrentTab > 1 then
                        Menu.CurrentTab = Menu.CurrentTab - 1
                        local newTab = category.tabs[Menu.CurrentTab]
                        if newTab and newTab.items then
                            Menu.CurrentItem = findNextNonSeparator(newTab.items, 0, 1)
                        else
                            Menu.CurrentItem = 1
                        end
                        Menu.ItemScrollOffset = 0
                    elseif Menu.TopLevelTabs then
                        Menu.CurrentTopTab = Menu.CurrentTopTab - 1
                        if Menu.CurrentTopTab < 1 then Menu.CurrentTopTab = #Menu.TopLevelTabs end
                        Menu.UpdateCategoriesFromTopTab()
                    end
                elseif (ePressed == true) or (eDown == true and not eWasDown) then
                    if Menu.CurrentTab < #category.tabs then
                        Menu.CurrentTab = Menu.CurrentTab + 1
                        local newTab = category.tabs[Menu.CurrentTab]
                        if newTab and newTab.items then
                            Menu.CurrentItem = findNextNonSeparator(newTab.items, 0, 1)
                        else
                            Menu.CurrentItem = 1
                        end
                        Menu.ItemScrollOffset = 0
                    elseif Menu.TopLevelTabs then
                         Menu.CurrentTopTab = Menu.CurrentTopTab + 1
                         if Menu.CurrentTopTab > #Menu.TopLevelTabs then Menu.CurrentTopTab = 1 end
                         Menu.UpdateCategoriesFromTopTab()
                    end
                elseif (backPressed == true) or (backDown == true and not backWasDown) then
                    if Menu.TopLevelTabs and Menu.TopLevelTabs[Menu.CurrentTopTab].autoOpen then
                         if Menu.CurrentTopTab > 1 then
                             Menu.CurrentTopTab = 1
                             Menu.UpdateCategoriesFromTopTab()
                         else
                             Menu.Visible = false
                         end
                    else
                        Menu.OpenedCategory = nil
                        Menu.CurrentItem = 1
                        Menu.CurrentTab = 1
                        Menu.ItemScrollOffset = 0
                    end
                elseif (leftPressed == true) or (leftDown == true and not leftWasDown) then
                    if Menu.CurrentItem > 0 and Menu.CurrentItem <= #currentTab.items then
                        local selectedItem = currentTab.items[Menu.CurrentItem]
                        if selectedItem then
                            if selectedItem.type == "slider" then
                                local step = 1.0
                                if selectedItem.step then
                                    step = selectedItem.step
                                end
                                selectedItem.value = math.max(selectedItem.min or 0.0, (selectedItem.value or selectedItem.min or 0.0) - step)
                                if selectedItem.name == "Smooth Menu" then
                                    Menu.SmoothFactor = selectedItem.value / 100.0
                                elseif selectedItem.name == "Menu Size" then
                                    Menu.Scale = selectedItem.value / 100.0
                                end
                                if selectedItem.onClick then selectedItem.onClick(selectedItem.value) end
                            elseif selectedItem.type == "toggle" and selectedItem.hasSlider then
                                local step = selectedItem.sliderStep or 0.1
                                selectedItem.sliderValue = math.max(selectedItem.sliderMin or 0.0, (selectedItem.sliderValue or selectedItem.sliderMin or 0.0) - step)
                            elseif selectedItem.type == "toggle_selector" then
                                local currentIndex = selectedItem.selected or 1
                                if selectedItem.options and #selectedItem.options > 0 then
                                    currentIndex = currentIndex - 1
                                    if currentIndex < 1 then
                                        currentIndex = #selectedItem.options
                                    end
                                end
                                selectedItem.selected = currentIndex
                            elseif selectedItem.type == "selector" then
                                local currentIndex = selectedItem.selected or 1

                                local isWardrobeSelector = false
                                local wardrobeItemNames = {"Hat", "Mask", "Glasses", "Torso", "Tshirt", "Pants", "Shoes"}
                                for _, name in ipairs(wardrobeItemNames) do
                                    if selectedItem.name == name then
                                        isWardrobeSelector = true
                                        break
                                    end
                                end

                                if isWardrobeSelector then
                                    currentIndex = math.max(1, currentIndex - 1)
                                else
                                    if selectedItem.options and #selectedItem.options > 0 then
                                        currentIndex = currentIndex - 1
                                        if currentIndex < 1 then
                                            currentIndex = #selectedItem.options
                                        end
                                    end
                                end
                                selectedItem.selected = currentIndex

                                if selectedItem.name == "Menu Theme" and selectedItem.options then
                                    local theme = selectedItem.options[currentIndex]
                                    Menu.ApplyTheme(theme)
                                elseif selectedItem.name == "Gradient" and selectedItem.options then
                                    local gradientVal = selectedItem.options[currentIndex]
                                    Menu.GradientType = tonumber(gradientVal) or 1
                                elseif selectedItem.name == "Scroll Bar Position" and selectedItem.options then
                                    local pos = selectedItem.options[currentIndex]
                                    if pos == "Left" then
                                        Menu.ScrollbarPosition = 1
                                    elseif pos == "Right" then
                                        Menu.ScrollbarPosition = 2
                                    end
                                end

                            end
                        end
                    end
                elseif (rightPressed == true) or (rightDown == true and not rightWasDown) then
                    if Menu.CurrentItem > 0 and Menu.CurrentItem <= #currentTab.items then
                        local selectedItem = currentTab.items[Menu.CurrentItem]
                        if selectedItem then
                            if selectedItem.type == "slider" then
                                local step = 1.0
                                if selectedItem.step then
                                    step = selectedItem.step
                                end
                                selectedItem.value = math.min(selectedItem.max or 100.0, (selectedItem.value or selectedItem.min or 0.0) + step)
                                if selectedItem.name == "Smooth Menu" then
                                    Menu.SmoothFactor = selectedItem.value / 100.0
                                elseif selectedItem.name == "Menu Size" then
                                    Menu.Scale = selectedItem.value / 100.0
                                end
                                if selectedItem.onClick then selectedItem.onClick(selectedItem.value) end
                            elseif selectedItem.type == "toggle" and selectedItem.hasSlider then
                                local step = selectedItem.sliderStep or 0.1
                                selectedItem.sliderValue = math.min(selectedItem.sliderMax or 100.0, (selectedItem.sliderValue or selectedItem.sliderMin or 0.0) + step)
                            elseif selectedItem.type == "toggle_selector" then
                                local currentIndex = selectedItem.selected or 1
                                if selectedItem.options and #selectedItem.options > 0 then
                                    currentIndex = currentIndex + 1
                                    if currentIndex > #selectedItem.options then
                                        currentIndex = 1
                                    end
                                end
                                selectedItem.selected = currentIndex
                            elseif selectedItem.type == "selector" then
                                local currentIndex = selectedItem.selected or 1

                                local isWardrobeSelector = false
                                local wardrobeItemNames = {"Hat", "Mask", "Glasses", "Torso", "Tshirt", "Pants", "Shoes"}
                                for _, name in ipairs(wardrobeItemNames) do
                                    if selectedItem.name == name then
                                        isWardrobeSelector = true
                                        break
                                    end
                                end

                                if isWardrobeSelector then
                                    currentIndex = currentIndex + 1
                                else
                                    if selectedItem.options and #selectedItem.options > 0 then
                                        currentIndex = currentIndex + 1
                                        if currentIndex > #selectedItem.options then
                                            currentIndex = 1
                                        end
                                    end
                                end
                                selectedItem.selected = currentIndex

                                if selectedItem.name == "Menu Theme" and selectedItem.options then
                                    local theme = selectedItem.options[currentIndex]
                                    Menu.ApplyTheme(theme)
                                elseif selectedItem.name == "Gradient" and selectedItem.options then
                                    local gradientVal = selectedItem.options[currentIndex]
                                    Menu.GradientType = tonumber(gradientVal) or 1
                                elseif selectedItem.name == "Scroll Bar Position" and selectedItem.options then
                                    local pos = selectedItem.options[currentIndex]
                                    if pos == "Left" then
                                        Menu.ScrollbarPosition = 1
                                    elseif pos == "Right" then
                                        Menu.ScrollbarPosition = 2
                                    end
                                end

                            end
                        end
                    end
                end
            end

            if Menu.IsKeyJustPressed(0x0D) then
                local item = currentTab.items[Menu.CurrentItem]
                if item and not item.isSeparator then
                    if item.type == "toggle" or item.type == "toggle_selector" then
                        item.value = not item.value
                        if item.name == "Show Menu Keybinds" then
                            Menu.ShowKeybinds = item.value
                        elseif item.name == "Editor Mode" then
                            Menu.EditorMode = item.value
                        elseif item.name == "Flakes" then
                            Menu.ShowSnowflakes = item.value
                        end
                        if item.onClick then item.onClick(item.value) end
                    elseif item.type == "action" then
                        if item.name == "Change Menu Keybind" then
                            Menu.SelectingKey = true
                            Menu.SelectedKey = Menu.SelectedKey
                            Menu.SelectedKeyName = Menu.SelectedKeyName
                            print("Changing menu keybind...")
                        end
                        if item.onClick then item.onClick() end
                    elseif item.type == "selector" then
                        if item.onClick then
                             local option = (item.options and item.options[item.selected]) or nil
                             item.onClick(item.selected, option)
                        end
                    end
                end
            end
        end
    else
        if Susano and Susano.GetAsyncKeyState then
            local upDown, upPressed = Susano.GetAsyncKeyState(0x26)
            local downDown, downPressed = Susano.GetAsyncKeyState(0x28)
            local aDown, aPressed = Susano.GetAsyncKeyState(0x41)
            local eDown, ePressed = Susano.GetAsyncKeyState(0x45)

            local upWasDown = Menu.KeyStates[0x26] or false
            local downWasDown = Menu.KeyStates[0x28] or false
            local aWasDown = Menu.KeyStates[0x41] or false
            local eWasDown = Menu.KeyStates[0x45] or false

            if upDown == true then Menu.KeyStates[0x26] = true else Menu.KeyStates[0x26] = false end
            if downDown == true then Menu.KeyStates[0x28] = true else Menu.KeyStates[0x28] = false end
            if aDown == true then Menu.KeyStates[0x41] = true else Menu.KeyStates[0x41] = false end
            if eDown == true then Menu.KeyStates[0x45] = true else Menu.KeyStates[0x45] = false end

            if (upPressed == true) or (upDown == true and not upWasDown) then
                Menu.CurrentCategory = Menu.CurrentCategory - 1
                if Menu.CurrentCategory < 2 then
                    Menu.CurrentCategory = #Menu.Categories
                end
            elseif (downPressed == true) or (downDown == true and not downWasDown) then
                Menu.CurrentCategory = Menu.CurrentCategory + 1
                if Menu.CurrentCategory > #Menu.Categories then
                    Menu.CurrentCategory = 2
                end
            elseif (aPressed == true) or (aDown == true and not aWasDown) then
                if Menu.TopLevelTabs then
                    Menu.CurrentTopTab = Menu.CurrentTopTab - 1
                    if Menu.CurrentTopTab < 1 then Menu.CurrentTopTab = #Menu.TopLevelTabs end
                    Menu.UpdateCategoriesFromTopTab()
                end
            elseif (ePressed == true) or (eDown == true and not eWasDown) then
                if Menu.TopLevelTabs then
                    Menu.CurrentTopTab = Menu.CurrentTopTab + 1
                    if Menu.CurrentTopTab > #Menu.TopLevelTabs then Menu.CurrentTopTab = 1 end
                    Menu.UpdateCategoriesFromTopTab()
                end
            end
        end

        if Menu.IsKeyJustPressed(0x0D) then
            local category = Menu.Categories[Menu.CurrentCategory]
            if category and category.hasTabs and category.tabs then
                Menu.OpenedCategory = Menu.CurrentCategory
                Menu.CurrentTab = 1
                if category.tabs[1] and category.tabs[1].items then
                    Menu.CurrentItem = findNextNonSeparator(category.tabs[1].items, 0, 1)
                else
                    Menu.CurrentItem = 1
                end
                Menu.ItemScrollOffset = 0
            end
        end
    end
end


CreateThread(function()
    Menu.LoadingStartTime = GetGameTimer() or 0

    while Menu.IsLoading do
        local currentTime = GetGameTimer() or Menu.LoadingStartTime
        local elapsedTime = currentTime - Menu.LoadingStartTime

        Menu.LoadingProgress = (elapsedTime / Menu.LoadingDuration) * 100.0

        if Menu.LoadingProgress >= 100.0 then
            Menu.LoadingProgress = 100.0
            Menu.IsLoading = false
            Menu.LoadingComplete = true
            Menu.SelectingKey = true
            break
        end

        Wait(0)
    end
end)

CreateThread(function()
    while true do
        Menu.Render()

        if Menu.LoadingComplete then
            Menu.HandleInput()
        end

        Wait(0)
    end
end)


function Menu.OpenInput(title, subtitle, callback)
    if type(subtitle) == "function" then
        callback = subtitle
        subtitle = "Enter text below"
    end
    Menu.InputTitle = title
    Menu.InputSubtitle = subtitle
    Menu.InputText = ""
    Menu.InputCallback = callback
    Menu.InputOpen = true
    Menu.SelectingKey = false
    Menu.SelectingBind = false
end

function Menu.DrawInputWindow()
    if not Menu.InputOpen then return end

    local screenWidth = 1920
    local screenHeight = 1080
    if Susano and Susano.GetScreenWidth and Susano.GetScreenHeight then
        screenWidth = Susano.GetScreenWidth()
        screenHeight = Susano.GetScreenHeight()
    end

    -- Overlay
    if Susano and Susano.DrawRectFilled then
        Susano.DrawRectFilled(0, 0, screenWidth, screenHeight, 0, 0, 0, 0.72, 0)
    else
        Menu.DrawRect(0, 0, screenWidth, screenHeight, 0, 0, 0, 184)
    end

    local accentR = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.r) and (Menu.Colors.SelectedBg.r / 255.0) or 0.58
    local accentG = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.g) and (Menu.Colors.SelectedBg.g / 255.0) or 0.0
    local accentB = (Menu.Colors.SelectedBg and Menu.Colors.SelectedBg.b) and (Menu.Colors.SelectedBg.b / 255.0) or 0.83

    local width = 370
    local height = 148
    local cardR = 10
    local x = math.floor((screenWidth / 2) - (width / 2))
    local y = math.floor((screenHeight / 2) - (height / 2))

    -- Card glow + body
    if Susano and Susano.DrawRectFilled then
        Susano.DrawRectFilled(x - 16, y - 16, width + 32, height + 32, accentR, accentG, accentB, 0.07, cardR + 10)
        Susano.DrawRectFilled(x - 6, y - 6, width + 12, height + 12, accentR, accentG, accentB, 0.10, cardR + 5)
        Susano.DrawRectFilled(x, y, width, height, 0.07, 0.07, 0.09, 1.0, cardR)
        -- Top accent line
        Susano.DrawRectFilled(x + cardR, y, width - cardR * 2, 2, accentR, accentG, accentB, 0.9, 0)
    else
        Menu.DrawRoundedRect(x, y, width, height, 18, 18, 23, 255, cardR)
        Menu.DrawRect(x + cardR, y, width - cardR * 2, 2, math.floor(accentR*255), math.floor(accentG*255), math.floor(accentB*255), 230)
    end

    -- Title centered
    local titleText = Menu.InputTitle or "Input"
    local titleSize = 16
    local titleWidth = Susano and Susano.GetTextWidth and Susano.GetTextWidth(titleText, titleSize) or (string.len(titleText) * 9)
    Menu.DrawText(math.floor(x + width/2 - titleWidth/2), y + 16, titleText, titleSize, 1.0, 1.0, 1.0, 1.0)

    -- Subtitle
    local subText = Menu.InputSubtitle or "Enter text below:"
    local subSize = 12
    Menu.DrawText(x + 20, y + 40, subText, subSize, accentR, accentG, accentB, 0.8)

    -- Input box with accent border when focused
    local boxW = width - 40
    local boxH = 34
    local boxX = x + 20
    local boxY = y + 62

    if Susano and Susano.DrawRectFilled then
        Susano.DrawRectFilled(boxX - 1, boxY - 1, boxW + 2, boxH + 2, accentR, accentG, accentB, 0.5, 6)
        Susano.DrawRectFilled(boxX, boxY, boxW, boxH, 0.11, 0.11, 0.14, 1.0, 5)
    else
        Menu.DrawRoundedRect(boxX, boxY, boxW, boxH, 28, 28, 36, 255, 5)
    end

    local displayText = Menu.InputText or ""
    if math.floor(GetGameTimer() / 500) % 2 == 0 then
        displayText = displayText .. "|"
    end

    local maxDisplayChars = 30
    if string.len(displayText) > maxDisplayChars then
        displayText = "..." .. string.sub(displayText, -maxDisplayChars)
    end

    Menu.DrawText(boxX + 10, boxY + 8, displayText, 15, 1.0, 1.0, 1.0, 1.0)

    -- Hint
    local hintText = "[ENTER] Confirm   [ESC] Cancel"
    local hintSize = 10
    local hintW = Susano and Susano.GetTextWidth and Susano.GetTextWidth(hintText, hintSize) or (string.len(hintText) * 6)
    Menu.DrawText(math.floor(x + width/2 - hintW/2), y + height - 18, hintText, hintSize, 0.5, 0.5, 0.55, 0.8)
    
    if Susano and Susano.GetAsyncKeyState then
         if Menu.IsKeyJustPressed(0x0D) then
             Menu.InputOpen = false
             if Menu.InputCallback then
                 Menu.InputCallback(Menu.InputText)
             end
         end
         
         if Menu.IsKeyJustPressed(0x08) then
             if string.len(Menu.InputText) > 0 then
                 Menu.InputText = string.sub(Menu.InputText, 1, -2)
             end
         end
         
         if Menu.IsKeyJustPressed(0x1B) then
             Menu.InputOpen = false
         end
         
         local shiftPressed = false
         if Susano.GetAsyncKeyState(0x10) or Susano.GetAsyncKeyState(0xA0) or Susano.GetAsyncKeyState(0xA1) then
             shiftPressed = true
         end
         
         for i = 0x41, 0x5A do
             if Menu.IsKeyJustPressed(i) then
                 local char = string.char(i)
                 if not shiftPressed then
                     char = string.lower(char)
                 end
                 Menu.InputText = Menu.InputText .. char
             end
         end
         for i = 0x30, 0x39 do
             if Menu.IsKeyJustPressed(i) then
                 Menu.InputText = Menu.InputText .. string.char(i)
             end
         end
         if Menu.IsKeyJustPressed(0x20) then
             Menu.InputText = Menu.InputText .. " "
         end
         if Menu.IsKeyJustPressed(0xBD) then
             if shiftPressed then Menu.InputText = Menu.InputText .. "_" else Menu.InputText = Menu.InputText .. "-" end
         end
    end
end

if Menu.Banner.enabled and Menu.Banner.imageUrl then
    Menu.LoadBannerTexture(Menu.Banner.imageUrl)
end


return Menu
