if _G.UTG then
	pcall(_G.UTG.Unload)
	_G.UTG = nil
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
	AutoRoll = true,
	AutoVault = true,

	HardLandingSpeed = 40,
	TargetMs = 0.001,
	StampOffset = 0.0032,

	HighVaultOnly = false,
	HighVaultMinHeight = 2.0,
	VaultMinSpeed = 10,
	VaultForwardDot = 0.3,
	VaultCooldown = 0.35,

	VaultWhileFalling = true,
	FallingVaultMinDownSpeed = 6,

	ToggleRollKey = Enum.KeyCode.T,
	ToggleVaultKey = Enum.KeyCode.Y,
	ToggleHighVaultKey = Enum.KeyCode.H,
	UnloadKey = Enum.KeyCode.Delete,
}

local State = {
	Loaded = true,
	RollStampCount = 0,
	VaultPressCount = 0,
	LastVaultHeight = 0,
	LastVaultPress = 0,
	LastRollMs = nil,
	PendingRollTune = false,
	RollQueueInput = nil,
	VaultInstance = nil,
	Controller = nil,
	LastBindRetry = 0,
	CharTag = nil,
	CharRayParams = nil,
	OverlapParams = nil,
	Connections = {},
}

local function Notify(title, text, duration)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title or "UTG",
			Text = text or "",
			Duration = duration or 3,
		})
	end)
end

local function Track(conn)
	if conn ~= nil then
		table.insert(State.Connections, conn)
	end
end

local function BindRollModule()
	State.RollQueueInput = nil
	local char = LocalPlayer.Character
	local scripts = char and char:FindFirstChild("scripts")
	local movement = scripts and scripts:FindFirstChild("movement")
	local parkour = movement and movement:FindFirstChild("Parkour")
	local module = parkour and parkour:FindFirstChild("Roll")
	if not module then
		return
	end
	local ok, factory = pcall(require, module)
	if not ok or type(factory) ~= "function" then
		return
	end
	local okInst, inst = pcall(factory, {})
	if okInst and type(inst) == "table" and type(inst.QueueInput) == "function" then
		State.RollQueueInput = inst.QueueInput
	end
end

local function ControllerScore(ctrl, char)
	if type(ctrl) ~= "table" or type(ctrl.RollMs) ~= "number" then
		return 0
	end
	local rig = ctrl.Rig
	local instance = type(rig) == "table" and rig.Instance or nil
	if typeof(instance) ~= "Instance" or not instance:IsDescendantOf(Workspace) then
		return 0
	end
	if not char or not instance:IsDescendantOf(char) then
		return 0
	end
	local score = 1
	if type(ctrl.EmoteRestricted) == "function" then
		score += 1
	end
	if type(ctrl.IsSlideHeld) == "function" then
		score += 1
	end
	if type(ctrl.AddMomentum) == "function" then
		score += 1
	end
	if ctrl.Params ~= nil then
		score += 1
	end
	return score
end

local function IsLiveController(ctrl, char)
	return ControllerScore(ctrl, char) > 0
end

local function BindController()
	State.Controller = nil
	local ok, matches = pcall(filtergc, "table", { Keys = { "RollMs", "VaultDebounce" } }, false)
	if not ok or type(matches) ~= "table" then
		return
	end
	if matches.RollMs ~= nil then
		matches = { matches }
	end
	local char = LocalPlayer.Character
	local best, bestScore = nil, 0
	for _, ctrl in ipairs(matches) do
		local score = ControllerScore(ctrl, char)
		if score > bestScore then
			best, bestScore = ctrl, score
		end
	end
	State.Controller = best
end

local function StampRollInput()
	if not State.RollQueueInput or type(setupvalue) ~= "function" then
		return
	end
	local ok = pcall(setupvalue, State.RollQueueInput, 1, time() + CONFIG.StampOffset)
	if ok then
		State.RollStampCount += 1
		State.PendingRollTune = true
	end
end

