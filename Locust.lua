local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	return
end

local CONFIG = {
	FolderNames = {
		Monsters = true,

		Angels = {
			RequireHumanoid = false,
			BoxColor = Color3.fromRGB(120, 210, 255),
		},

		Snipers = true,
		SovietRiflemen = true,

		RedPeppers = {
			RequireHumanoid = false,
			BoxColor = Color3.fromRGB(255, 140, 40),
			MaxDistance = 0,
			MinBoxSize = 8,
			TagTextSize = 11,
			TagPadX = 4,
			TagPadY = 1,
		},

		Landmines = {
			RequireHumanoid = false,
			BoxColor = Color3.fromRGB(150, 150, 150),
			MaxDistance = 0,
			MinBoxSize = 9,
			TagTextSize = 11,
			TagPadX = 4,
			TagPadY = 1,
			StateColors = {
				Armed = Color3.fromRGB(255, 60, 60),
			},
		},

		Tripwires = {
			RequireHumanoid = false,
			BoxColor = Color3.fromRGB(150, 150, 150),
			MaxDistance = 0,
			MinBoxSize = 2,
			TagTextSize = 11,
			TagPadX = 4,
			TagPadY = 1,
			StateColors = {
				Armed = Color3.fromRGB(255, 130, 0),
			},
		},

		Deadlights = {
			RequireHumanoid = false,
			BoxColor = Color3.fromRGB(180, 120, 255),
			MinBoxSize = 10,
		},

		LittleGirl = {
			BoxColor = Color3.fromRGB(255, 105, 180),
		},

		QuestGivers = {
			BoxColor = Color3.fromRGB(255, 105, 180),
		},
	},

	BoxColor        = Color3.fromRGB(255, 64, 64),
	BoxThickness    = 2,
	BoxTransparency = 0.15,

	TagBackground   = Color3.fromRGB(18, 18, 18),
	TagTextColor    = Color3.fromRGB(255, 255, 255),
	TagTextSize     = 14,
	TagPadX         = 6,
	TagPadY         = 2,
	TagOffset       = 6,

	CornerRadius    = 4,
	MaxDistance     = 600,
	RescanInterval  = 0.2,

	ShowDistance    = true,
	TagFormat       = "%s [%dm]",

	AngelAlert = {
		Enabled            = true,
		Folder             = "Angels",
		Radius             = 75,
		Text               = "ANGEL",
		Color              = Color3.fromRGB(120, 210, 255),
		ShowBanner         = true,
		ShowOffscreenArrow = true,
		LockCamera         = true,
		EdgeMargin         = 28,
	},
}

if _G.EntityBoxOverlay and _G.EntityBoxOverlay.Destroy then
	pcall(function()
		_G.EntityBoxOverlay:Destroy()
	end)
end

local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "EntityBoxOverlay"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 100
gui.Parent = playerGui

local screenGui = gui

local function makeBox(color)
	local frame = Instance.new("Frame")
	frame.Name = "Box"
	frame.AnchorPoint = Vector2.new(0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Visible = false

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = color or CONFIG.BoxColor
	stroke.Thickness = CONFIG.BoxThickness
	stroke.Transparency = CONFIG.BoxTransparency
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Parent = frame

	return frame
end

local function makeTag(opts)
	local o = opts or {}
	local textSize = o.TagTextSize or CONFIG.TagTextSize
	local padX = o.TagPadX or CONFIG.TagPadX
	local padY = o.TagPadY or CONFIG.TagPadY

	local label = Instance.new("TextLabel")
	label.Name = "Tag"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.BackgroundColor3 = CONFIG.TagBackground
	label.BackgroundTransparency = 0.15
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = CONFIG.TagTextColor
	label.TextSize = textSize
	label.TextStrokeTransparency = 0.5
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Visible = false
	label.ZIndex = 2

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, padX)
	pad.PaddingRight = UDim.new(0, padX)
	pad.PaddingTop = UDim.new(0, padY)
	pad.PaddingBottom = UDim.new(0, padY)
	pad.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, CONFIG.CornerRadius)
	corner.Parent = label

	return label
end

local targetFolders = {}
local tracked = {}

local DEFAULT_FOLDER_OPTS = { RequireHumanoid = true }

local function registerFolder(folder, opts)
	targetFolders[folder] = opts or true
end

local function resolveFolderOptions(opts)
	if type(opts) ~= "table" then
		return DEFAULT_FOLDER_OPTS
	end
	return opts
end

local function unregisterFolder(folder)
	targetFolders[folder] = nil
