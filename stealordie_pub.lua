local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local UserInputService   = game:GetService("UserInputService")
local CoreGui            = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local genv = (getgenv and getgenv()) or _G
local gethuiFn = gethui or function() return CoreGui end
local clonerefFn = cloneref or function(o) return o end

if genv.__SOD_ESP and genv.__SOD_ESP.unload then
    pcall(genv.__SOD_ESP.unload)
end

local Config = {
    RenderDistance = 1500,
    Items = {
        Enabled = true,
        Color   = Color3.fromRGB(255, 255, 255),
        UseRarityColor = true,
        ShowName = true,
        ShowValue = true,
        Keybind = Enum.KeyCode.F1,
    },
    Monsters = {
        Enabled = true,
        Color   = Color3.fromRGB(255, 60, 60),
        ShowName = true,
        Keybind = Enum.KeyCode.F2,
    },
    Players = {
        Enabled = true,
        Color   = Color3.fromRGB(80, 170, 255),
        ShowName = true,
        ShowHealth = true,
        IncludeLocal = false,
        Keybind = Enum.KeyCode.F3,
    },
    Tracers = {
        Enabled = false,
        Keybind = Enum.KeyCode.F4,
    },
    MasterKeybind = Enum.KeyCode.F5,
    UnloadKeybind = Enum.KeyCode.F6,
}

local RarityColors = {
    Common    = Color3.fromRGB(156, 162, 170),
    Uncommon  = Color3.fromRGB(84, 184, 104),
    Rare      = Color3.fromRGB(152, 98, 216),
    Legendary = Color3.fromRGB(228, 184, 62),
    Mythic    = Color3.fromRGB(208, 62, 58),
    Secret    = Color3.fromRGB(228, 228, 236),
}

local KindNames = {
    Hollow  = "The Hollow",
    Locust  = "The Locust",
    Wendell = "Wendell",
    Rictus  = "Rictus",
}

task.spawn(function()
    local ok, gameConfig = pcall(function() return require(ReplicatedStorage:WaitForChild("GameConfig", 10)) end)
    if ok and type(gameConfig) == "table" and type(gameConfig.RarityColour) == "table" then
        for name, color in pairs(gameConfig.RarityColour) do
            if typeof(color) == "Color3" then
                RarityColors[name] = color
            end
        end
    end
end)

task.spawn(function()
    local ok, entityConfig = pcall(function() return require(ReplicatedStorage:WaitForChild("EntityConfig", 10)) end)
    if ok and type(entityConfig) == "table" and type(entityConfig.Kinds) == "table" then
        for key, profile in pairs(entityConfig.Kinds) do
            if type(profile) == "table" and type(profile.name) == "string" then
                KindNames[key] = profile.name
            end
        end
    end
end)

local function distanceTo(position)
    local camera = workspace.CurrentCamera
    if not camera then return math.huge end
    return (camera.CFrame.Position - position).Magnitude
end

local function boundingBox(object)
    if object:IsA("Model") then
        local ok, cframe, size = pcall(function() return object:GetBoundingBox() end)
        if ok and cframe and size then
            return cframe, size
        end
        return nil
    elseif object:IsA("BasePart") then
        return object.CFrame, object.Size
    end
    return nil
end

local function projectBox(cframe, size)
    local camera = workspace.CurrentCamera
    if not camera then return nil end

    local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyOnScreen = false

    for xi = -1, 1, 2 do
        for yi = -1, 1, 2 do
            for zi = -1, 1, 2 do
                local corner = cframe * Vector3.new(hx * xi, hy * yi, hz * zi)
                local screenPoint, onScreen = camera:WorldToViewportPoint(corner)
                if onScreen and screenPoint.Z > 0 then
                    anyOnScreen = true
                    minX = math.min(minX, screenPoint.X)
                    minY = math.min(minY, screenPoint.Y)
                    maxX = math.max(maxX, screenPoint.X)
                    maxY = math.max(maxY, screenPoint.Y)
                end
            end
        end
    end

    if not anyOnScreen then return nil end

    return Vector2.new(minX, minY), Vector2.new(math.max(maxX - minX, 6), math.max(maxY - minY, 6))