local function CanRollOnLanding(root)
	local ctrl = State.Controller
	if ctrl and type(ctrl.FallingSpeed) == "number" then
		return ctrl.FallingSpeed <= -CONFIG.HardLandingSpeed
	end
	return root.AssemblyLinearVelocity.Y <= -CONFIG.HardLandingSpeed
end

local function TuneRoll()
	State.PendingRollTune = false
	local ctrl = State.Controller
	if not ctrl or type(ctrl.RollMs) ~= "number" then
		return
	end
	if ctrl.RollMs == State.LastRollMs then
		return
	end
	State.LastRollMs = ctrl.RollMs
	local delta = ctrl.RollMs / 1000 - CONFIG.TargetMs
	CONFIG.StampOffset = math.clamp(CONFIG.StampOffset + delta, 0, 0.004)
end

local function BuildParams(char)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { char, Workspace.CurrentCamera }
	rayParams.CollisionGroup = "Player"

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { char, Workspace.CurrentCamera }
	overlap.CollisionGroup = "Player"
	overlap.MaxParts = 1

	State.CharRayParams = rayParams
	State.OverlapParams = overlap
end

local function BindVaultModule()
	State.VaultInstance = nil
	local ctrl = State.Controller
	if not ctrl then
		return
	end
	local char = LocalPlayer.Character
	local scripts = char and char:FindFirstChild("scripts")
	local movement = scripts and scripts:FindFirstChild("movement")
	local parkour = movement and movement:FindFirstChild("Parkour")
	local module = parkour and parkour:FindFirstChild("Vault")
	if not module then
		return
	end
	local ok, factory = pcall(require, module)
	if not ok or type(factory) ~= "function" then
		return
	end
	local okInst, inst = pcall(factory, ctrl)
	if okInst and type(inst) == "table" and type(inst.Probe) == "function" and type(inst.Activate) == "function" then
		State.VaultInstance = inst
	end
end

local function EnsureBindings()
	local char = State.CharTag
	if not char or char ~= LocalPlayer.Character then
		return
	end
	local staleController = not IsLiveController(State.Controller, char)
	local missingRoll = State.RollQueueInput == nil
	local missingVault = State.VaultInstance == nil
	if not (staleController or missingRoll or missingVault) then
		return
	end
	if os.clock() - State.LastBindRetry < 1 then
		return
	end
	State.LastBindRetry = os.clock()

	local previous = State.Controller
	if staleController then
		BindController()
		BuildParams(char)
	end
	if State.RollQueueInput == nil then
		BindRollModule()
	end
	if State.Controller and (State.Controller ~= previous or State.VaultInstance == nil) then
		BindVaultModule()
	end
end

local function Unload()
	State.Loaded = false
	for _, conn in ipairs(State.Connections) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	table.clear(State.Connections)
end

Track(RunService.RenderStepped:Connect(function()
	if not State.Loaded then
		return
	end
	EnsureBindings()
	if not CONFIG.AutoRoll then
		return
	end

	local char = State.CharTag
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or humanoid.FloorMaterial ~= Enum.Material.Air then
		if State.PendingRollTune then
			TuneRoll()
		end
		return
	end

	if humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
		return
	end

	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	if not CanRollOnLanding(root) then
		return
	end

	StampRollInput()
end))

Track(RunService.Heartbeat:Connect(function()
	if not State.Loaded or not CONFIG.AutoVault then
		return
	end
	local inst = State.VaultInstance
	if not inst then
		return
	end
	if os.clock() - State.LastVaultPress < CONFIG.VaultCooldown then
		return
	end

	local char = State.CharTag
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air

	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local velocity = root.AssemblyLinearVelocity
	if grounded then
		local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
		local look = root.CFrame.LookVector
		local lookFlat = Vector3.new(look.X, 0, look.Z)
		if horizontal.Magnitude < CONFIG.VaultMinSpeed then
			return
		end
		if lookFlat.Magnitude < 0.01 then
			return
		end
		if horizontal.Unit:Dot(lookFlat.Unit) < CONFIG.VaultForwardDot then
			return
		end
	else
		if not CONFIG.VaultWhileFalling then
			return
		end
		if velocity.Y > -CONFIG.FallingVaultMinDownSpeed then
			return
		end
	end

	local ok, ledge, swingBar = pcall(inst.Probe, true)
	if not ok or not ledge or swingBar then
		return
	end

	local height = math.abs(ledge.Position.Y - root.Position.Y)
	if CONFIG.HighVaultOnly and height < CONFIG.HighVaultMinHeight then
		return
	end

	local activated = pcall(inst.Activate, ledge)
	if activated then
		State.LastVaultHeight = height
		State.LastVaultPress = os.clock()
		State.VaultPressCount += 1
	end
end))

