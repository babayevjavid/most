-- Canonical power ids used by UI and server.
export type PowerId = "Electrokinesis" | "Hydrokinesis" | "Chlorokinesis"

local Powers = {
	List = {
		"Electrokinesis",
		"Hydrokinesis",
		"Chlorokinesis",
	} :: { string },
}

function Powers.isValid(name: string): boolean
	for _, id in Powers.List do
		if id == name then
			return true
		end
	end
	return false
end

return Powers
