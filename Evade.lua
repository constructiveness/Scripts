local CONFIG = {
    SpeedMultiplier = 2.0,
    AccelerationMultiplier = 2.0,
    BunnyhopEnabled = true,
    BunnyhopToggleKey = Enum.KeyCode.RightShift,
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local SPEED_KEY = "EvadeSpeedChanger"
local MIN_MULTIPLIER = 0.1
local MAX_MULTIPLIER = 50

local SPEED_MULTIPLIER = math.clamp(
    tonumber(CONFIG.SpeedMultiplier) or 1,
    MIN_MULTIPLIER,
    MAX_MULTIPLIER
)
local ACCEL_MULTIPLIER = math.clamp(
    tonumber(CONFIG.AccelerationMultiplier) or 1,
    MIN_MULTIPLIER,
    MAX_MULTIPLIER
)

local ACCEL_FIELDS = {
    "RunAccel",
    "AirAcceleration",
    "AirStrafeAcceleration",
    "SprintAcceleration",
}

local player = Players.LocalPlayer

local CharacterService
do
    local ok, result = pcall(function()
        return require(
            game:GetService("ReplicatedStorage")
                :WaitForChild("Services")
                :WaitForChild("Asset")
                :WaitForChild("CharacterService")
        )
    end)

    if ok then
        CharacterService = result
    end
end

local previous = getgenv().EvadeAutoBhop

if previous then
    pcall(function()
        if previous.heartbeat then previous.heartbeat:Disconnect() end
        if previous.input then previous.input:Disconnect() end
        if previous.inputEnded then previous.inputEnded:Disconnect() end
        if previous.focus then previous.focus:Disconnect() end

        for _, connection in ipairs(previous.guiConnections or {}) do
            if connection then connection:Disconnect() end
        end

        if previous.gui then previous.gui:Destroy() end

        if previous.moveStats then
            previous.moveStats:SpeedChange(SPEED_KEY, nil)

            if previous.baseAccel and previous.statsTable then
                for field, baseValue in pairs(previous.baseAccel) do
                    previous.statsTable[field] = baseValue
                end
            end
        end

        if previous.movement then
            previous.movement.JumpHeldDown = false
            previous.movement.XboxJumping = false
        end
    end)
end

do
    local playerGui = player:FindFirstChild("PlayerGui")

    if playerGui then
        local oldPanel = playerGui:FindFirstChild("EvadeMovementPanel")

        if oldPanel then
            oldPanel:Destroy()
        end
    end
end

local state = {
    enabled = CONFIG.BunnyhopEnabled == true,
    spaceHeld = UserInputService:IsKeyDown(Enum.KeyCode.Space),
    speedMult = SPEED_MULTIPLIER,
    accelMult = ACCEL_MULTIPLIER,
    character = nil,
    humanoid = nil,
    movement = nil,
    moveStats = nil,
    statsTable = nil,
    baseAccel = nil,
    baseSpeed = nil,
    appliedAccel = 1,
    heartbeat = nil,
    input = nil,
    inputEnded = nil,
    focus = nil,
}

local function getLocalCharacter()
    if not CharacterService then
        return nil
    end

    local ok, localCharacter = pcall(function()
        return CharacterService:GetLocalCharacter()
    end)

    if ok then
        return localCharacter
    end

    return nil
end

local function findMovement(character, humanoid)
    local localCharacter = getLocalCharacter()

    if localCharacter and localCharacter.Model == character and localCharacter.Movement then
        return localCharacter.Movement
    end

    if type(getgc) ~= "function" then
        return nil
    end

    for _, object in getgc(true) do
        if type(object) == "table"
            and rawget(object, "Character") == character
            and rawget(object, "Humanoid") == humanoid
        then
            local metatable = getrawmetatable(object)
            local index = metatable and metatable.__index

            if type(index) == "table" and type(rawget(index, "JumpReact")) == "function" then
                return object
            end
        end
    end

    return nil
end

local function setJumping(movement, enabled)
    if not movement then
        return
    end

    pcall(function()
        movement.JumpHeldDown = enabled
        movement.XboxJumping = enabled
    end)
end

local function snapshotAccel(stats)
    local snapshot = {}

    for _, field in ipairs(ACCEL_FIELDS) do
        local value = stats[field]

        if type(value) == "number" then
            snapshot[field] = value
        end
    end

    return snapshot
end

local function applyTuning(movement)
    local moveStats = movement and movement.MoveStats
    local stats = moveStats and moveStats.MoveStats

    if not stats then
        return
    end

    if state.moveStats ~= moveStats or state.statsTable ~= stats then
        state.moveStats = moveStats
        state.statsTable = stats
        state.baseAccel = snapshotAccel(stats)
        state.baseSpeed = stats.BaseSpeed
        state.appliedAccel = 1
    elseif stats.BaseSpeed ~= state.baseSpeed then
        state.baseSpeed = stats.BaseSpeed
        state.baseAccel = snapshotAccel(stats)
        state.appliedAccel = 1
    end

    local desiredSpeed = state.speedMult ~= 1 and state.speedMult or nil

    if moveStats.SpeedChanges[SPEED_KEY] ~= desiredSpeed then
        pcall(function()
            moveStats:SpeedChange(SPEED_KEY, desiredSpeed)
        end)
    end

    local baseAccel = state.baseAccel

    if baseAccel then
        local desiredAccel = state.accelMult
        local baseRunAccel = baseAccel.RunAccel
        local matches = baseRunAccel ~= nil
            and math.abs(stats.RunAccel - baseRunAccel * state.appliedAccel) < 0.0001

        if state.appliedAccel ~= desiredAccel or not matches then
            for field, baseValue in pairs(baseAccel) do
                stats[field] = baseValue * desiredAccel
            end

            state.appliedAccel = desiredAccel
        end
    end
end

state.heartbeat = RunService.Heartbeat:Connect(function()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if not humanoid or humanoid.Health <= 0 then
        setJumping(state.movement, false)
        state.character = nil
        state.humanoid = nil
        state.movement = nil
        state.moveStats = nil
        state.statsTable = nil
        return
    end

    local localCharacter = getLocalCharacter()
    local movement = localCharacter and localCharacter.Movement or state.movement

    if not movement or (localCharacter and localCharacter.Model ~= character) then
        movement = findMovement(character, humanoid)
    end

    if character ~= state.character or humanoid ~= state.humanoid or movement ~= state.movement then
        setJumping(state.movement, false)
        state.character = character
        state.humanoid = humanoid
        state.movement = movement
        state.moveStats = nil
        state.statsTable = nil
    end

    local active = state.enabled
        and state.spaceHeld
        and not UserInputService:GetFocusedTextBox()

    if movement then
        setJumping(movement, active)
        applyTuning(movement)
        return
    end

    if active then
        local humanoidState = humanoid:GetState()

        if humanoidState == Enum.HumanoidStateType.Running
            or humanoidState == Enum.HumanoidStateType.RunningNoPhysics
            or humanoidState == Enum.HumanoidStateType.Landed
        then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

state.input = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.KeyCode == Enum.KeyCode.Space then
        state.spaceHeld = true
        return
    end

    if gameProcessed then
        return
    end

    if input.KeyCode == CONFIG.BunnyhopToggleKey then
        state.enabled = not state.enabled

        if not state.enabled then
            setJumping(state.movement, false)
        end

        print(("[Evade Movement] Bunnyhop %s"):format(state.enabled and "enabled" or "disabled"))
    end
end)

state.inputEnded = UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Space then
        state.spaceHeld = false
        setJumping(state.movement, false)
    end
end)

state.focus = UserInputService.WindowFocusReleased:Connect(function()
    state.spaceHeld = false
    setJumping(state.movement, false)
end)

getgenv().EvadeAutoBhop = state

print(("[Evade Movement] Loaded - Speed x%.2f | Acceleration x%.2f | Bunnyhop %s")
    :format(SPEED_MULTIPLIER, ACCEL_MULTIPLIER, state.enabled and "ON" or "OFF"))
