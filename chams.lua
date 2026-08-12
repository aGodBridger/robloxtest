-- // VisionWare Chams

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local connectionList = {}

cham = cham or {}

local ChamConfig = {
	Enabled = true,
	Color = Color3.fromRGB(0, 255, 0),
	Material = Enum.Material.ForceField,  -- how the body looks; ForceField glows through walls
	Transparency = 0,
	IgnoreLocal = true,                   -- never cham your own character
}

local cache = {}

function cham.new(model, properties, hideParts, deleteImages, ignoreTransparency)
	if model then
		properties = properties or {}
		local controlled = {}
		local data = {
			model = model,
			parts = controlled,
			properties = properties,
			ignore = ignoreTransparency,
			hide = (type(hideParts) == "table" and hideParts)
		}
		table.insert(cache, data)

		local function uncache()
			table.remove(cache, table.find(cache, data))
		end

		local function classify(part)
			if part:IsA("BasePart") then
				if not table.find(controlled, part) then
					table.insert(controlled, part)
				end
			elseif deleteImages and (part.ClassName == "Decal" or part.ClassName == "Texture") then
				part:Destroy()
			end
		end

		local parts = model:GetDescendants()
		for _, part in ipairs(parts) do
			classify(part)
		end

		table.insert(connectionList, model.DescendantAdded:Connect(classify))

		return properties, uncache
	end
end

-- Rendering loop (colors every part each frame, like your version)
local lastChamCheck = 0
table.insert(connectionList, RunService.RenderStepped:Connect(function()
	if tick() - lastChamCheck < 1 / 60 then return end
	lastChamCheck = tick()

	for _, data in ipairs(cache) do
		if data.model:IsDescendantOf(workspace) then
			for _, part in ipairs(data.parts) do
				if data.hide and table.find(data.hide, part) then
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
		end
	end
end))

local applied = {}

local function applyToCharacter(player, character)
	if not character then return end
	if ChamConfig.IgnoreLocal and player == LocalPlayer then return end
	if applied[character] then return end
	applied[character] = true
	cham.new(character, {
		Color = ChamConfig.Color,
		Material = ChamConfig.Material,
		Transparency = ChamConfig.Transparency,
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