end

local function createOverlay(model, opts)
	local o = resolveFolderOptions(opts)

	local box = makeBox(o.BoxColor)
	box.Parent = screenGui

	local tag = makeTag(o)
	tag.Text = model.Name
	tag.Parent = screenGui

	tracked[model] = {
		box = box,
		stroke = box:FindFirstChild("Stroke"),
		tag = tag,
		lastDist = -1,
		maxDistance = o.MaxDistance,
		minSize = (o.MinBoxSize and o.MinBoxSize > 0) and o.MinBoxSize or nil,
		baseColor = o.BoxColor or CONFIG.BoxColor,
		stateColors = o.StateColors,
		stateAttribute = o.StateAttribute or "State",
		lastStateColor = nil,
	}
end

local function destroyOverlay(model)
	local entry = tracked[model]
	if not entry then
		return
	end
	if entry.box then
		entry.box:Destroy()
	end
	if entry.tag then
		entry.tag:Destroy()
	end
	tracked[model] = nil
end

local function reconcile()
	local desired = {}

	for folder, opts in pairs(targetFolders) do
		if folder.Parent then
			local requireHumanoid = resolveFolderOptions(opts).RequireHumanoid ~= false

			for _, d in ipairs(folder:GetDescendants()) do
				if d:IsA("Model") then
					if not requireHumanoid or d:FindFirstChildOfClass("Humanoid") then
						desired[d] = opts
					end
				end
			end
		else
			targetFolders[folder] = nil
		end
	end

	for model, opts in pairs(desired) do
		if not tracked[model] then
			createOverlay(model, opts)
		end
	end

	for model in pairs(tracked) do
		if not desired[model] or not model.Parent then
			destroyOverlay(model)
		end
	end
end

local angelFolders = {}

local function noteFolder(d)
	if not d:IsA("Folder") then
		return
	end
	if CONFIG.FolderNames[d.Name] then
		registerFolder(d, CONFIG.FolderNames[d.Name])
	end
	if d.Name == CONFIG.AngelAlert.Folder then
		angelFolders[d] = true
	end
end

for _, d in ipairs(Workspace:GetDescendants()) do
	noteFolder(d)
end

Workspace.DescendantAdded:Connect(noteFolder)

Workspace.DescendantRemoving:Connect(function(d)
	if targetFolders[d] then
		unregisterFolder(d)
	end
	if angelFolders[d] then
		angelFolders[d] = nil
	end
end)

local CORNERS = {}
for xi = -1, 1, 2 do
	for yi = -1, 1, 2 do
		for zi = -1, 1, 2 do
			table.insert(CORNERS, Vector3.new(xi, yi, zi))
		end
	end
end

local function projectModel(camera, model, viewport, minSize)
	local ok, cf, size = pcall(function()
		local c, s = model:GetBoundingBox()
		return c, s
	end)
	if not ok or not cf then
		return nil
	end

	local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	local any = false

	for _, sign in ipairs(CORNERS) do
		local world = (cf * CFrame.new(sign.X * hx, sign.Y * hy, sign.Z * hz)).Position
		local sp = camera:WorldToViewportPoint(world)
		if sp.Z > 0 then
			any = true
			if sp.X < minX then minX = sp.X end
			if sp.X > maxX then maxX = sp.X end
			if sp.Y < minY then minY = sp.Y end
			if sp.Y > maxY then maxY = sp.Y end
		end
	end

	if not any then
		return nil
	end

	minX = math.clamp(minX, 0, viewport.X)
	maxX = math.clamp(maxX, 0, viewport.X)
	minY = math.clamp(minY, 0, viewport.Y)
	maxY = math.clamp(maxY, 0, viewport.Y)

	local w, h = maxX - minX, maxY - minY

	if minSize then
		if w <= 0 and h <= 0 then
			return nil
		end
		if w < minSize then
			local cx = (minX + maxX) * 0.5
			minX = math.clamp(cx - minSize * 0.5, 0, viewport.X)
			maxX = math.clamp(cx + minSize * 0.5, 0, viewport.X)
		end
		if h < minSize then
			local cy = (minY + maxY) * 0.5
			minY = math.clamp(cy - minSize * 0.5, 0, viewport.Y)
			maxY = math.clamp(cy + minSize * 0.5, 0, viewport.Y)
		end
	elseif w < 1 or h < 1 then
		return nil
	end

	return minX, minY, maxX, maxY
end

