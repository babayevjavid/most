return function(attachmentMap, characterRoot: BasePart?)
	local folder = Instance.new("Folder")
	folder.Name = "NoCollisionConstraints"
	if not characterRoot then
		return folder
	end

	local seen = {}
	local function pairKey(a: BasePart, b: BasePart): string
		local aPath = a:GetFullName()
		local bPath = b:GetFullName()
		if aPath < bPath then
			return aPath .. "|" .. bPath
		end
		return bPath .. "|" .. aPath
	end
	for _, jointData in pairs(attachmentMap) do
		local p0 = jointData.Attachment0 and jointData.Attachment0.Parent
		local p1 = jointData.Attachment1 and jointData.Attachment1.Parent
		if p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") and p0 ~= p1 then
			local key = pairKey(p0, p1)
			if not seen[key] then
				seen[key] = true
				local ncc = Instance.new("NoCollisionConstraint")
				ncc.Name = p0.Name .. "<->" .. p1.Name
				ncc.Part0 = p0
				ncc.Part1 = p1
				ncc.Parent = folder
			end
		end
	end

	return folder
end
