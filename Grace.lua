local CONFIG = {
    AutoRoomProgress = true,
    TeleportPastMin = 5,
    TeleportPastMax = 10,
    RoomTeleportInterval = 0.1,
    RoomWaitTimeout = 0.5,
    AutoVault = true,
    VaultRetryInterval = 1.2,
    VaultMaxAttempts = 30,
    VaultHoldTime = 1.5,
    AutoReady = true,
    AutoRearm = false,
    AutoScale = true,
    ScaleHoldTime = 1.0,
    ScaleInterval = 0.2,
    ScaleTeleports = 2,
    AutoDodge = true,
    CameraDodge = true,
    DodgeInterval = 0.1,
    ParryCooldown = 0.15,
    DozerKeyHold = true,
    DozerCrouchKeyCode = 306,
    RushGuard = true,
    RushShield = true,
    RushGuardRange = 45,
    WormRadius = 55,
    WormSafeDistance = 22,
    WormInterval = 0.03,
    WormReleaseDistance = 70,
    WormMaxEngage = 20,
    WormEmergencyDistance = 9,
    WormSpawnWait = 0.5,
    WormSpawnOffset = 14,
    WormUpwardDodge = true,
    WormUpwardHeight = 50,
    WormUpwardTrigger = 9,
    WormUpwardTriggerPad = 3,
    WormUpwardHoldMax = 30,
    WormUpwardGrace = 0.8,
    WormDownCooldown = 0.6,
    Debug = true,
    StatusInterval = 5,
    KeyToggleRooms = Enum.KeyCode.RightShift,
    KeyToggleDodge = Enum.KeyCode.RightControl,
    KeyDozer = Enum.KeyCode.RightAlt,
    KeyUnload = Enum.KeyCode.LeftControl
}

local log = (type(log) == "function" and log) or function(fmt, ...)
        if CONFIG.Debug then
            pcall(print, ("[Grace] " .. tostring(fmt)):format(...))
        end
    end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = workspace

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    return
end

local ClientShared = nil
pcall(
    function()
        ClientShared = require(ReplicatedStorage.GraceCharacter.ClientShared)
    end
)

if type(_G.GraceAuto) == "table" and type(_G.GraceAuto.Stop) == "function" then
    pcall(_G.GraceAuto.Stop)
end

local state = {
    LoadedAt = os.clock(),
    JobId = game.JobId,
    PlaceId = game.PlaceId,
    Running = true,
    Teleports = 0,
    Dodges = 0,
    Errors = 0,
    LastError = nil,
    LastTeleport = 0,
    LastParry = 0,
    LastDodge = nil,
    Deaths = 0,
    Dead = false,
    DeathInfo = nil
}

local rearmState = {}
local vaultState = {
    Instance = nil,
    Phase = "approach",
    PhaseAt = 0,
    Attempts = 0,
    LastAttempt = 0,
    Open = false,
    Done = nil,
    GaveUp = false,
    Room = nil,
    Settled = false
}

local scaleState = {
    Done = nil,
    Room = nil,
    Phase = "idle",
    At = 0,
    Held = 0,
    LastTick = 0,
    Point = nil
}

local rushGuard = {
    Active = false,
    PreviousVoid = nil,
    Shield = nil,
    Hits = 0,
    LastSeen = nil
}

local noteDodge = state.Dodges and function(label)
        state.Dodges = state.Dodges + 1
        state.LastDodge = label
    end or function(label)
    end

local function noteDodge(label)
    state.Dodges = state.Dodges + 1
    state.LastDodge = label
end

local function resolveSelfPath()
    return nil
end

local function setupRearm()
    rearmState.Err = "auto re-arm disabled"
    return false
end

local function clearRearm()
end

local function noteDodge(label)
    state.Dodges = state.Dodges + 1
    state.LastDodge = label
end

local function rushActive()
    local value = Workspace:GetAttribute("CarnationsGoing")
    return (tonumber(value) or 0) > 0
end

local function ensureRushImmunity()
    if not CONFIG.RushGuard then
        return false
    end
    local character = LocalPlayer.Character
    if not character then
        return false
    end
    if not rushGuard.Active then
        rushGuard.Active = true
        rushGuard.PreviousVoid = character:GetAttribute("VOID")
        noteDodge("rush guard")
        log("Rush guard -> VOID immunity on")
    end
    rushGuard.LastSeen = os.clock()
    pcall(
        function()
            character:SetAttribute("VOID", true)
        end
    )
    return true
end

local freezeState = {
    Active = false,
    StartedAt = 0,
    CrouchPressed = false,
    Keys = {},
    KeyNames = "",
    Err = nil,
    MaxDuration = 8,
    CrouchApplied = false,
    CrouchValue = nil,
    MobileCrouch = nil,
    MobileCrouchWas = nil
}

local dozerState = {
    Active = false,
    Gui = nil,
    GuiStart = 0
}

local camOverride = {
    Mode = nil,
    Target = nil
}

local function getCharacter()
    local character = LocalPlayer.Character
    if not character or not character.Parent then
        return nil
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then
        return nil
    end
    return character, humanoid, root
end

local function getPlayerGui()
    return LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

local function isDead()
    if LocalPlayer:HasTag("Dead") then
        return true
    end
    local character = LocalPlayer.Character
    if not character or not character.Parent then
        return true
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return true
    end
    local gui = getPlayerGui()
    if gui and (gui:FindFirstChild("losescreen") or gui:FindFirstChild("deathscreen")) then
        return true
    end
    return false
end

local function queryTagged(tag)
    local ok, result =
        pcall(
        function()
            return Workspace:QueryDescendants("." .. tag)
        end
    )
    if ok and result then
        return result
    end
    local fallback = {}
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:HasTag(tag) then
            table.insert(fallback, descendant)
        end
    end
    return fallback
end

local function instancePosition(instance)
    if instance:IsA("BasePart") then
        return instance.Position
    elseif instance:IsA("Model") then
        local ok, pivot =
            pcall(
            function()
                return instance:GetPivot().Position
            end
        )
        if ok then
            return pivot
        end
    end
    return nil
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.RespectCanCollide = true
pcall(
    function()
        losParams.CollisionGroup = "NodeVision"
    end
)

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function isFree(position)
    local character = LocalPlayer.Character
    overlapParams.FilterDescendantsInstances = character and {character} or {}
    local parts = Workspace:GetPartBoundsInBox(CFrame.new(position), Vector3.new(2.6, 4.4, 2.6), overlapParams)
    for _, part in ipairs(parts) do
        if part.CanCollide then
            return false
        end
    end
    return true
end

local standParams = RaycastParams.new()
standParams.FilterType = Enum.RaycastFilterType.Exclude
standParams.RespectCanCollide = true

local function standOnFloor(position, drop)
    local character = LocalPlayer.Character
    standParams.FilterDescendantsInstances = character and {character} or {}
    local origin = position + Vector3.new(0, 4, 0)
    local hit = Workspace:Raycast(origin, Vector3.new(0, -(drop or 30), 0), standParams)
    if not hit then
        return nil
    end
    return Vector3.new(position.X, hit.Position.Y + 3.05, position.Z)
end

local function losBlocked(fromPosition, toPosition, extraIgnore)
    local ignore = {}
    local character = LocalPlayer.Character
    if character then
        table.insert(ignore, character)
    end
    if extraIgnore then
        for _, instance in ipairs(extraIgnore) do
            table.insert(ignore, instance)
        end
    end
    losParams.FilterDescendantsInstances = ignore
    local origin = fromPosition + Vector3.new(0, 1, 0)
    local result = Workspace:Raycast(origin, toPosition - origin, losParams)
    return result ~= nil
end

local function getRoomsFolder()
    return Workspace:FindFirstChild("Rooms")
end

local function currentRoomIndex()
    local raw = Workspace:GetAttribute("ClientInRoom")
    if raw == nil then
        raw = Workspace:GetAttribute("CurrentRoom")
    end
    return tonumber(raw)