local alertArrow = Instance.new("TextLabel")
alertArrow.Name = "AngelArrow"
alertArrow.AnchorPoint = Vector2.new(0.5, 0.5)
alertArrow.Size = UDim2.fromOffset(64, 64)
alertArrow.BackgroundTransparency = 1
alertArrow.BorderSizePixel = 0
alertArrow.Font = Enum.Font.GothamBold
alertArrow.Text = "▲"
alertArrow.TextColor3 = CONFIG.AngelAlert.Color
alertArrow.TextSize = 44
alertArrow.TextStrokeColor3 = Color3.new(0, 0, 0)
alertArrow.TextStrokeTransparency = 0.4
alertArrow.Rotation = 0
alertArrow.Visible = false
alertArrow.ZIndex = 5
alertArrow.Parent = screenGui

local alertBanner = Instance.new("TextLabel")
alertBanner.Name = "AngelNotice"
alertBanner.AnchorPoint = Vector2.new(0.5, 0)
alertBanner.Position = UDim2.new(0.5, 0, 0, 84)
alertBanner.AutomaticSize = Enum.AutomaticSize.XY
alertBanner.BackgroundColor3 = CONFIG.TagBackground
alertBanner.BackgroundTransparency = 0.1
alertBanner.BorderSizePixel = 0
alertBanner.Font = Enum.Font.GothamBold
alertBanner.Text = ""
alertBanner.TextColor3 = CONFIG.AngelAlert.Color
alertBanner.TextSize = 20
alertBanner.TextStrokeTransparency = 0.6
alertBanner.Visible = false
alertBanner.ZIndex = 6
alertBanner.Parent = screenGui
do
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = alertBanner

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, CONFIG.CornerRadius)
	corner.Parent = alertBanner
end

local alert = { target = nil, aim = nil, dist = nil }
local ANGEL_LOOK_BIND = "EntityBoxAngelLookAt"

local function aimPosition(model)
	local root = model:FindFirstChild("Root") or model.PrimaryPart
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	local ok, pivot = pcall(function()
		return model:GetPivot().Position
	end)
	return ok and pivot or nil
end

local function findNearestAngel(refPos, radius)
	local best, bestPos, bestDist, count = nil, nil, nil, 0
	for folder in pairs(angelFolders) do
		if folder.Parent then
			for _, m in ipairs(folder:GetChildren()) do
				if m:IsA("Model") then
					local ok, pivot = pcall(function()
						return m:GetPivot().Position
					end)
					if ok then
						local d = (pivot - refPos).Magnitude
						if d <= radius then
							count += 1
							if not bestDist or d < bestDist then
								best, bestPos, bestDist = m, pivot, d
							end
						end
					end
				end
			end
		else
			angelFolders[folder] = nil
		end
	end
	return best, bestPos, bestDist, count
end

local function clearAlert()
	alert.target, alert.aim, alert.dist = nil, nil, nil
	alertArrow.Visible = false
	alertBanner.Visible = false
end

local function updateAngelAlert(camera, viewport, refPos)
	local cfg = CONFIG.AngelAlert
	if not cfg.Enabled then
		clearAlert()
		return
	end

	local model, pivot, dist, count = findNearestAngel(refPos, cfg.Radius)
	if not model then
		clearAlert()
		return
	end

	local aim = aimPosition(model) or pivot
	alert.target, alert.aim, alert.dist = model, aim, dist

	local pulse = 0.5 + 0.5 * math.sin(os.clock() * 8)

	if cfg.ShowBanner then
		local text = string.format("%s  %dm", cfg.Text, math.floor(dist + 0.5))
		if count > 1 then
			text = string.format("%s x%d  %dm", cfg.Text, count, math.floor(dist + 0.5))
		end
		alertBanner.Text = text
		alertBanner.TextColor3 = cfg.Color
		alertBanner.TextTransparency = 0.1 + 0.35 * pulse
		alertBanner.Visible = true
	else
		alertBanner.Visible = false
	end

	if not cfg.ShowOffscreenArrow then
		alertArrow.Visible = false
		return
	end

	local vp = camera:WorldToViewportPoint(aim)
	local margin = cfg.EdgeMargin
	local onScreen = vp.Z > 0
		and vp.X >= margin and vp.X <= viewport.X - margin
		and vp.Y >= margin and vp.Y <= viewport.Y - margin

	if onScreen then
		alertArrow.Visible = false
		return
	end

	local rel = camera.CFrame:PointToObjectSpace(aim)
	local dir = Vector2.new(rel.X, -rel.Y)
	if dir.Magnitude < 1e-3 then
		dir = Vector2.new(0, -1)
	end
	dir = dir.Unit

	local center = Vector2.new(viewport.X, viewport.Y) * 0.5
	local half = Vector2.new(viewport.X * 0.5 - margin, viewport.Y * 0.5 - margin)
	local scale = math.min(
		half.X / math.max(math.abs(dir.X), 1e-4),
		half.Y / math.max(math.abs(dir.Y), 1e-4)
	)
	local pos = center + dir * scale

	alertArrow.Position = UDim2.fromOffset(pos.X, pos.Y)
	alertArrow.Rotation = math.deg(math.atan2(dir.Y, dir.X)) + 90
	alertArrow.TextColor3 = cfg.Color
	alertArrow.TextTransparency = 0.05 + 0.35 * pulse
	alertArrow.TextStrokeTransparency = 0.4 + 0.3 * pulse
	alertArrow.Visible = true
