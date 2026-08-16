local BitWorkerModule = script.Parent.Parent.Parent
local Utils = require(BitWorkerModule.UtilityFuncs)

local HEX = {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"}


local strCompressor = {}

local function isUncompressedGuid() : boolean
    return false -- placeholder
end

local function isCompressedGuid(str:string) : boolean
    for i = 1, #str, 1 do -- Ensure all characters in the GUID are valid hexadecimal digits
		local char = str:sub(i, i)
		if not table.find(HEX, char) then
			if char == "{" or char == "}" or char == "-" then
				continue
			else
				return false
			end
		end
	end

	return true
end

function guidCompress(guid:string) : string
    local offset = 0 -- Moves the index up to skip non hex characters
	guid = guid:lower()
	local compressedGuid = ""
	local isCurly = false

	for i = 1,  #guid, 2 do
		local root = guid:sub(i + offset, i + offset)

		if root == "" or i + offset >= #guid then 
			break
		elseif root == "{" then 
			isCurly = true 
            offset += 1
		elseif root == "}" then
			break
		elseif root == "-" then
			offset += 1
		end

		local octet = guid:sub(i+offset, i+offset+1)
		local num = Utils.HexToDecimal(octet)
		compressedGuid = string.format("%s%s", compressedGuid, string.char(num))
	end

	if isCurly then
		compressedGuid = Utils.InsertString(compressedGuid, string.char(1), 1)
	else
		compressedGuid = Utils.InsertString(compressedGuid, string.char(0), 1)
	end

	return compressedGuid
end

function guidDecode(guid:string) : string
    local decodedGuid = ""
	local isCurly = string.byte(guid,1,1) == 1

	local function packCodePoints(...) : {[number] : number}
		local numTable = {}
		for _, num in ipairs({...}) do
			table.insert(numTable, num)
		end

		return numTable
	end

	local nums = packCodePoints(string.byte(guid, 2, -1))

	for _, num in ipairs(nums) do
		local octet = Utils.DecimalToHex(num)
		if #octet == 1 then
			octet = string.format("%s%s", "0", octet)
		end
		decodedGuid = string.format("%s%s", decodedGuid, octet)
	end

	-- Adding GUID hyphons
	decodedGuid = Utils.InsertString(decodedGuid, "-", 21)
	decodedGuid = Utils.InsertString(decodedGuid, "-", 17)
	decodedGuid = Utils.InsertString(decodedGuid, "-", 13)
	decodedGuid = Utils.InsertString(decodedGuid, "-", 9)
	if isCurly then
		decodedGuid = Utils.InsertString(decodedGuid, "{", 1)
		decodedGuid = Utils.InsertString(decodedGuid, "}", #decodedGuid + 1)
	end

	return decodedGuid
end

function strCompressor.Compress(val:string, isGuid:boolean)
    local compressedStr = nil

    if isGuid then
        compressedStr = guidCompress(val)
    end

    return compressedStr or val
end

function strCompressor.Decompress(val:string, isGuid:boolean)
    local decompressedStr = nil

    if isGuid then
        decompressedStr = guidDecode(val)
    end

    return decompressedStr or val
end

return strCompressor