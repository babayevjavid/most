local function getLastWordFromPascalCase(value: string): string
	local words = {}
	for word in string.gmatch(value, "%u[%l%d]*") do
		table.insert(words, word)
	end
	if #words == 0 then
		return value
	end
	return words[#words]
end

return getLastWordFromPascalCase

