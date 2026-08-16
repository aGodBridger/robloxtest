local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local Pf = _G.Pf or (getgenv and getgenv().Pf)

local Library = _G.Library
local Color3fromRGB = Color3.fromRGB
local Vector2_new = Vector2.new
local Vector3_new = Vector3.new
local CFrame_new = CFrame.new
local MathClamp = math.clamp

local function flag(name, default)
	if Library == nil then
		Library = _G.Library or (getgenv and getgenv().Library)
	end
	local v = Library and Library.Flags and Library.Flags[name]
	if v == nil then return default end
	return v
end

-- Snapshot all ESP flags once per frame so the per-player loop only does
-- plain table reads instead of a bunch of _G lookups every single player.
local C = {}
local function RefreshCache()
	local L = Library
	if L == nil then
		L = _G.Library or (getgenv and getgenv().Library)
		Library = L
	end
	local F = L and L.Flags or {}
	local function get(n, d)
		local v = F[n]
		if v == nil then return d end
		return v
	end
	C.Enabled = get("ESP_Enabled", true)
	C.Panic = get("Misc_Panic", false)
	C.Range = get("ESP_Range", 500)
	C.TeamCheck = get("ESP_TeamCheck", false)
	C.ShowTeam = get("ESP_ShowTeam", false)
	C.VisibleOnly = get("ESP_VisibleOnly", false)
	C.Rainbow = get("ESP_Rainbow", false)
	C.RainbowSpeed = get("ESP_RainbowSpeed", 1)
	C.RainbowPart = get("ESP_RainbowParts", "All")
	C.TracerType = get("ESP_TracerType", "From Bottom")
	C.TracerColor = get("ESP_TracerColor", nil)
	C.Tracers = get("ESP_Tracers", true)
	C.TracerThickness = get("ESP_TracerThickness", 1)
	C.TextSize = get("ESP_TextSize", 13)
	C.Names = get("ESP_Names", true)
	C.NameMode = get("ESP_NameMode", "DisplayName")
	C.Distance = get("ESP_Distance", false)
	C.Health = get("ESP_Health", true)
	C.HealthStyle = get("ESP_HealthStyle", "Both")
	C.HealthBarSide = get("ESP_HealthBarSide", "Left")
	C.HealthColor = get("ESP_HealthColor", Color3fromRGB(0, 255, 0))
	C.Boxes = get("ESP_Boxes", true)
	C.BoxType = get("ESP_BoxType", "2D Box")
	C.Outline = get("ESP_Outline", true)
	C.BoxThickness = get("ESP_BoxThickness", 1)
	C.Opacity = get("ESP_Opacity", 75)
	C.HeadDot = get("ESP_Head", false)
	C.Skeleton = get("ESP_Skeleton", false)
	C.SkeletonColor = get("ESP_SkeletonColor", Color3fromRGB(255, 255, 255))
	C.SkeletonThickness = get("ESP_SkeletonThickness", 1)
	C.TeamColor = get("ESP_TeamColor", Color3fromRGB(86, 227, 120))
	C.EnemyColor = get("ESP_EnemyColor", Color3fromRGB(255, 25, 25))
end

local function GetColor(player, isEnemy)
	local L = Library
	if L then
		if L.Priorities and table.find(L.Priorities, player) then
			return Color3fromRGB(255, 210, 0)
		elseif L.Friends and table.find(L.Friends, player) then
			return Color3fromRGB(0, 255, 0)
		elseif (Pf and Pf.Active) then
			return isEnemy and C.EnemyColor or C.TeamColor
		elseif player.Team == LocalPlayer.Team then
			return C.TeamColor
		end
	end
	return C.EnemyColor
end

-- Resolve a player's ESP data. In Phantom Forces we read the game's
-- replicated character (PF hides Humanoids/teams from the normal API).
-- Returns character, rootPart, humanoid (or proxy), isEnemy.
local function ResolvePlayer(player)
	if Pf and Pf.Active then
		local view = Pf.Resolve(player)
		if not view then return nil end
		return view.Character, view.Root, { Health = view.Health, MaxHealth = view.MaxHealth }, view.Enemy
	end
	local character = player.Character
	if not character then return nil end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then return nil end
	local isEnemy = true
	if player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then
		isEnemy = false
	end
	return character, rootPart, humanoid, isEnemy
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