end

local Overlay = {
	Enabled = true,
	Config = CONFIG,
	_connections = {},
}

function Overlay:Destroy()
	for _, conn in ipairs(self._connections) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	self._connections = {}
	for model in pairs(tracked) do
		destroyOverlay(model)
	end
	pcall(function()
		RunService:UnbindFromRenderStep(ANGEL_LOOK_BIND)
	end)
	clearAlert()
	if screenGui then
		screenGui:Destroy()
	end
	if _G.EntityBoxOverlay == self then
		_G.EntityBoxOverlay = nil
	end
end

local lastScan = 0

local renderConn = RunService.RenderStepped:Connect(function()
	if not Overlay.Enabled then
		clearAlert()
		return
	end

	local now = os.clock()
	if now - lastScan >= CONFIG.RescanInterval then
		lastScan = now
		reconcile()
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		clearAlert()
		return
	end
	local viewport = camera.ViewportSize
	local camPos = camera.CFrame.Position

	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local refPos = root and root.Position or camPos

	for model, entry in pairs(tracked) do
		local box, tag = entry.box, entry.tag
		local hide = false

		if entry.stateColors and entry.stroke then
			local state = model:GetAttribute(entry.stateAttribute)
			local color = (state and entry.stateColors[state]) or entry.baseColor
			if entry.lastStateColor ~= color then
				entry.lastStateColor = color
				entry.stroke.Color = color
			end
		end

		local rect
		local ok, pivot = pcall(function()
			return model:GetPivot().Position
		end)
		if not ok then
			hide = true
		else
			local dist = (pivot - refPos).Magnitude

			if CONFIG.ShowDistance then
				local shown = math.floor(dist + 0.5)
				if entry.lastDist ~= shown then
					entry.lastDist = shown
					tag.Text = string.format(CONFIG.TagFormat, model.Name, shown)
				end
			end

			local maxDistance = entry.maxDistance
			if maxDistance == nil then
				maxDistance = CONFIG.MaxDistance
			end
			if maxDistance > 0 and dist > maxDistance then
				hide = true
			end
		end

		if not hide then
			rect = { projectModel(camera, model, viewport, entry.minSize) }
			if rect[1] == nil then
				hide = true
			end
		end

		if hide then
			box.Visible = false
			tag.Visible = false
		else
			local minX, minY, maxX, maxY = rect[1], rect[2], rect[3], rect[4]
			local w, h = maxX - minX, maxY - minY

			box.Position = UDim2.fromOffset(minX, minY)
			box.Size = UDim2.fromOffset(w, h)
			box.Visible = true

			tag.Position = UDim2.fromOffset(minX + w * 0.5, minY - CONFIG.TagOffset)
			tag.Visible = true
		end
	end

	updateAngelAlert(camera, viewport, refPos)
end)

table.insert(Overlay._connections, renderConn)

pcall(function()
	RunService:UnbindFromRenderStep(ANGEL_LOOK_BIND)
end)
RunService:BindToRenderStep(ANGEL_LOOK_BIND, Enum.RenderPriority.Camera.Value + 1, function()
	local cfg = CONFIG.AngelAlert
	if not Overlay.Enabled or not cfg.Enabled or not cfg.LockCamera then
		return
	end
	local target, aim = alert.target, alert.aim
	if not target or not aim or not target.Parent then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	if (aim - origin).Magnitude < 0.05 then
		return
	end
	camera.CFrame = CFrame.lookAt(origin, aim)
end)

_G.EntityBoxOverlay = Overlay

reconcile()

print("[EntityBoxOverlay] active — watching folders: " .. table.concat((function()
	local names = {}
	for name in pairs(CONFIG.FolderNames) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end)(), ", "))
