-- Backwards-compatible alias for older code that expects `Shared:WaitForChild("Config")`.
-- This simply exposes the same table as `RagdollConfig`.
local shared = script.Parent
local ragdollConfig = require(shared:WaitForChild("RagdollConfig"))
return ragdollConfig

