local CONFIG = {
	SwingSpeedMultiplier = 2,
	MinCooldown          = 0.05,

	HoldToAutoSwing      = true,
	AutoSwingGap         = 0.05,

	AutoTrain            = true,
	TrainTickGap         = 0.05,

	AutoSell             = true,
	AutoSellInterval     = 2,

	Enabled              = true,
	ToggleKey            = Enum.KeyCode.F,
	TrainToggleKey       = Enum.KeyCode.G,
	SellToggleKey        = Enum.KeyCode.H,

	ShowNotifications    = true,
}

local env = (type(getgenv) == "function" and getgenv()) or _G

local STATE = env.SaberSimSwing
if STATE and type(STATE.Cleanup) == "function" then
	STATE.Cleanup()
end
env.SaberSimSwing = nil

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local MainClient = LocalPlayer:WaitForChild("PlayerScripts", 10)
	and LocalPlayer.PlayerScripts:WaitForChild("MainClient", 10)
if not MainClient then
	warn("[SwingSpeed] Could not find PlayerScripts.MainClient — aborting.")
	return
end

local ClientToolModule = MainClient:WaitForChild("ClientTool", 10)
if not ClientToolModule then
	warn("[SwingSpeed] Could not find the ClientTool module — aborting.")
	return
end

local SwingSaber = ReplicatedStorage:FindFirstChild("Events", true)
	and ReplicatedStorage.Events:FindFirstChild("SwingSaber")
if not SwingSaber then
	warn("[SwingSpeed] Could not find SwingSaber remote — aborting.")
	return
end

local SellStrength      = ReplicatedStorage.Events:FindFirstChild("SellStrength")
local ClientTool        = require(ClientToolModule)
local Animations        = require(ClientToolModule:WaitForChild("Animations"))
local HitDetection      = require(ClientToolModule:WaitForChild("HitDetection"))
local ClientDataManager = require(MainClient:WaitForChild("ClientDataManager"))

local connections  = {}
local holdThread   = nil
local trainThread  = nil
local sellThread   = nil
local holding      = false
local trainOn      = false
local sellOn       = false
local nextAllowed  = 0
local attackNum    = 1
local vanillaSwing = nil
local notifyList   = {}

local function notify(text)
	if not CONFIG.ShowNotifications then return end
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", {
			Title = "Swing Speed",
			Text = text,
			Duration = 3,
		})
	end)
	table.insert(notifyList, text)
	print("[SwingSpeed] " .. text)
end

local function canSwing()
	local char = LocalPlayer.Character
	if not char then return false end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0) then return false end
	return char:FindFirstChildOfClass("Tool") ~= nil
end

local function FasterSwing()
	if not CONFIG.Enabled then
		return vanillaSwing and vanillaSwing(ClientTool)
	end

	local now = tick()
	if now < nextAllowed then return end
	if not canSwing() then return end

	local vanillaCd = (ClientDataManager.Data and ClientDataManager.Data.SwingCooldown) or 0.6
	local cooldown = math.max(vanillaCd / CONFIG.SwingSpeedMultiplier, CONFIG.MinCooldown)
	nextAllowed = now + cooldown

	pcall(function()
		local dual = type(ClientDataManager.Data) == "table"
			and table.find(ClientDataManager.Data.Passes or {}, "DualSaber") ~= nil
		Animations:PlayAnim(attackNum, dual)
	end)
	attackNum = attackNum % 3 + 1

	pcall(function()
		SwingSaber:FireServer(HitDetection:GetBossesAndMobsHit(LocalPlayer))
	end)

	return true
end

if type(ClientTool.Swing) ~= "function" then
	warn("[SwingSpeed] ClientTool.Swing is not a function — aborting (already patched?).")
	return
end
vanillaSwing = ClientTool.Swing
ClientTool.Swing = FasterSwing

local function startHoldLoop()
	if not CONFIG.HoldToAutoSwing or holding then return end
	holding = true
	holdThread = task.spawn(function()
		while holding do
			task.wait(CONFIG.AutoSwingGap)
			if holding then FasterSwing() end
		end
	end)
end

local function setTrain(on, silent)
	if on == trainOn then return end
	trainOn = on
	if trainOn then
		trainThread = task.spawn(function()
			while trainOn do
				task.wait(CONFIG.TrainTickGap)
				if trainOn then FasterSwing() end
			end
		end)
	end
	if not silent then
		notify("AutoTrain " .. (trainOn and "ON" or "OFF"))
	end
end

local function setSell(on, silent)
	if not SellStrength then
		if not silent then notify("AutoSell unavailable — SellStrength remote not found") end
		return
	end
	if on == sellOn then return end
	sellOn = on
	if sellOn then
		sellThread = task.spawn(function()
			while sellOn do
				pcall(function() SellStrength:FireServer() end)
				task.wait(CONFIG.AutoSellInterval)
			end
		end)
	end
	if not silent then
		notify("AutoSell " .. (sellOn and "ON" or "OFF"))
	end
end

setTrain(CONFIG.AutoTrain, true)
setSell(CONFIG.AutoSell, true)

table.insert(connections, UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.ButtonR2 then
		startHoldLoop()
	end
end))

table.insert(connections, UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.ButtonR2 then
		local anyDown = false
		for _, i in ipairs(UserInputService:GetKeysPressed()) do
			if i.KeyCode == Enum.KeyCode.ButtonR2 then
				anyDown = true
				break
			end
		end
		for _, i in ipairs(UserInputService:GetMouseButtonsPressed()) do
			if i.UserInputType == Enum.UserInputType.MouseButton1 then
				anyDown = true
				break
			end
		end
		if not anyDown then holding = false end
	end
end))

table.insert(connections, UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == CONFIG.ToggleKey then
		CONFIG.Enabled = not CONFIG.Enabled
		notify(CONFIG.Enabled
			and ("Enabled — x%.1f swing speed"):format(CONFIG.SwingSpeedMultiplier)
			or "Disabled — vanilla speed")
	elseif input.KeyCode == CONFIG.TrainToggleKey then
		setTrain(not trainOn)
	elseif input.KeyCode == CONFIG.SellToggleKey then
		setSell(not sellOn)
	end
end))

local thisInstance = {}

function thisInstance.Cleanup()
	holding = false
	trainOn = false
	sellOn = false
	if holdThread then
		pcall(function() task.cancel(holdThread) end)
		holdThread = nil
	end
	if trainThread then
		pcall(function() task.cancel(trainThread) end)
		trainThread = nil
	end
	if sellThread then
		pcall(function() task.cancel(sellThread) end)
		sellThread = nil
	end
	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(connections)
	if vanillaSwing and ClientTool and type(ClientTool.Swing) ~= "nil" then
		pcall(function() ClientTool.Swing = vanillaSwing end)
	end
	env.SaberSimSwing = nil
	print("[SwingSpeed] Cleaned up — vanilla swing behavior restored.")
end

env.SaberSimSwing = thisInstance

notify(("Ready — x%.1f speed | AutoTrain %s | AutoSell %s | keys: %s speed / %s train / %s sell | re-exec safe."):format(
	CONFIG.SwingSpeedMultiplier,
	trainOn and "ON" or "OFF",
	sellOn and "ON" or "OFF",
	CONFIG.ToggleKey.Name, CONFIG.TrainToggleKey.Name, CONFIG.SellToggleKey.Name))

return thisInstance
