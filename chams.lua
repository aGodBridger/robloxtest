-- // VisionWare Chams (self-contained)
-- // Highlights all players when the toggle is on. Works standalone.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

local Config = {
	Enabled = false,
	Color = Color3.fromRGB(255, 88, 166),
}

local activeHighlights = {}

local function createHighlightForCharacter(character)
	if not character or not character:IsA("Model") then return nil end
	if not Config.Enabled then return nil end
	local existing = character:FindFirstChild("VisionWareCham")
	if existing then return existing end

	local highlight = Instance.new("Highlight")
	highlight.Name = "VisionWareCham"
	highlight.FillColor = Config.Color
	highlight.OutlineColor = Config.Color
	highlight.FillTransparency = 0.5
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = true
	highlight.Adornee = character
	highlight.Parent = character

	activeHighlights[character] = highlight
	return highlight
end

local function highlightAllPlayers()
	if not Config.Enabled then return end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			createHighlightForCharacter(player.Character)
		end
	end
end

local function removeHighlightFromCharacter(character)
	if character and character:IsA("Model") then
		local highlight = character:FindFirstChild("VisionWareCham")
		if highlight then
			highlight:Destroy()
			activeHighlights[character] = nil
		end
	end
end

local function clearAllHighlights()
	for character, highlight in pairs(activeHighlights) do
		if highlight then highlight:Destroy() end
	end
	activeHighlights = {}
end

local function onCharacterAdded(character)
	task.wait(0.1)
	if Config.Enabled and character and character:IsA("Model") and character:FindFirstChild("Humanoid") then
		createHighlightForCharacter(character)
	end
end

local function onPlayerAdded(player)
	if player.Character then onCharacterAdded(player.Character) end
	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(removeHighlightFromCharacter)
end

local function onPlayerRemoving(player)
	if player.Character then removeHighlightFromCharacter(player.Character) end
end

for _, player in ipairs(Players:GetPlayers()) do onPlayerAdded(player) end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

RunService.Heartbeat:Connect(function()
	for character, highlight in pairs(activeHighlights) do
		if not character or not character:IsA("Model") or not character:FindFirstChild("Humanoid") then
			if highlight then highlight:Destroy() end
			activeHighlights[character] = nil
		end
	end
end)

-- ===== Minimal GUI =====
local GUI = Instance.new("ScreenGui")
GUI.Name = "VisionWare"
GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
GUI.Parent = game:GetService("CoreGui")

local Window = Instance.new("Frame")
Window.Size = UDim2.new(0, 210, 0, 60)
Window.Position = UDim2.new(0.5, -105, 0.5, -30)
Window.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
Window.BorderColor3 = Color3.fromRGB(0, 0, 0)
Window.Visible = true
Window.Parent = GUI

local Inline = Instance.new("Frame")
Inline.Size = UDim2.new(1, -2, 1, -2)
Inline.Position = UDim2.new(0, 1, 0, 1)
Inline.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
Inline.BorderSizePixel = 0
Inline.MouseButton1Down = nil
Inline.Parent = Window

local Title = Instance.new("TextLabel")
Title.Text = "VisionWare Chams"
Title.Size = UDim2.new(1, 0, 0, 22)
Title.BackgroundTransparency = 1
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 13
Title.Parent = Inline

-- Toggle
local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(1, -12, 0, 22)
ToggleButton.Position = UDim2.new(0, 6, 0, 24)
ToggleButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
ToggleButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
ToggleButton.AutoButtonColor = false
ToggleButton.Text = "Enable Chams: OFF"
ToggleButton.TextColor3 = Color3.fromRGB(220, 220, 220)
ToggleButton.TextSize = 13
ToggleButton.Parent = Inline

-- Color picker (simple preset swatches)
local Swatches = {}
for i, hex in ipairs({ "FF58A6", "FF0000", "00FF00", "0000FF", "FFFF00", "FFFFFF" }) do
	local swatch = Instance.new("TextButton")
	swatch.Size = UDim2.new(0, 26, 0, 16)
	swatch.Position = UDim2.new(0, 6 + (i - 1) * 30, 0, 48 + (i > 3 and 18 or 0))
	swatch.BackgroundColor3 = Color3.fromHex(hex)
	swatch.BorderColor3 = Color3.fromRGB(0, 0, 0)
	swatch.AutoButtonColor = false
	swatch.Parent = Inline
	swatch.Size = UDim2.new(0, 26, 0, 16)
	swatch.Position = UDim2.new(0, 6 + ((i - 1) % 3) * 30, 0, 48 + ((i - 1) >= 3 and 18 or 0))
	swatch.MouseButton1Click:Connect(function()
		Config.Color = swatch.BackgroundColor3
		for character, highlight in pairs(activeHighlights) do
			if highlight then
				highlight.FillColor = Config.Color
				highlight.OutlineColor = Config.Color
			end
		end
	end)
	table.insert(Swatches, swatch)
end

-- Resize window to fit both rows of swatches
Window.Size = UDim2.new(0, 210, 0, 84)

-- Drag window
local dragging, dragOffset = false
Window.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		local mouse = game:GetService("UserInputService"):GetMouseLocation()
		dragOffset = UDim2.new(0, mouse.X - Window.AbsolutePosition.X, 0, mouse.Y - Window.AbsolutePosition.Y)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local mouse = UserInputService:GetMouseLocation()
		Window.Position = UDim2.new(0, mouse.X - dragOffset.X.Offset, 0, mouse.Y - dragOffset.Y.Offset)
	end
end)

-- Toggle visibility with END key
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.End then
		Window.Visible = not Window.Visible
	end
end)

ToggleButton.MouseButton1Click:Connect(function()
	Config.Enabled = not Config.Enabled
	ToggleButton.Text = "Enable Chams: " .. (Config.Enabled and "ON" or "OFF")
	ToggleButton.BackgroundColor3 = Config.Enabled and Config.Color or Color3.fromRGB(40, 40, 40)
	if Config.Enabled then
		highlightAllPlayers()
	else
		clearAllHighlights()
	end
end)

print("[VisionWare] Chams loaded")