local CONFIG = {

    TeleportInterval = 0.1,
    TeleportPastMin = 5,
    TeleportPastMax = 10,

    FloorProbeDepth = 500,

    AutoFruit = true,
    FruitHold = 1.5,

    Debug = true,
    StatusInterval = 5,

    KeyPause = Enum.KeyCode.RightShift,
    KeyFruit = Enum.KeyCode.RightControl,
    KeyUnload = Enum.KeyCode.RightAlt,
}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    return
end

if type(_G.GraceZen) == "table" and type(_G.GraceZen.Stop) == "function" then
    pcall(_G.GraceZen.Stop)
end

local state = {
    Running = true,
    Paused = false,

    Room = nil,

    Teleports = 0,
    FruitTouches = 0,
    FruitFired = 0,
    Errors = 0,
    LastError = nil,
    LastIssue = nil,
    LastTeleport = 0,
    LastFruit = nil,
    HoldUntil = 0,
    LastStatusLog = 0,
    StartedAt = os.clock(),
    Connections = {},
}

local touchedRooms = {}

local function log(fmt, ...)
    if not CONFIG.Debug then
        return
    end
    local ok, msg = pcall(string.format, fmt, ...)
    print("[ZenAuto] " .. (ok and msg or tostring(fmt)))
end

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

local function getRooms()
    return workspace:FindFirstChild("Rooms")
end

local function roomModel(index)
    local rooms = getRooms()
    if not rooms or not index then
        return nil
    end
    return rooms:FindFirstChild(tostring(index))
end

local function currentRoomIndex()
    local raw = workspace:GetAttribute("ClientInRoom")
    if raw == nil then
        raw = workspace:GetAttribute("CurrentRoom")
    end
    return tonumber(raw)
end

local function teleportTo(position)
    local character = getCharacter()
    if not character then
        return false
    end
    character:PivotTo(CFrame.new(position))
    local _, _, root = getCharacter()
    if root then
        root.AssemblyLinearVelocity = Vector3.zero
    end
    return true
end

local function nearestExitIndex()
    local rooms = getRooms()
    local _, _, root = getCharacter()
    if not rooms or not root then
        return nil
    end
    local best, bestDistance
    for _, room in ipairs(rooms:GetChildren()) do
        local index = tonumber(room.Name)
        local exitPart = room:FindFirstChild("Exit", true)
        if index and exitPart and exitPart:IsA("BasePart") then
            local distance = (exitPart.Position - root.Position).Magnitude
            if distance >= 12 and (not bestDistance or distance < bestDistance) then
                best, bestDistance = index, distance
            end
        end
    end
    return best
end

local function resolveRoom()
    local rooms = getRooms()
    if not rooms then
        return nil
    end

    local server = currentRoomIndex()
    local pointer = state.Room

    if pointer and rooms:FindFirstChild(tostring(pointer)) then

        if server and server > pointer and rooms:FindFirstChild(tostring(server)) then
            state.Room = server
            return server
        end
        return pointer
    end

    if server and rooms:FindFirstChild(tostring(server)) then
        state.Room = server
        return server
    end

    local geometric = nearestExitIndex()
    if geometric then
        state.Room = geometric
        return geometric
    end
    return nil
end

local function findFloor(x, z, fromY, ignore)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    params.RespectCanCollide = true
    return workspace:Raycast(
        Vector3.new(x, fromY, z),
        Vector3.new(0, -CONFIG.FloorProbeDepth, 0),
        params
    )
end

local function teleportPastExit(index)
    local room = roomModel(index)
    if not room then
        return false, "room missing"
    end
    local exitPart = room:FindFirstChild("Exit", true)
    local entrancePart = room:FindFirstChild("Entrance", true)
    if not exitPart or not exitPart:IsA("BasePart") then
        return false, "no Exit part"
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

    local past = CONFIG.TeleportPastMin
        + math.random() * (CONFIG.TeleportPastMax - CONFIG.TeleportPastMin)
    local target = exitPart.Position + flat * past

    local character = LocalPlayer.Character
    local ignore = character and { character } or {}

    local hit = findFloor(target.X, target.Z, exitPart.Position.Y + 3, ignore)
    local landingTarget = target

    if not hit then
        local rooms = getRooms()
        local nextRoom = rooms and rooms:FindFirstChild(tostring(index + 1))
        local nextEntrance = nextRoom and nextRoom:FindFirstChild("Entrance", true)
        if nextEntrance and nextEntrance:IsA("BasePart") then
            landingTarget = nextEntrance.Position
            hit = findFloor(
                landingTarget.X,
                landingTarget.Z,
                nextEntrance.Position.Y + 10,
                ignore
            )
        end
    end

    local landing
    if hit then
        landing = Vector3.new(landingTarget.X, hit.Position.Y + 3.05, landingTarget.Z)
    else
        landing = Vector3.new(
            landingTarget.X,
            landingTarget.Y + 3.05,
            landingTarget.Z
        )
    end

    if not teleportTo(landing) then
        return false, "no character"
    end
    return true, past
end

local function fireTouch(character, target)
    if type(firetouchinterest) ~= "function" then
        return false
    end

    local parts = {}
    local root = character:FindFirstChild("HumanoidRootPart")
    if root then
        table.insert(parts, root)
    end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part ~= root then
            table.insert(parts, part)
        end
    end

    for _, part in ipairs(parts) do
        local ok = pcall(function()
            firetouchinterest(part, target, 0)
            firetouchinterest(part, target, 1)
        end)
        if ok then
            return true
        end
    end
    return false
end

