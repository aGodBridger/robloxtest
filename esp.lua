-- // VisionWare ESP
-- // Boxes + extras via local Drawing, name via head-anchored BillboardGui (RobotoMono, like the GUI).
-- // All features are driven by gui.lua's ESP page flags.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local function getLibrary()
	return _G.Library or (getgenv and getgenv().Library)
end

local function flag(name, default)
	local L = getLibrary()
	local v = L and L.Flags and L.Flags[name]
	if v == nil then return default end
	return v
end

local newDrawing = function(kind)
	local ok, d = pcall(function()
		if not Drawing then return nil end
		return Drawing.new(kind)
	end)
	if ok and d then return d end
	return nil
end

local function worldToScreen(position)
	local cam = Workspace.CurrentCamera
	if not cam or not cam.CFrame then return nil end
	local screenPoint = cam:WorldToScreenPoint(position)
	return Vector2.new(screenPoint.X, screenPoint.Y)
end

-- Box anchored to head (top) and feet (bottom), fixed width ratio.
local function getBodyBoxRect(character)
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
	if not head or not root then return nil end

	local topWorld = head.Position + Vector3.new(0, head.Size.Y * 0.5 + 0.2, 0)
	local minY = root.Position.Y - root.Size.Y / 2
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			minY = math.min(minY, part.Position.Y - part.Size.Y / 2)
		end
	end

	local top = cam:WorldToScreenPoint(topWorld)
	local bottom = cam:WorldToScreenPoint(Vector3.new(root.Position.X, minY, root.Position.Z))

	local topY = math.min(top.Y, bottom.Y)
	local bottomY = math.max(top.Y, bottom.Y)
	local height = bottomY - topY
	if height < 2 then return nil end

	local width = height * 0.5
	local centerX = (top.X + bottom.X) / 2
	local minX = centerX - width / 2

	return {
		minX = minX, maxX = minX + width,
		minY = topY, maxY = bottomY,
		width = width, height = height,
		centerX = centerX, topY = topY, bottomY = bottomY,
	}
end

