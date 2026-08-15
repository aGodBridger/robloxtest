-- // VisionWare Loader
-- // Fetches and runs every script in the list from GitHub, in order.
-- // To add more modules later, just append the filename to the Files table.
local Loader = {
	User = "aGodBridger",            -- GitHub username / owner
	Repo = "robloxtest",             -- Repo name
	Branch = "main",                 -- Branch (main or master)
	Files = {
		"gui.lua",                   -- always first: creates the Library every other script reads
		"esp.lua",
		"chams.lua",
		-- add more files below, e.g. "combat.lua",
	},
	Silent = false,                  -- true = hide "loaded" messages
}

local BaseUrl = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(
	Loader.User, Loader.Repo, Loader.Branch
)
assert(#Loader.Files > 0, "[VisionWare] Loader.Files is empty!")

local function HttpGet(url)
	local ok, result = pcall(game.HttpGet, game, url)
	return ok and result or nil
end

local function RunScript(name, source)
	local ok, compiled = pcall(loadstring, source)
	if not ok or not compiled then
		return nil, "failed to compile: " .. tostring(compiled)
	end
	local ok2, err = pcall(compiled)
	if not ok2 then
		return nil, "errored while running: " .. tostring(err)
	end
	return true
end

local Success, Errors = 0, {}
for _, FileName in ipairs(Loader.Files) do
	local Source = HttpGet(BaseUrl .. FileName)
	if not Source then
		table.insert(Errors, FileName .. " - failed to fetch (check username/repo/branch)")
	else
		local ok, err = RunScript(FileName, Source)
		if ok then
			Success = Success + 1
			if not Loader.Silent then
				print("[VisionWare] Loaded " .. FileName)
			end
		else
			table.insert(Errors, FileName .. " - " .. err)
		end
	end
end

if #Errors > 0 then
	print(("[VisionWare] %d loaded, %d failed"):format(Success, #Errors))
	for _, Err in ipairs(Errors) do
		warn("[VisionWare] " .. Err)
	end
else
	print(("[VisionWare] Loader finished - %d scripts loaded"):format(Success))
	print("[VisionWare] All systems ready! Press END to toggle the menu.")
end