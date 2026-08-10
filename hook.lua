local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteEvent")
local antiFFlagScript

local __namecall; __namecall = hookmetamethod(game, "__namecall", function(self, ...)
    if self == remote then
        local callingScript = getcallingscript()
        local args = table.pack(...)

        if callingScript == antiFFlagScript then
            return
        end

        if args[1] == "clientVersion" then
            antiFFlagScript = callingScript
        end
    end

    return __namecall(self, ...)
end)