local function touchFruit(character, fruit)
    character:PivotTo(CFrame.new(fruit.Position))
    local _, _, root = getCharacter()
    if root then
        root.AssemblyLinearVelocity = Vector3.zero
    end
    return fireTouch(character, fruit)
end

local function step()
    if not state.Running or state.Paused then
        return
    end

    local character = getCharacter()
    if not character then
        state.Room = nil
        return
    end

    local index = resolveRoom()
    if not index then
        return
    end

    local room = roomModel(index)
    if not room then
        state.Room = nil
        return
    end

    local rooms = getRooms()
    local nextRoom = rooms and rooms:FindFirstChild(tostring(index + 1))
    local roomCount = tonumber(workspace:GetAttribute("RoomCount")) or 0
    if not nextRoom and roomCount <= index then
        return
    end

    if CONFIG.AutoFruit and not touchedRooms[room.Name] then
        local fruit = room:FindFirstChild("fruit", true)
        if fruit and fruit:IsA("BasePart") then
            local ok, fired = pcall(touchFruit, character, fruit)
            if ok then
                touchedRooms[room.Name] = true
                state.FruitTouches = state.FruitTouches + 1
                if fired then
                    state.FruitFired = state.FruitFired + 1
                end
                state.LastFruit = {
                    Room = room.Name,
                    Fired = fired,
                    Position = fruit.Position,
                    At = os.clock(),
                }
                log(
                    "fruit room %s -> %s at (%.1f, %.1f, %.1f) | fruits=%d",
                    room.Name,
                    fired and "touch fired" or "placed (no firetouchinterest)",
                    fruit.Position.X,
                    fruit.Position.Y,
                    fruit.Position.Z,
                    state.FruitTouches
                )
                if CONFIG.FruitHold > 0 then
                    state.HoldUntil = os.clock() + CONFIG.FruitHold
                end
            end
        end
    end

    if os.clock() < state.HoldUntil then
        return
    end

    local ok, info = teleportPastExit(index)
    if not ok then
        if state.LastIssue ~= info then
            state.LastIssue = info
            log("room %s exit not crossed: %s", room.Name, tostring(info))
        end
        return
    end

    state.LastIssue = nil
    state.Room = index + 1
    state.Teleports = state.Teleports + 1
    state.LastTeleport = os.clock()
    state.HoldUntil = 0
end

task.spawn(function()
    local interval = CONFIG.TeleportInterval
    local nextAt = os.clock()
    while state.Running do
        local now = os.clock()
        if now >= nextAt then
            local ok, err = pcall(step)
            if not ok then
                state.Errors = state.Errors + 1
                state.LastError = tostring(err)
                log("error in step: %s", tostring(err))
            end
            nextAt = math.max(nextAt + interval, now)
        end
        task.wait()
    end
end)

local function statusStep()
    local _, humanoid, root = getCharacter()
    local rubbleAttribute = workspace:GetAttribute("RUBBLE")
    local sinAttribute = workspace:GetAttribute("SIN")
    local hereComesSin = workspace:GetAttribute("HERECOMESSIN")

    _G.GraceZenStatus = {
        Room = state.Room,
        ServerRoom = currentRoomIndex(),
        RoomCount = tonumber(workspace:GetAttribute("RoomCount")),
        Teleports = state.Teleports,
        FruitTouches = state.FruitTouches,
        FruitFired = state.FruitFired,
        LastFruit = state.LastFruit,
        Paused = state.Paused,
        AutoFruit = CONFIG.AutoFruit,
        Health = humanoid and humanoid.Health or nil,
        Position = root and tostring(root.Position) or nil,
        Errors = state.Errors,
        LastError = state.LastError,
        RubbleAttribute = rubbleAttribute,
        RubbleModel = workspace:FindFirstChild("RUBBLE") ~= nil,
        Sin = sinAttribute,
        HereComesSin = hereComesSin,
        UpdatedAt = os.clock(),
    }

    if os.clock() - state.LastStatusLog >= CONFIG.StatusInterval then
        state.LastStatusLog = os.clock()
        log(
            "status room=%s server=%s/%s tp=%d fruits=%d/%d err=%d paused=%s",
            tostring(state.Room),
            tostring(currentRoomIndex()),
            tostring(workspace:GetAttribute("RoomCount")),
            state.Teleports,
            state.FruitTouches,
            state.FruitFired,
            state.Errors,
            tostring(state.Paused)
        )
    end
end

task.spawn(function()
    while state.Running do
        pcall(statusStep)
        task.wait(1)
    end
end)

local function stop()
    if not state.Running then
        return
    end
    state.Running = false
    for _, connection in ipairs(state.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    _G.GraceZenStatus = nil
    log("stopped")
end

_G.GraceZen = {
    Stop = stop,
    State = state,
    Config = CONFIG,
}

table.insert(state.Connections, UserInputService.InputBegan:Connect(function(input, processed)
    if processed then
        return
    end
    if input.KeyCode == CONFIG.KeyPause then
        state.Paused = not state.Paused
        log("paused: %s", tostring(state.Paused))
    elseif input.KeyCode == CONFIG.KeyFruit then
        CONFIG.AutoFruit = not CONFIG.AutoFruit
        log("fruit touching: %s", CONFIG.AutoFruit and "on" or "off")
    elseif input.KeyCode == CONFIG.KeyUnload then
        stop()
    end
end))

log(
    "loaded | job=%s room=%s/%s fruit=%s firetouch=%s interval=%.2fs",
    game.JobId,
    tostring(currentRoomIndex()),
    tostring(workspace:GetAttribute("RoomCount")),
    tostring(CONFIG.AutoFruit),
    tostring(type(firetouchinterest) == "function"),
    CONFIG.TeleportInterval
)
