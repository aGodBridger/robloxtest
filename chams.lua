-- // VisionWare Chams

local connectionList = {}

local cache = {}

cham = cham or {}

local ChamConfig = {
	Enabled = true,
	ThroughWalls = true,          -- see players through walls
	Color = Color3.fromRGB(0, 255, 0),
	HideOriginal = true,          -- hide the actual body (only glow shows)
	RefreshRate = 0
}

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
		local parts = model:GetDescendants()
		table.insert(parts, model)
		table.insert(cache, data)

		local function uncache()
			table.remove(cache, table.find(cache, data))
		end

		local function classify(part)
			if part:IsA("BasePart") then
				table.insert(controlled, part)
			elseif deleteImages and (part.ClassName == "Decal" or part.ClassName == "Texture") then
				part:Destroy()
			end
		end

		for _, part in parts do
			classify(part)
		end

		table.insert(connectionList, model.DescendantAdded:Connect(classify))

		return properties, uncache
	end
end

-- Rendering loop for chams
table.insert(connectionList, game:GetService("RunService").RenderStepped:Connect(function()
	for _, data in cache do
		if data.model:IsDescendantOf(workspace) then
			for _, part in data.parts do
				if data.throughwalls then
					part.Transparency = data.properties.Transparency or 1
					part.CanCollide = false
					part.CanQuery = false
				elseif data.hide and table.find(data.hide, part) then
					part.Transparency = 1
				elseif (part.Transparency < 1) or data.ignore then
					for i, v in data.properties do
						if i == "Color" and part:IsA("SpecialMesh") then
							part.VertexColor = Vector3.new(v.R * 1.2, v.G * 1.2, v.B * 1.2)
						end
						part[i] = v
					end
				end
			end
			if data.throughwalls then
				local highlight = data.model:FindFirstChildOfClass("Highlight")
				if not highlight then
					highlight = Instance.new("Highlight")
					highlight.Name = "VisionCham"
					highlight.Parent = data.model
				end
				highlight.FillColor = data.properties.Color or ChamConfig.Color
				highlight.FillTransparency = 1
				highlight.OutlineColor = data.properties.Color or ChamConfig.Color
				highlight.OutlineTransparency = 0
				highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			end
		end
	end
end))

local function applyToCharacter(player, character)
	if not character then return end
	if character:FindFirstChildOfClass("Highlight") then return end
	cham.new(character, {
		Color = ChamConfig.Color,
		Transparency = ChamConfig.HideOriginal and 1 or 0.7,
	}, nil, nil, true)
end

if ChamConfig.Enabled then
	local Players = game:GetService("Players")
	local function onCharacter(player, character)
		applyToCharacter(player, character or player.Character or player.CharacterAdded:Wait())
	end
	table.insert(connectionList, Players.PlayerAdded:Connect(function(player)
		table.insert(connectionList, player.CharacterAdded:Connect(function(character)
			applyToCharacter(player, character)
		end))
		if player.Character then
			applyToCharacter(player, player.Character)
		end
	end))
	for _, player in ipairs(Players:GetPlayers()) do
		onCharacter(player)
	end
end

print("[VisionWare] Chams Loaded!")