-- // VisionWare ESP
-- // Self-contained ESP with full feature set

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local Config = {
	Enabled = true,
	Boxes = true,
	BoxType = "2D Box",      -- "2D Box", "3D Box", "Corner Box", "Filled Box"
	Outline = true,
	Names = true,
	HealthBar = true,
	Distance = false,
	Tracers = true,
	TracerType = "From Bottom", -- "From Bottom", "From Mouse"
	Skeleton = false,
	HeadDot = false,
	TeamColor = false,
	Color = Color3.fromRGB(255, 88, 166),
	TeamColorValue = Color3.fromRGB(86, 227, 120),
}

local EspObjects = {}

-- ===== Drawing helpers =====
local function newDrawing(kind)
	local ok, d = pcall(Drawing.new, kind)
	if ok and d then return d end
	return nil
end

local function setColor(d, color, transparency)
	if not d then return end
	d.Color = color
	d.Transparency = transparency or 1
end

local function worldToScreen(position)
	local cam = Workspace.CurrentCamera
	if not cam or not cam.CFrame then return nil, 0 end
	local screenPoint, onScreen = cam:WorldToScreenPoint(position)
	if not onScreen then return nil, screenPoint.Z end
	return Vector2.new(screenPoint.X, screenPoint.Y), screenPoint.Z
end

local function getCharPart(character, name)
	return character:FindFirstChild(name)
end

-- ===== Player setup =====
local function createEspForPlayer(player)
	local esp = {
		Player = player,
		box = {
			o1 = newDrawing("Square"), o2 = newDrawing("Square"),
			o3 = newDrawing("Square"), o4 = newDrawing("Square"),
			f1 = newDrawing("Square"), f2 = newDrawing("Square"),
			f3 = newDrawing("Square"), f4 = newDrawing("Square"),
			fill = newDrawing("Square"),
		},
		name = newDrawing("Text"),
		distance = newDrawing("Text"),
		healthbg = newDrawing("Square"),
		healthfg = newDrawing("Square"),
		tracer = newDrawing("Line"),
		head = newDrawing("Square"),
		skeleton = {},
		Connections = {},
	}
	for i = 1, 11 do
		esp.skeleton[i] = newDrawing("Line")
	end
	EspObjects[player] = esp
	return esp
end

-- ===== Skeleton bones =====
local BONES = {
	{ "Head", "Neck" },
	{ "Neck", "Torso" },
	{ "Torso", "HumanoidRootPart" },
	{ "Torso", "LeftShoulder" },
	{ "LeftShoulder", "LeftUpperArm" },
	{ "LeftUpperArm", "LeftLowerArm" },
	{ "LeftLowerArm", "LeftHand" },
	{ "Torso", "RightShoulder" },
	{ "RightShoulder", "RightUpperArm" },
	{ "RightUpperArm", "RightLowerArm" },
	{ "RightLowerArm", "RightHand" },
	{ "Torso", "LeftHip" },
	{ "LeftHip", "LeftUpperLeg" },
	{ "LeftUpperLeg", "LeftLowerLeg" },
	{ "LeftLowerLeg", "LeftFoot" },
	{ "Torso", "RightHip" },
	{ "RightHip", "RightUpperLeg" },
	{ "RightUpperLeg", "RightLowerLeg" },
	{ "RightLowerLeg", "RightFoot" },
}

-- ===== Render =====
local function isEnemy(player)
	if player == LocalPlayer then return false end
	if Config.TeamColor then
		if player.Team == LocalPlayer.Team then return false end
	end
	return true
end

local function getPlayerColor(player)
	if Config.TeamColor and player.Team == LocalPlayer.Team then
		return Config.TeamColorValue
	end
	return Config.Color
end