end

local function getRoomModel(index)
    local rooms = getRoomsFolder()
    if not rooms or not index then
        return nil
    end
    return rooms:FindFirstChild(tostring(index))
end

local function teleportTo(position)
    local character = getCharacter()
    if not character then
        return false
    end

    if rushActive() then
        ensureRushImmunity()
    end
    character:PivotTo(CFrame.new(position))
    local _, _, root = getCharacter()
    if root then
        root.AssemblyLinearVelocity = Vector3.zero
    end
    return true
end

local function teleportPastExit(index, force)
    local room = getRoomModel(index)
    if not room then
        return false, "room missing"
    end
    local exitPart = room:FindFirstChild("Exit", true)
    local entrancePart = room:FindFirstChild("Entrance", true)
    if not exitPart or not exitPart:IsA("BasePart") then
        return false, "no Exit part"
    end

    if not force then
        local rooms = getRoomsFolder()
        local nextRoom = rooms and rooms:FindFirstChild(tostring(index + 1))
        local roomCount = tonumber(Workspace:GetAttribute("RoomCount")) or 0
        if not nextRoom and roomCount <= index then
            return false, "next room not generated"
        end
    end

    local direction
    if entrancePart and entrancePart:IsA("BasePart") then
        local delta = exitPart.Position - entrancePart.Position
        if delta.Magnitude > 0.01 then
            direction = delta.Unit
        end
    end
    direction = direction or exitPart.CFrame.LookVector
    local flat = Vector3.new(direction.X, 0, direction.Z)
    if flat.Magnitude < 0.01 then
        flat = Vector3.new(0, 0, -1)
    end
    flat = flat.Unit

    local past = CONFIG.TeleportPastMin + math.random() * (CONFIG.TeleportPastMax - CONFIG.TeleportPastMin)
    local target = exitPart.Position + flat * past

    local character = LocalPlayer.Character
    local floorParams = RaycastParams.new()
    floorParams.FilterType = Enum.RaycastFilterType.Exclude
    floorParams.FilterDescendantsInstances = character and {character} or {}
    floorParams.RespectCanCollide = true
    local probeOrigin = Vector3.new(target.X, exitPart.Position.Y + 3, target.Z)
    local floorHit = Workspace:Raycast(probeOrigin, Vector3.new(0, -30, 0), floorParams)
    if not floorHit then
        return false, "no floor past exit"
    end

    local landing = Vector3.new(target.X, floorHit.Position.Y + 3.05, target.Z)
    if not teleportTo(landing) then
        return false, "no character"
    end
    return true, past
end

local function findSafeSpot(threatPosition, minThreatDistance, requireCover, extraIgnore)
    local _, _, root = getCharacter()
    if not root then
        return nil
    end
    local base = root.Position
    local radii = {8, 14, 20, 26, 32}
    for _, radius in ipairs(radii) do
        for step = 0, 11 do
            local angle = (step / 12) * math.pi * 2
            local candidate = Vector3.new(base.X + math.cos(angle) * radius, base.Y, base.Z + math.sin(angle) * radius)
            local threatDistance = (candidate - threatPosition).Magnitude
            if threatDistance > minThreatDistance and isFree(candidate) then
                if not requireCover or losBlocked(threatPosition, candidate, extraIgnore) then
                    return candidate
                end
            end
        end
    end
    return nil
end

local function fireParry(targetPosition, label)
    local now = os.clock()
    if now - state.LastParry < CONFIG.ParryCooldown then
        return false
    end
    local camera = Workspace.CurrentCamera
    if not camera then
        return false
    end
    local origin = camera.CFrame.Position
    if (targetPosition - origin).Magnitude < 0.1 then
        return false
    end

    state.LastParry = now
    local proxy = Instance.new("Part")
    proxy.Name = "SWORD"
    proxy.Size = Vector3.new(0.2, 0.2, 2)
    proxy.Transparency = 1
    proxy.CanCollide = false
    proxy.Anchored = true
    proxy.CFrame = CFrame.lookAt(origin, targetPosition)
    proxy:SetAttribute("Charge", 1)

    local ok =
        pcall(
        function()
            ReplicatedStorage.ClientParryAttempt:Fire(proxy)
        end
    )
    proxy:Destroy()
    if ok then
        noteDodge((label or "entity") .. " parry")
    end
    return ok
end

local function findRush()
    local going = tonumber(Workspace:GetAttribute("CarnationsGoing")) or 0
    if going <= 0 then
        return nil, nil
    end
    local _, _, root = getCharacter()
    local origin = root and root.Position or Workspace.CurrentCamera.CFrame.Position
    local bestPosition, bestDistance, bestInstance
    for _, instance in ipairs(queryTagged("Rush")) do
        local position = instancePosition(instance)
        if position then
            local distance = (position - origin).Magnitude
            if not bestDistance or distance < bestDistance then
                bestPosition, bestDistance, bestInstance = position, distance, instance
            end
        end
    end
    return bestPosition, bestInstance
end

local function findWorm()
    local _, _, root = getCharacter()
    local origin = root and root.Position or Workspace.CurrentCamera.CFrame.Position
    local bestPosition, bestDistance, bestInstance
    for _, instance in ipairs(queryTagged("Worm")) do
        local position = instancePosition(instance)
        if position then
            local distance = (position - origin).Magnitude
            if not bestDistance or distance < bestDistance then
                bestPosition, bestDistance, bestInstance = position, distance, instance
            end
        end
    end
    return bestPosition, bestInstance
end

local function queryNamed(name)
    local ok, result =
        pcall(
        function()
            return Workspace:QueryDescendants("#" .. name)
        end
    )
    if ok and result then
        return result
    end
    return {}
end

local function findEyes()
    local eyes = {}
    local function consider(instance, kind)
        if instance:IsA("BasePart") and instance:FindFirstChild("BillboardGui") then
            table.insert(
                eyes,
                {
                    Part = instance,
                    Kind = kind,
                    Position = instance.Position
                }
            )
        end
    end
    for _, instance in ipairs(queryNamed("eye")) do
        consider(instance, "eye")
    end
    for _, instance in ipairs(queryNamed("eyePrime")) do
        consider(instance, "eyePrime")
    end
    return eyes
end

local function findElkman()
    for _, model in ipairs(queryNamed("elkman")) do
        if model:IsA("Model") then
            local cube = model:FindFirstChild("Cube", true)
            if cube and cube:IsA("BasePart") then
                return cube, model
            end
        end
    end
    return nil, nil
end

local dozerState = {Gui = nil, GuiStart = 0, ParryUntil = 0, ReleasedGui = nil}

local function dozerActive()
    local gui = getPlayerGui()
    local smile = gui and (gui:FindFirstChild("smilegui") or gui:FindFirstChild("gg"))
    if smile then
        if dozerState.Gui ~= smile then
            dozerState.Gui = smile
            dozerState.GuiStart = os.clock()
        end

        if os.clock() - dozerState.GuiStart < 9 then
            return true
        end
        return _G.Dozer == true
    end
    dozerState.Gui = nil
    return _G.Dozer == true
end

local sorrowState = {LastActive = 0}

local function sorrowActive()
    if Workspace:GetAttribute("sorrow") == true or Workspace:GetAttribute("sorrowAttack") == true then
        sorrowState.LastActive = os.clock()
        return true
    end

    return os.clock() - sorrowState.LastActive < 3
end

local function goatmanPosition()
    local gui = getPlayerGui()
    local goatGui = gui and gui:FindFirstChild("GOATPORT")
    if not goatGui then
        return nil
    end
    local viewport = goatGui:FindFirstChild("ViewportFrame")
    local world = viewport and viewport:FindFirstChild("WorldModel")
    local goat = world and (world:FindFirstChild("goat") or world:FindFirstChild("Goat"))
    local root = goat and goat:FindFirstChild("RootPart")
    if root and root:IsA("BasePart") then
        return root.Position
    end
    return nil