local function TracerOrigin(camera)
	local kind = C.TracerType
	if kind == "From Mouse" then
		return UserInputService:GetMouseLocation()
	elseif kind == "From Top" then
		return Vector2_new(camera.ViewportSize.X / 2, 0)
	elseif kind == "From Center" then
		return Vector2_new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	end
	return Vector2_new(camera.ViewportSize.X / 2, camera.ViewportSize.Y)
end

local function RainbowColor(speed)
	return Color3.fromHSV(tick() * math.max(speed or 1, 0.1) % 1, 1, 1)
end

local function PlayerNameText(player)
	if C.NameMode == "Username" then
		return player.Name
	end
	return player.DisplayName or player.Name
end

local function IsTeammate(player)
	local lp = LocalPlayer
	if not (lp and player and player.Team) or not lp.Team then return false end
	return player.Team == lp.Team
end

-- Require ALL drawing kinds to work before trusting the Drawing API.
-- Some executors expose Drawing.new but return nil for certain kinds,
-- which used to throw inside RenderStepped and silently kill all rendering.
local haveDrawing = false
do
	if type(Drawing) == "table" and type(Drawing.new) == "function" then
		local okLine, line = pcall(Drawing.new, "Line")
		local okSq, sq = pcall(Drawing.new, "Square")
		local okTxt, txt = pcall(Drawing.new, "Text")
		if okLine and line and okSq and sq and okTxt and txt then
			haveDrawing = true
			pcall(function() line:Remove() end)
			pcall(function() sq:Remove() end)
			pcall(function() txt:Remove() end)
		end
	end
end

-- ================= DRAWING BACKEND =================

local Drawings = {}

local function safeDrawing(kind)
	if not haveDrawing then return nil end
	local ok, d = pcall(Drawing.new, kind)
	return ok and d or nil
end

local function newLinePool(count)
	local pool = {}
	for i = 1, count do
		local line = safeDrawing("Line")
		if line then
			local ok = pcall(function()
				line.Visible = false
				line.Color = Color3.new(1, 1, 1)
				line.Thickness = 1
			end)
			if ok then pool[i] = line end
		end
	end
	return pool
end

local function newText()
	local text = safeDrawing("Text")
	if text then
		local ok = pcall(function()
			text.Visible = false
			text.Center = true
			text.Size = 13
			text.Color = Color3.new(1, 1, 1)
			text.Outline = true
			text.Font = Enum.Font.RobotoMono
		end)
		if not ok then
			pcall(function() text:Remove() end)
			return nil
		end
	end
	return text
end

local function newSquare(filled)
	local square = safeDrawing("Square")
	if not square then return nil end
	pcall(function() square.Visible = false end)
	pcall(function() square.Color = Color3.new(1, 1, 1) end)
	pcall(function() square.Filled = filled end)
	pcall(function() square.Thickness = 1 end)
	pcall(function() square.Transparency = 0 end)
	return square
end

