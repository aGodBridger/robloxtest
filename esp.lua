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

if not Drawing then
	warn("[VisionWare] Drawing API not available, ESP disabled.")
	return
end

local function safeDrawing(kind)
	local ok, d = pcall(Drawing.new, kind)
	return ok and d or nil
end

local function newLinePool(count)
	local pool = {}
	for i = 1, count do
		local line = safeDrawing("Line")
		if line then
			line.Visible = false
			line.Color = Color3.new(1, 1, 1)
			line.Thickness = 1
			pool[i] = line
		end
	end
	return pool
end

local function newText()
	local text = safeDrawing("Text")
	if text then
		text.Visible = false
		text.Center = true
		text.Size = 13
		text.Color = Color3.new(1, 1, 1)
		text.Outline = true
		text.Font = Enum.Font.RobotoMono
	end
	return text
end

local function newSquare(filled)
	local square = safeDrawing("Square")
	if square then
		square.Visible = false
		square.Color = Color3.new(1, 1, 1)
		square.Filled = filled
		square.Thickness = 1
		square.Transparency = 0
	end
	return square
end

local Drawings = {}

local function CreateESP(player)
	if player == LocalPlayer or Drawings[player] then return end
	Drawings[player] = {
		BoxPool = newLinePool(24),
		Skeleton = newLinePool(20),
		Tracer = safeDrawing("Line"),
		Head = newSquare(true),
		Fill = newSquare(true),
		HealthBack = newSquare(false),
		HealthFill = newSquare(true),
		Name = newText(),
		Distance = newText(),
		HealthText = newText(),
	}
end

local function RemoveESP(player)
	local esp = Drawings[player]
	if esp then
		for _, line in ipairs(esp.BoxPool) do if line then line:Remove() end end
		for _, line in ipairs(esp.Skeleton) do if line then line:Remove() end end
		local extras = { esp.Tracer, esp.Head, esp.Fill, esp.HealthBack, esp.HealthFill, esp.Name, esp.Distance, esp.HealthText }
		for _, d in ipairs(extras) do if d then d:Remove() end end
		Drawings[player] = nil
	end
end

local function hidePlayer(esp)
	for _, line in ipairs(esp.BoxPool) do if line then line.Visible = false end end
	for _, line in ipairs(esp.Skeleton) do if line then line.Visible = false end end
	if esp.Tracer then esp.Tracer.Visible = false end
	if esp.Head then esp.Head.Visible = false end
	if esp.Fill then esp.Fill.Visible = false end
	if esp.HealthBack then esp.HealthBack.Visible = false end
	if esp.HealthFill then esp.HealthFill.Visible = false end
	if esp.Name then esp.Name.Visible = false end
	if esp.Distance then esp.Distance.Visible = false end
	if esp.HealthText then esp.HealthText.Visible = false end
end

local function drawSegment(pool, index, from, to, color, thickness, outline)
	local backing = pool[index * 2 - 1]
	local fg = pool[index * 2]
	if backing and fg then
		if outline then
			backing.Color = Color3.fromRGB(0, 0, 0)
			backing.Thickness = thickness + 2
			backing.From = from
			backing.To = to
			backing.Visible = true
		else
			backing.Visible = false
		end
		fg.Color = color
		fg.Thickness = thickness
		fg.From = from
		fg.To = to
		fg.Visible = true
	end
end

local function isVisible(origin, target, character)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character, LocalPlayer and LocalPlayer.Character }
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true
	local result = Workspace:Raycast(origin, target - origin, params)
	if not result then return true end
	if result.Instance and result.Instance:IsDescendantOf(character) then return true end
	return false
end

local function GetColor(player)
	local L = getLibrary()
	if L then
		if L.Priorities and table.find(L.Priorities, player) then
			return Color3.fromRGB(255, 210, 0)
		elseif L.Friends and table.find(L.Friends, player) then
			return Color3.fromRGB(0, 255, 0)
		elseif player.Team == LocalPlayer.Team then
			return flag("ESP_TeamColor", Color3.fromRGB(86, 227, 120))
		end
	end
	return flag("ESP_EnemyColor", Color3.fromRGB(255, 25, 25))
end