end

local coverPart = nil
local coverBound = false

local function isCovered()
    local _, _, root = getCharacter()
    if not root then
        return true
    end
    local params = RaycastParams.new()
    local character = LocalPlayer.Character
    params.FilterDescendantsInstances = character and {character} or {}
    params.CollisionGroup = "NodeVision"
    params.RespectCanCollide = true
    local ok, result =
        pcall(
        function()
            return Workspace:Spherecast(root.Position, 1, Vector3.new(0, 500, 0), params)
        end
    )
    return ok and result ~= nil
end

local function updateCover()
    local _, _, root = getCharacter()
    if not root then
        return
    end
    if not coverPart or not coverPart.Parent then
        coverPart = Instance.new("Part")
        coverPart.Name = "GraceAutoCover"
        coverPart.Size = Vector3.new(40, 2, 40)
        coverPart.Anchored = true
        coverPart.CanCollide = true
        coverPart.Transparency = 1
        coverPart.Parent = Workspace
    end
    coverPart.CFrame = CFrame.new(root.Position + Vector3.new(0, 8, 0))
end

local function bindCover()
    if coverBound then
        return
    end
    coverBound = true
    pcall(
        function()
            RunService:BindToRenderStep(
                "GraceAutoCover",
                Enum.RenderPriority.Camera.Value + 2,
                function()
                    if not state.Running or not sorrowActive() then
                        return
                    end
                    local ok, err = pcall(updateCover)
                    if not ok then
                        state.Errors = state.Errors + 1
                        state.LastError = tostring(err)
                    end
                end
            )
        end
    )
end

local function ensureCover()
    bindCover()
    updateCover()
end

local function removeCover()
    if coverPart then
        coverPart:Destroy()
        coverPart = nil
    end
end

local function dozerCrouchKeys()
    local key = Enum.KeyCode.LeftControl
    pcall(
        function()
            key = Enum.KeyCode:FromValue(CONFIG.DozerCrouchKeyCode)
        end
    )
    return {key}
end

local function virtualKeyboard()
    local ok, service =
        pcall(
        function()
            return game:GetService("VirtualInputManager")
        end
    )
    return ok and service or nil
end

local function pressDozerCrouch()
    if freezeState.CrouchPressed then
        return
    end
    freezeState.CrouchPressed = true

    pcall(
        function()
            local flag = game:GetService("ReplicatedFirst"):FindFirstChild("MobileCrouch")
            if flag and flag:IsA("BoolValue") then
                freezeState.MobileCrouch = flag
                freezeState.MobileCrouchWas = flag.Value
                flag.Value = true
            end
        end
    )
    freezeState.Keys = dozerCrouchKeys()
    local names = {}
    for _, key in ipairs(freezeState.Keys) do
        table.insert(names, key.Name)
    end
    local keyboard = virtualKeyboard()
    if keyboard then
        for _, key in ipairs(freezeState.Keys) do
            pcall(
                function()
                    keyboard:SendKeyEvent(true, key, false, game)
                end
            )
        end
    else
        freezeState.Err = "no VirtualInputManager"
    end
    freezeState.KeyNames = table.concat(names, "+")
    log("Dozer -> holding crouch (%s + MobileCrouch), no teleports", freezeState.KeyNames)
end

local function releaseDozerCrouch()
    if not freezeState.CrouchPressed then
        return
    end
    freezeState.CrouchPressed = false
    local keyboard = virtualKeyboard()
    if keyboard then
        for _, key in ipairs(freezeState.Keys) do
            pcall(
                function()
                    keyboard:SendKeyEvent(false, key, false, game)
                end
            )
        end
    end
    if freezeState.MobileCrouch then
        pcall(
            function()
                freezeState.MobileCrouch.Value = freezeState.MobileCrouchWas
            end
        )
        freezeState.MobileCrouch = nil
    end
    freezeState.Keys = {}
    log("Dozer -> smile gone, crouch released")
end

local function setFreeze(on)
    if on then
        if freezeState.Active then
            return
        end
        freezeState.Active = true
        freezeState.StartedAt = os.clock()
        pressDozerCrouch()
    else
        if not freezeState.Active then
            return
        end
        freezeState.Active = false
        releaseDozerCrouch()
    end
end

local function maintainDozerFreeze()
    local character = LocalPlayer.Character
    if not character or not freezeState.CrouchPressed then
        return
    end
    if character:GetAttribute("ClientStanceState") == -1 then
        return
    end
    if freezeState.MobileCrouch then
        pcall(
            function()
                freezeState.MobileCrouch.Value = true
            end
        )
    end
    local keyboard = virtualKeyboard()
    if not keyboard then
        return
    end
    for _, key in ipairs(freezeState.Keys) do
        pcall(
            function()
                keyboard:SendKeyEvent(true, key, false, game)
            end
        )
    end
end

local dozerBound = false

local function bindDozerGuard()
    if dozerBound then
        return
    end
    dozerBound = true
    pcall(
        function()
            RunService:BindToRenderStep(
                "GraceAutoDozer",
                Enum.RenderPriority.Camera.Value + 3,
                function()
                    if not state.Running then
                        return
                    end
                    if not freezeState.Active then
                        return
                    end
                    local ok, err = pcall(maintainDozerFreeze)
                    if not ok then
                        state.Errors = state.Errors + 1
                        state.LastError = tostring(err)
                    end
                end
            )
        end
    )
end

local function toggleDozer()
    dozerState.Active = not dozerState.Active
    if dozerState.Active then
        bindDozerGuard()
        log("Dozer auto-dodge -> enabled")
    else
        if rushGuard.Shield then
            rushGuard.Shield:Destroy()
            rushGuard.Shield = nil
        end
        if rushGuard.Active then
            rushGuard.Active = false
            local character = LocalPlayer.Character
            if character then
                pcall(
                    function()
                        character:SetAttribute("VOID", rushGuard.PreviousVoid)
                    end
                )
            end
        end
        clearRushGuard()
        freezeState.Active = false
        releaseDozerCrouch()
        log("Dozer auto-dodge -> disabled")
    end
end

local function clearRushGuard()
    if rushGuard.Shield then
        rushGuard.Shield:Destroy()
        rushGuard.Shield = nil
    end
    if not rushGuard.Active then
        return
    end
    rushGuard.Active = false
    local character = LocalPlayer.Character
    if character then
        pcall(
            function()
                character:SetAttribute("VOID", rushGuard.PreviousVoid)
            end
        )
    end
    rushGuard.PreviousVoid = nil
    rushGuard.LastSeen = nil
    log("Rush clear -> guard off")
end

local function updateRushShield(rushPosition, root)
    if not CONFIG.RushShield then
        return
    end
    local shield = rushGuard.Shield
    if not shield or not shield.Parent then
        shield = Instance.new("Part")
        shield.Name = "GraceAutoShield"
        shield.Size = Vector3.new(14, 14, 1)
        shield.Anchored = true
        shield.CanCollide = true
        shield.Transparency = 1
        shield.Parent = Workspace
        rushGuard.Shield = shield
    end
    local midpoint = rushPosition:Lerp(root.Position, 0.5)
    shield.CFrame = CFrame.lookAt(midpoint, root.Position)
end

local function dodgeRush()
    local _, _, root = getCharacter()
    if not root then
        clearRushGuard()
        return
    end

    local active = rushActive()
    local position = findRush()
    local distance = position and (position - root.Position).Magnitude or nil

    if active then
        ensureRushImmunity()
    end

    if position and distance and distance <= CONFIG.RushGuardRange then
        ensureRushImmunity()
        updateRushShield(position, root)
        return
    end

    if rushGuard.Shield then
        rushGuard.Shield:Destroy()
        rushGuard.Shield = nil
    end

    if not active and (not rushGuard.LastSeen or os.clock() - rushGuard.LastSeen > 2.5) then
        clearRushGuard()
    end
end