local function renderEsp(esp)
	local player = esp.Player
	local character = player.Character
	if not character or not character:FindFirstChild("Humanoid") then
		for _, d in pairs(esp.box) do if d then d.Visible = false end end
		if esp.name then esp.name.Visible = false end
		if esp.distance then esp.distance.Visible = false end
		if esp.healthbg then esp.healthbg.Visible = false end
		if esp.healthfg then esp.healthfg.Visible = false end
		if esp.tracer then esp.tracer.Visible = false end
		if esp.head then esp.head.Visible = false end
		for _, l in ipairs(esp.skeleton) do if l then l.Visible = false end end
		return
	end

	local humanoid = character:FindFirstChild("Humanoid")
	local head = getCharPart(character, "Head")
	local hrp = getCharPart(character, "HumanoidRootPart")
	local color = getPlayerColor(player)

	-- Determine bounding corners
	local topPos, bottomPos
	if hrp then
		bottomPos = hrp.Position
	end
	if head then
		topPos = head.Position
	end
	if not topPos or not bottomPos then
		for _, d in pairs(esp.box) do if d then d.Visible = false end end
		return
	end

	local headPos, headZ = worldToScreen(topPos)
	local footPos, footZ = worldToScreen(bottomPos)
	if not headPos or not footPos or headZ < 0 then
		for _, d in pairs(esp.box) do if d then d.Visible = false end end
		if esp.name then esp.name.Visible = false end
		if esp.distance then esp.distance.Visible = false end
		if esp.healthbg then esp.healthbg.Visible = false end
		if esp.healthfg then esp.healthfg.Visible = false end
		if esp.tracer then esp.tracer.Visible = false end
		if esp.head then esp.head.Visible = false end
		for _, l in ipairs(esp.skeleton) do if l then l.Visible = false end end
		return
	end

	local height = math.max(footPos.Y - headPos.Y, 5)
	local width = height * 0.6

	-- Tracer origin
	local tracerOrigin
	if Config.TracerType == "From Bottom" then
		tracerOrigin = Vector2.new(UserInputService:GetMouseLocation().X, 1080)
	else
		tracerOrigin = UserInputService:GetMouseLocation()
	end

	local distanceText = math.round((Workspace.CurrentCamera.CFrame.Position - bottomPos).Magnitude) .. " studs"

	-- ===== Box =====
	if Config.Boxes then
		local x = headPos.X - width / 2
		local y = headPos.Y
		local bx = (footPos.X + headPos.X) / 2 - width / 2
		local by = footPos.Y - height

		if Config.BoxType == "2D Box" or Config.BoxType == "Filled Box" then
			-- two rectangles: border + inner
			esp.box.fill.Visible = Config.BoxType == "Filled Box"
			esp.box.fill.Position = Vector2.new(x, y)
			esp.box.fill.Size = Vector2.new(width, height)
			esp.box.fill.Color = color
			esp.box.fill.Transparency = Config.BoxType == "Filled Box" and 0.85 or 1
			esp.box.fill.Filled = true

			esp.box.o1.Visible = true
			esp.box.o1.Position = Vector2.new(x, y)
			esp.box.o1.Size = Vector2.new(width, height)
			esp.box.o1.Thickness = 1
			esp.box.o1.Filled = false
			esp.box.o1.Color = Color3.new(0, 0, 0)
			esp.box.o1.Transparency = 1

			esp.box.f1.Visible = Config.Outline
			esp.box.f1.Position = Vector2.new(x, y)
			esp.box.f1.Size = Vector2.new(width, height)
			esp.box.f1.Thickness = 1
			esp.box.f1.Filled = false
			esp.box.f1.Color = color
			esp.box.f1.Transparency = 1

			for i = 2, 4 do
				if esp.box["o" .. i] then esp.box["o" .. i].Visible = false end
				if esp.box["f" .. i] then esp.box["f" .. i].Visible = false end
			end

		elseif Config.BoxType == "3D Box" then
			-- simple: draw all four corners using projected corners of the character
			esp.box.fill.Visible = false
			local parts = { head, hrp or head }
			local corners = {}
			local size = (hrp and hrp.Size.Magnitude or 2)
			local positions = {
				bottomPos + Vector3.new(-1, 0, -1) * size,
				bottomPos + Vector3.new(1, 0, -1) * size,
				bottomPos + Vector3.new(1, 0, 1) * size,
				bottomPos + Vector3.new(-1, 0, 1) * size,
				topPos + Vector3.new(-1, 0, -1) * size,
				topPos + Vector3.new(1, 0, -1) * size,
				topPos + Vector3.new(1, 0, 1) * size,
				topPos + Vector3.new(-1, 0, 1) * size,
			}
			for i = 1, 8 do
				local p, z = worldToScreen(positions[i])
				if p then corners[i] = p end
			end
			-- Hide unused rectangles
			for i = 2, 4 do
				if esp.box["o" .. i] then esp.box["o" .. i].Visible = false end
				if esp.box["f" .. i] then esp.box["f" .. i].Visible = false end
			end
			-- Use a single filled box as a fallback representation for 3D via lines not available in Square
			-- Fall back to drawing corner markers with small filled squares
			for i = 1, 4 do
				local c = corners[i]
				if c and esp.box["o" .. i] then
					esp.box["o" .. i].Visible = true
					esp.box["o" .. i].Position = c - Vector2.new(1, 1)
					esp.box["o" .. i].Size = Vector2.new(2, 2)
					esp.box["o" .. i].Filled = true
					esp.box["o" .. i].Color = color
					esp.box["o" .. i].Transparency = 1
				end
			end
		elseif Config.BoxType == "Corner Box" then
			esp.box.fill.Visible = false
			local x2 = x + width
			local y2 = y + height
			local seg = math.min(width, height) * 0.25
			local corners = {
				{ x, y, x + seg, y },
				{ x2 - seg, y, x2, y },
				{ x, y2, x + seg, y2 },
				{ x2 - seg, y2, x2, y2 },
				{ x, y, x, y + seg },
				{ x2, y, x2, y + seg },
				{ x, y2 - seg, x, y2 },
				{ x2, y2 - seg, x2, y2 },
			}
			for i = 1, 8 do
				local c = corners[i]
				local d = esp.box["o" .. (math.floor((i - 1) / 2) + 1)]
				local fd = esp.box["f" .. (math.floor((i - 1) / 2) + 1)]
				if d and fd then
					d.Visible = true
					fd.Visible = Config.Outline
					-- approximate as filled rectangles
					d.Filled = true
					d.Color = Color3.new(0, 0, 0)
					d.Transparency = 1
					d.Size = Vector2.new(1, 1)
					d.Position = Vector2.new(c[1], c[2])
					fd.Filled = true
					fd.Color = color
					fd.Transparency = 1
					fd.Size = Vector2.new(1, 1)
					fd.Position = Vector2.new(c[1], c[2])
				end
			end
		end
	else
		for _, d in pairs(esp.box) do if d then d.Visible = false end end
	end

	-- ===== Health bar =====
	if Config.HealthBar then
		local health = humanoid.Health
		local maxHealth = humanoid.MaxHealth
		local ratio = math.clamp(health / maxHealth, 0, 1)
		local x = headPos.X - width / 2
		local y = headPos.Y

		esp.healthbg.Visible = true
		esp.healthbg.Position = Vector2.new(x - 5, y)
		esp.healthbg.Size = Vector2.new(3, height)
		esp.healthbg.Color = Color3.new(0, 0, 0)
		esp.healthbg.Filled = true
		esp.healthbg.Transparency = 1

		esp.healthfg.Visible = true
		esp.healthfg.Position = Vector2.new(x - 5, y + (height * (1 - ratio)))
		esp.healthfg.Size = Vector2.new(3, height * ratio)
		esp.healthfg.Color = Color3.fromHSV(math.clamp(ratio * 0.35, 0, 0.35), 1, 1)
		esp.healthfg.Filled = true
		esp.healthfg.Transparency = 1
	else
		if esp.healthbg then esp.healthbg.Visible = false end
		if esp.healthfg then esp.healthfg.Visible = false end
	end

	-- ===== Names =====
	if Config.Names then
		esp.name.Visible = true
		esp.name.Text = player.Name
		esp.name.Color = color
		esp.name.Position = Vector2.new(headPos.X, headPos.Y - 18)
		esp.name.Size = 14
		esp.name.Center = true
		esp.name.Outline = true
		esp.name.Font = 2
	else
		if esp.name then esp.name.Visible = false end
	end

	-- ===== Distance =====
	if Config.Distance then
		esp.distance.Visible = true
		esp.distance.Text = distanceText
		esp.distance.Color = Color3.fromRGB(255, 255, 255)
		esp.distance.Position = Vector2.new(headPos.X, headPos.Y - 4)
		esp.distance.Size = 13
		esp.distance.Center = true
		esp.distance.Outline = true
		esp.distance.Font = 2
	else
		if esp.distance then esp.distance.Visible = false end
	end

	-- ===== Tracers =====
	if Config.Tracers then
		esp.tracer.Visible = true
		esp.tracer.From = Vector2.new(footPos.X, footPos.Y)
		esp.tracer.To = tracerOrigin
		esp.tracer.Color = color
		esp.tracer.Thickness = 1
		esp.tracer.Transparency = 1
	else
		if esp.tracer then esp.tracer.Visible = false end
	end

	-- ===== Head dot =====
	if Config.HeadDot then
		esp.head.Visible = true
		esp.head.Position = headPos - Vector2.new(2, 2)
		esp.head.Size = Vector2.new(4, 4)
		esp.head.Color = color
		esp.head.Filled = true
		esp.head.Transparency = 1
	else
		if esp.head then esp.head.Visible = false end
	end

	-- ===== Skeleton =====
	if Config.Skeleton then
		for i, pair in ipairs(BONES) do
			local line = esp.skeleton[i]
			local a = getCharPart(character, pair[1])
			local b = getCharPart(character, pair[2])
			if line then
				local ap, _ = a and worldToScreen(a.Position) or nil
				local bp, _ = b and worldToScreen(b.Position) or nil
				if ap and bp then
					line.Visible = true
					line.From = ap
					line.To = bp
					line.Color = color
					line.Thickness = 1
					line.Transparency = 1
				else
					line.Visible = false
				end
			end
		end
	else
		for _, l in ipairs(esp.skeleton) do if l then l.Visible = false end end
	end
