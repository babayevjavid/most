--!strict

local RemoteSetup = require(script.Services.RemoteSetup)
local CharacterSelectService = require(script.Services.CharacterSelectService)

local remotes = RemoteSetup.create()
CharacterSelectService.setup(remotes)

print("[Server] Marvel Testing Place initialized")
