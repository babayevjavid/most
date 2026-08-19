--!strict

local UIController = require(script.Controllers.UIController)
local InputController = require(script.Controllers.InputController)
local ShieldClient = require(script.ShieldClient)
local BeamClient = require(script.BeamClient)
local FlightClient = require(script.FlightClient)
local TelekinesisClient = require(script.TelekinesisClient)

UIController.init()
InputController.setup()
TelekinesisClient.setup()
ShieldClient.setup()
BeamClient.setup()
FlightClient.setup()

print("[Client] Marvel Testing Place initialized")