local wormState = {
    Instance = nil,
    LastPosition = nil,
    LastTime = 0,
    Velocity = Vector3.zero,
    LastDodge = 0,
    Engaged = false,
    EngagedAt = 0,
    EmergencyUsed = 0,
    SpawnPosition = nil,
    SpawnAt = 0,
    SpawnUsed = false,
    HoldToEnd = false,
    Upward = false,
    UpwardAt = 0,
    UpwardY = nil,
    UpwardSeen = 0,
    DownAt = 0,
    FrozenUsed = false
}

local WORM_LOOKAHEAD = {0, 0.08, 0.16, 0.24, 0.34, 0.5}

local function wormLaneDistance(position, velocity, target)
    local closest = math.huge
    for _, step in ipairs(WORM_LOOKAHEAD) do
        local future = position + velocity * step
        local distance = (future - target).Magnitude
        if distance < closest then
            closest = distance
        end
    end
    return closest
end

local laneCache = {Index = nil, Points = {}, BuiltAt = 0}

local function roomLanePoints()
    local index = currentRoomIndex()
    if not index then
        return {}
    end
    local now = os.clock()
    if laneCache.Index == index and now - laneCache.BuiltAt < 1 then
        return laneCache.Points
    end
    local points = {}
    local room = getRoomModel(index)
    if room then
        local entrance = room:FindFirstChild("Entrance", true)
        if entrance and entrance:IsA("BasePart") then
            table.insert(points, entrance.Position)
        end
        local nodes = room:FindFirstChild("Nodes")
        if nodes then
            local sorted = {}
            for _, child in ipairs(nodes:GetChildren()) do
                local position = instancePosition(child)
                local order = tonumber(child.Name)
                if position and order then
                    table.insert(sorted, {Order = order, Position = position})
                end
            end
            table.sort(
                sorted,
                function(a, b)
                    return a.Order < b.Order
                end
            )
            for _, entry in ipairs(sorted) do
                table.insert(points, entry.Position)
            end
        end
        local exitPart = room:FindFirstChild("Exit", true)
        if exitPart and exitPart:IsA("BasePart") then
            table.insert(points, exitPart.Position)
        end
    end
    laneCache.Index = index
    laneCache.Points = points
    laneCache.BuiltAt = now
    return points
end

local function distanceToLane(points, target)
    if #points == 0 then
        return math.huge
    end
    if #points == 1 then
        return (points[1] - target).Magnitude
    end
    local closest = math.huge
    for i = 1, #points - 1 do
        local from, to = points[i], points[i + 1]
        local segment = to - from
        local length = segment.Magnitude
        if length > 0.01 then
            local t = math.clamp((target - from):Dot(segment) / (length * length), 0, 1)
            local distance = (from + segment * t - target).Magnitude
            if distance < closest then
                closest = distance
            end
        end
    end
    return closest
end

