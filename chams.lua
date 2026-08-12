-- // VisionWare Chams

local connectionList = {}

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
				if data.hide and table.find(data.hide, part) then
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
		end
	end
end))

print("[VisionWare] Chams Loaded!")