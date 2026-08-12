-- // VisionWare Chams

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local connectionList = {}

local cache = {}

cham = cham or {}

local ChamConfig = {
	Enabled = true,
	ThroughWalls = true,          -- see players through walls
	Color = Color3.fromRGB(0, 255, 0),
	HideOriginal = true,          -- hide the actual body (only glow shows)
	IgnoreLocal = true,           -- never cham your own character
}

local function refreshParts(data)
	for _, part in ipairs(data.model:GetDescendants()) do
		if part:IsA("BasePart") then
			if not table.find(data.parts, part) then
				table.insert(data.parts, part)
			end
		end
	end
end

function cham.new(model, properties, hideParts, deleteImages, ignoreTransparency)
	if model then
		properties = properties or {}
		local controlled = {}
		local data = {
			model = model,
			parts = controlled,
			properties = properties,
			ignore = ignoreTransparency,
			throughwalls = ChamConfig.ThroughWalls,
			hide = (type(hideParts) == "table" and hideParts)
		}
		table.insert(cache, data)

		local function classify(part)
			if part:IsA("BasePart") then
				if not table.find(controlled, part) then
					table.insert(controlled, part)
				end
			elseif deleteImages and (part.ClassName == "Decal" or part.ClassName == "Texture") then
				part:Destroy()
			end
		end

		refreshParts(data)

		table.insert(connectionList, model.DescendantAdded:Connect(classify))

		local function uncache()
			table.remove(cache, table.find(cache, data))
		end

		return properties, uncache
	end
end

-- Rendering loop for chams
table.insert(connectionList, RunService.RenderStepped:Connect(function()
	for _, data in ipairs(cache) do
		if data.model and data.model:IsDescendantOf(workspace) then
			refreshParts(data)
			for _, part in ipairs(data.parts) do
				if data.throughwalls then
					part.Transparency = data.properties.Transparency or 1
				elseif data.hide and table.find(data.hide, part) then
					part.Transparency = 1
				elseif (part.Transparency < 1) or data.ignore then
					for i, v in pairs(data.properties) do
						if i == "Color" and part:IsA("SpecialMesh") then
							part.VertexColor = Vector3.new(v.R * 1.2, v.G * 1.2, v.B * 1.2)
						end
						part[i] = v
					end
				end
			end
			if data.throughwalls then
				local highlight = data.model:FindFirstChild("VisionCham")
				if not highlight then
					highlight = Instance.new("Highlight")
					highlight.Name = "VisionCham"
					highlight.Parent = data.model
				end
				highlight.FillColor = data.properties.Color or ChamConfig.Color
				highlight.FillTransparency = 1
				highlight.OutlineColor = data.properties.Color or ChamConfig.Color
				highlight.OutlineTransparency = 0.35
				highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			end
		end
	end
end))

local function applyToCharacter(player, character)
	if not character then return end
	if ChamConfig.IgnoreLocal and player == LocalPlayer then return end
	if character:FindFirstChild("VisionCham") then return end
	cham.new(character, {
		Color = ChamConfig.Color,
		Transparency = ChamConfig.HideOriginal and 1 or 0.7,
	}, nil, nil, true)
end

if ChamConfig.Enabled then
	table.insert(connectionList, Players.PlayerAdded:Connect(function(player)
		if ChamConfig.IgnoreLocal and player == LocalPlayer then return end
		table.insert(connectionList, player.CharacterAdded:Connect(function(character)
			applyToCharacter(player, character)
		end))
		if player.Character then
			applyToCharacter(player, player.Character)
		end
	end))
	for _, player in ipairs(Players:GetPlayers()) do
		if not (ChamConfig.IgnoreLocal and player == LocalPlayer) then
			local character = player.Character or player.CharacterAdded:Wait()
			applyToCharacter(player, character)
		end
	end
end

print("[VisionWare] Chams Loaded!")