-- // VisionWare Chams
-- // Tries to hook into the main VisionWare GUI; falls back to a self-contained window.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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

local function toggleFrom(State)
	Config.Enabled = State
	if State then
		highlightAllPlayers()
	else
		clearAllHighlights()
	end
end

local function colorFrom(Color)
	Config.Color = Color
	for character, highlight in pairs(activeHighlights) do
		if highlight then
			highlight.FillColor = Color
			highlight.OutlineColor = Color
		end
	end
end

-- ===== Try to integrate into the main VisionWare GUI =====
local Library = _G.Library or (getgenv and getgenv().Library)
local Hooked = false

if Library and Library.Pages then
	-- Add to the currently open page so the toggle is visible immediately
	local targetPage
	for _, page in ipairs(Library.Pages) do
		if page.Name ~= nil and (page.Open or page.Open == nil) then
			targetPage = page
			break
		end
	end
	targetPage = targetPage or Library.Pages[1]

	if targetPage and targetPage.Section then
		local ok, err = pcall(function()
			local Section = targetPage:Section({
				Name = "Chams",
				side = #targetPage.Sections == 0 and "left" or "right",
			})
			Section:Toggle({ Name = "Enable Chams", Flag = "ChamsEnabled", callback = toggleFrom })
			Section:Colorpicker({
				Name = "Cham Color",
				Flag = "ChamsColor",
				Default = Config.Color,
				Callback = colorFrom,
			})
		end)
		if ok then
			Hooked = true
			print("[VisionWare] Chams hooked into GUI page: " .. targetPage.Name)
		else
			warn("[VisionWare] GUI hook failed: " .. tostring(err))
		end
	end
end

-- ===== Fallback: self-contained window =====
if not Hooked then
	warn("[VisionWare] GUI unavailable - using standalone window")

	local UIS = game:GetService("UserInputService")
	local GUI = Instance.new("ScreenGui")
	GUI.Name = "VisionWareChams"
	GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	GUI.Parent = game:GetService("CoreGui")

	local Window = Instance.new("Frame")
	Window.Size = UDim2.new(0, 220, 0, 84)
	Window.Position = UDim2.new(0.5, -110, 0.5, -42)
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
	Title.Text = "VisionWare Chams"
	Title.Size = UDim2.new(1, 0, 0, 22)
	Title.BackgroundTransparency = 1
	Title.TextColor3 = Color3.fromRGB(255, 255, 255)
	Title.TextSize = 14
	Title.Parent = Inline

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
	ToggleButton.MouseButton1Click:Connect(function()
		toggleFrom(not Config.Enabled)
		ToggleButton.Text = "Enable Chams: " .. (Config.Enabled and "ON" or "OFF")
		ToggleButton.BackgroundColor3 = Config.Enabled and Config.Color or Color3.fromRGB(40, 40, 40)
	end)

	local colors = { { 1, "FF58A6" }, { 2, "FF0000" }, { 3, "00FF00" }, { 4, "0000FF" }, { 5, "FFFF00" }, { 6, "FFFFFF" } }
	for _, c in ipairs(colors) do
		local swatch = Instance.new("TextButton")
		swatch.Size = UDim2.new(0, 26, 0, 16)
		swatch.Position = UDim2.new(0, 6 + ((c[1] - 1) % 3) * 30, 0, 48 + ((c[1] - 1) >= 3 and 18 or 0))
		swatch.BackgroundColor3 = Color3.fromHex(c[2])
		swatch.BorderColor3 = Color3.fromRGB(0, 0, 0)
		swatch.AutoButtonColor = false
		swatch.Parent = Inline
		swatch.MouseButton1Click:Connect(function()
			colorFrom(swatch.BackgroundColor3)
			if Config.Enabled then
				ToggleButton.BackgroundColor3 = swatch.BackgroundColor3
			end
		end)
	end

	local dragging, drag
	Window.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			local mouse = UIS:GetMouseLocation()
			drag = UDim2.new(0, mouse.X - Window.AbsolutePosition.X, 0, mouse.Y - Window.AbsolutePosition.Y)
		end
	end)
	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
	end)
	UIS.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local mouse = UIS:GetMouseLocation()
			Window.Position = UDim2.new(0, mouse.X - drag.X.Offset, 0, mouse.Y - drag.Y.Offset)
		end
	end)
	UIS.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.End then
			Window.Visible = not Window.Visible
		end
	end)
end

print("[VisionWare] Chams loaded")