local stringCompressor = require(script._StringCompressor)

local Compressor = {}

function Compressor.Compress(val, valType: string?)
    local t = valType or typeof(val)
    local compressedVal = nil

    if t == "string" then
        compressedVal = stringCompressor.Compress(val, false)
    elseif t == "Guid" or t == "CurlyGuid" then
        compressedVal = stringCompressor.Compress(val, true)
    end

    return compressedVal or val
end

function Compressor.Decompress(val:any, valType: string?)
    local t = valType or typeof(val)
    local decompressedVal = nil

    if t == "string" then
        decompressedVal = stringCompressor.Decompress(val, false)
    elseif t == "Guid" or t == "CurlyGuid" then
        decompressedVal = stringCompressor.Decompress(val, true)
    end

    return decompressedVal or val
end


return Compressor