local function BindCharacter()
	local char = LocalPlayer.Character
	if not char then
		return
	end
	State.CharTag = char
	BuildParams(char)
	BindRollModule()
	BindController()
	BindVaultModule()
end

Track(LocalPlayer.CharacterAdded:Connect(function(char)
	task.delay(0.25, function()
		if State.Loaded then
			State.CharTag = char or LocalPlayer.Character
			BuildParams(State.CharTag)
			BindRollModule()
			BindController()
			BindVaultModule()
			State.LastRollMs = nil
			Notify("UTG", "Rebound to new character", 2)
		end
	end)
end))

BindCharacter()

State.Unload = function()
	Unload()
	_G.UTG = nil
	Notify("UTG", "Script unloaded", 2)
end

State.Status = function()
	return {
		AutoRoll = CONFIG.AutoRoll,
		AutoVault = CONFIG.AutoVault,
		HighVaultOnly = CONFIG.HighVaultOnly,
		VaultWhileFalling = CONFIG.VaultWhileFalling,
		RollStamps = State.RollStampCount,
		LastRollMs = State.LastRollMs,
		StampOffsetMs = CONFIG.StampOffset * 1000,
		RollBound = State.RollQueueInput ~= nil,
		ControllerLive = IsLiveController(State.Controller, State.CharTag),
		VaultBound = State.VaultInstance ~= nil,
		VaultPresses = State.VaultPressCount,
		LastVaultHeight = State.LastVaultHeight,
		Grounded = State.CharTag ~= nil
			and State.CharTag:FindFirstChildOfClass("Humanoid")
			and State.CharTag:FindFirstChildOfClass("Humanoid").FloorMaterial ~= Enum.Material.Air,
	}
end

State.ToggleHighVaultOnly = function()
	CONFIG.HighVaultOnly = not CONFIG.HighVaultOnly
	Notify("UTG", ("HighVaultOnly: %s"):format(CONFIG.HighVaultOnly and "ON (2+ studs)" or "OFF (all vaults)"), 3)
	return CONFIG.HighVaultOnly
end

State.ToggleAutoRoll = function()
	CONFIG.AutoRoll = not CONFIG.AutoRoll
	Notify("UTG", ("AutoRoll: %s"):format(CONFIG.AutoRoll and "ON" or "OFF"), 2)
	return CONFIG.AutoRoll
end

State.ToggleAutoVault = function()
	CONFIG.AutoVault = not CONFIG.AutoVault
	Notify("UTG", ("AutoVault: %s"):format(CONFIG.AutoVault and "ON" or "OFF"), 2)
	return CONFIG.AutoVault
end

_G.UTG = State

Track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == CONFIG.ToggleRollKey then
		State.ToggleAutoRoll()
	elseif input.KeyCode == CONFIG.ToggleVaultKey then
		State.ToggleAutoVault()
	elseif input.KeyCode == CONFIG.ToggleHighVaultKey then
		State.ToggleHighVaultOnly()
	elseif input.KeyCode == CONFIG.UnloadKey then
		State.Unload()
	end
end))

Notify("UTG", ("Loaded - AutoRoll[%s] AutoVault[%s] (high vaults 2+ studs)"):format(
	CONFIG.AutoRoll and "on" or "off",
	CONFIG.AutoVault and "on" or "off"
), 6)