end

-- ===== Init =====
local function setupPlayer(player)
	createEspForPlayer(player)
end

for _, player in ipairs(Players:GetPlayers()) do setupPlayer(player) end
Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
	local esp = EspObjects[player]
	if esp then
		for _, d in pairs(esp.box) do if d then pcall(function() d:Remove() end) end end
		if esp.name then pcall(function() esp.name:Remove() end) end
		if esp.distance then pcall(function() esp.distance:Remove() end) end
		if esp.healthbg then pcall(function() esp.healthbg:Remove() end) end
		if esp.healthfg then pcall(function() esp.healthfg:Remove() end) end
		if esp.tracer then pcall(function() esp.tracer:Remove() end) end
		if esp.head then pcall(function() esp.head:Remove() end) end
		for _, l in ipairs(esp.skeleton) do if l then pcall(function() l:Remove() end) end end
		EspObjects[player] = nil
	end
end)

RunService.RenderStepped:Connect(function()
	for player, esp in pairs(EspObjects) do
		if not Config.Enabled or not isEnemy(player) then
			for _, d in pairs(esp.box) do if d then d.Visible = false end end
			if esp.name then esp.name.Visible = false end
			if esp.distance then esp.distance.Visible = false end
			if esp.healthbg then esp.healthbg.Visible = false end
			if esp.healthfg then esp.healthfg.Visible = false end
			if esp.tracer then esp.tracer.Visible = false end
			if esp.head then esp.head.Visible = false end
			for _, l in ipairs(esp.skeleton) do if l then l.Visible = false end end
		else
			renderEsp(esp)
		end
	end
end)