end

local function displayRarity(rarity)
    if type(rarity) ~= "string" or rarity == "" then return nil end
    return (rarity:sub(1, 1):upper() .. rarity:sub(2))
end

local Drawing = Drawing
local USE_DRAWING = (type(Drawing) == "table") and (pcall(function()
    local t = Drawing.new("Text")
    t:Remove()
end))

local FONT = 2
if USE_DRAWING and Drawing.Fonts then
    FONT = Drawing.Fonts.Plex or Drawing.Fonts.UI or Drawing.Fonts.System or 2
end

local function createDrawingHandle()
    local handle = {}

    local box = Drawing.new("Square")
    box.Filled = false
    box.Transparency = 1
    box.Thickness = 1

    local tracer = Drawing.new("Line")
    tracer.Transparency = 1
    tracer.Thickness = 1

    local name = Drawing.new("Text")
    name.Center = true
    name.Outline = true
    name.OutlineColor = Color3.new(0, 0, 0)
    name.Font = FONT
    name.Size = 15

    local info = Drawing.new("Text")
    info.Center = true
    info.Outline = true
    info.OutlineColor = Color3.new(0, 0, 0)
    info.Font = FONT
    info.Size = 13

    handle.parts = { box, name, info }
    handle.tracer = tracer
    handle.tracerWanted = false

    function handle:render(position, size, color, nameText, infoText, drawTracer)
        local centerX = position.X + size.X / 2

        box.Position = position
        box.Size = size
        box.Color = color
        box.Visible = true

        name.Position = Vector2.new(centerX, position.Y - 16)
        name.Color = color
        name.Text = nameText or ""
        name.Visible = nameText ~= nil and nameText ~= ""

        info.Position = Vector2.new(centerX, position.Y + size.Y + 2)
        info.Color = Color3.fromRGB(235, 235, 235)
        info.Text = infoText or ""
        info.Visible = infoText ~= nil and infoText ~= ""

        handle.tracerWanted = drawTracer == true
        if drawTracer then
            local camera = workspace.CurrentCamera
            local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
            tracer.From = Vector2.new(viewport.X / 2, viewport.Y)
            tracer.To = Vector2.new(centerX, position.Y + size.Y)
            tracer.Color = color
            tracer.Visible = true
        else
            tracer.Visible = false
        end
    end

    function handle:setVisible(visible)
        for _, part in ipairs(handle.parts) do
            part.Visible = visible
        end
        tracer.Visible = visible and handle.tracerWanted
    end

    function handle:destroy()
        for _, part in ipairs(handle.parts) do
            pcall(function() part:Remove() end)
        end
    end

    return handle
end

local function createHighlightHandle(object, color)
    local highlight = Instance.new("Highlight")
    highlight.Name = "SOD_ESP_Highlight"
    highlight.Adornee = object
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = 0.75
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = gethuiFn()

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "SOD_ESP_Label"
    billboard.Adornee = object
    billboard.Size = UDim2.fromOffset(220, 40)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = gethuiFn()

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.TextStrokeTransparency = 0
    label.TextColor3 = color
    label.Text = ""
    label.Parent = billboard

    local handle = {}

    function handle:render(_, _, renderColor, nameText, infoText, _)
        highlight.FillColor = renderColor
        highlight.OutlineColor = renderColor
        label.TextColor3 = renderColor
        local text = nameText or ""
        if infoText and infoText ~= "" then
            text = text .. (text ~= "" and "  " or "") .. infoText
        end
        label.Text = text
    end

    function handle:setVisible(visible)
        highlight.Enabled = visible
        billboard.Enabled = visible
    end

    function handle:destroy()
        pcall(function() highlight:Destroy() end)
        pcall(function() billboard:Destroy() end)
    end

    return handle
end

local function createHandle(object, color)
    if USE_DRAWING then
        return createDrawingHandle()
    end
    return createHighlightHandle(object, color)
end