local function CreateESP(player)
	if player == LocalPlayer or Drawings[player] then return end
	Drawings[player] = {
		BoxPool = newLinePool(24),
		Skeleton = newLinePool(20),
		Tracer = safeDrawing("Line"),
		Head = newLinePool(64),
		Fill = newSquare(true),
		HealthBack = newLinePool(8),
		HealthFill = safeDrawing("Line"),
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
		for _, line in ipairs(esp.Head) do if line then line:Remove() end end
		for _, line in ipairs(esp.HealthBack) do if line then line:Remove() end end
		local extras = { esp.Tracer, esp.Fill, esp.HealthFill, esp.Name, esp.Distance, esp.HealthText }
		for _, d in ipairs(extras) do if d then d:Remove() end end
		Drawings[player] = nil
	end
end

local function hidePlayer(esp)
	for _, line in ipairs(esp.BoxPool) do if line then line.Visible = false end end
	for _, line in ipairs(esp.Skeleton) do if line then line.Visible = false end end
	for _, line in ipairs(esp.Head) do if line then line.Visible = false end end
	for _, line in ipairs(esp.HealthBack) do if line then line.Visible = false end end
	if esp.Tracer then esp.Tracer.Visible = false end
	if esp.Fill then esp.Fill.Visible = false end
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
			backing.Color = Color3fromRGB(0, 0, 0)
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

local function drawHeadDot(dotPool, center, radius, color)
	local outlineSegments = math.max(10, math.floor(radius * 4))
	local outlineThickness = MathClamp(radius * 0.4, 1, 2.5)
	local fillThickness = MathClamp(radius * 0.3, 1, 2)
	local count = 0
	local function put(index, from, to, lcolor, thickness)
		local line = dotPool[index]
		if line then
			line.Color = lcolor
			line.Thickness = thickness
			line.From = from
			line.To = to
			line.Visible = true
		end
	end
	-- dark outline ring (genuine circle, many segments)
	for i = 1, outlineSegments do
		count = count + 1
		local a1 = (i - 1) / outlineSegments * math.pi * 2
		local a2 = i / outlineSegments * math.pi * 2
		put(count,
			Vector2_new(center.X + math.cos(a1) * radius, center.Y + math.sin(a1) * radius),
			Vector2_new(center.X + math.cos(a2) * radius, center.Y + math.sin(a2) * radius),
			Color3fromRGB(0, 0, 0), outlineThickness)
	end
	-- filled interior: overlapping 1px-stepped horizontal bands so it's fully solid
	local inner = math.max(0, radius - outlineThickness * 0.5 - 0.5)
	local maxY = math.max(0, math.floor(inner))
	for y = -maxY, maxY do
		local half = math.sqrt(math.max(0, inner * inner - y * y))
		count = count + 1
		put(count,
			Vector2_new(center.X - half, center.Y + y),
			Vector2_new(center.X + half, center.Y + y),
			color, fillThickness)
	end
	-- hide unused pool lines
	for i = count + 1, #dotPool do
		if dotPool[i] then dotPool[i].Visible = false end
	end
end

local function updatePlayer(player, esp, camera)
	local character, rootPart, humanoid, isEnemy = ResolvePlayer(player)
	if not (character and rootPart and humanoid) then hidePlayer(esp) return end
	if humanoid.Health <= 0 then hidePlayer(esp) return end

	local screen, onScreen = camera:WorldToViewportPoint(rootPart.Position)
	if not onScreen then hidePlayer(esp) return end

	local distance = (rootPart.Position - camera.CFrame.Position).Magnitude
	if distance > C.Range then hidePlayer(esp) return end

	if C.TeamCheck and not C.ShowTeam and not isEnemy then
		hidePlayer(esp)
		return
	end

	if C.VisibleOnly then
		if not isVisible(camera.CFrame.Position, rootPart.Position + Vector3_new(0, 2, 0), character) then
			hidePlayer(esp)
			return
		end
	end

	local color = GetColor(player, isEnemy)
	local size = character:GetExtentsSize()
	local cf = rootPart.CFrame

	local rainbow = C.Rainbow
	local rainbowSpeed = C.RainbowSpeed
	local rainbowPart = C.RainbowPart
	local rbColor = rainbow and RainbowColor(rainbowSpeed)

	local boxColor = (rainbow and (rainbowPart == "All" or rainbowPart == "Boxes")) and rbColor or color
	local tracerColor = (rainbow and (rainbowPart == "All" or rainbowPart == "Tracers")) and rbColor or (C.TracerColor or color)
	local textColor = (rainbow and (rainbowPart == "All" or rainbowPart == "Text")) and rbColor or color

	local headWorld = cf * CFrame_new(0, size.Y / 2, 0)
	local feetWorld = cf * CFrame_new(0, -size.Y / 2, 0)
	local headScreen = camera:WorldToViewportPoint(headWorld.Position)
	local feetScreen = camera:WorldToViewportPoint(feetWorld.Position)

	if headScreen.Z < 0 or feetScreen.Z < 0 then hidePlayer(esp) return end

	local screenHeight = feetScreen.Y - headScreen.Y
	local boxWidth = screenHeight * 0.65
	local left = headScreen.X - boxWidth / 2
	local top = headScreen.Y
	local rect = {
		TL = Vector2_new(left, top),
		TR = Vector2_new(left + boxWidth, top),
		BL = Vector2_new(left, top + screenHeight),
		BR = Vector2_new(left + boxWidth, top + screenHeight),
	}

	local boxEnabled = C.Boxes
	local boxType = C.BoxType
	local outline = C.Outline
	local thickness = C.BoxThickness

	for i = 1, #esp.BoxPool do
		if esp.BoxPool[i] then esp.BoxPool[i].Visible = false end
	end

	if boxEnabled and boxType ~= "3D Box" then
		if boxType == "Filled Box" and esp.Fill then
			local opacity = C.Opacity
			esp.Fill.Color = boxColor
			esp.Fill.Position = rect.TL
			esp.Fill.Size = Vector2_new(boxWidth, screenHeight)
			esp.Fill.Transparency = MathClamp(1 - opacity / 100, 0, 1)
			esp.Fill.Visible = true
		elseif esp.Fill then
			esp.Fill.Visible = false
		end

		if boxType == "Corner Box" then
			local cs = boxWidth * 0.2
			local segs = {
				{ rect.TL, rect.TL + Vector2_new(cs, 0) },
				{ rect.TR, rect.TR - Vector2_new(cs, 0) },
				{ rect.BL, rect.BL + Vector2_new(cs, 0) },
				{ rect.BR, rect.BR - Vector2_new(cs, 0) },
				{ rect.TL, rect.TL + Vector2_new(0, cs) },
				{ rect.TR, rect.TR + Vector2_new(0, cs) },
				{ rect.BL, rect.BL - Vector2_new(0, cs) },
				{ rect.BR, rect.BR - Vector2_new(0, cs) },
			}
			for i, seg in ipairs(segs) do
				drawSegment(esp.BoxPool, i, seg[1], seg[2], boxColor, thickness, outline)
			end
		else
			local segs = {
				{ rect.TL, rect.TR },
				{ rect.TR, rect.BR },
				{ rect.BR, rect.BL },
				{ rect.BL, rect.TL },
			}
			for i, seg in ipairs(segs) do
				drawSegment(esp.BoxPool, i, seg[1], seg[2], boxColor, thickness, outline)
			end
		end
	elseif boxEnabled then
		if esp.Fill then esp.Fill.Visible = false end

		local sx, sy, sz = size.X / 2, size.Y / 2, size.Z / 2
		local corners = {
			Vector3_new(-sx, sy, -sz),
			Vector3_new(sx, sy, -sz),
			Vector3_new(sx, -sy, -sz),
			Vector3_new(-sx, -sy, -sz),
			Vector3_new(-sx, sy, sz),
			Vector3_new(sx, sy, sz),
			Vector3_new(sx, -sy, sz),
			Vector3_new(-sx, -sy, sz),
		}

		local proj = {}
		local allInFront = true
		for i, corner in ipairs(corners) do
			local p, ok = camera:WorldToViewportPoint((cf * CFrame_new(corner)).Position)
			if not ok or p.Z < 0 then
				allInFront = false
				break
			end
			proj[i] = Vector2_new(p.X, p.Y)
		end

		if not allInFront then hidePlayer(esp) return end

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
		if C.Tracers then
			esp.Tracer.From = TracerOrigin(camera)
			esp.Tracer.To = Vector2_new(screen.X, screen.Y)
			esp.Tracer.Color = tracerColor
			esp.Tracer.Thickness = C.TracerThickness
			esp.Tracer.Visible = true
		else
			esp.Tracer.Visible = false
		end
	end

	local textSize = C.TextSize

	if esp.Name then
		if C.Names then
			esp.Name.Text = PlayerNameText(player)
			esp.Name.Position = Vector2_new(rect.TL.X + boxWidth / 2, top - 18)
			esp.Name.Color = textColor
			esp.Name.Size = textSize
			esp.Name.Visible = true
		else
			esp.Name.Visible = false
		end
	end

	if esp.Distance then
		if C.Distance then
			esp.Distance.Text = string.format("%.0f studs", distance)
			esp.Distance.Position = Vector2_new(rect.TL.X + boxWidth / 2, top + screenHeight + 4)
			esp.Distance.Color = textColor
			esp.Distance.Size = textSize
			esp.Distance.Visible = true
		else
			esp.Distance.Visible = false
		end
	end

	if esp.HealthBack and esp.HealthFill then
		if C.Health then
			local healthPercent = MathClamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
			local barHeight = screenHeight * 0.8
			local barWidth = 4
			local showBar = C.HealthStyle ~= "Text"
			local barSide = C.HealthBarSide
			local barPosX = rect.TL.X - barWidth - 2
			if barSide == "Right" then barPosX = rect.TR.X + 2 end
			local barPos = Vector2_new(barPosX, top + (screenHeight - barHeight) / 2)
			local healthColor = C.HealthColor or Color3fromRGB(0, 255, 0)

			if showBar then
				local barTL, barTR = barPos, Vector2_new(barPos.X + barWidth, barPos.Y)
				local barBL, barBR = Vector2_new(barPos.X, barPos.Y + barHeight), Vector2_new(barPos.X + barWidth, barPos.Y + barHeight)
				drawSegment(esp.HealthBack, 1, barTL, barTR, Color3fromRGB(0, 0, 0), 1, false)
				drawSegment(esp.HealthBack, 2, barTR, barBR, Color3fromRGB(0, 0, 0), 1, false)
				drawSegment(esp.HealthBack, 3, barBR, barBL, Color3fromRGB(0, 0, 0), 1, false)
				drawSegment(esp.HealthBack, 4, barBL, barTL, Color3fromRGB(0, 0, 0), 1, false)

				if esp.HealthFill then
					local fillTop = barPos.Y + barHeight * (1 - healthPercent)
					local fillHeight = math.max(0, barHeight * healthPercent)
					esp.HealthFill.Color = healthColor
					esp.HealthFill.Thickness = barWidth - 1
					esp.HealthFill.From = Vector2_new(barPos.X + barWidth / 2, fillTop)
					esp.HealthFill.To = Vector2_new(barPos.X + barWidth / 2, fillTop + fillHeight)
					esp.HealthFill.Visible = true
				end
			else
				for _, line in ipairs(esp.HealthBack) do if line then line.Visible = false end end
				if esp.HealthFill then esp.HealthFill.Visible = false end
			end

			if esp.HealthText then
				if C.HealthStyle ~= "Bar" then
					esp.HealthText.Text = tostring(math.floor(humanoid.Health))
					local tx = barPos.X - 4
					if barSide == "Right" then tx = barPos.X + barWidth + 2 end
					esp.HealthText.Position = Vector2_new(tx, barPos.Y + barHeight / 2)
					esp.HealthText.Color = rainbow and rbColor or healthColor
					esp.HealthText.Size = textSize
					esp.HealthText.Visible = true
				else
					esp.HealthText.Visible = false
				end
			end
		else
			for _, line in ipairs(esp.HealthBack) do if line then line.Visible = false end end
			if esp.HealthFill then esp.HealthFill.Visible = false end
			if esp.HealthText then esp.HealthText.Visible = false end
		end
	end

	if esp.Head then
		if C.HeadDot then
			local headPart = character:FindFirstChild("Head")
			local headPos = headPart and headPart.Position or headWorld.Position
			local headScreenPos = camera:WorldToViewportPoint(headPos)
			local dotRadius = MathClamp(screenHeight * 0.055, 2, 10)
			drawHeadDot(esp.Head, Vector2_new(headScreenPos.X, headScreenPos.Y), dotRadius, boxColor)
		else
			for _, line in ipairs(esp.Head) do if line then line.Visible = false end end
		end
	end

	if C.Skeleton then
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
			line.From = Vector2_new(a.X, a.Y)
			line.To = Vector2_new(b.X, b.Y)
			line.Color = C.SkeletonColor or Color3fromRGB(255, 255, 255)
			line.Thickness = C.SkeletonThickness
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

	return true
end

-- ================= UI BACKEND =================

local ESPUI = nil
local GuiInset = Vector2_new(0, 0)
local UIPlayers = {}

local function SetupUI()
	ESPUI = Instance.new("ScreenGui")
	ESPUI.Name = "VisionWareESP"
	ESPUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local ok = pcall(function() ESPUI.Parent = game:GetService("CoreGui") end)
	if not ok or not ESPUI.Parent then
		pcall(function() ESPUI.Parent = LocalPlayer:WaitForChild("PlayerGui", 5) end)
	end
	if not ESPUI.Parent then
		pcall(function() ESPUI.Parent = game:GetService("CoreGui") end)
	end
	GuiInset = game:GetService("GuiService"):GetGuiInset()
end

local function newUIFrame(parent)
	local f = Instance.new("Frame", parent)
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.BorderColor3 = Color3.new(0, 0, 0)
	f.ZIndex = 50
	return f
end

local function newUIText(parent)
	local t = Instance.new("TextLabel", parent)
	t.Font = Enum.Font.RobotoMono
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextSize = 13
	t.TextStrokeTransparency = 0
	t.ZIndex = 51
	return t
end

local function CreateUIFallback(player)
	if player == LocalPlayer or UIPlayers[player] then return end
	if not ESPUI then SetupUI() end
	local root = newUIFrame(ESPUI)
	local fb = {
		Root = root,
		Box = newUIFrame(root),
		Fill = newUIFrame(root),
		Corners = {},
		Tracer = newUIFrame(root),
		Head = newUIFrame(root),
		Name = newUIText(root),
		Distance = newUIText(root),
		HealthBack = newUIFrame(root),
		HealthFill = newUIFrame(root),
		HealthText = newUIText(root),
	}
	fb.Box.BorderSizePixel = 1
	fb.HealthBack.BorderSizePixel = 1
	for i = 1, 8 do
		fb.Corners[i] = newUIFrame(root)
	end
	UIPlayers[player] = fb
end

local function RemoveUIFallback(player)
	local fb = UIPlayers[player]
	if fb then
		fb.Root:Destroy()
		UIPlayers[player] = nil
	end
end

local function hideUIPlayer(fb)
	for _, child in ipairs(fb.Root:GetChildren()) do
		child.Visible = false
	end
end

local function positionUILine(frame, from, to, thickness, color)
	local dx, dy = to.X - from.X, to.Y - from.Y
	local len = math.sqrt(dx * dx + dy * dy)
	frame.AnchorPoint = Vector2_new(0, 0.5)
	frame.Position = UDim2.fromOffset(from.X + GuiInset.X, from.Y + GuiInset.Y)
	frame.Size = UDim2.fromOffset(len, thickness)
	frame.Rotation = math.deg(math.atan2(dy, dx))
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 0
end

local function updatePlayerUI(player, fb, camera)
	local character, rootPart, humanoid, isEnemy = ResolvePlayer(player)
	if not (character and rootPart and humanoid) then hideUIPlayer(fb) return end
	if humanoid.Health <= 0 then hideUIPlayer(fb) return end

	local screen, onScreen = camera:WorldToViewportPoint(rootPart.Position)
	if not onScreen then hideUIPlayer(fb) return end

	local distance = (rootPart.Position - camera.CFrame.Position).Magnitude
	if distance > C.Range then hideUIPlayer(fb) return end

	if C.TeamCheck and not C.ShowTeam and not isEnemy then
		hideUIPlayer(fb)
		return
	end

	if C.VisibleOnly then
		if not isVisible(camera.CFrame.Position, rootPart.Position + Vector3_new(0, 2, 0), character) then
			hideUIPlayer(fb)
			return
		end
	end

	local color = GetColor(player, isEnemy)
	local size = character:GetExtentsSize()
	local cf = rootPart.CFrame

	local rainbow = C.Rainbow
	local rainbowSpeed = C.RainbowSpeed
	local rainbowPart = C.RainbowPart
	local rbColor = rainbow and RainbowColor(rainbowSpeed)

	local boxColor = (rainbow and (rainbowPart == "All" or rainbowPart == "Boxes")) and rbColor or color
	local tracerColor = (rainbow and (rainbowPart == "All" or rainbowPart == "Tracers")) and rbColor or (C.TracerColor or color)
	local textColor = (rainbow and (rainbowPart == "All" or rainbowPart == "Text")) and rbColor or color

	local top = camera:WorldToViewportPoint((cf * CFrame_new(0, size.Y / 2, 0)).Position)
	local bottom = camera:WorldToViewportPoint((cf * CFrame_new(0, -size.Y / 2, 0)).Position)
	if top.Z < 0 or bottom.Z < 0 then hideUIPlayer(fb) return end

	local height = bottom.Y - top.Y
	local width = height * 0.65
	local left = top.X - width / 2
	local ty = top.Y

	local function P(x, y)
		return UDim2.fromOffset(x + GuiInset.X, y + GuiInset.Y)
	end

	local boxOn = C.Boxes
	local boxType = C.BoxType
	local outline = C.Outline

	fb.Box.Visible = false
	fb.Fill.Visible = false
	for i = 1, 8 do
		fb.Corners[i].Visible = false
	end

	if boxOn and boxType ~= "3D Box" then
		if boxType == "Filled Box" then
			fb.Fill.Visible = true
			fb.Fill.BackgroundColor3 = boxColor
			fb.Fill.BackgroundTransparency = MathClamp(1 - C.Opacity / 100, 0, 1)
			fb.Fill.Position = P(left, ty)
			fb.Fill.Size = UDim2.fromOffset(width, height)
		end

		if boxType == "Corner Box" then
			local cs = width * 0.2
			local segs = {
				{ left, ty, cs, 1 },
				{ left + width - cs, ty, cs, 1 },
				{ left, ty + height - 1, cs, 1 },
				{ left + width - cs, ty + height - 1, cs, 1 },
				{ left, ty, 1, cs },
				{ left + width - 1, ty, 1, cs },
				{ left, ty + height - cs, 1, cs },
				{ left + width - 1, ty + height - cs, 1, cs },
			}
			for i, s in ipairs(segs) do
				local seg = fb.Corners[i]
				seg.Visible = true
				seg.BackgroundColor3 = boxColor
				seg.BackgroundTransparency = 0
				seg.AnchorPoint = Vector2_new(0, 0)
				seg.Position = P(s[1], s[2])
				seg.Size = UDim2.fromOffset(s[3], s[4])
			end
		else
			fb.Box.Visible = true
			fb.Box.BackgroundTransparency = 1
			fb.Box.BorderColor3 = boxColor
			fb.Box.BorderSizePixel = outline and C.BoxThickness or 0
			fb.Box.Position = P(left, ty)
			fb.Box.Size = UDim2.fromOffset(width, height)
		end
	end

	if C.Tracers then
		positionUILine(fb.Tracer, TracerOrigin(camera), Vector2_new(screen.X, screen.Y), C.TracerThickness, tracerColor)
		fb.Tracer.Visible = true
	else
		fb.Tracer.Visible = false
	end

	local textSize = C.TextSize

	if C.Names then
		fb.Name.Text = PlayerNameText(player)
		fb.Name.TextColor3 = textColor
		fb.Name.TextSize = textSize
		fb.Name.AnchorPoint = Vector2_new(0.5, 0.5)
		fb.Name.Position = P(left + width / 2, ty - 10)
		fb.Name.Size = UDim2.fromOffset(200, textSize + 2)
		fb.Name.Visible = true
	else
		fb.Name.Visible = false
	end

	if C.Distance then
		fb.Distance.Text = string.format("%.0f studs", distance)
		fb.Distance.TextColor3 = textColor
		fb.Distance.TextSize = textSize
		fb.Distance.AnchorPoint = Vector2_new(0.5, 0)
		fb.Distance.Position = P(left + width / 2, ty + height + 4)
		fb.Distance.Size = UDim2.fromOffset(200, textSize + 2)
		fb.Distance.Visible = true
	else
		fb.Distance.Visible = false
	end

	if C.Health then
		local hp = MathClamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
		local bh = height * 0.8
		local bw = 4
		local showBar = C.HealthStyle ~= "Text"
		local barSide = C.HealthBarSide
		local bx = left - bw - 2
		if barSide == "Right" then bx = left + width + 2 end
		local by = ty + (height - bh) / 2
		local hc = C.HealthColor or Color3fromRGB(0, 255, 0)

		if showBar then
			fb.HealthBack.Visible = true
			fb.HealthBack.BackgroundColor3 = Color3.new(0, 0, 0)
			fb.HealthBack.BackgroundTransparency = 0
			fb.HealthBack.BorderColor3 = Color3.new(0, 0, 0)
			fb.HealthBack.Position = P(bx, by)
			fb.HealthBack.Size = UDim2.fromOffset(bw, bh)

			fb.HealthFill.Visible = true
			fb.HealthFill.BackgroundColor3 = hc
			fb.HealthFill.BackgroundTransparency = 0
			fb.HealthFill.Position = P(bx + 1, by + bh * (1 - hp))
			fb.HealthFill.Size = UDim2.fromOffset(bw - 2, math.max(1, bh * hp))
		else
			fb.HealthBack.Visible = false
			fb.HealthFill.Visible = false
		end

		if C.HealthStyle ~= "Bar" then
			fb.HealthText.Text = tostring(math.floor(humanoid.Health))
			fb.HealthText.TextColor3 = rainbow and rbColor or hc
			fb.HealthText.TextSize = textSize
			fb.HealthText.AnchorPoint = Vector2_new(0, 0.5)
			local hx = bx - 4
			if barSide == "Right" then hx = bx + bw + 2 end
			fb.HealthText.Position = P(hx, by + bh / 2)
			fb.HealthText.Size = UDim2.fromOffset(100, textSize + 2)
			fb.HealthText.Visible = true
		else
			fb.HealthText.Visible = false
		end
	else
		fb.HealthBack.Visible = false
		fb.HealthFill.Visible = false
		fb.HealthText.Visible = false
	end

	if C.HeadDot then
		local hs = camera:WorldToViewportPoint((cf * CFrame_new(0, size.Y / 2, 0)).Position)
		local dotRadius = MathClamp(height * 0.055, 2, 10)
		fb.Head.Visible = true
		fb.Head.AnchorPoint = Vector2_new(0, 0)
		fb.Head.BackgroundColor3 = boxColor
		fb.Head.BackgroundTransparency = 0
		fb.Head.Position = P(hs.X - dotRadius, hs.Y - dotRadius)
		fb.Head.Size = UDim2.fromOffset(dotRadius * 2, dotRadius * 2)
	else
		fb.Head.Visible = false
	end

	return true
end

-- ================= MAIN =================

local StatusGUI = nil
local StatusLabel = nil
local LastError = nil
local VisibleCount = 0
local PlayerCount = 0

local function SetupStatus()
	if StatusGUI then return end
	StatusGUI = Instance.new("ScreenGui")
	StatusGUI.Name = "VisionWareESPStatus"
	StatusGUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	StatusGUI.IgnoreGuiInset = true
	local ok = pcall(function() StatusGUI.Parent = game:GetService("CoreGui") end)
	if not ok or not StatusGUI.Parent then
		pcall(function() StatusGUI.Parent = LocalPlayer:WaitForChild("PlayerGui", 5) end)
	end
	if not StatusGUI.Parent then
		StatusGUI:Destroy()
		StatusGUI = nil
		return
	end
	StatusLabel = Instance.new("TextLabel", StatusGUI)
	StatusLabel.Name = "Status"
	StatusLabel.BackgroundColor3 = Color3.new(0, 0, 0)
	StatusLabel.BackgroundTransparency = 0.35
	StatusLabel.BorderSizePixel = 0
	StatusLabel.Font = Enum.Font.RobotoMono
	StatusLabel.TextColor3 = Color3.new(255, 255, 255)
	StatusLabel.TextSize = 13
	StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	StatusLabel.Position = UDim2.fromOffset(8, 8)
	StatusLabel.Size = UDim2.fromOffset(320, 46)
	StatusLabel.Text = "VisionWare ESP - starting..."
end

local doneSetup = false

local function statusText()
	local backend = haveDrawing and "Drawing API" or "UI Frames"
	local line = "ESP [" .. backend .. "] visible: " .. VisibleCount .. "/" .. PlayerCount
	if LastError then
		line = line .. " | error: " .. tostring(LastError)
	end
	if not C.Enabled then
		line = "ESP DISABLED (toggle ESP page)"
	elseif C.Panic then
		line = "ESP DISABLED (Panic ON)"
	end
	return line
end

Players.PlayerAdded:Connect(function(p)
	if p == LocalPlayer then return end
	if haveDrawing then CreateESP(p) else CreateUIFallback(p) end
end)
Players.PlayerRemoving:Connect(function(p)
	RemoveESP(p)
	RemoveUIFallback(p)
end)

for _, player in ipairs(Players:GetPlayers()) do
	if player ~= LocalPlayer then
		if haveDrawing then
			CreateESP(player)
		else
			CreateUIFallback(player)
		end
	end
end

local function renderPlayerDrawing(player, camera)
	local esp = Drawings[player]
	if not esp then return end
	if not C.Enabled or C.Panic then
		hidePlayer(esp)
		return
	end
	local ok, err = pcall(updatePlayer, player, esp, camera)
	if ok and err == true then
		VisibleCount = VisibleCount + 1
	elseif not ok then
		hidePlayer(esp)
		LastError = err
	end
end

local function renderPlayerUI(player, camera)
	if not UIPlayers[player] then CreateUIFallback(player) end
	local fb = UIPlayers[player]
	if not fb then return end
	if not C.Enabled or C.Panic then
		hideUIPlayer(fb)
		return
	end
	local ok, err = pcall(updatePlayerUI, player, fb, camera)
	if ok and err == true then
		VisibleCount = VisibleCount + 1
	elseif not ok then
		hideUIPlayer(fb)
		LastError = err
	end
end

RunService.RenderStepped:Connect(function()
	if not doneSetup then
		SetupStatus()
		doneSetup = true
	end

	local camera = Workspace.CurrentCamera
	if not camera then return end

	RefreshCache()

	PlayerCount = 0
	VisibleCount = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			PlayerCount = PlayerCount + 1
			if haveDrawing then
				renderPlayerDrawing(player, camera)
			else
				renderPlayerUI(player, camera)
			end
		end
	end

	if StatusLabel and C.Status then
		StatusLabel.Text = statusText()
	end
end)

if haveDrawing then
	print("[VisionWare] ESP loaded (Drawing API)")
else
	warn("[VisionWare] Drawing API not found - using UI fallback.")
	print("[VisionWare] ESP loaded (UI fallback)")
end
