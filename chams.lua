-- // VisionWare Chams
-- // Syncs with gui.lua ESP page. When "Visible Only" is on, only visible parts get highlighted.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local Pf = _G.Pf or (getgenv and getgenv().Pf)

local function getLibrary()
	return _G.Library or (getgenv and getgenv().Library)
end

local function flag(name, default)
	local L = getLibrary()
	local v = L and L.Flags and L.Flags[name]
	if v == nil then return default end
	return v
end

local C = {}
local function RefreshCache()
	local L = getLibrary()
	local F = L and L.Flags or {}
	local function get(n, d)
		local v = F[n]
		if v == nil then return d end
		return v
	end
	C.Enabled = get("ESP_Chams", false)
	C.Color = get("ESP_ChamsColor", Color3.fromRGB(255, 255, 255))
	C.Opacity = get("ESP_Opacity", 75)
	C.VisibleOnly = get("ESP_VisibleOnly", false)
end

local DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

-- state[character] = { model = Highlight|nil, parts = { [part] = Highlight } }
local state = {}

local function newHighlight(parent, adornee, color, opacity)
	local highlight = Instance.new("Highlight")
	highlight.Name = "VisionWareCham"
	highlight.Adornee = adornee
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 1 - (opacity / 100)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = DepthMode
	highlight.Enabled = true
	highlight.Parent = parent
	return highlight
end

local function removeState(character)
	local s = state[character]
	if s then
		if s.model then pcall(function() s.model:Destroy() end) end
		for part, h in pairs(s.parts) do
			if h then pcall(function() h:Destroy() end) end
		end
		state[character] = nil
	end
end

local function raycastVisible(camera, origin, target, character)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character, LocalPlayer and LocalPlayer.Character }
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true
	local result = Workspace:Raycast(origin, target - origin, params)
	if not result then return true end
	if result.Instance and result.Instance:IsDescendantOf(character) then return true end
	return false
end

local function partVisible(camera, character, part)
	local origin = camera.CFrame.Position
	local dir = part.Position - origin
	if dir.Magnitude < 0.01 then return true end
	return raycastVisible(camera, origin, part.Position, character)
end

local function updateCharacter(character, color, opacity, visibleOnly)
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then removeState(character); return end

	local camera = Workspace.CurrentCamera
	if not camera then return end

	local s = state[character]
	if not s then
		s = { model = nil, parts = {} }
		state[character] = s
	end

	if not visibleOnly then
		-- Whole-model highlight, remove leftover per-part highlights
		if not s.model or not s.model.Parent then
			s.model = newHighlight(character, character, color, opacity)
		else
			s.model.FillColor = color
			s.model.OutlineColor = color
			s.model.FillTransparency = 1 - (opacity / 100)
		end
		for part, h in pairs(s.parts) do
			if h then pcall(function() h:Destroy() end) end
		end
		s.parts = {}
	else
		-- Per-part visibility highlighting
		if s.model then
			pcall(function() s.model:Destroy() end)
			s.model = nil
		end

		local seen = {}
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") and not part:IsA("Accessory") then
				seen[part] = true
				local h = s.parts[part]
				if partVisible(camera, character, part) then
					if not h or not h.Parent then
						s.parts[part] = newHighlight(character, part, color, opacity)
					else
						h.FillColor = color
						h.OutlineColor = color
						h.FillTransparency = 1 - (opacity / 100)
					end
				else
					if h then
						pcall(function() h:Destroy() end)
						s.parts[part] = nil
					end
				end
			end
		end
		-- Remove highlights for parts no longer in the character
		for part, h in pairs(s.parts) do
			if not seen[part] then
				if h then pcall(function() h:Destroy() end) end
				s.parts[part] = nil
			end
		end
	end
end

local function updateAll(color, opacity, visibleOnly)
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character then
			updateCharacter(player.Character, color, opacity, visibleOnly)
		end
	end
end

local function clearAll()
	for character in pairs(state) do
		removeState(character)
	end
	state = {}
end

-- ===== Player lifecycle =====
local function applyToCharacter(character)
	if not character or not character:IsA("Model") then return end
	if not C.Enabled then return end
	updateCharacter(character, C.Color, C.Opacity, C.VisibleOnly)
end

local function hookPlayer(player)
	if player == LocalPlayer then return end
	if player.Character then applyToCharacter(player.Character) end
	player.CharacterAdded:Connect(applyToCharacter)
end

for _, player in ipairs(Players:GetPlayers()) do
	hookPlayer(player)
end

Players.PlayerAdded:Connect(hookPlayer)
Players.PlayerRemoving:Connect(function(player)
	if player.Character then removeState(player.Character) end
end)

RunService.Heartbeat:Connect(function()
	for character, s in pairs(state) do
		if not character or not character:IsA("Model") or not character:FindFirstChild("Humanoid") then
			removeState(character)
		else
			-- clean orphaned part highlights
			for part, h in pairs(s.parts) do
				if not part.Parent then
					if h then pcall(function() h:Destroy() end) end
					s.parts[part] = nil
				end
			end
		end
	end
end)

-- ===== Phantom Forces mode =====
-- PF characters live in the game's replication system (no Humanoid to
-- host per-part chams), so we Highlight the whole replicated model per enemy.
local PfState = {}

local function removePfHighlight(player)
	local h = PfState[player]
	if h then
		pcall(function() h:Destroy() end)
		PfState[player] = nil
	end
end

local function clearPfHighlights()
	for player in pairs(PfState) do
		removePfHighlight(player)
	end
	PfState = {}
end

local function updatePfAll(color, opacity, visibleOnly)
	if not (Pf and Pf.Active) then return end
	local seen = {}
	Pf.ForEachEnemy(function(player)
		seen[player] = true
		local view = Pf.Resolve(player)
		if view and view.Character then
			local h = PfState[player]
			if not h or not h.Parent then
				removePfHighlight(player)
				h = newHighlight(view.Character, view.Character, color, opacity)
				PfState[player] = h
			end
			h.FillColor = color
			h.OutlineColor = color
			h.FillTransparency = 1 - (opacity / 100)
			h.DepthMode = visibleOnly and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
		end
	end)
	for player in pairs(PfState) do
		if not seen[player] then
			removePfHighlight(player)
		end
	end
end

-- ===== Main loop =====
task.spawn(function()
	local lastEnabled = false
	local lastColor = nil
	local lastOpacity = -1
	local lastVisibleOnly = nil

	while true do
		task.wait(0.1)
		RefreshCache()

		local enabled = C.Enabled
		local color = C.Color
		local opacity = C.Opacity
		local visibleOnly = C.VisibleOnly

		if enabled ~= lastEnabled then
			if enabled then
				if Pf and Pf.Active then
					updatePfAll(color, opacity, visibleOnly)
				else
					updateAll(color, opacity, visibleOnly)
				end
				print("[Chams] Enabled")
			else
				clearAll()
				clearPfHighlights()
				print("[Chams] Disabled")
			end
		elseif enabled then
			-- Re-apply every tick so players who joined or respawned
			-- (including while the character was still loading) get chams.
			if Pf and Pf.Active then
				updatePfAll(color, opacity, visibleOnly)
			else
				updateAll(color, opacity, visibleOnly)
			end
		end

		lastEnabled = enabled
		lastColor = color
		lastOpacity = opacity
		lastVisibleOnly = visibleOnly
	end
end)

print("[VisionWare] Chams loaded")