local state = {
    running = true,
    master = true,
    entries = {},
    connections = {},
    gui = nil,
    buttons = {},
}

local function classify(object)
    local kind = object:GetAttribute("EntityKind")
    local owner = nil
    if object:IsA("Model") then
        local player = Players:GetPlayerFromCharacter(object)
        if player then
            if kind == nil and player:GetAttribute("IsEntity") == true then
                kind = player:GetAttribute("EntityKind") or "Hollow"
            end
            owner = player
        end
    end
    if kind ~= nil then
        return Config.Monsters, "monster", { kind = kind, owner = owner }
    end

    if object:IsA("Model") then
        local player = Players:GetPlayerFromCharacter(object)
        if player then
            if player == LocalPlayer and not Config.Players.IncludeLocal then
                return nil
            end
            return Config.Players, "player", { player = player }
        end
    end

    local myLoot = workspace:FindFirstChild("MyLoot")
    if myLoot and object:IsDescendantOf(myLoot) then
        if object.Parent == myLoot and (object:IsA("BasePart") or object:IsA("Model")) then
            return Config.Items, "item", {}
        end
    end

    return nil
end

local function makeEntry(object, category, flavor)
    local handle = createHandle(object, category.Color)
    local entry = {
        object = object,
        category = category,
        handle = handle,
        flavor = flavor,
    }
    state.entries[object] = entry
    return entry
end

local function removeEntry(entry)
    if entry.handle then
        pcall(function() entry.handle:destroy() end)
    end
    if state.entries[entry.object] == entry then
        state.entries[entry.object] = nil
    end
end

local function clearEntries()
    for _, entry in pairs(state.entries) do
        pcall(function() entry.handle:destroy() end)
    end
    state.entries = {}
end