local function GetTracerOrigin()
	if flag("ESP_TracerType", "From Bottom") == "From Mouse" then
		return UserInputService:GetMouseLocation()
	end
	return Vector2.new(Workspace.CurrentCamera.ViewportSize.X / 2, Workspace.CurrentCamera.ViewportSize.Y)
end

local function updatePlayer(player, esp, camera)
	local character = player.Character
	if not character then hidePlayer(esp) return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then hidePlayer(esp) return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then hidePlayer(esp) return end

	local screen, onScreen = camera:WorldToViewportPoint(rootPart.Position)
	if not onScreen then hidePlayer(esp) return end

	local distance = (rootPart.Position - camera.CFrame.Position).Magnitude
	local maxDist = flag("ESP_Range", 500)
	if distance > maxDist then hidePlayer(esp) return end

	if flag("ESP_VisibleOnly", false) then
		local origin = camera.CFrame.Position
		local target = rootPart.Position + Vector3.new(0, 2, 0)
		if not isVisible(origin, target, character) then hidePlayer(esp) return end
	end

	local color = GetColor(player)
	local size = character:GetExtentsSize()
	local cf = rootPart.CFrame

	local headWorld = cf * CFrame.new(0, size.Y / 2, 0)
	local feetWorld = cf * CFrame.new(0, -size.Y / 2, 0)
	local headScreen = camera:WorldToViewportPoint(headWorld.Position)
	local feetScreen = camera:WorldToViewportPoint(feetWorld.Position)

	if headScreen.Z < 0 or feetScreen.Z < 0 then hidePlayer(esp) return end

	local screenHeight = feetScreen.Y - headScreen.Y
	local boxWidth = screenHeight * 0.65
	local left = headScreen.X - boxWidth / 2
	local top = headScreen.Y
	local rect = {
		TL = Vector2.new(left, top),
		TR = Vector2.new(left + boxWidth, top),
		BL = Vector2.new(left, top + screenHeight),
		BR = Vector2.new(left + boxWidth, top + screenHeight),
	}

	local boxEnabled = flag("ESP_Boxes", true)
	local boxType = flag("ESP_BoxType", "2D Box")
	local outline = flag("ESP_Outline", true)
	local thickness = 1

	for i = 1, #esp.BoxPool do
		if esp.BoxPool[i] then esp.BoxPool[i].Visible = false end
	end

	if boxEnabled and boxType ~= "3D Box" then
		if boxType == "Filled Box" and esp.Fill then
			local opacity = flag("ESP_Opacity", 75)
			esp.Fill.Color = color
			esp.Fill.Position = rect.TL
			esp.Fill.Size = Vector2.new(boxWidth, screenHeight)
			esp.Fill.Transparency = math.clamp(1 - opacity / 100, 0, 1)
			esp.Fill.Visible = true
		elseif esp.Fill then
			esp.Fill.Visible = false
		end

		if boxType == "Corner Box" then
			local cs = boxWidth * 0.2
			local segs = {
				{ rect.TL, rect.TL + Vector2.new(cs, 0) },
				{ rect.TR, rect.TR - Vector2.new(cs, 0) },
				{ rect.BL, rect.BL + Vector2.new(cs, 0) },
				{ rect.BR, rect.BR - Vector2.new(cs, 0) },
				{ rect.TL, rect.TL + Vector2.new(0, cs) },
				{ rect.TR, rect.TR + Vector2.new(0, cs) },
				{ rect.BL, rect.BL - Vector2.new(0, cs) },
				{ rect.BR, rect.BR - Vector2.new(0, cs) },
			}
			for i, seg in ipairs(segs) do
				drawSegment(esp.BoxPool, i, seg[1], seg[2], color, thickness, outline)
			end
		else
			local segs = {
				{ rect.TL, rect.TR },
				{ rect.TR, rect.BR },
				{ rect.BR, rect.BL },
				{ rect.BL, rect.TL },
			}
			for i, seg in ipairs(segs) do
				drawSegment(esp.BoxPool, i, seg[1], seg[2], color, thickness, outline)
			end
		end
	elseif boxEnabled then
		if esp.Fill then esp.Fill.Visible = false end

		local sx, sy, sz = size.X / 2, size.Y / 2, size.Z / 2
		local corners = {
			Vector3.new(-sx, sy, -sz),
			Vector3.new(sx, sy, -sz),
			Vector3.new(sx, -sy, -sz),
			Vector3.new(-sx, -sy, -sz),
			Vector3.new(-sx, sy, sz),
			Vector3.new(sx, sy, sz),
			Vector3.new(sx, -sy, sz),
			Vector3.new(-sx, -sy, sz),
		}

		local proj = {}
		for i, corner in ipairs(corners) do
			local p, ok = camera:WorldToViewportPoint((cf * CFrame.new(corner)).Position)
			if not ok or p.Z < 0 then
				for j = 1, #esp.BoxPool do
					if esp.BoxPool[j] then esp.BoxPool[j].Visible = false end
				end
				hidePlayer(esp)
				return
			end
			proj[i] = Vector2.new(p.X, p.Y)
		end

		local segs = {
			{ proj[1], proj[2] }, { proj[2], proj[3] }, { proj[3], proj[4] }, { proj[4], proj[1] },
			{ proj[5], proj[6] }, { proj[6], proj[7] }, { proj[7], proj[8] }, { proj[8], proj[5] },
			{ proj[1], proj[5] }, { proj[2], proj[6] }, { proj[3], proj[7] }, { proj[4], proj[8] },
		}
		for i, seg in ipairs(segs) do
			drawSegment(esp.BoxPool, i, seg[1], seg[2], color, thickness, outline)
		end
	elseif esp.Fill then
		esp.Fill.Visible = false
	end

	if esp.Tracer then
		if flag("ESP_Tracers", true) then
			esp.Tracer.From = GetTracerOrigin()
			esp.Tracer.To = Vector2.new(screen.X, screen.Y)
			esp.Tracer.Color = flag("ESP_TracerColor", color)
			esp.Tracer.Thickness = 1
			esp.Tracer.Visible = true
		else
			esp.Tracer.Visible = false
		end
	end

	if esp.Name then
		if flag("ESP_Names", true) then
			esp.Name.Text = player.DisplayName
			esp.Name.Position = Vector2.new(rect.TL.X + boxWidth / 2, top - 18)
			esp.Name.Color = color
			esp.Name.Visible = true
		else
			esp.Name.Visible = false
		end
	end

	if esp.Distance then
		if flag("ESP_Distance", false) then
			esp.Distance.Text = string.format("%.0f studs", distance)
			esp.Distance.Position = Vector2.new(rect.TL.X + boxWidth / 2, top + screenHeight + 4)
			esp.Distance.Color = color
			esp.Distance.Visible = true
		else
			esp.Distance.Visible = false
		end
	end

	if esp.HealthBack and esp.HealthFill then
		if flag("ESP_Health", true) then
			local healthPercent = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
			local barHeight = screenHeight * 0.8
			local barWidth = 4
			local barPos = Vector2.new(rect.TL.X - barWidth - 2, top + (screenHeight - barHeight) / 2)
			local healthColor = flag("ESP_HealthColor", Color3.fromRGB(0, 255, 0))

			esp.HealthBack.Position = barPos
			esp.HealthBack.Size = Vector2.new(barWidth, barHeight)
			esp.HealthBack.Color = Color3.fromRGB(0, 0, 0)
			esp.HealthBack.Thickness = 1
			esp.HealthBack.Visible = true

			esp.HealthFill.Position = Vector2.new(barPos.X + 0.5, barPos.Y + barHeight * (1 - healthPercent))
			esp.HealthFill.Size = Vector2.new(barWidth - 1, math.max(0, barHeight * healthPercent))
			esp.HealthFill.Color = healthColor
			esp.HealthFill.Visible = true

			if esp.HealthText then
				esp.HealthText.Text = tostring(math.floor(humanoid.Health))
				esp.HealthText.Position = Vector2.new(barPos.X - 4, barPos.Y + barHeight / 2)
				esp.HealthText.Color = healthColor
				esp.HealthText.Visible = true
			end
		else
			esp.HealthBack.Visible = false
			esp.HealthFill.Visible = false
			if esp.HealthText then esp.HealthText.Visible = false end
		end
	end

	if esp.Head then
		if flag("ESP_Head", false) then
			local headScreenPos = camera:WorldToViewportPoint(headWorld.Position)
			esp.Head.Color = color
			esp.Head.Position = Vector2.new(headScreenPos.X - 2, headScreenPos.Y - 2)
			esp.Head.Size = Vector2.new(4, 4)
			esp.Head.Visible = true
		else
			esp.Head.Visible = false
		end
	end

	if flag("ESP_Skeleton", false) then
		local bones = {}
		local function get(part, fallback)
			local found = character:FindFirstChild(part)
			if not found and fallback then found = character:FindFirstChild(fallback) end
			return found
		end

		bones.Head = get("Head")
		bones.UpperTorso = get("UpperTorso", "Torso")
		bones.LowerTorso = get("LowerTorso", "Torso")
		bones.LeftUpperArm = get("LeftUpperArm", "Left Arm")
		bones.LeftLowerArm = get("LeftLowerArm", "Left Arm")
		bones.LeftHand = get("LeftHand", "Left Arm")
		bones.RightUpperArm = get("RightUpperArm", "Right Arm")
		bones.RightLowerArm = get("RightLowerArm", "Right Arm")
		bones.RightHand = get("RightHand", "Right Arm")
		bones.LeftUpperLeg = get("LeftUpperLeg", "Left Leg")
		bones.LeftLowerLeg = get("LeftLowerLeg", "Left Leg")
		bones.LeftFoot = get("LeftFoot", "Left Leg")
		bones.RightUpperLeg = get("RightUpperLeg", "Right Leg")
		bones.RightLowerLeg = get("RightLowerLeg", "Right Leg")
		bones.RightFoot = get("RightFoot", "Right Leg")

		local function drawBone(from, to, index)
			local line = esp.Skeleton[index]
			if not line then return end
			if not from or not to then
				line.Visible = false
				return
			end
			local a, aok = camera:WorldToViewportPoint(from.Position)
			local b, bok = camera:WorldToViewportPoint(to.Position)
			if not (aok and bok) or a.Z < 0 or b.Z < 0 then
				line.Visible = false
				return
			end
			local sizeVS = camera.ViewportSize
			if a.X < 0 or a.X > sizeVS.X or a.Y < 0 or a.Y > sizeVS.Y
				or b.X < 0 or b.X > sizeVS.X or b.Y < 0 or b.Y > sizeVS.Y then
				line.Visible = false
				return
			end
			line.From = Vector2.new(a.X, a.Y)
			line.To = Vector2.new(b.X, b.Y)
			line.Color = color
			line.Thickness = 1
			line.Visible = true
		end

		drawBone(bones.Head, bones.UpperTorso, 1)
		drawBone(bones.UpperTorso, bones.LowerTorso, 2)
		drawBone(bones.UpperTorso, bones.LeftUpperArm, 3)
		drawBone(bones.LeftUpperArm, bones.LeftLowerArm, 4)
		drawBone(bones.LeftLowerArm, bones.LeftHand, 5)
		drawBone(bones.UpperTorso, bones.RightUpperArm, 6)
		drawBone(bones.RightUpperArm, bones.RightLowerArm, 7)
		drawBone(bones.RightLowerArm, bones.RightHand, 8)
		drawBone(bones.LowerTorso, bones.LeftUpperLeg, 9)
		drawBone(bones.LeftUpperLeg, bones.LeftLowerLeg, 10)
		drawBone(bones.LeftLowerLeg, bones.LeftFoot, 11)
		drawBone(bones.LowerTorso, bones.RightUpperLeg, 12)
		drawBone(bones.RightUpperLeg, bones.RightLowerLeg, 13)
		drawBone(bones.RightLowerLeg, bones.RightFoot, 14)
	else
		for _, line in ipairs(esp.Skeleton) do
			if line then line.Visible = false end
		end
	end
end

Players.PlayerRemoving:Connect(RemoveESP)
Players.PlayerAdded:Connect(CreateESP)

for _, player in ipairs(Players:GetPlayers()) do
	if player ~= LocalPlayer then CreateESP(player) end
end

RunService.RenderStepped:Connect(function()
	local camera = Workspace.CurrentCamera
	if not camera then return end

	local panic = flag("Misc_Panic", false)
	local enabled = not panic and flag("ESP_Enabled", true)

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			if enabled then
				if not Drawings[player] then CreateESP(player) end
				local esp = Drawings[player]
				if esp then updatePlayer(player, esp, camera) end
			else
				local esp = Drawings[player]
				if esp then hidePlayer(esp) end
			end
		end
	end
end)

print("[VisionWare] ESP loaded")