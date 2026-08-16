local UtilityFuncs = {}

function UtilityFuncs.HexToDecimal(hex:string) : number
    hex = hex:lower()
    local num = tonumber(hex, 16)
    assert(num, "Passed string is not a valid hexadecimal number")
    return num
end

function UtilityFuncs.DecimalToHex(num:number) : string
    return string.format("%x", num)
end

function UtilityFuncs.InsertString(str1:string, str2:string, i:number?) : string
	i = i or #str1

	local clippedStr1 = str1:sub(i)
	local clippedStr2 = str1:sub(1, i-1)
	return table.concat({clippedStr2, clippedStr1}, str2)
end

function UtilityFuncs.BetterToStr(val)
    local valType = typeof(val)
        if valType == "table" then
            local str = "{" 
            for key, subVal in pairs(val) do
                if typeof(key) == "number" then
                    str = string.format("%s%s, ", str, UtilityFuncs.BetterToStr(subVal))
                else
                    str = string.format("%s%s = %s, ", str, UtilityFuncs.BetterToStr(key), UtilityFuncs.BetterToStr(subVal))
                end
            end
            str = str:sub(1, str:len() - 2)
            str = string.format("%s}", str)
            return str
        elseif valType == "buffer" then
            return "buffer"
        else
            return tostring(val)
        end
end

-- acts the same as pairs except it preserves holey tables
function UtilityFuncs.hpairs(t)
    local maxIndex = 0
    for k, _ in pairs(t) do
        if type(k) == "number" and k == math.floor(k) and k > maxIndex then
            maxIndex = k
        end
    end
    
    local i = 0
    return function()
        i += 1
        if i > maxIndex then return nil end
        return i, t[i]
    end
end


-- Takes an array of booleans and returns a bit mask in the form of a u8.
function UtilityFuncs.ArrayToBitmasks(arr: {boolean}): {number}
    local bitmasks = {}

    local byteIndex = 1
    local bitCount = 0
    local currentByte = 0

    for _, val in ipairs(arr) do
        local bitIndex = 6 - (bitCount % 7)

        if val then
            currentByte = bit32.bor(currentByte, bit32.lshift(1, bitIndex))
        end

        bitCount += 1

        -- 7 bits, push the byte
        if bitCount % 7 == 0 then
            table.insert(bitmasks, currentByte)
            currentByte = 0
            byteIndex += 1
        end
    end

    -- push remaining bits if any
    if bitCount % 7 ~= 0 then
        table.insert(bitmasks, currentByte)
    end

    -- apply continuation flag
    for i = 1, #bitmasks - 1 do
        bitmasks[i] = bit32.bor(bitmasks[i], 128)
    end

    return bitmasks
end


-- Takes a buffer and position, assuming that corresponds to encrypted bitmasks with a continuation format, and decodes it into an array of true-falses.
function UtilityFuncs.BitmasksToArray(b: buffer, pos: number): {boolean}
    local arr = {}

    local continuation = true
    local maskCount = 0
    while continuation do
        local numRepresentative = buffer.readu8(b, pos)
        maskCount += 1
        for bitOffset = 0, 6 do
            local bitIndex = 6 - bitOffset
            local i = (maskCount - 1) * 7 + bitOffset + 1
            arr[i] = bit32.band(numRepresentative, bit32.lshift(1, bitIndex)) ~= 0
        end
        continuation = bit32.band(numRepresentative, 128) == 128 -- checks if last bit is 1 (continuation)
        pos += 1
    end

    return arr, pos
end


-- given a number of bits, this function will return the number of bytes required to represent that. Output will always be an unsigned int.
function UtilityFuncs.BitSizeToByteSize(bitSize: number) : number
    return (bitSize-1)//8 + 1
end

-- merges buffers b1 into b2 starting at mergeStart, b2 is ordered first sequentially then b1. Mutates b2.
function UtilityFuncs.MergeBufferIntoBuffer(b1: buffer, b2: buffer, mergeStart:number)
    buffer.copy(b2, mergeStart, b1, 0)
end

-- Merges array a into array b. Mutates array b
function UtilityFuncs.MergeArrayIntoArray(a: {[number]: any}, b: {[number]: any})
    table.move(a, 1, #a, #b + 1, b)
end



return UtilityFuncs