local function updateEntry(entry)
    local object = entry.object
    if not object or object.Parent == nil then
        return false
    end

    local camera = workspace.CurrentCamera
    if not camera then return true end

    local cframe, size = boundingBox(object)
    if not cframe then return true end

    local distance = distanceTo(cframe.Position)
    if distance > Config.RenderDistance then
        entry.handle:setVisible(false)
        return true
    end

    local position, screenSize = projectBox(cframe, size)
    if not position then
        entry.handle:setVisible(false)
        return true
    end

    local category = entry.category
    local color = category.Color
    local nameText, infoText

    if entry.flavor.kind then
        local kind = entry.flavor.kind
        local display = KindNames[kind] or kind
        local owner = entry.flavor.owner
        nameText = owner and (display .. "  (" .. owner.Name .. ")") or display
        infoText = string.format("%d studs", math.floor(distance))
    elseif entry.flavor.player then
        local player = entry.flavor.player
        nameText = category.ShowName and player.Name or nil
        local parts = {}
        if category.ShowHealth then
            local humanoid = object:FindFirstChildOfClass("Humanoid")
            if humanoid then
                parts[#parts + 1] = string.format("%d/%d", math.ceil(humanoid.Health), math.ceil(humanoid.MaxHealth))
            end
        end
        parts[#parts + 1] = string.format("%d studs", math.floor(distance))
        infoText = table.concat(parts, "  ")
    else
        local rarity = object:GetAttribute("Rarity")
        local value = object:GetAttribute("Value")
        nameText = category.ShowName and (object.Name) or nil
        if category.UseRarityColor then
            color = RarityColors[rarity] or category.Color
        end
        local parts = {}
        local rarityLabel = displayRarity(rarity)
        if rarityLabel then parts[#parts + 1] = rarityLabel end
        if category.ShowValue and type(value) == "number" then
            parts[#parts + 1] = "$" .. value
        end
        parts[#parts + 1] = string.format("%d studs", math.floor(distance))
        infoText = table.concat(parts, "  ")
    end

    entry.handle:render(position, screenSize, color, nameText, infoText, Config.Tracers.Enabled)
    entry.handle:setVisible(state.master)
    return true
end

local function collectTargets()
    local wanted = {}

    if Config.Items.Enabled then
        local myLoot = workspace:FindFirstChild("MyLoot")
        if myLoot then
            for _, child in ipairs(myLoot:GetChildren()) do
                if child:IsA("BasePart") or child:IsA("Model") then
                    wanted[child] = true
                end
            end
        end
    end

    if Config.Monsters.Enabled then
        for _, child in ipairs(workspace:GetChildren()) do
            if child:IsA("Model") and child:GetAttribute("EntityKind") ~= nil then
                wanted[child] = true
            end
        end
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player:GetAttribute("IsEntity") == true then
                local character = player.Character
                if character and character.Parent == workspace then
                    wanted[character] = true
                end
            end
        end
    end

    if Config.Players.Enabled then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player:GetAttribute("IsEntity") ~= true then
                local character = player.Character
                if character and character.Parent == workspace then
                    wanted[character] = true
                end
            end
        end
    end

    return wanted
end

local function step()
    if not state.running then return end

    local wanted = collectTargets()

    for object, entry in pairs(state.entries) do
        if not wanted[object] then
            removeEntry(entry)
        end
    end

    for object in pairs(wanted) do
        local entry = state.entries[object]
        if not entry then
            local category, categoryName, flavor = classify(object)
            if category and category.Enabled then
                entry = makeEntry(object, category, flavor or {})
            end
        end
        if entry then
            updateEntry(entry)
        end
    end

    if not state.master then
        for _, entry in pairs(state.entries) do
            entry.handle:setVisible(false)
        end
    end
end

local function notify(text)
    local gui = state.gui
    if not gui then return end
    local label = gui:FindFirstChild("SOD_Notify")
    if not label then return end
    label.Text = text
    label.Visible = true
    task.delay(1.6, function()
        if label.Text == text then label.Visible = false end
    end)
end

local function buildGui()
    local gui = Instance.new("ScreenGui")
    gui.Name = "SOD_ESP"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = gethuiFn()

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.Size = UDim2.fromOffset(210, 0)
    panel.AutomaticSize = Enum.AutomaticSize.Y
    panel.Position = UDim2.fromOffset(16, 120)
    panel.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    panel.BackgroundTransparency = 0.15
    panel.BorderSizePixel = 0
    panel.Active = true
    panel.Parent = gui
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(60, 60, 70)
    stroke.Thickness = 1
    stroke.Parent = panel

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 26)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Text = "Steal Or Die  ESP"
    title.LayoutOrder = 0
    title.Parent = panel

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 4)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = panel

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 8)
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)
    padding.PaddingBottom = UDim.new(0, 8)
    padding.Parent = panel

    local function makeButton(order, text, onClick)
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1, 0, 0, 24)
        button.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
        button.BorderSizePixel = 0
        button.Font = Enum.Font.Gotham
        button.TextSize = 13
        button.TextColor3 = Color3.fromRGB(230, 230, 230)
        button.Text = text
        button.LayoutOrder = order
        button.AutoButtonColor = true
        button.Parent = panel
        Instance.new("UICorner", button).CornerRadius = UDim.new(0, 5)

        button.MouseButton1Click:Connect(function()
            onClick(button)
        end)
        return button
    end

    local function refresh()
        state.buttons.items.Text    = string.format("Items      [F1]   %s", Config.Items.Enabled and "ON" or "OFF")
        state.buttons.monsters.Text = string.format("Monsters   [F2]   %s", Config.Monsters.Enabled and "ON" or "OFF")
        state.buttons.players.Text  = string.format("Players    [F3]   %s", Config.Players.Enabled and "ON" or "OFF")
        state.buttons.tracers.Text  = string.format("Tracers    [F4]   %s", Config.Tracers.Enabled and "ON" or "OFF")
        state.buttons.master.Text   = string.format("Master     [F5]   %s", state.master and "ON" or "OFF")
    end
    state.refresh = refresh

    state.buttons.items = makeButton(1, "", function()
        Config.Items.Enabled = not Config.Items.Enabled
        notify("Items: " .. (Config.Items.Enabled and "ON" or "OFF"))
        refresh()
    end)
    state.buttons.monsters = makeButton(2, "", function()
        Config.Monsters.Enabled = not Config.Monsters.Enabled
        notify("Monsters: " .. (Config.Monsters.Enabled and "ON" or "OFF"))
        refresh()
    end)
    state.buttons.players = makeButton(3, "", function()
        Config.Players.Enabled = not Config.Players.Enabled
        notify("Players: " .. (Config.Players.Enabled and "ON" or "OFF"))
        refresh()
    end)
    state.buttons.tracers = makeButton(4, "", function()
        Config.Tracers.Enabled = not Config.Tracers.Enabled
        notify("Tracers: " .. (Config.Tracers.Enabled and "ON" or "OFF"))
        refresh()
    end)
    state.buttons.master = makeButton(5, "", function()
        state.master = not state.master
        notify("Master: " .. (state.master and "ON" or "OFF"))
        refresh()
    end)
    state.buttons.unload = makeButton(6, "Unload     [F6]", function()
        if genv.__SOD_ESP then genv.__SOD_ESP.unload() end
    end)

    local notification = Instance.new("TextLabel")
    notification.Name = "SOD_Notify"
    notification.Size = UDim2.new(1, 0, 0, 20)
    notification.BackgroundTransparency = 1
    notification.Font = Enum.Font.GothamBold
    notification.TextSize = 15
    notification.TextColor3 = Color3.fromRGB(255, 255, 255)
    notification.TextStrokeTransparency = 0
    notification.Visible = false
    notification.Text = ""
    notification.Parent = gui

    local function syncNotification()
        notification.Position = UDim2.new(
            panel.Position.X.Scale,
            panel.Position.X.Offset,
            panel.Position.Y.Scale,
            panel.Position.Y.Offset + panel.AbsoluteSize.Y + 6
        )
    end

    local dragging = false
    local dragStart, startPosition

    panel.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = panel.Position
            local connection
            connection = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if connection then connection:Disconnect() end
                end
            end)
        end
    end)

    panel.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            panel.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
            syncNotification()
        end
    end)

    panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncNotification)

    state.gui = gui
    refresh()
    syncNotification()