-- ===== GUI =====
local GUI = Instance.new("ScreenGui")
GUI.Name = "VisionWareESP"
GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
GUI.Parent = game:GetService("CoreGui")

local Window = Instance.new("Frame")
Window.Size = UDim2.new(0, 230, 0, 360)
Window.Position = UDim2.new(1, -240, 0.5, -180)
Window.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
Window.BorderColor3 = Color3.fromRGB(0, 0, 0)
Window.Parent = GUI

local Inline = Instance.new("Frame")
Inline.Size = UDim2.new(1, -2, 1, -2)
Inline.Position = UDim2.new(0, 1, 0, 1)
Inline.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
Inline.BorderSizePixel = 0
Inline.Parent = Window

local Title = Instance.new("TextLabel")
Title.Text = "VisionWare ESP"
Title.Size = UDim2.new(1, 0, 0, 24)
Title.BackgroundTransparency = 1
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 14
Title.Parent = Inline

local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, -8, 1, -28)
Scroll.Position = UDim2.new(0, 4, 0, 26)
Scroll.BackgroundTransparency = 1
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 6
Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Scroll.Parent = Inline

local ListLayout = Instance.new("UIListLayout")
ListLayout.Padding = UDim.new(0, 4)
ListLayout.Parent = Scroll
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder

