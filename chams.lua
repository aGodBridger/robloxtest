-- // VisionWare Chams
-- // Run after gui.lua so the Library is available

local Library = Library or getgenv().Library
if not Library then
	warn("[VisionWare] gui.lua must be loaded before chams.lua")
	return
end

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local Chams = {
	Enabled = false,
	Color = Color3.fromRGB(255, 88, 166),
	FillTransparency = 0.5,
	OutlineTransparency = 0,
}

local function addHighlight(Character)
	if Character:FindFirstChild("VisionWareCham") then return end
	local Highlight = Instance.new("Highlight")
	Highlight.Name = "VisionWareCham"
	Highlight.Parent = Character
	Highlight.FillColor = Chams.Color
	Highlight.FillTransparency = Chams.FillTransparency
	Highlight.OutlineColor = Chams.Color
	Highlight.OutlineTransparency = Chams.OutlineTransparency
end

local function refresh()
	if not Chams.Enabled then return end
	for _, Player in ipairs(Players:GetPlayers()) do
		if Player ~= LocalPlayer and Player.Character then
			addHighlight(Player.Character)
		end
	end
end

local function cleanup()
	for _, Player in ipairs(Players:GetPlayers()) do
		if Player.Character then
			local Highlight = Player.Character:FindFirstChild("VisionWareCham")
			if Highlight then
				Highlight:Destroy()
			end
		end
	end
end

local function toggle(State)
	Chams.Enabled = State
	if State then
		refresh()
	else
		cleanup()
	end
end

local function setupPlayer(Player)
	if Player == LocalPlayer then return end
	Player.CharacterAdded:Connect(function(Character)
		if Chams.Enabled then
			task.wait(0.25)
			addHighlight(Character)
		end
	end)
end

for _, Player in ipairs(Players:GetPlayers()) do
	setupPlayer(Player)
end

Players.PlayerAdded:Connect(setupPlayer)

Players.PlayerRemoving:Connect(function(Player)
	if Player.Character then
		local Highlight = Player.Character:FindFirstChild("VisionWareCham")
		if Highlight then
			Highlight:Destroy()
		end
	end
end)

local Window = Library:Window({ Name = "VisionWare", Amount = 2 })
local VisualsPage = Window:Page({ Name = "Visuals" })
local VisualsSection = VisualsPage:Section({ Name = "Chams", side = "left" })

VisualsSection:Toggle({
	Name = "Enable Chams",
	flag = "ChamsEnabled",
	callback = toggle,
})

VisualsSection:Colorpicker({
	Name = "Cham Color",
	Flag = "ChamsColor",
	Default = Chams.Color,
	Callback = function(Color)
		Chams.Color = Color
		for _, Player in ipairs(Players:GetPlayers()) do
			if Player.Character then
				local Highlight = Player.Character:FindFirstChild("VisionWareCham")
				if Highlight then
					Highlight.FillColor = Color
					Highlight.OutlineColor = Color
				end
			end
		end
	end,
})

print("[VisionWare] Chams loaded")