end

local api

local function unload()
    state.running = false

    for _, connection in ipairs(state.connections) do
        pcall(function() connection:Disconnect() end)
    end
    state.connections = {}

    clearEntries()

    if state.gui then
        pcall(function() state.gui:Destroy() end)
        state.gui = nil
    end

    if genv.__SOD_ESP == api then
        genv.__SOD_ESP = nil
    end
end

local function toggleWithKey(input, key, onChange)
    if input.KeyCode == key then
        onChange()
    end
end

api = {
    Config = Config,
    state = state,
    unload = unload,
}

genv.__SOD_ESP = api

buildGui()

table.insert(state.connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    toggleWithKey(input, Config.Items.Keybind, function()
        Config.Items.Enabled = not Config.Items.Enabled
        notify("Items: " .. (Config.Items.Enabled and "ON" or "OFF"))
    end)
    toggleWithKey(input, Config.Monsters.Keybind, function()
        Config.Monsters.Enabled = not Config.Monsters.Enabled
        notify("Monsters: " .. (Config.Monsters.Enabled and "ON" or "OFF"))
    end)
    toggleWithKey(input, Config.Players.Keybind, function()
        Config.Players.Enabled = not Config.Players.Enabled
        notify("Players: " .. (Config.Players.Enabled and "ON" or "OFF"))
    end)
    toggleWithKey(input, Config.Tracers.Keybind, function()
        Config.Tracers.Enabled = not Config.Tracers.Enabled
        notify("Tracers: " .. (Config.Tracers.Enabled and "ON" or "OFF"))
    end)
    toggleWithKey(input, Config.MasterKeybind, function()
        state.master = not state.master
        notify("Master: " .. (state.master and "ON" or "OFF"))
    end)
    toggleWithKey(input, Config.UnloadKeybind, function()
        unload()
    end)
    if state.refresh then state.refresh() end
end))

table.insert(state.connections, RunService.RenderStepped:Connect(step))

if state.refresh then state.refresh() end

return api
