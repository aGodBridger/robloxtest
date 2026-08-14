-- // VisionWare ESP (BillboardGui approach)
-- // Anchors a Name + Health label to each player's head. Driven by gui.lua flags.

local Players = game:GetService("Players")
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

local activeEsp = {}

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
	local root = character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("Head")
		or character:FindFirstChild("Torso")
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

local function removeEsp(player)
	local e = activeEsp[player]
	if e then
		if e.gui then pcall(function() e.gui:Destroy() end) end
		if e.healthCon then pcall(function() e.healthCon:Disconnect() end) end
	end
	activeEsp[player] = nil
end

local function updatePlayer(player)
	if player == LocalPlayer then return end

	local e = activeEsp[player]
	if not e then
		e = { gui = nil, label = nil, healthCon = nil }
		activeEsp[player] = e
	end

	local enabled = flag("ESP_Enabled", true)
	local character = player.Character

	if not enabled or not character then
		if e.gui then pcall(function() e.gui:Destroy() end) end
		e.gui = nil
		e.label = nil
		return
	end

	local head = character:FindFirstChild("Head")
	local humanoid = character:FindFirstChild("Humanoid")
	if not head or not humanoid then return end

	local visible = isCharacterVisible(character)

	if not e.gui or not e.gui.Parent then
		if e.healthCon then pcall(function() e.healthCon:Disconnect() end) end

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "VisionWareESP"
		billboard.Adornee = head
		billboard.Parent = head
		billboard.Size = UDim2.new(0, 200, 0, 50)
		billboard.StudsOffset = Vector3.new(0, 3.2, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = flag("ESP_Range", 500)
		billboard.Enabled = visible

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.TextSize = 14
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextColor3 = getPlayerColor(player)
		label.Parent = billboard

		e.gui = billboard
		e.label = label

		e.healthCon = humanoid.HealthChanged:Connect(function()
			if e.label then
				e.label.Text = player.Name .. " | Health: " .. math.floor(humanoid.Health)
			end
		end)
	else
		if e.gui then e.gui.Enabled = visible end
		if e.label then
			e.label.TextColor3 = getPlayerColor(player)
			e.label.Text = player.Name .. " | Health: " .. math.floor(humanoid.Health)
		end
	end
end

-- ===== Player lifecycle =====
local function initPlayer(player)
	player.CharacterAdded:Connect(function()
		removeEsp(player)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do initPlayer(player) end
Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(removeEsp)

-- ===== Sync loop =====
task.spawn(function()
	while task.wait(0.2) do
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer then
				updatePlayer(player)
			else
				removeEsp(player)
			end
		end
	end
end)

print("[VisionWare] ESP loaded")