local function makeRow(order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 24)
	row.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
	row.BorderColor3 = Color3.fromRGB(0, 0, 0)
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = Scroll
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -40, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(230, 230, 230)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextSize = 13
	label.Parent = row
	return row, label
end

local function makeToggle(row, initial)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 34, 0, 20)
	btn.Position = UDim2.new(1, -38, 0.5, -10)
	btn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	btn.BorderColor3 = Color3.fromRGB(0, 0, 0)
	btn.AutoButtonColor = false
	btn.Text = initial and "ON" or "OFF"
	btn.TextColor3 = initial and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(220, 220, 220)
	btn.TextSize = 12
	btn.Parent = row
	return btn
end

local function makeList(row, options)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 90, 0, 20)
	btn.Position = UDim2.new(1, -94, 0.5, -10)
	btn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	btn.BorderColor3 = Color3.fromRGB(0, 0, 0)
	btn.AutoButtonColor = false
	btn.Text = options[1]
	btn.TextColor3 = Color3.fromRGB(220, 220, 220)
	btn.TextSize = 11
	btn.Parent = row
	btn.MouseButton1Click:Connect(function()
		local cur = options[btn.Index] or options[1]
		local idx = 1
		for i, o in ipairs(options) do if o == cur then idx = i end end
		idx = idx % #options + 1
		btn.Index = idx
		btn.Text = options[idx]
		btn.Callback(options[idx])
	end)
	return btn
end

local order = 0
local function addToggle(name, key)
	order = order + 1
	local row, label = makeRow(order)
	label.Text = name
	local btn = makeToggle(row, Config[key])
	btn.MouseButton1Click:Connect(function()
		Config[key] = not Config[key]
		btn.Text = Config[key] and "ON" or "OFF"
		btn.TextColor3 = Config[key] and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(220, 220, 220)
		btn.BackgroundColor3 = Config[key] and Config.Color or Color3.fromRGB(60, 60, 60)
	end)
end

-- Build UI
order = order + 1
do
	local row, label = makeRow(order)
	label.Text = "Enable ESP"
	local btn = makeToggle(row, Config.Enabled)
	btn.MouseButton1Click:Connect(function()
		Config.Enabled = not Config.Enabled
		btn.Text = Config.Enabled and "ON" or "OFF"
		btn.TextColor3 = Config.Enabled and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(220, 220, 220)
		btn.BackgroundColor3 = Config.Enabled and Config.Color or Color3.fromRGB(60, 60, 60)
	end)
end

addToggle("Boxes", "Boxes")

order = order + 1
do
	local row, label = makeRow(order)
	label.Text = "Box Type"
	local btn = makeList(row, { "2D Box", "3D Box", "Corner Box", "Filled Box" })
	btn.Index = 1
	btn.Callback = function(v) Config.BoxType = v end
end

addToggle("Outline", "Outline")
addToggle("Names", "Names")
addToggle("Health Bar", "HealthBar")
addToggle("Distance", "Distance")
addToggle("Tracers", "Tracers")

order = order + 1
do
	local row, label = makeRow(order)
	label.Text = "Tracer Type"
	local btn = makeList(row, { "From Bottom", "From Mouse" })
	btn.Index = 1
	btn.Callback = function(v) Config.TracerType = v end
end

addToggle("Skeleton", "Skeleton")
addToggle("Head Dot", "HeadDot")

-- Drag window
local dragging, drag
Window.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		local mouse = UserInputService:GetMouseLocation()
		drag = UDim2.new(0, mouse.X - Window.AbsolutePosition.X, 0, mouse.Y - Window.AbsolutePosition.Y)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local mouse = UserInputService:GetMouseLocation()
		Window.Position = UDim2.new(0, mouse.X - drag.X.Offset, 0, mouse.Y - drag.Y.Offset)
	end
end)
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.End then
		Window.Visible = not Window.Visible
	end
end)

print("[VisionWare] ESP loaded")