local BOX3D_EDGES = {
	{ 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 },
	{ 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 },
	{ 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
}
local CORNER_OFFSETS = {
	Vector3.new(-1, -1, -1), Vector3.new(1, -1, -1), Vector3.new(1, -1, 1), Vector3.new(-1, -1, 1),
	Vector3.new(-1, 1, -1),  Vector3.new(1, 1, -1),  Vector3.new(1, 1, 1),  Vector3.new(-1, 1, 1),
}
local SKELETON = {
	{ "Head", "Neck" }, { "Neck", "Torso" }, { "Torso", "HumanoidRootPart" },
	{ "Torso", "LeftShoulder" }, { "LeftShoulder", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
	{ "Torso", "RightShoulder" }, { "RightShoulder", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
	{ "Torso", "LeftHip" }, { "LeftHip", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
	{ "Torso", "RightHip" }, { "RightHip", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}

local function getPlayerColor(player)
	if LocalPlayer and player.Team and player.Team == LocalPlayer.Team then
		return flag("ESP_TeamColor", Color3.fromRGB(86, 227, 120))
	end
	return flag("ESP_EnemyColor", Color3.fromRGB(255, 88, 166))
end

local function isCharacterVisible(character)
	if not flag("ESP_VisibleOnly", false) then return true end
	if not character or not character:IsA("Model") then return true end
	local cam = Workspace.CurrentCamera
	if not cam then return true end
	local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head") or character:FindFirstChild("Torso")
	if not root then return true end
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character, LocalPlayer and LocalPlayer.Character }
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true
	local result = Workspace:Raycast(cam.CFrame.Position, root.Position - cam.CFrame.Position, params)
	if not result then return true end
	if result.Instance and result.Instance:IsDescendantOf(character) then return true end
	return false
end

local EspObjects = {}

local function createEspForPlayer(player)
	local esp = {
		Player = player,
		boxOutline = newDrawing("Square"),
		boxFill = newDrawing("Square"),
		boxFilled = newDrawing("Square"),
		boxLines = {},
		healthbg = newDrawing("Square"),
		healthfg = newDrawing("Square"),
		distance = newDrawing("Text"),
		tracer = newDrawing("Line"),
		head = newDrawing("Square"),
		skeleton = {},
		nameGui = nil,
		nameLabel = nil,
		nameCon = nil,
	}
	for i = 1, 12 do esp.boxLines[i] = newDrawing("Line") end
	for i = 1, 19 do esp.skeleton[i] = newDrawing("Line") end
	EspObjects[player] = esp
	return esp
end

local function hideAll(esp)
	for i = 1, 12 do if esp.boxLines[i] then esp.boxLines[i].Visible = false end end
	if esp.boxOutline then esp.boxOutline.Visible = false end
	if esp.boxFill then esp.boxFill.Visible = false end
	if esp.boxFilled then esp.boxFilled.Visible = false end
	if esp.distance then esp.distance.Visible = false end
	if esp.healthbg then esp.healthbg.Visible = false end
	if esp.healthfg then esp.healthfg.Visible = false end
	if esp.tracer then esp.tracer.Visible = false end
	if esp.head then esp.head.Visible = false end
	for _, l in ipairs(esp.skeleton) do if l then l.Visible = false end end
end

local function setLine(line, a, b, color, alpha, thickness)
	if not line then return end
	line.Visible = true
	line.From = a
	line.To = b
	line.Color = color
	line.Thickness = thickness or 1
	line.Transparency = alpha
end

local function updateNameBillboard(esp)
	local player = esp.Player
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local enabled = flag("ESP_Names", true)

	if not enabled or not head then
		if esp.nameGui then
			pcall(function() esp.nameGui:Destroy() end)
			esp.nameGui = nil
			esp.nameLabel = nil
		end
		return
	end

	if not esp.nameGui or not esp.nameGui.Parent then
		if esp.nameCon then pcall(function() esp.nameCon:Disconnect() end) end
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "VisionWareESPName"
		billboard.Adornee = head
		billboard.Parent = head
		billboard.Size = UDim2.new(0, 180, 0, 28)
		billboard.StudsOffset = Vector3.new(0, 3.4, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = flag("ESP_Range", 500)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Font.fromEnum(Enum.Font.RobotoMono)
		label.Text = player.Name
		label.TextSize = 14
		label.TextColor3 = getPlayerColor(player)
		label.TextStrokeTransparency = 0.25
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.Parent = billboard

		esp.nameGui = billboard
		esp.nameLabel = label
		local refHumanoid = character:FindFirstChild("Humanoid")
		if refHumanoid then
			esp.nameCon = refHumanoid.HealthChanged:Connect(function()
				if esp.nameLabel then
					esp.nameLabel.Text = player.Name .. (" (%d)"):format(math.floor(refHumanoid.Health))
				end
			end)
		end
	else
		if esp.nameLabel then
			esp.nameLabel.TextColor3 = getPlayerColor(player)
			local h = character:FindFirstChild("Humanoid")
			if h then
				esp.nameLabel.Text = player.Name .. (" (%d)"):format(math.floor(h.Health))
			end
		end
	end

	esp.nameGui.Enabled = isCharacterVisible(character)
end

local function renderEsp(esp)
	local player = esp.Player
	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	if not character or not humanoid then hideAll(esp); updateNameBillboard(esp); return end

	local cam = Workspace.CurrentCamera
	if not cam then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		local range = flag("ESP_Range", 500)
		if (cam.CFrame.Position - hrp.Position).Magnitude > range then
			hideAll(esp); updateNameBillboard(esp); return
		end
	end

	if not isCharacterVisible(character) then
		hideAll(esp); updateNameBillboard(esp); return
	end

	local rect = getBodyBoxRect(character)
	updateNameBillboard(esp)
	if not rect then hideAll(esp); return end

	local color = getPlayerColor(player)
	local alpha = flag("ESP_Opacity", 75) / 100
	local boxType = flag("ESP_BoxType", "2D Box")
	local boxes = flag("ESP_Boxes", true)
	local outline = flag("ESP_Outline", true)

	local minX, maxX = rect.minX, rect.maxX
	local minY, topY = rect.minY, rect.topY
	local maxY = rect.maxY
	local centerX, bottomY = rect.centerX, rect.bottomY
	local width, height = rect.width, rect.height

	-- ===== Box =====
	for i = 1, 12 do if esp.boxLines[i] then esp.boxLines[i].Visible = false end end
	if esp.boxOutline then esp.boxOutline.Visible = false end
	if esp.boxFill then esp.boxFill.Visible = false end
	if esp.boxFilled then esp.boxFilled.Visible = false end

	if boxes then
		if boxType == "3D Box" then
			local bboxCF, bboxSize = character:GetBoundingBox()
			local projected = {}
			for i, off in ipairs(CORNER_OFFSETS) do
				local p = worldToScreen(bboxCF * ((bboxSize / 2) * off))
				if p then projected[i] = p end
			end
			for e, edge in ipairs(BOX3D_EDGES) do
				local a, b = projected[edge[1]], projected[edge[2]]
				if a and b then
					if outline and esp.boxLines[e + 1] then
						setLine(esp.boxLines[e + 1], a, b, Color3.new(0, 0, 0), 1, 3)
					end
					setLine(esp.boxLines[e], a, b, color, alpha, 1)
				end
			end
		elseif boxType == "Corner Box" then
			local seg = math.min(width, height) * 0.25
			local corners = {
				{ minX, topY, minX + seg, topY }, { maxX - seg, topY, maxX, topY },
				{ minX, maxY, minX + seg, maxY }, { maxX - seg, maxY, maxX, maxY },
				{ minX, topY, minX, topY + seg }, { maxX, topY, maxX, topY + seg },
				{ minX, maxY - seg, minX, maxY }, { maxX, maxY - seg, maxX, maxY },
			}
			for i, c in ipairs(corners) do
				local a = Vector2.new(c[1], c[2])
				local b = Vector2.new(c[3], c[4])
				if outline and esp.boxLines[i + 1] then
					setLine(esp.boxLines[i + 1], a, b, Color3.new(0, 0, 0), 1, 3)
				end
				setLine(esp.boxLines[i], a, b, color, alpha, 1)
			end
		else
			if boxType == "Filled Box" then
				esp.boxFilled.Visible = true
				esp.boxFilled.Position = Vector2.new(minX, topY)
				esp.boxFilled.Size = Vector2.new(width, height)
				esp.boxFilled.Color = color
				esp.boxFilled.Filled = true
				esp.boxFilled.Transparency = alpha * 0.85
			end
			esp.boxOutline.Visible = outline
			esp.boxOutline.Position = Vector2.new(minX - 1, topY - 1)
			esp.boxOutline.Size = Vector2.new(width + 2, height + 2)
			esp.boxOutline.Color = Color3.new(0, 0, 0)
			esp.boxOutline.Thickness = 1
			esp.boxOutline.Filled = false
			esp.boxOutline.Transparency = 1
			esp.boxFill.Visible = true
			esp.boxFill.Position = Vector2.new(minX, topY)
			esp.boxFill.Size = Vector2.new(width, height)
			esp.boxFill.Color = color
			esp.boxFill.Thickness = 1
			esp.boxFill.Filled = false
			esp.boxFill.Transparency = alpha
		end
	end

	-- ===== Health bar =====
	if flag("ESP_Health", true) then
		local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
		esp.healthbg.Visible = true
		esp.healthbg.Position = Vector2.new(minX - 5, topY)
		esp.healthbg.Size = Vector2.new(3, height)
		esp.healthbg.Color = Color3.new(0, 0, 0)
		esp.healthbg.Filled = true
		esp.healthbg.Transparency = 1
		esp.healthfg.Visible = true
		esp.healthfg.Position = Vector2.new(minX - 5, topY + height * (1 - ratio))
		esp.healthfg.Size = Vector2.new(3, height * ratio)
		esp.healthfg.Color = flag("ESP_HealthColor", Color3.fromRGB(0, 255, 0))
		esp.healthfg.Filled = true
		esp.healthfg.Transparency = 1
	else
		if esp.healthbg then esp.healthbg.Visible = false end
		if esp.healthfg then esp.healthfg.Visible = false end
	end

	-- ===== Distance =====
	if flag("ESP_Distance", false) and hrp then
		local dist = math.round((cam.CFrame.Position - hrp.Position).Magnitude)
		esp.distance.Visible = true
		esp.distance.Text = tostring(dist) .. " studs"
		esp.distance.Color = Color3.fromRGB(255, 255, 255)
		esp.distance.Position = Vector2.new(centerX, bottomY + 18)
		esp.distance.Size = 13
		esp.distance.Center = true
		esp.distance.Outline = true
		pcall(function() esp.distance.Font = Enum.Font.Code end)
		esp.distance.Transparency = alpha
	else
		if esp.distance then esp.distance.Visible = false end
	end

	-- ===== Tracers =====
	if flag("ESP_Tracers", true) and hrp then
		local origin = Vector2.new(centerX, maxY)
		local target
		if flag("ESP_TracerType", "From Bottom") == "From Bottom" then
			local m = UserInputService:GetMouseLocation()
			target = Vector2.new(m.X, 1080)
		else
			target = UserInputService:GetMouseLocation()
		end
		esp.tracer.Visible = true
		esp.tracer.From = origin
		esp.tracer.To = target
		esp.tracer.Color = flag("ESP_TracerColor", color)
		esp.tracer.Thickness = 1
		esp.tracer.Transparency = alpha
	else
		if esp.tracer then esp.tracer.Visible = false end
	end

	-- ===== Head dot =====
	if flag("ESP_Head", false) then
		local hp = worldToScreen((character:FindFirstChild("Head") or hrp or character).Position)
		if hp then
			esp.head.Visible = true
			esp.head.Position = hp - Vector2.new(2, 2)
			esp.head.Size = Vector2.new(4, 4)
			esp.head.Color = color
			esp.head.Filled = true
			esp.head.Transparency = alpha
		else
			esp.head.Visible = false
		end
	else
		if esp.head then esp.head.Visible = false end
	end

	-- ===== Skeleton =====
	if flag("ESP_Skeleton", false) then
		for i, pair in ipairs(SKELETON) do
			local aPart = character:FindFirstChild(pair[1])
			local bPart = character:FindFirstChild(pair[2])
			local line = esp.skeleton[i]
			local a = aPart and worldToScreen(aPart.Position)
			local b = bPart and worldToScreen(bPart.Position)
			if line and a and b then
				setLine(line, a, b, color, alpha, 1)
			elseif line then
				line.Visible = false
			end
		end
	else
		for _, l in ipairs(esp.skeleton) do if l then l.Visible = false end end
	end
end

-- ===== Init =====
for _, player in ipairs(Players:GetPlayers()) do createEspForPlayer(player) end
Players.PlayerAdded:Connect(createEspForPlayer)
Players.PlayerRemoving:Connect(function(player)
	local esp = EspObjects[player]
	if esp then
		for _, l in ipairs(esp.boxLines) do if l then pcall(function() l:Remove() end) end end
		for _, l in ipairs(esp.skeleton) do if l then pcall(function() l:Remove() end) end end
		for _, k in ipairs({ "boxOutline", "boxFill", "boxFilled", "healthbg", "healthfg", "distance", "tracer", "head" }) do
			if esp[k] then pcall(function() esp[k]:Remove() end) end
		end
		if esp.nameGui then pcall(function() esp.nameGui:Destroy() end) end
		EspObjects[player] = nil
	end
end)

RunService.RenderStepped:Connect(function()
	if not flag("ESP_Enabled", true) then
		for _, esp in pairs(EspObjects) do
			hideAll(esp)
			if esp.nameGui then esp.nameGui.Enabled = false end
		end
		return
	end
	for _, esp in pairs(EspObjects) do
		renderEsp(esp)
	end
end)

print("[VisionWare] ESP loaded")