local function wormEscapeSpot(position, velocity, base)
    local direction
    if velocity.Magnitude > 4 then
        local flat = Vector3.new(velocity.X, 0, velocity.Z)
        if flat.Magnitude > 0.01 then
            direction = flat.Unit
        end
    end

    local lane = roomLanePoints()
    local candidates = {}
    if direction then
        local perpendicular = Vector3.new(-direction.Z, 0, direction.X)

        for _, radius in ipairs({18, 22, 26, 30, 36, 44}) do
            for _, side in ipairs({1, -1}) do
                for _, along in ipairs({0, -10, 10}) do
                    table.insert(candidates, base + perpendicular * radius * side + direction * along)
                end
            end
        end

        for _, distance in ipairs({20, 30, 40}) do
            table.insert(candidates, base - direction * distance)
        end
    end

    for _, radius in ipairs({18, 24, 30, 36}) do
        for step = 0, 9 do
            local angle = (step / 10) * math.pi * 2
            table.insert(candidates, base + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
        end
    end

    local best
    for _, candidate in ipairs(candidates) do
        local spot = standOnFloor(candidate, 40)
        if spot and isFree(spot) then
            local headDistance = (position - spot).Magnitude
            local laneDistance = math.min(wormLaneDistance(position, velocity, spot), distanceToLane(lane, spot))
            local score = math.min(headDistance, laneDistance)
            if headDistance >= 18 and laneDistance >= 20 then
                return spot
            end
            if not best or score > best.Score then
                best = {Spot = spot, Score = score}
            end
        end
    end

    if best and best.Score >= 12 then
        return best.Spot
    end
    return nil
end

local function wormRetreatSpot(velocity)
    local index = currentRoomIndex()
    local room = index and getRoomModel(index)
    local entrance = room and room:FindFirstChild("Entrance", true)
    if not entrance or not entrance:IsA("BasePart") then
        return nil
    end
    local target = entrance.Position
    if velocity.Magnitude > 4 then
        local flat = Vector3.new(velocity.X, 0, velocity.Z)
        if flat.Magnitude > 0.01 then
            target = target - flat.Unit * 8
        end
    end
    return standOnFloor(target, 40)
end

local function wormTrack(position, instance)
    local now = os.clock()
    if wormState.Instance == instance and wormState.LastPosition and now > wormState.LastTime then
        local elapsed = now - wormState.LastTime
        if elapsed > 0.005 then
            local measured = (position - wormState.LastPosition) / elapsed
            wormState.Velocity = wormState.Velocity:Lerp(measured, 0.5)
        end
    else
        wormState.Velocity = Vector3.zero
    end
    wormState.Instance = instance
    wormState.LastPosition = position
    wormState.LastTime = now
    if wormState.Velocity.Magnitude < 4 then
        return Vector3.zero
    end
    return wormState.Velocity
end

local function wormSpawnSpot(spawn, velocity)
    local target = spawn
    local flat = Vector3.new(velocity.X, 0, velocity.Z)
    if flat.Magnitude > 4 then
        local side = Vector3.new(-flat.Unit.Z, 0, flat.Unit.X)
        target = spawn + side * CONFIG.WormSpawnOffset
    end
    return standOnFloor(target, 60) or standOnFloor(spawn, 60)
end

local function wormHolding()
    return CONFIG.WormUpwardDodge and wormState.Upward
end

local function wormDownLocked()
    return wormState.DownAt > 0 and os.clock() - wormState.DownAt < CONFIG.WormDownCooldown
end

local function wormHoldPoint(root)
    local baseY = root.Position.Y
    local lifts = {
        CONFIG.WormUpwardHeight,
        CONFIG.WormUpwardHeight + 15,
        CONFIG.WormUpwardHeight + 30
    }
    for _, lift in ipairs(lifts) do
        local point = Vector3.new(root.Position.X, baseY + lift, root.Position.Z)
        if isFree(point) then
            return point
        end
    end
    local short = Vector3.new(root.Position.X, baseY + 25, root.Position.Z)
    if isFree(short) then
        return short
    end
    return Vector3.new(root.Position.X, baseY + CONFIG.WormUpwardHeight, root.Position.Z)
end

local function wormGoUp(root, headDistance, velocity)
    local speed = velocity and velocity.Magnitude or 0
    local trigger = math.max(CONFIG.WormUpwardTrigger, speed * CONFIG.WormInterval + CONFIG.WormUpwardTriggerPad)
    if headDistance > trigger then
        return false
    end
    local point = wormHoldPoint(root)
    if not teleportTo(point) then
        return false
    end
    wormState.Upward = true
    wormState.UpwardAt = os.clock()
    wormState.UpwardSeen = os.clock()
    wormState.UpwardY = point.Y
    wormState.Engaged = false
    wormState.SpawnUsed = true
    if freezeState.Active then
        wormState.FrozenUsed = true
    end
    noteDodge("slugfish upward")
    log(
        "Slugfish -> head %.0f studs away, holding %.0f studs up until the pass ends",
        headDistance,
        point.Y - root.Position.Y
    )
    return true
end

local function wormMaintainUpward(root)
    if not wormState.UpwardY then
        return
    end
    if math.abs(root.Position.Y - wormState.UpwardY) > 4 then
        teleportTo(Vector3.new(root.Position.X, wormState.UpwardY, root.Position.Z))
    end
end

local function wormReturnToGround(root)
    local from = Vector3.new(root.Position.X, root.Position.Y, root.Position.Z)

    local landing = standOnFloor(from, CONFIG.WormUpwardHeight + 140)
    if not landing then
        local room = getRoomModel(currentRoomIndex())
        local entrance = room and room:FindFirstChild("Entrance", true)
        if entrance and entrance:IsA("BasePart") then
            landing = standOnFloor(entrance.Position, 60)
        end
    end
    wormState.Upward = false
    wormState.UpwardY = nil
    wormState.UpwardAt = 0
    wormState.DownAt = os.clock()
    wormState.Engaged = false
    wormState.SpawnUsed = true
    wormState.FrozenUsed = false
    if landing and teleportTo(landing) then
        log("Slugfish -> pass over, back on the floor")
        return
    end

    log("Slugfish -> pass over, no floor under the hold point; holding position")
end

local function wormStep()
    if not CONFIG.AutoDodge or not state.Running then
        return
    end
    if isDead() then
        wormState.Engaged = false
        wormState.Upward = false
        wormState.UpwardY = nil
        wormState.FrozenUsed = false
        return
    end

    local _, _, root = getCharacter()
    if not root then
        return
    end

    local now = os.clock()
    local eventActive = Workspace:GetAttribute("SlowSorrow") ~= nil
    local position, instance = findWorm()
    if eventActive then
        wormState.UpwardSeen = now
    end

    if wormState.Upward then
        if eventActive then
            wormMaintainUpward(root)
            if position then
                local headDistance = (position - root.Position).Magnitude
                if headDistance < 6 then
                    wormState.UpwardY = root.Position.Y + CONFIG.WormUpwardHeight
                    teleportTo(Vector3.new(root.Position.X, wormState.UpwardY, root.Position.Z))
                end
            end
            if now - wormState.UpwardAt > CONFIG.WormUpwardHoldMax then
                if freezeState.Active then
                    wormMaintainUpward(root)
                else
                    log("Slugfish -> upward hold timeout, returning to the floor")
                    wormReturnToGround(root)
                end
            end
            return
        end

        if now - wormState.UpwardSeen >= CONFIG.WormUpwardGrace then
            if freezeState.Active then
                wormMaintainUpward(root)
            else
                wormReturnToGround(root)
            end
        else
            wormMaintainUpward(root)
        end
        return
    end

    if not eventActive then
        if wormState.Instance or wormState.Engaged then
            if wormState.Engaged then
                log("Slugfish -> event over, resuming room skipping")
            end
            wormState.Instance = nil
            wormState.LastPosition = nil
            wormState.Velocity = Vector3.zero
            wormState.Engaged = false
        end
        wormState.SpawnPosition = nil
        wormState.SpawnUsed = false
        wormState.HoldToEnd = false
        wormState.FrozenUsed = false
        return
    end

    if not position then
        return
    end

    local velocity = wormTrack(position, instance)
    local danger = wormLaneDistance(position, velocity, root.Position)
    local headDistance = (position - root.Position).Magnitude

    if CONFIG.WormUpwardDodge then
        wormGoUp(root, headDistance, velocity)
        return
    end

    if freezeState.Active then
        if wormState.FrozenUsed then
            return
        end
        if now - wormState.LastDodge < 0.12 then
            return
        end
        if danger > CONFIG.WormRadius then
            return
        end
        local spot = wormEscapeSpot(position, velocity, root.Position)
        if not spot then
            spot = wormRetreatSpot(velocity)
        end
        if spot and teleportTo(spot) then
            wormState.FrozenUsed = true
            wormState.LastDodge = now
            wormState.Engaged = true
            wormState.EngagedAt = now
            noteDodge("slugfish frozen sidestep")
            log("Slugfish + Dozer -> one frozen sidestep (head %.0f studs, lane %.0f)", headDistance, danger)
        end
        return
    end

    if not wormState.SpawnUsed and not wormState.Engaged then
        if not wormState.SpawnPosition then
            wormState.SpawnPosition = position
            wormState.SpawnAt = now
            log(
                "Slugfish spawned %.0f studs away -> waiting %.1fs before taking its spawn ground",
                headDistance,
                CONFIG.WormSpawnWait
            )
        elseif now - wormState.SpawnAt >= CONFIG.WormSpawnWait then
            local target = wormSpawnSpot(wormState.SpawnPosition, velocity)
            if target and teleportTo(target) then
                wormState.SpawnUsed = true
                wormState.Engaged = true
                wormState.EngagedAt = now
                wormState.HoldToEnd = true
                wormState.EmergencyUsed = 0
                wormState.LastDodge = now
                noteDodge("slugfish spawn")
                log(
                    "Slugfish spawn dodge -> took the spawn ground (head %.0f studs, %.0f studs/s) -> holding for the pass",
                    headDistance,
                    velocity.Magnitude
                )
            end
        end
    end

    if wormState.Engaged then
        local passed = headDistance > CONFIG.WormReleaseDistance and danger > CONFIG.WormReleaseDistance
        if passed and not wormState.HoldToEnd then
            wormState.Engaged = false
            log("Slugfish passed (head %.0f studs away) -> resuming room skipping", headDistance)
            return
        end
        if now - wormState.EngagedAt > CONFIG.WormMaxEngage then
            wormState.Engaged = false
            log("Slugfish -> engagement timeout (head %.0f studs), resuming", headDistance)
            return
        end

        if danger < CONFIG.WormEmergencyDistance and wormState.EmergencyUsed < 1 and now - wormState.LastDodge > 0.4 then
            wormState.EmergencyUsed = wormState.EmergencyUsed + 1
            local emergency = wormEscapeSpot(position, velocity, root.Position) or wormRetreatSpot(velocity)
            if emergency and teleportTo(emergency) then
                wormState.LastDodge = now
                noteDodge("slugfish emergency")
                log("Slugfish -> head still closing (%.0f studs), one emergency hop", danger)
            end
        end
        return
    end

    if danger > CONFIG.WormRadius then
        return
    end
    if now - wormState.LastDodge < 0.12 then
        return
    end

    local spot = wormEscapeSpot(position, velocity, root.Position)
    if spot and teleportTo(spot) then
        wormState.LastDodge = now
        wormState.Engaged = true
        wormState.EngagedAt = now
        wormState.EmergencyUsed = 0
        noteDodge("slugfish sidestep")
        log(
            "Slugfish dodge -> %.0f studs off its lane (head %.0f studs, %.0f studs/s, lane was %.0f) -> holding",
            (spot - position).Magnitude,
            headDistance,
            velocity.Magnitude,
            danger
        )
        return
    end

    local retreat = wormRetreatSpot(velocity)
    if retreat and teleportTo(retreat) then
        wormState.LastDodge = now
        wormState.Engaged = true
        wormState.EngagedAt = now
        wormState.EmergencyUsed = 0
        noteDodge("slugfish retreat")
        log("Slugfish dodge -> no lane escape, retreated behind the head -> holding")
    end
end

local function threatNearby()
    local _, _, root = getCharacter()
    if not root then
        return false
    end
    local rushPosition = findRush()
    if rushPosition and (rushPosition - root.Position).Magnitude < CONFIG.RushGuardRange then
        return true
    end
    local wormPosition = findWorm()
    if wormPosition and (wormPosition - root.Position).Magnitude < 18 then
        return true
    end
    return false
end

local function dodgeEyes()
    local eyes = findEyes()
    if #eyes == 0 then
        camOverride.Mode = nil
        camOverride.Target = nil
        return
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end
    local cameraPosition = camera.CFrame.Position

    local nearest, nearestDistance
    for _, eye in ipairs(eyes) do
        local distance = (eye.Position - cameraPosition).Magnitude
        if not nearestDistance or distance < nearestDistance then
            nearest, nearestDistance = eye, distance
        end
    end
    if not nearest then
        return
    end

    if CONFIG.CameraDodge and nearestDistance < 110 then
        camOverride.Target = nearest.Position
        camOverride.Mode = (nearest.Kind == "eyePrime") and "toward" or "away"
    else
        camOverride.Mode = nil
    end

    if nearestDistance < 17 then
        if fireParry(nearest.Position, nearest.Kind) then
            log("%s -> parried at %.0f studs", nearest.Kind, nearestDistance)
        end
    end
end

local function dodgeElkman()
    if wormHolding() or wormDownLocked() then
        return
    end
    local cube, model = findElkman()
    if not cube then
        return
    end
    local _, _, root = getCharacter()
    if not root then
        return
    end
    local position = cube.Position
    local distance = (position - root.Position).Magnitude
    if distance > 120 then
        return
    end
    if distance < 34 then
        if fireParry(position, "elkman") then
            log("Elkman -> parried at %.0f studs", distance)
        end
        return
    end
    if not losBlocked(position, root.Position, model and {model} or nil) then
        local spot = findSafeSpot(position, 10, true, model and {model} or nil)
        if spot and teleportTo(spot) then
            noteDodge("elkman cover")
            log("Elkman -> broke line of sight")
        end
    end
end

local function dodgeGoatman()
    local position = goatmanPosition()
    if not position then
        return
    end
    local _, _, root = getCharacter()
    if not root then
        return
    end
    local distance = (position - root.Position).Magnitude
    if distance < 45 then
        if fireParry(position, "goatman") then
            log("Goatman -> parried at %.0f studs", distance)
        end
    end
end

local CAMERA_BIND_NAME = "GraceAutoCamera"

local function updateCameraOverride()
    if not camOverride.Mode or not CONFIG.AutoDodge or not CONFIG.CameraDodge then
        return
    end
    local camera = Workspace.CurrentCamera
    if not camera or not camOverride.Target then
        return
    end
    local position = camera.CFrame.Position
    local delta = camOverride.Target - position
    if delta.Magnitude < 0.1 then
        return
    end
    local direction
    if camOverride.Mode == "away" then
        direction = -delta.Unit
    else
        direction = delta.Unit
    end
    local flat = Vector3.new(direction.X, 0, direction.Z)
    if flat.Magnitude < 0.01 then
        flat = Vector3.new(0, 0, -1)
    end
    camera.CFrame = CFrame.lookAt(position, position + flat.Unit)
end

pcall(
    function()
        RunService:UnbindFromRenderStep(CAMERA_BIND_NAME)
    end
)
RunService:BindToRenderStep(
    CAMERA_BIND_NAME,
    Enum.RenderPriority.Camera.Value + 1,
    function()
        local ok, err = pcall(updateCameraOverride)
        if not ok then
            state.Errors = state.Errors + 1
            state.LastError = tostring(err)
        end
    end
)

local function safeLoop(name, interval, callback)
    task.spawn(
        function()
            while state.Running do
                local ok, err = pcall(callback)
                if not ok then
                    state.Errors = state.Errors + 1
                    state.LastError = ("%s: %s"):format(name, tostring(err))
                    log("error in %s: %s", name, tostring(err))
                end
                task.wait(interval)
            end
        end
    )
end

local VAULT_SEARCH_RANGE = 300

local function findNearestVault()
    local rooms = getRoomsFolder()
    if not rooms then
        return nil
    end
    local _, _, root = getCharacter()
    local origin = root and root.Position or Workspace.CurrentCamera.CFrame.Position
    local best, bestVault, bestBase, bestHinged, bestPrompt, bestDistance
    for _, room in ipairs(rooms:GetChildren()) do
        local vault = room:FindFirstChild("VaultEntrance")
        if vault then
            local base = vault:FindFirstChild("Base")
            local hinged = vault:FindFirstChild("Hinged")
            if base and hinged then
                local doorPart = hinged:FindFirstChild("Cylinder")
                local doorPosition = doorPart and doorPart.Position or vault:GetPivot().Position
                local distance = (doorPosition - origin).Magnitude
                if not bestDistance or distance < bestDistance then
                    best = room
                    bestVault = vault
                    bestBase = base
                    bestHinged = hinged
                    bestPrompt = hinged:FindFirstChild("ProximityPrompt", true)
                    bestDistance = distance
                end
            end
        end
    end
    if bestVault and bestDistance and bestDistance <= VAULT_SEARCH_RANGE then
        return bestVault, bestBase, bestHinged, bestPrompt, best, bestDistance
    end
    return nil
end

local function vaultStandPoint(base, hinged)
    local doorPart = hinged:FindFirstChild("Cylinder")
    local doorPosition = doorPart and doorPart.Position or hinged:GetPivot().Position
    local best, bestDistance
    for _, part in ipairs(base:GetDescendants()) do
        if part:IsA("BasePart") and part.Size.Y <= 3 then
            local candidate = Vector3.new(part.Position.X, part.Position.Y + part.Size.Y / 2 + 3.05, part.Position.Z)
            local distance = (candidate - doorPosition).Magnitude
            if (not bestDistance or distance < bestDistance) and isFree(candidate) then
                best, bestDistance = candidate, distance
            end
        end
    end
    return best or Vector3.new(doorPosition.X, doorPosition.Y + 3.05, doorPosition.Z)
end

local function triggerVaultPrompt(prompt)
    if not prompt then
        return false
    end
    local ok =
        pcall(
        function()
            prompt:SetAttribute("ClientTriggered", true)
            ReplicatedStorage.TriggerPrompt:FireServer(prompt)
        end
    )
    if type(fireproximityprompt) == "function" then
        pcall(fireproximityprompt, prompt)
    end
    return ok
end

local function vaultStep()
    if not CONFIG.AutoVault or not state.Running then
        return
    end
    if isDead() or freezeState.Active then
        return
    end

    if scaleState.Phase == "hold" then
        return
    end
    if Workspace:GetAttribute("SlowSorrow") ~= nil or wormHolding() or wormDownLocked() then
        return
    end
    local character = getCharacter()
    if not character then
        return
    end

    local vault, base, hinged, prompt, room = findNearestVault()
    if not vault then
        vaultState.Instance = nil
        vaultState.Phase = "approach"
        vaultState.Open = false
        vaultState.Done = nil
        vaultState.GaveUp = false
        vaultState.Attempts = 0
        return
    end
    vaultState.Room = room
    if vaultState.Done == vault then
        return
    end
    if vaultState.Instance ~= vault then
        vaultState.Instance = vault
        vaultState.Phase = "approach"
        vaultState.PhaseAt = 0
        vaultState.HoldElapsed = 0
        vaultState.HoldLast = 0
        vaultState.Attempts = 0
        vaultState.GaveUp = false
        vaultState.Settled = false
        log("VaultEntrance found in room %s", room and room.Name or tostring(currentRoomIndex()))
    end

    if vault:GetAttribute("Open") == true then
        if not vaultState.Open then
            vaultState.Open = true
            vaultState.Done = vault
            vaultState.Settled = true
            log("VaultEntrance open")
        end
        return
    end

    if not prompt then
        vaultState.Done = vault
        vaultState.Settled = true
        log("VaultEntrance has no prompt left, moving on")
        return
    end

    if threatNearby() then
        return
    end

    local roomIndex = room and tonumber(room.Name)

    if vaultState.Phase == "approach" then
        local ok, info
        if roomIndex then
            ok, info = teleportPastExit(roomIndex)
            if not ok then
                ok, info = teleportPastExit(roomIndex, true)
            end
        end
        if ok then
            state.Teleports = state.Teleports + 1
            state.LastTeleport = os.clock()
            log("VaultEntrance: crossed room %s Exit (%.1f studs past)", tostring(roomIndex), info)
        else
            log("VaultEntrance: could not cross Exit (%s), holding here", tostring(info))
        end
        vaultState.Phase = "hold"
        vaultState.PhaseAt = os.clock()
        vaultState.HoldElapsed = 0
        vaultState.HoldLast = os.clock()
        return
    end

    if vaultState.Phase == "hold" then
        if threatNearby() then
            vaultState.HoldLast = os.clock()
            return
        end
        local now = os.clock()
        vaultState.HoldElapsed = (vaultState.HoldElapsed or 0) + math.min(now - (vaultState.HoldLast or now), 0.5)
        vaultState.HoldLast = now
        if vaultState.HoldElapsed < CONFIG.VaultHoldTime then
            return
        end
        vaultState.Phase = "activate"
        log("VaultEntrance: hold done, moving onto the Base")
    end

    if threatNearby() then
        return
    end

    local stand = vaultStandPoint(base, hinged)
    if stand and (character:GetPivot().Position - stand).Magnitude > 2 then
        teleportTo(stand)
    end

    if vaultState.GaveUp or os.clock() - vaultState.LastAttempt < CONFIG.VaultRetryInterval then
        return
    end
    if vaultState.Attempts >= CONFIG.VaultMaxAttempts then
        vaultState.GaveUp = true
        vaultState.Settled = true
        log("VaultEntrance gave up after %d attempts", vaultState.Attempts)
        return
    end

    vaultState.LastAttempt = os.clock()
    vaultState.Attempts = vaultState.Attempts + 1
    if triggerVaultPrompt(prompt) then
        log("VaultEntrance trigger attempt %d", vaultState.Attempts)
    end
end

local readyState = {
    Clicks = 0,
    RemoteFires = 0,
    LastAttempt = 0
}

local function readyStep()
    if not CONFIG.AutoReady or not state.Running then
        return
    end
    if LocalPlayer:GetAttribute("serverReadied") then
        return
    end
    local gui = getPlayerGui()
    local intro = gui and gui:FindFirstChild("Intro")
    local base = intro and intro:FindFirstChild("Base")
    local button = base and base:FindFirstChild("READY")
    if not button or not button:IsA("GuiButton") or not button.Visible then
        return
    end
    if os.clock() - readyState.LastAttempt < 1.0 then
        return
    end
    readyState.LastAttempt = os.clock()
    readyState.Clicks = readyState.Clicks + 1
    if type(firesignal) == "function" then
        pcall(firesignal, button.MouseButton1Click)
    end
    log("Intro READY pressed (attempt %d)", readyState.Clicks)

    task.delay(
        0.5,
        function()
            if not state.Running or not CONFIG.AutoReady then
                return
            end
            if LocalPlayer:GetAttribute("serverReadied") then
                return
            end
            local game2 = Workspace:FindFirstChild("Game")
            local remote = game2 and game2:FindFirstChild("Ready")
            if remote and remote:IsA("RemoteEvent") then
                pcall(
                    function()
                        remote:FireServer()
                    end
                )
                readyState.RemoteFires = readyState.RemoteFires + 1
                log("Intro READY -> fired Ready remote directly")
            end
        end
    )
end

local function saferoomScale(index)
    local room = getRoomModel(index or currentRoomIndex())
    if not room then
        return nil, nil
    end
    local safe = room:FindFirstChild("SafeRoom")
    local scale = safe and safe:FindFirstChild("Scale")
    if not scale then
        return nil, room
    end
    return scale, room
end

local function scaleStep()
    if not CONFIG.AutoScale or not state.Running then
        return
    end
    if isDead() or freezeState.Active or wormHolding() or wormDownLocked() then
        return
    end
    local character, _, root = getCharacter()
    if not character then
        return
    end
    local index = currentRoomIndex()
    if not index then
        return
    end
    local scale, room = saferoomScale(index)
    if not scale then
        scaleState.Phase = "idle"
        scaleState.Room = nil
        return
    end
    if scaleState.Done == room then
        return
    end

    if vaultState.Room == room and not vaultState.Settled then
        return
    end
    local vault, _, _, prompt = findNearestVault()
    if vault and vault ~= vaultState.Done and prompt and not vaultState.GaveUp then
        return
    end
    if scaleState.Room ~= room then
        scaleState.Room = room
        scaleState.Phase = "move"
        scaleState.Tries = 0
    end

    local ok, pivot =
        pcall(
        function()
            return scale:GetPivot().Position
        end
    )
    local point = ok and pivot and standOnFloor(pivot + Vector3.new(0, 4, 0), 60) or nil
    if not point then
        scaleState.Done = room
        scaleState.Phase = "idle"
        log("Saferoom Scale -> nothing to stand on, skipping")
        return
    end

    if scaleState.Phase == "move" then
        scaleState.Tries = (scaleState.Tries or 0) + 1
        scaleState.Point = point
        if teleportTo(point) then
            noteDodge("saferoom scale")
        end
        if scaleState.Tries >= CONFIG.ScaleTeleports then
            scaleState.Phase = "hold"
            scaleState.At = os.clock()
            scaleState.Held = 0
            scaleState.LastTick = os.clock()
            scaleState.Hops = 0
            log(
                "Saferoom -> on Scale after %d hops, holding %.1fs without moving",
                scaleState.Tries,
                CONFIG.ScaleHoldTime
            )
        end
        return
    end

    if scaleState.Phase == "hold" then
        if root and scaleState.Point and (root.Position - scaleState.Point).Magnitude > 6 then
            if (scaleState.Hops or 0) < 1 and teleportTo(scaleState.Point) then
                scaleState.Hops = 1
                log("Saferoom Scale -> drifted off the plate, snapped back")
            end
        end
        local now = os.clock()
        local delta = now - (scaleState.LastTick or now)
        scaleState.LastTick = now
        scaleState.Held = (scaleState.Held or 0) + delta
        if scaleState.Held >= CONFIG.ScaleHoldTime then
            scaleState.Done = room
            scaleState.Phase = "idle"
            log("Saferoom Scale hold done (%.2fs) -> resuming room skipping", scaleState.Held)
        end
    end
end

local lastRoomMessage = nil

local function reportRoomIssue(message)
    if lastRoomMessage == message then
        return
    end
    lastRoomMessage = message
    log("%s", message)
end

local function roomStep()
    if not CONFIG.AutoRoomProgress or not state.Running then
        return
    end
    if isDead() or freezeState.Active then
        return
    end

    if Workspace:GetAttribute("SlowSorrow") ~= nil or wormState.Engaged or wormHolding() or wormDownLocked() then
        return
    end
    local character = getCharacter()
    if not character then
        return
    end
    local index = currentRoomIndex()
    if not index then
        return
    end
    local pendingVault, _, _, pendingPrompt = findNearestVault()
    if pendingVault and pendingVault ~= vaultState.Done and pendingPrompt and not vaultState.GaveUp then
        return
    end

    local scale, scaleRoom = saferoomScale(index)
    if scale and scaleState.Done ~= scaleRoom then
        return
    end
    local ok, result = teleportPastExit(index)
    if not ok then
        reportRoomIssue(("room %d skipped: %s"):format(index, tostring(result)))
        return
    end
    lastRoomMessage = nil
    state.Teleports = state.Teleports + 1
    state.LastTeleport = os.clock()
    log("room %d -> teleported %.1f studs past Exit", index, result)
end

local function dodgeStep()
    if not CONFIG.AutoDodge or not state.Running then
        return
    end
    if isDead() then
        if freezeState.Active then
            setFreeze(false)
        end
        removeCover()
        camOverride.Mode = nil
        camOverride.Target = nil
        return
    end

    local character = getCharacter()
    if not character then
        return
    end

    local dozer = dozerActive()
    if dozer then
        if not freezeState.Active then
            wormState.FrozenUsed = false
        end
        bindDozerGuard()
        setFreeze(true)
        maintainDozerFreeze()
    elseif freezeState.Active then
        setFreeze(false)
    end

    if freezeState.Active and os.clock() - freezeState.StartedAt > freezeState.MaxDuration then
        log("Dozer -> crouch timeout, releasing")
        setFreeze(false)
    end

    if freezeState.Active then
        dodgeRush()
        if sorrowActive() then
            ensureCover()
        end
        return
    end
    if sorrowActive() then
        ensureCover()
    else
        removeCover()
    end

    if goatmanPosition() then
        dodgeGoatman()
    end
    dodgeRush()
    dodgeEyes()
    dodgeElkman()
end

local function statusStep()
    local character, humanoid, root = getCharacter()
    local dead = isDead()
    if dead and not state.Dead then
        state.Dead = true
        state.Deaths = state.Deaths + 1
        local nearestRush, nearestWorm
        pcall(
            function()
                local rushPosition = findRush()
                local wormPosition = findWorm()
                if root and rushPosition then
                    nearestRush = math.floor((rushPosition - root.Position).Magnitude)
                end
                if root and wormPosition then
                    nearestWorm = math.floor((wormPosition - root.Position).Magnitude)
                end
            end
        )
        state.DeathInfo = {
            Room = Workspace:GetAttribute("ClientInRoom"),
            CarnationsGoing = Workspace:GetAttribute("CarnationsGoing"),
            Sorrow = Workspace:GetAttribute("sorrow"),
            SorrowAttack = Workspace:GetAttribute("sorrowAttack"),
            RushGuard = rushGuard.Active,
            RushGuardPreviousVoid = rushGuard.PreviousVoid,
            Dozer = dozerActive(),
            DozerCrouchHeld = freezeState.CrouchPressed,
            DozerKeys = freezeState.KeyNames,
            SlugfishEngaged = wormState.Engaged,
            NearestRush = nearestRush,
            NearestWorm = nearestWorm,
            LastDodge = state.LastDodge,
            Position = root and tostring(root.Position) or nil
        }
        log(
            "DEAD state detected | job=%s deaths=%d room=%s",
            state.JobId,
            state.Deaths,
            tostring(Workspace:GetAttribute("ClientInRoom"))
        )
        log(
            "DEAD context | carnations=%s guard=%s prevVoid=%s nearRush=%s nearWorm=%s lastDodge=%s",
            tostring(state.DeathInfo.CarnationsGoing),
            tostring(state.DeathInfo.RushGuard),
            tostring(state.DeathInfo.RushGuardPreviousVoid),
            tostring(nearestRush),
            tostring(nearestWorm),
            tostring(state.LastDodge)
        )
    elseif not dead and state.Dead then
        state.Dead = false
        log("RESPAWNED / alive again | job=%s room=%s", state.JobId, tostring(Workspace:GetAttribute("ClientInRoom")))
    end

    local gui = getPlayerGui()
    local ready = dead or character == nil or (gui ~= nil and gui:FindFirstChild("losescreen") ~= nil)

    _G.GraceAutoStatus = {
        JobId = state.JobId,
        PlaceId = state.PlaceId,
        Room = Workspace:GetAttribute("ClientInRoom"),
        CurrentRoom = Workspace:GetAttribute("CurrentRoom"),
        RoomCount = Workspace:GetAttribute("RoomCount"),
        Health = humanoid and humanoid.Health or nil,
        Dead = dead,
        Ready = ready,
        InRun = Workspace:GetAttribute("WeGoin"),
        RoomProgress = CONFIG.AutoRoomProgress,
        AutoDodge = CONFIG.AutoDodge,
        Vault = vaultState.Instance and vaultState.Instance:GetFullName() or nil,
        VaultPhase = vaultState.Phase,
        ScalePhase = scaleState.Phase,
        ScaleRoom = scaleState.Room and scaleState.Room.Name or nil,
        ScaleDone = scaleState.Done and scaleState.Done.Name or nil,
        ScaleHeld = scaleState.Held,
        VaultOpen = vaultState.Open,
        VaultAttempts = vaultState.Attempts,
        RushGuard = rushGuard.Active,
        ReadyClicks = readyState.Clicks,
        CarnationsGoing = Workspace:GetAttribute("CarnationsGoing"),
        DeathInfo = state.DeathInfo,
        DozerFrozen = freezeState.Active,
        DozerCrouchHeld = freezeState.CrouchPressed,
        DozerKeys = freezeState.KeyNames,
        SlugfishEngaged = wormState.Engaged,
        SlugfishUpward = wormState.Upward,
        SlugfishUpwardY = wormState.UpwardY,
        SlugfishFrozenMove = wormState.FrozenUsed,
        Rearm = rearmState.Registered and rearmState.Path or ("off: " .. tostring(rearmState.Err)),
        Teleports = state.Teleports,
        Dodges = state.Dodges,
        LastDodge = state.LastDodge,
        Errors = state.Errors,
        LastError = state.LastError,
        LastTeleport = state.LastTeleport,
        Frozen = freezeState.Active,
        UpdatedAt = os.clock(),
        Position = root and tostring(root.Position) or nil
    }
end

local function statusLogStep()
    local snapshot = _G.GraceAutoStatus or {}
    local mode = "alive"
    if snapshot.Dead then
        mode = "dead/ready"
    end
    log(
        "job=%s room=%s/%s hp=%s mode=%s tp=%d dodge=%d err=%d",
        tostring(state.JobId),
        tostring(snapshot.Room),
        tostring(snapshot.RoomCount),
        tostring(snapshot.Health),
        mode,
        state.Teleports,
        state.Dodges,
        state.Errors
    )
end

safeLoop("rooms", CONFIG.RoomTeleportInterval, roomStep)
safeLoop("vault", 0.5, vaultStep)
safeLoop("ready", 0.5, readyStep)
safeLoop("scale", CONFIG.ScaleInterval, scaleStep)
safeLoop("dodge", CONFIG.DodgeInterval, dodgeStep)
safeLoop("slugfish", CONFIG.WormInterval, wormStep)
safeLoop("status", 1, statusStep)
safeLoop("statusLog", CONFIG.StatusInterval, statusLogStep)

local connections = {}

table.insert(
    connections,
    Workspace:GetAttributeChangedSignal("CarnationsGoing"):Connect(
        function()
            if not CONFIG.AutoDodge or not state.Running or isDead() then
                return
            end
            if rushActive() then
                ensureRushImmunity()
            end
        end
    )
)

local function stop()
    if not state.Running then
        return
    end
    state.Running = false
    setFreeze(false)
    removeCover()
    clearRushGuard()
    clearRearm()
    camOverride.Mode = nil
    camOverride.Target = nil
    pcall(
        function()
            RunService:UnbindFromRenderStep(CAMERA_BIND_NAME)
        end
    )
    for _, connection in ipairs(connections) do
        pcall(
            function()
                connection:Disconnect()
            end
        )
    end
    _G.GraceAutoStatus = nil
    log("stopped")
end

_G.GraceAuto = {
    Stop = stop,
    State = state,
    Config = CONFIG
}

table.insert(
    connections,
    UserInputService.InputBegan:Connect(
        function(input, processed)
            if processed then
                return
            end
            if input.KeyCode == CONFIG.KeyToggleRooms then
                CONFIG.AutoRoomProgress = not CONFIG.AutoRoomProgress
                log("room skipping: %s", CONFIG.AutoRoomProgress and "on" or "off")
            elseif input.KeyCode == CONFIG.KeyToggleDodge then
                CONFIG.AutoDodge = not CONFIG.AutoDodge
                log("auto dodge: %s", CONFIG.AutoDodge and "on" or "off")
            elseif input.KeyCode == CONFIG.KeyUnload then
                stop()
            elseif input.KeyCode == CONFIG.KeyDozer then
                toggleDozer()
                log("Dozer auto-dodge: %s", dozerState.Active and "on" or "off")
            end
        end
    )
)

setupRearm()
log("loaded | job=%s place=%s", state.JobId, tostring(state.PlaceId))
