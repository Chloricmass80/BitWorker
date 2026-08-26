local BitWorkerModule = script.Parent.Parent

local Utils = require(BitWorkerModule.UtilityFuncs)
local Compressor = require(script.Parent.Compressor)
local ErrMessages = require(BitWorkerModule.ErrorMessages)

type TagIdReadFunc = (b: buffer, offset: number) -> (number)
type TagIdWriteFunc = (b: buffer, offset: number, val: number) -> ()


local TAG_ID_SIZE = 1
local tagIdBitSize = TAG_ID_SIZE * 8
local maxTagCount = (2 ^ tagIdBitSize) - 1
local tagIdSizeStr = tostring(tagIdBitSize)
local TAG_ID_READ: TagIdReadFunc = buffer[string.format("readu%s", tagIdSizeStr)]
local TAG_ID_WRITE: TagIdWriteFunc = buffer[string.format("writeu%s", tagIdSizeStr)]

type MetaType = {
    fieldSizes : {number | MetaType}; -- sizes of each field, or if a sub-table, the sub-meta data.
    subByteFields : {string | number}; -- stores the sub-byte fields sequentially, in the order of valueIndex, valType, first index is the bit size of all combined
    totalSize : number; -- payload size (includes tag identifiers, bitmasks, etc. this is good for trusting with buffer size)
    nonDynamicSize : number; -- the totalSize subtracted by the size of string indicies
    stringCount : number; -- the number of strings in the tag
    valReadFuncs : {(b: buffer, offset: number) -> (any)}; -- the read function of each val index
    valWriteFuncs : {(b: buffer, offset: number, val: any) -> ()}; -- the write function of each val index
    dynamic : boolean; -- does this table, or any descendant table, have a string value?
    sparse : boolean; -- is THIS table sparse?
    deepSparse : boolean; -- is any descendant table sparse?
    repetitive : boolean; -- is this table repetitive (variable # of arguments)?
    mask : {bitMask: number, arrayMask: {boolean}}?; -- never filled for non-per-request generated meta data.
    repetitions : number? -- number of repetitions in a repetitive table (never filled for non-per-request generated meta data).
}

type handlerFunc = (args: {any}) -> () & (plyr: Player, args: {any}) -> () 

type Packet = {
    tagName : string;
    data : {any}
}

local Series = {
    debugMode = false
}
Series.__index = Series

local handlers : {handlerFunc} = {}
-- Schema is global so the tag registery is shared between all series.
local tagRegistery = {} -- keyed by tag name, {num, valTypes, meta}
local tagNumLookup = {} -- keyed by tag number, tagName
local tagCount = 0

local lengthLookup = {
    u8 = 1;
    u16 = 2;
    u32 = 4;
    i8 = 1;
    i16 = 2;
    i32 = 4;
    f32 = 4;
    f64 = 8;
    guid = 17;
    --boolean = 1;
    u1 = -1;
    u2 = -2;
    u3 = -3;
    u4 = -4;
    u5 = -5;
    u6 = -6;
    u7 = -7;
    boolean = -1;
}

local function sharedNumberValidity(val: any, valType: string, tagName: string)
    local typeVal = type(val)
    if typeVal ~= "number" then
        error(string.format("Passed value representing %s on tag %s is of invalid type. Expected number, got %s (%s)."..ErrMessages.Unpredictable, valType, tagName, tostring(val), typeVal))
    end
end

local function checkNumberRange(val: number, valType: string, tagName: string, minRange: number, maxRange: number)
    if val < minRange or val > maxRange then
        error(string.format("Passed number representing %s on tag %s is out of 8-bit range. Expected a number between %s-%s, got %s."..ErrMessages.Unpredictable, valType, tagName, tostring(minRange), tostring(maxRange), tostring(val)))
    end
end

local function checkInteger(val: number, valType: string, tagName: string)
    local flr = math.floor(val)
    if flr ~= val then
        warn(string.format("Passed number representing %s on tag %s is a decimal value (float), the serializer must round it. Got %s, sending across the network as %s"..ErrMessages.Unpredictable), valType, tagName, tostring(val), tostring(flr))
        return flr
    end

    return val
end

local function sharedStringValidity(val: any, valType: string, tagName: string)
    local typeVal = type(val)
    if typeVal ~= "string" then
        error(string.format("Passed value representing %s on tag %s is of invalid type. Expected string, got %s (%s)."..ErrMessages.Unpredictable, valType, tagName, tostring(val), typeVal))
    end
end

local validityFuncs = {
    u1 = function(val: any, tagName: string)
        local valType = "u1"
        sharedNumberValidity(val, valType, tagName)
        checkNumberRange(val, valType, tagName, 0, 1)
        val = checkInteger(val, valType, tagName)

        return val
    end;
    u2 = function(val: any, tagName: string)
        local valType = "u2"
        sharedNumberValidity(val, valType, tagName)
        checkNumberRange(val, valType, tagName, 0, 3)
        val = checkInteger(val, valType, tagName)

        return val
    end;
    u3 = function(val: any, tagName: string)
        local valType = "u3"
        sharedNumberValidity(val, valType, tagName)
        checkNumberRange(val, valType, tagName, 0, 7)
        val = checkInteger(val, valType, tagName)

        return val
    end;
    u4 = function(val: any, tagName: string)
        local valType = "u4"
        sharedNumberValidity(val, valType, tagName)
        checkNumberRange(val, valType, tagName, 0, 15)
        val = checkInteger(val, valType, tagName)

        return val
    end;
    u5 = function(val: any, tagName: string)
        local valType = "u5"
        sharedNumberValidity(val, valType, tagName)
        checkNumberRange(val, valType, tagName, 0, 31)
        val = checkInteger(val, valType, tagName)

        return val
    end;
    u6 = function(val: any, tagName: string)
        local valType = "u6"
        sharedNumberValidity(val, valType, tagName)
        checkNumberRange(val, valType, tagName, 0, 63)
        val = checkInteger(val, valType, tagName)

        return val
    end;
    u7 = function(val: any, tagName: string)
        local valType = "u7"
        sharedNumberValidity(val, valType, tagName)
        checkNumberRange(val, valType, tagName, 0, 127)
        val = checkInteger(val, valType, tagName)

        return val
    end;
    boolean = function(val: any, tagName: string)
        local typeVal = type(val)
        if typeVal ~= "boolean" then
            error(string.format("Passed value representing boolean is of invalid type. Expected boolean, got %s (%s)."..ErrMessages.Unpredictable, tostring(val), typeVal))
        end

        return val
    end;
    u8 = function(val: any, tagName: string)
        local valType = "u8"
        sharedNumberValidity(val, valType, tagName)
        checkNumberRange(val, valType, tagName, 0, 0xFF)
        val = checkInteger(val, valType, tagName)

        return val
    end;
    u16 = function(val: any, tagName: string)
        local valType = "u16"
        sharedNumberValidity(val, valType, tagName)
        checkNumberRange(val, valType, tagName, 0, 0xFFFF)
        val = checkInteger(val, valType, tagName)

        return val
    end;
    u32 = function(val: any, tagName: string)
        local valType = "u32"
        sharedNumberValidity(val, valType, tagName)
        checkNumberRange(val, valType, tagName, 0, 0xFFFFFFFF)
        val = checkInteger(val, valType, tagName)

        return val
    end;
i8 = function(val: any, tagName: string)
        local valType = "i8"
        sharedNumberValidity(val, valType, tagName)
        checkNumberRange(val, valType, tagName, -128, 127)
        val = checkInteger(val, valType, tagName)

        return val
    end;
    i16 = function(val: any, tagName: string)
        local valType = "i16"
        sharedNumberValidity(val, valType, tagName)
        checkNumberRange(val, valType, tagName, -32768, 32767)
        val = checkInteger(val, valType, tagName)

        return val
    end;
    i32 = function(val: any, tagName: string)
        local valType = "i32"
        sharedNumberValidity(val, valType, tagName)
        checkNumberRange(val, valType, tagName, -2147483648, 2147483647)
        val = checkInteger(val, valType, tagName)

        return val
    end;
    f32 = function(val: any, tagName: string)
        local valType = "f32"
        sharedNumberValidity(val, valType, tagName)

        return val
    end;
    f64 = function(val: any, tagName: string)
        local valType = "f64"
        sharedNumberValidity(val, valType, tagName)

        return val
    end;
    guid = function(val: any, tagName: string)
        local valType = "guid"
        sharedStringValidity(val, valType, tagName)

        return val
    end;
    string = function(val: any, tagName: string)
        local valType = "string"
        sharedStringValidity(val, valType, tagName)

        return val
    end;
    instance = function(val: any, tagName: string)
        local valType = "instance"
        local typeVal = typeof(val)
        if typeVal ~= "Instance" then
            error(string.format("Passed value representing %s on tag %s is of invalid type. Expected Instance, got %s (%s)."..ErrMessages.Unpredictable, valType, tagName, tostring(val), typeVal))
        end

        return val
    end
}

local bWriteFuncs = {
    u8 = buffer.writeu8,
    u16 = buffer.writeu16,
    u32 = buffer.writeu32,
    i8 = buffer.writei8,
    i16 = buffer.writei16,
    i32 = buffer.writei32,
    f32 = buffer.writef32,
    f64 = buffer.writef64,
    guid = function(b: buffer, offset: number, val) -- GUID requires mutation before buffer assignment, cannot be a direct alias.
        val = Compressor.Compress(val, "Guid")
        buffer.writestring(b, offset, val)
    end,
}

local bReadFuncs = {
    u8 = buffer.readu8,
    u16 = buffer.readu16,
    u32 = buffer.readu32,
    i8 = buffer.readi8,
    i16 = buffer.readi16,
    i32 = buffer.readi32,
    f32 = buffer.readf32,
    f64 = buffer.readf64,
    guid = function(b: buffer, offset: number) -- GUID requires mutation after buffer extraction, cannot be a direct alias.
        local val = buffer.readstring(b, offset, 17)
        return Compressor.Decompress(val, "Guid")
    end,
}

function Series.new()
    local self = setmetatable({
        _requests = {};
        _instances = {};
        _currentPayloadSize = 0
    }, Series)

    return self
end

function Series.AddHandler(tagName:string, fn : handlerFunc)
    handlers[tagName] = fn
end

local function bakeTypeMeta(tagConfig:{any}?, tagName:string, isRecursive: boolean?) : MetaType
    local valTypes = table.clone(tagConfig) -- If the caller keeps the tag config it isn't mutated

    local meta : MetaType = {
        fieldSizes = {},
        subByteFields = {0},
        totalSize = 0,
        nonDynamicSize = 0,
        stringCount =  0,
        valReadFuncs = {};
        valWriteFuncs = {};
        dynamic = false,
        sparse = false,
        deepSparse = false,
        repetitive = false
    }
    
    local flagIndicies = {}

    for i=1, #valTypes do
        local valType = valTypes[i]
        if valType == "SPARSE" then
            meta.sparse = true
            meta.deepSparse = true
            table.insert(flagIndicies, i)
        elseif valType == "..." then
            meta.repetitive = true
            meta.dynamic = true
            meta.totalSize = nil
            table.insert(flagIndicies, i)
        end
    end

    -- remove flag mentions ("SPARSE", "...")
    for i=#flagIndicies, 1, -1 do -- Reverse in-place removal to avoid making the sparse index table out-dated
        local flagIndex = flagIndicies[i]
        table.remove(valTypes, flagIndex)
    end

    for i=1, #valTypes do
        local valType = valTypes[i]
        if typeof(valType) == "table" then
            local subMeta, valType = bakeTypeMeta(valType, tagName, true)
            valTypes[i] = valType
            meta.stringCount += subMeta.stringCount
            meta.fieldSizes[i] = subMeta
            if subMeta.dynamic then
                meta.dynamic = true
                meta.totalSize = nil -- totalSize = nil in the baked meta is a redundant sentinal that means that the tag is dynamic. Nil for lack of a better value.
            end
            if subMeta.deepSparse then
                meta.deepSparse = true
            end
        elseif valType == "string" then
            meta.dynamic = true
            meta.totalSize = nil
            meta.fieldSizes[i] = 0
            meta.stringCount += 1
        elseif valType == "instance" then
            continue
        else
            local sz = lengthLookup[valType]
            if sz == nil then
                warn("Malformed TLV tag config detected. TagName: " .. tagName .. " Malformed value type: " .. tostring(valType) .. ErrMessages.Unpredictable)
            elseif sz < 0 then
                table.insert(meta.subByteFields, i)
                table.insert(meta.subByteFields, valType)
                local bitSize = -sz
                meta.subByteFields[1] += bitSize
            else
                meta.valReadFuncs[i] = bReadFuncs[valType]
                meta.valWriteFuncs[i] = bWriteFuncs[valType]
                if not meta.dynamic then meta.totalSize += sz end
            end
            meta.fieldSizes[i] = sz
            meta.nonDynamicSize += sz
        end
    end


    if not meta.dynamic then
        local subByteSize = Utils.BitSizeToByteSize(meta.subByteFields[1])

        meta.totalSize += subByteSize
        meta.nonDynamicSize += subByteSize
        if not isRecursive then meta.totalSize += TAG_ID_SIZE end -- account for tag identifier
    end

    return meta, valTypes
end

local function validateNewTag(tagName: string) : boolean
    if tagRegistery[tagName] then 
        warn(string.format("TLV Tag Duplicate by name %s rejected."..ErrMessages.CallIgnored), tagName)
        return false
    end
    if tagCount == maxTagCount then
        warn(string.format("TLV Tag by name %s dropped, max tag count reached."..ErrMessages.Unpredictable), tagName)
        return false
    end

    return true
end

function Series._AddTag(tagName:string, tagConfig:{any}?)
    if Series.debugMode then
        if not validateNewTag(tagName) then return end
    end

    tagCount += 1
    tagNumLookup[tagCount] = tagName
    local bakedMetaData, valTypes
    if tagConfig then bakedMetaData, valTypes = bakeTypeMeta(tagConfig, tagName) end
    tagRegistery[tagName] = {tagCount, valTypes, bakedMetaData}
end

local function mapRepetitiveIndexToConfig(repetitive: boolean, i: number, valTypeTable : {string | {string}}) : (number)
    local valTypei = i
    if repetitive then
        valTypei = i % #valTypeTable
        if valTypei == 0 then valTypei = #valTypeTable end
    end

    return valTypei
end

-- Resolves the length of a sparse table in repetitive terms, so the repetitive tag can properly understand what it's length is in a way that repetitive logic will work with.
local function getSparseRepetitiveLength(lenValTable: number, valTypeTableLen: number)
    if lenValTable ~= 0 then
        local mod = lenValTable % valTypeTableLen
        if mod ~= 0 then
            lenValTable += (valTypeTableLen - (mod)) -- if it's sparse, lenValTable might be short and not include nils at the end of the table, this just makes sure that's included
        end
    else
        lenValTable = valTypeTableLen
    end

    return lenValTable
end


local function assertValueValidity(value: any, valType: string, tagName: string)
    local validityFunc = validityFuncs[valType]
    if validityFunc then
        return validityFunc(value, tagName)
    else -- table
        local typeVal = type(value)
        if typeVal ~= "table" then
            error(string.format("Passed value representing %s on tag %s is of invalid type. Expected table, got %s (%s)."..ErrMessages.Unpredictable, Utils.BetterToStr(valType), tagName, tostring(value), typeVal))
        end
        return value
    end
end

local function generatePerRequestMeta(valTable: {any}, valTypeTable : {string | {string}}, metaData:MetaType, tagName:string, isRecursive: boolean?) : MetaType
    if not metaData then return false end -- false is a sentinel for when the tag does not carry any data with it.
    if not metaData.dynamic and not metaData.sparse and not metaData.deepSparse then
        return metaData
    end
    local generatedMeta:MetaType = {
        totalSize = 0,
        nonDynamicSize = metaData.nonDynamicSize,
        stringCount = metaData.stringCount,
        valReadFuncs = metaData.valReadFuncs,
        valWriteFuncs = metaData.valWriteFuncs,
        fieldSizes = {},
        subByteFields = {0},
        dynamic = metaData.dynamic,
        sparse = metaData.sparse,
        deepSparse = metaData.deepSparse,
        repetitive = metaData.repetitive,
        repetitions = 1
    }
    local arrayMask = {}

    local function accumulateField(val: any, i: number, valTypei: number?)
        valTypei = valTypei or i
        local valType = valTypeTable[valTypei]
        if Series.debugMode then val = assertValueValidity(val, valType, tagName) end
        if valType == "instance" then
            return
        elseif typeof(valType) == "table" then
            local subMeta = generatePerRequestMeta(val, valType, metaData.fieldSizes[valTypei], tagName, true)
            generatedMeta.fieldSizes[i] = subMeta
            generatedMeta.totalSize += subMeta.totalSize
        else
            local sz = metaData.fieldSizes[valTypei]
            if sz < 0 then
                local bitSize = -sz
                table.insert(generatedMeta.subByteFields, i)
                table.insert(generatedMeta.subByteFields, valType)
                generatedMeta.subByteFields[1] += bitSize
            else
                generatedMeta.totalSize += sz
            end
            generatedMeta.fieldSizes[i] = sz
        end  
    end

    if metaData.repetitive then
        local lenValTable = table.maxn(valTable)
        if metaData.sparse then
            lenValTable = getSparseRepetitiveLength(lenValTable, #valTypeTable)
        end
        if lenValTable % #valTypeTable ~= 0 then
            error("RECURSE attempted to pass misorganized/malformed values into a repetitive network table. Offending tag: " .. tagName .. ".\n"..
            "expected format: " .. Utils.BetterToStr(valTypeTable, ", ") .. " ...\n"..
            "given values: " .. Utils.BetterToStr(valTable, ", ")..ErrMessages.Unpredictable)
        end
        local repetitions = (lenValTable / #valTypeTable)
        if repetitions > 255 then
            warn("Max repeitions of 255 surpassed. Offending tag: " .. tagName .. ". Dropping packet."..ErrMessages.Unpredictable)
            return
        end
        generatedMeta.repetitions = repetitions
        generatedMeta.totalSize += 1 -- for repetition count byte
    end

    if metaData.dynamic then
        local pFunc
        if metaData.sparse then
            pFunc = Utils.hpairs
        else
            pFunc = ipairs
        end
        for ri=1, generatedMeta.repetitions do
            local mappediSum = ((ri-1) * #valTypeTable) 
            for i=1, #valTypeTable do
                local mappedi = i + mappediSum
                local val = valTable[mappedi]
                if val ~= nil then
                    arrayMask[mappedi] = true
                    local valType = valTypeTable[i]
                    local sz = metaData.fieldSizes[i]
                    if sz ~= 0 then
                        accumulateField(val, mappedi, i)
                    elseif valType == "string" then
                        local sz = string.len(val)
                        if sz > 0xFF then
                            warn("Maximum network string length surpassed by the following string:\n"
                            .. val .. ErrMessages.CallIgnored)
                            return
                        end

                        generatedMeta.fieldSizes[mappedi] = sz
                        generatedMeta.totalSize += (sz + 1) -- 1 for string length identifier
                    else
                        error("Malformed TLV tag metadata under tag " .. tagName .. " detected. Expect major networking errors.." .. ErrMessages.Unpredictable)
                    end
                else                
                    arrayMask[mappedi] = false
                end
            end
        end
    elseif metaData.sparse then
        for i=1, #valTypeTable do
            local val = valTable[i]
            if val ~= nil then
                arrayMask[i] = true
                accumulateField(val, i)                  
            else
                arrayMask[i] = false
            end
        end
    elseif metaData.deepSparse then
        for i=1, #valTable do
            local val = valTable[i]
            accumulateField(val, i)
        end
    end

    if metaData.sparse then
        generatedMeta.mask = {bitMask = Utils.ArrayToBitmasks(arrayMask), arrayMask = arrayMask}
        local bitMaskLength = #generatedMeta.mask.bitMask
        generatedMeta.totalSize += bitMaskLength
    end

    generatedMeta.totalSize += Utils.BitSizeToByteSize(generatedMeta.subByteFields[1])
    if not isRecursive then generatedMeta.totalSize += TAG_ID_SIZE end -- tag identifier


    return generatedMeta
end

local function validateNetworkStruct(value: {any}, metaData: MetaType, tagName: string, valTypes: {string | {string}}) : boolean
    for i, element in pairs(value) do
        if typeof(i) ~= "number" then
            warn(string.format("RECURSE attempted an invalid TLV request type: Dictionary. Tag name: %s."..ErrMessages.Unpredictable, tagName))
            return false
        elseif element == nil and metaData.sparse == false then
            warn(string.format("RECURSE attempted to pass a nil value through a %s slot without a sparse identifier in the tag config. Tag name: %s."..ErrMessages.Unpredictable, valTypes[i], tagName))
            return false
        elseif Series.debugMode and type(element) == "table" then
            return validateNetworkStruct(element, metaData, tagName)
        end
    end

    return true
end

function Series._ProcessRequestData(tagName:string, value:any) : any
    local tagEntry = tagRegistery[tagName]
    if tagEntry == nil then
        warn(string.format("RECURSE could not find tag by name %s when prompted to create a TLV request."..ErrMessages.Unpredictable, tagName))
        return
    end

    local tagNum, valTypes, metaData = tagEntry[1], tagEntry[2], tagEntry[3]


    local processedValue = nil

    if type(value) == "table" then
        if not validateNetworkStruct(value, metaData, tagName, valTypes) then return end
        processedValue = table.clone(value) -- cloning the table is a safety protocal to make sure that the caller can't change passed data between receiving a request and sending it across the network.
    else
        processedValue = value
    end
    local request = {}

    local generatedMetaData = generatePerRequestMeta(processedValue, valTypes, metaData, tagName)
    if generatedMetaData == nil then
        return
    elseif generatedMetaData == false then
        request[1], request[2], request[3] = tagNum, processedValue, generatedMetaData
        return request
    end
    request[1], request[2], request[3] = tagNum, processedValue, generatedMetaData

    return request
end

function Series:AddRequest(tagName:string, value:any, requestTable:any?)
    if requestTable then
        table.insert(self._requests, requestTable)
        return requestTable
    end
    
    local request = self._ProcessRequestData(tagName, value)
    if not request then return end
    if request[3] == false then
        self._currentPayloadSize += TAG_ID_SIZE
    else
        self._currentPayloadSize += request[3].totalSize
    end

    table.insert(self._requests, request)

    return request
end

function Series:RemoveLastRequest() : {any}
    local request = self._requests[#self._requests]
    self._requests[#self._requests] = nil

    return request
end

function Series:ReadRequestSize(request) : number
    local metaData:MetaType = request[3]
    if not metaData then return end
    return metaData.totalSize
end


local function makeBitWriter(b: buffer, startPos: number)
    local acc, bitCount, pos = 0, 0, startPos
    return {
        write = function(value: number, width: number)
            value = bit32.band(value, bit32.lshift(1, width) - 1) -- clamp to width, see note below
            acc = bit32.bor(acc, bit32.lshift(value, bitCount))
            bitCount += width
            while bitCount >= 8 do
                buffer.writeu8(b, pos, bit32.band(acc, 0xFF))
                acc = bit32.rshift(acc, 8)
                bitCount -= 8
                pos += 1
            end
        end,
        finish = function() -- flush a trailing partial byte, if any
            if bitCount > 0 then
                buffer.writeu8(b, pos, bit32.band(acc, 0xFF))
                pos += 1
            end
            return pos
        end,
    }
end

function Series._serializeRequest(tagNum:number, vals:{any}, metaData:MetaType, b: buffer, pos: number, subTypes:{string}?, instances:{Instance}?) -- subTypes are non-nil only on recursive calls
    if not vals then return pos, instances end
    local tagName = tagNumLookup[tagNum]
    local tagEntry = tagRegistery[tagName]
    local valTypes = tagEntry[2]

    valTypes = subTypes or valTypes
    instances = instances or {}

    local valsLen = #vals

    if metaData.repetitive then
        buffer.writeu8(b, pos, metaData.repetitions)
        pos += 1
    end

    if metaData.sparse and metaData.repetitions ~= 0 then
        for i = 1, #metaData.mask.bitMask do
            local maskByte = metaData.mask.bitMask[i]
            buffer.writeu8(b, pos, maskByte)
            pos += 1
        end
        valsLen = table.maxn(vals)
    end


    if metaData.subByteFields[1] ~= 0 then
        local bitWriter = makeBitWriter(b, pos)
        for i = 2, #metaData.subByteFields, 2 do
            local valIndex = metaData.subByteFields[i]
            local valType = metaData.subByteFields[i+1]
            local val = vals[valIndex]
            local width = -metaData.fieldSizes[valIndex]

            if valType == "boolean" then
                if val == true then val = 1 else val = 0 end
            end

            bitWriter.write(val, width)
        end
        pos = bitWriter.finish()
    end

    for ri=1, metaData.repetitions or 1 do 
        local mappediSum = ((ri-1) * #valTypes) 
        for i=1, #valTypes do
            local mappedi = i + mappediSum
            local valType = valTypes[i]
            local size = metaData.fieldSizes[mappedi]
            local val = vals[mappedi]
            if val == nil then continue end

            if valType == "string" then
                buffer.writeu8(b, pos, size) -- strings are length-prefixed because string sizes aren't in the schema, without a prefix the receiver wouldn't be able to reckon where string data starts and ends.
                pos += 1
                buffer.writestring(b, pos, val)
                pos += size
            elseif valType == "instance" then
                table.insert(instances, val)
            elseif typeof(valType) == "table" then
                local subMeta = size
                pos = Series._serializeRequest(tagNum, val, subMeta, b, pos, valType, instances)
            else
                if size > 0 then
                    metaData.valWriteFuncs[i](b, pos, val)
                    pos += size
                end
            end
        end
    end
    return pos, instances
end

function Series._SerializeTag(b: buffer, pos: number, request)
    local tagNum = request[1]
    TAG_ID_WRITE(b, pos, tagNum) -- tag identifier
    pos += TAG_ID_SIZE
    local vals = request[2]
    local metaData = request[3]
    if metaData == false then return pos end
    return  Series._serializeRequest(tagNum, vals, metaData, b, pos)
end

-- Return an estimate of what the raw cost of the data that would be sent given a buffer or payloadSize and an array of instances
function Series.GetPacketSize(b: buffer?, payloadSize:number, instances: {Instance}?) : number
    local size
    if b then
        size = buffer.len(b)
    else
        size = payloadSize
    end
    if not size then
        error("Pass at least a buffer or a number representing buffer size. Must be one."..ErrMessages.Unpredictable)
    end
    if instances and #instances ~= 0 then
        size += 2
        size += (#instances * 4)
    end

    return size
end

function Series:EstimateSize() : number
    return self.GetPacketSize(nil, self._currentPayloadSize, self._instances)
end

function Series:Serialize() : buffer
    if #self._requests == 0 then return end

    local size = self._currentPayloadSize
    
    local b = buffer.create(size)
    local pos = 0

    for i=1, #self._requests do
        local request = self._requests[i]
        local instances
        pos, instances = self._SerializeTag(b, pos, request)
        if not instances then continue end
        Utils.MergeArrayIntoArray(instances, self._instances)
    end

    return b, self._instances, Series.GetPacketSize(b, nil, self._instances)
end


function Series.SerializeOnce(tag: string, value: any, request: any?) : (buffer?, {Instance}?, number?)
    request = request or Series._ProcessRequestData(tag, value)
    if not request then return end
    local size 
    if request[3] == false then
        size = TAG_ID_SIZE
    else
        size = request[3].totalSize
    end
    local b = buffer.create(size)

    local _, instances = Series._SerializeTag(b, 0, request)

    return b, instances, Series.GetPacketSize(b, nil, instances)
end

local function makeBitReader(b: buffer, startPos: number)
    local acc, bitCount, pos = 0, 0, startPos
    return {
        read = function(width: number): number
            while bitCount < width do
                acc = bit32.bor(acc, bit32.lshift(buffer.readu8(b, pos), bitCount))
                bitCount += 8
                pos += 1
            end
            local value = bit32.band(acc, bit32.lshift(1, width) - 1)
            acc = bit32.rshift(acc, width)
            bitCount -= width
            return value
        end,
        finish = function(): number
            return pos
        end,
    }
end


local function bitFieldSize(subByteFields: {number | string}, arrayMask: {boolean}, valTypes : {string | {string}}, fieldSizes: {number}, repetitions: number) : number
    repetitions = repetitions or 1
    if arrayMask == nil then return subByteFields[1] * repetitions end -- if not sparse then no mask exists and it cannot cover the sub-byte fields, so therefore the field size is just that of the baked bitSize.
    local bitSize = 0

    for ri = 1, repetitions do
        local mappediSum = ((ri-1) * #valTypes)
        for i = 2, #subByteFields, 2 do
            local subByteIndex = subByteFields[i]
            local subByteValIndex = subByteIndex + mappediSum
            if arrayMask[subByteValIndex] == true then
                bitSize -= fieldSizes[subByteIndex] -- subtraction because sub-byte values have negative sizes to represent a bit size instead of a byte size
            end
        end
    end

    return bitSize
end

function Series._DeserializeTag(b:buffer, instances:{Instance}?, instanceStartIndex:number, tagStartPos:number, valTypes:{string | {string}}?, metaData:MetaType?)
    local deserializedData = {}
    local pos = tagStartPos
    local instancePos = instanceStartIndex
    local tagName
    local stringsRead = 0
    if valTypes == nil then
        local tagNum = TAG_ID_READ(b, pos)
        pos += TAG_ID_SIZE
        tagName = tagNumLookup[tagNum]
        local tagEntry = tagRegistery[tagName]
        valTypes, metaData = tagEntry[2], tagEntry[3]
    end
    if valTypes == nil then return nil, pos, instancePos, tagName end
    if #valTypes == 0 then return {}, pos, instancePos, tagName end

    local repetitions = 1
    if metaData.repetitive then
        repetitions = buffer.readu8(b, pos)
        pos += 1
    end

    local arrayMask
    if metaData.sparse then
        arrayMask, pos = Utils.BitmasksToArray(b, pos)
    end

    local bitReader
    if metaData.subByteFields[1] ~= 0 and repetitions ~= 0 then
        local bitSize = bitFieldSize(metaData.subByteFields, arrayMask, valTypes, metaData.fieldSizes, repetitions)
        if bitSize ~= 0 then
            bitReader = makeBitReader(b, pos)
            pos += Utils.BitSizeToByteSize(bitSize)
        end
    end



    for ri = 1, repetitions do
        local mappediSum = ((ri-1) * #valTypes)
        for i=1, #valTypes do
            local mappedi = i + mappediSum
            local valType = valTypes[i]
            if arrayMask and arrayMask[mappedi] == false then continue end
            if typeof(valType) == "table" then
                local deserializedTable, newPos, _, _, tableStrings = Series._DeserializeTag(b, instances, instancePos, pos, valType, metaData.fieldSizes[i])
                stringsRead += tableStrings
                pos = newPos
                deserializedData[mappedi] = deserializedTable
            elseif valType == "string" then
                local valSize = buffer.readu8(b, pos)
                pos += 1
                local val = buffer.readstring(b, pos, valSize)
                deserializedData[mappedi] = val
                pos += valSize
                stringsRead += 1
            elseif valType == "instance" then
                deserializedData[mappedi] = instances[instancePos]
                instancePos += 1
            else
                local valSize = metaData.fieldSizes[i]

                if valSize > 0 then -- byte val
                    local val = metaData.valReadFuncs[i](b, pos)
                    deserializedData[mappedi] = val
                    pos += valSize
                elseif valSize < 0 then -- bit val
                    local width = -valSize
                    local val = bitReader.read(width)
                    if valType == "boolean" then
                        if val == 1 then val = true else val = false end
                    end
                    deserializedData[mappedi] = val
                end
            end
        end
    end

    return deserializedData, pos, instancePos, tagName, stringsRead
end

function Series.Deserialize(plyr: Player?, b:buffer, instances : {Instance}?) : {Packet}
    local deserializedPackets = {}
    local size = buffer.len(b)
    local pos = 0
    local instancePos = 1
    while pos < size do
        local data, newPos, newInstancePos, tagName = Series._DeserializeTag(b, instances, instancePos, pos)
        local packet = {tagName = tagName, data = data}
        pos = newPos
        instancePos = newInstancePos
        table.insert(deserializedPackets, packet)
    end

    return plyr, deserializedPackets
end

function Series.ExecuteHandlers(plyr: Player?, Packets : {Packet})
    for i=1, #Packets do
        local packet:Packet = Packets[i]
        print("Incoming packet:", packet.tagName)
        local handler = handlers[packet.tagName]
        if handler then
            if plyr then handler(plyr, packet.data) else handler(packet.data) end
        else
            warn("No handler registered for tag: " .. packet.tagName)
        end
    end
end

return Series