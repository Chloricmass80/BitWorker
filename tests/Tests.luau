-- Consider this script to be server-side.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local testCount = 0
local tests = {}
local testNumLookup = {}

type Condition = {
    AddCheck : (self: Condition, checkName: string, expectedOutput: any) -> ();
    RunCheck : (self: Condition, checkName: string, input: any) -> (boolean, string?);
    RunChecks : (self: Condition, input : {any}) -> ();
    GetCheckNames : (self: Condition) -> ({string});
    GetResults : (self: Condition) -> (boolean, string?);
}

-- tables or buffers printed to CLI are memory adresses, this just makes it debuggable.
function betterToStr(val : any) : string
    local valType = typeof(val)
    if valType == "table" then
        local str = "{" 
        for key, subVal in pairs(val) do
            if typeof(key) == "number" then
                str = string.format("%s%s, ", str, betterToStr(subVal))
            else
                str = string.format("%s%s = %s, ", str, betterToStr(key), betterToStr(subVal))
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

-- equivalence between tables from value to value, ignores memory adress equivalence
local function deepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end

    for k, v in pairs(a) do
        if not deepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end

    return true
end



local Condition = {}
Condition.__index = Condition

function Condition.new() : Condition
    local self = setmetatable({
        _checks = {};
        _passed = true;
        _checkFailMsgs = {};
    }, Condition)

    return self :: Condition
end

function Condition:AddCheck(checkName:string, expectedOutput:any) : ()
    table.insert(self._checks, {checkName, expectedOutput, false})
end

function Condition:_CheckCommon(check, input)
    if check[3] == true then
        return
    end

    local expectedOutput = check[2]
    local checkName = check[1]
    local checkPass = nil
    if deepEqual(input, expectedOutput) then
        checkPass = true
    else
        checkPass = false
        table.insert(self._checkFailMsgs, string.format("'%s check' expected %s, got %s.", checkName, betterToStr(expectedOutput), betterToStr(input)))
    end

    check[3] = true
    self._passed = self._passed and checkPass
end

function Condition:RunCheck(checkName:string, input:any)
    local check = nil
    for _, chk in ipairs(self._checks) do
        if chk[1] == checkName then
            check = chk
            break
        end
    end

    assert(check, string.format("Check by name %s not found", checkName))

    self:_CheckCommon(check, input)
end

function Condition:_RunCheckByIndex(checkIndex:number, input:any)
    local check = self._checks[checkIndex]
    self:_CheckCommon(check, input)
end

function Condition:RunChecks(inputs : {any})
    for i, _ in ipairs(self._checks) do
        local input = inputs[i]
        
        self:_RunCheckByIndex(i, input)
    end
end


function Condition:GetCheckNames() : {string}
    local checkNameArray = {}
    for _, check in ipairs(self._checks) do
        table.insert(checkNameArray, check[1])
    end

    return checkNameArray
end

function Condition:GetResults() : (boolean, string?)
    if #self._checkFailMsgs == 0 then
        return self._passed
    end
    local errMsg = ""
    for i, msg in ipairs(self._checkFailMsgs) do
        if i == #self._checkFailMsgs then
            errMsg = string.format("%s%s", errMsg, msg)
        else
            errMsg = string.format("%s%s\n", errMsg, msg)
        end
    end

    return self._passed, errMsg
end


TestClass = {}
TestClass.__index = TestClass

function TestClass.new(name:string, actionFunc: () -> ...any, passCondition : (...any) -> (boolean, string?))
    local self = setmetatable({
        _actionFunc = actionFunc;
        _passCondition = passCondition;
        _name = name;
        _hasPassed = nil;
        _failReason = nil;
        _execTime = nil;
        _error = nil;
    }, TestClass)
    testCount += 1
    tests[name] = self
    testNumLookup[testCount] = name

    return self
end

function TestClass:Execute() : ...any
    local strtTime = os.clock()
    local results = table.pack(pcall(self._actionFunc))
    self._execTime = os.clock() - strtTime
    local passed = results[1]
    table.remove(results, 1)
    if passed then
        passed, results = self._passCondition(table.unpack(results))
        if passed == nil then
            self._failReason = "runtime error"
            self._error = string.format("%s's Condition function did not return a value, make sure to end it with 'return Condition:GetResults()'.", self._name)
            self._hasPassed = false
            return
        end
    else
        self._failReason = "runtime error"
        self._error = results[1]
        self._hasPassed = passed
        return
    end
    if not passed then
        self._failReason = "did not meet pass conditions"
    end
    self._error = results
    self._hasPassed = passed
end



-------------------------- TESTS --------------------------

----- EXAMPLE TEST -----
--[[
function ExampleAction()
    * action to be tested*

    return result1, result2
end

function ExampleCondition(result1, result2)
    local condition = Condition.new()
    
    condition:AddCheck("ExampleCheckName", "ExampleExpectedValue")
    condition:AddCheck("ExampleCheckName2", "ExampleExpectedValue2")

    condition:RunChecks({result1, result2})  -- ex: if result1 ~= "ExampleExpectedValue", check failed

    return condition:GetResults()
end
TestClass.new("ExampleTest", ExampleAction, ExampleCondition)
--]]
----- EXAMPLE TEST -----

BitWorkerModule = ReplicatedStorage.BitWorker

-- TLV TESTS --
function TLVSetDebugAction()
    local TLVLayer = require(BitWorkerModule.TLV)

    local dbg = true
    TLVLayer.SetDebugMode(dbg)

    return dbg
end
function TLVSetDebugCondition(dbg)
    local condition = Condition.new()
    local TLVLayer = require(BitWorkerModule.TLV)

    condition:AddCheck("Debug Set", dbg)

    condition:RunChecks({TLVLayer._debugMode})
    
    return condition:GetResults()
end
TestClass.new("TLV Set Debug Test", TLVSetDebugAction, TLVSetDebugCondition)

function TLVGeneralAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local TLV = TLVLayer.new(8192)
    local Series = require(BitWorkerModule.TLV.Series)
    Series._AddTag("GENERAL_TEST_TAG", {"string", "string", {"f32", "f32"}})
    local rawData = {HttpService:GenerateGUID(false), "NewSound", {2.4, 2.3}}
    TLV:AddData("GENERAL_TEST_TAG", rawData)
    local packedData = TLV:WithdrawData()[1]
    local encoded, instances = packedData.packet[1], packedData.packet[2]
    local decoded = TLV.Deserialize(encoded, instances)[1].data
    if decoded[3][1] then
        decoded[3][1] = math.round(decoded[3][1] * 1000) / 1000 -- resolves floating point error from f32 to f64 default conversion
    end
    if decoded[3][2] then
        decoded[3][2] = math.round(decoded[3][2] * 1000) / 1000 -- resolves floating point error from f32 to f64 default conversion
    end

    return rawData, encoded, decoded
end
function TLVGeneralCondition(rawData, encoded, decoded)
    local condition = Condition.new()

    condition:AddCheck("Input Output Equivalence", rawData)
    condition:AddCheck("Compression", true)

    condition:RunChecks({decoded, rawData ~= encoded})
    
    return condition:GetResults()
end
TestClass.new("TLV General Test", TLVGeneralAction, TLVGeneralCondition)


function TLVSparseAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local TLV = TLVLayer.new(8192)
    local Series = require(BitWorkerModule.TLV.Series)

    Series._AddTag("SPARSE_TEST_TAG", {"SPARSE", "string", "string", {"SPARSE", "f32", "f32"}})
    local rawData = {nil, "NewSound", {nil, 2.3}}
    TLV:AddData("SPARSE_TEST_TAG", rawData)
    
    local packedData = TLV:WithdrawData()[1]
    local encoded, instances = packedData.packet[1], packedData.packet[2]
    local unpackedData = TLV.Deserialize(encoded, instances)[1].data
    if unpackedData[3] and unpackedData[3][2] then
        unpackedData[3][2] = math.round(unpackedData[3][2] * 1000) / 1000
    end

    return rawData, unpackedData
end
function TLVSparseCondition(rawData, unpackedData)
    local condition = Condition.new()

    condition:AddCheck("Input Output Equivalence", rawData)

    condition:RunChecks({unpackedData})

    return condition:GetResults()
end
TestClass.new("TLV Sparse Test", TLVSparseAction, TLVSparseCondition)

function TLVDoubleSparseAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local TLV = TLVLayer.new(8192)
    local Series = require(BitWorkerModule.TLV.Series)

    Series._AddTag("DOUBLE_SPARSE_TEST_TAG", {"SPARSE", "SPARSE", "string", "string", {"SPARSE", "f32", "f32"}})
    local rawData = {nil, "NewSound", {nil, 2.3}}
    TLV:AddData("DOUBLE_SPARSE_TEST_TAG", rawData)
    
    local packedData = TLV:WithdrawData()[1]
    local encoded, instances = packedData.packet[1], packedData.packet[2]
    local unpackedData = TLV.Deserialize(encoded, instances)[1].data
    if unpackedData[3] and unpackedData[3][2] then
        unpackedData[3][2] = math.round(unpackedData[3][2] * 1000) / 1000
    end

    return rawData, unpackedData
end
function TLVDoubleSparseCondition(rawData, unpackedData)
    local condition = Condition.new()

    condition:AddCheck("Input Output Equivalence", rawData)

    condition:RunChecks({unpackedData})

    return condition:GetResults()
end
TestClass.new("TLV Double Sparse Test", TLVDoubleSparseAction, TLVDoubleSparseCondition)


function TLVDeepSparseAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local TLV = TLVLayer.new(8192)
    local Series = require(BitWorkerModule.TLV.Series)

    Series._AddTag("DEEP_SPARSE_TEST_TAG", {"string", "string", {"SPARSE", "f32", "f32"}})
    local rawData = {HttpService:GenerateGUID(false), "NewSound", {nil, 2.3}}
    TLV:AddData("DEEP_SPARSE_TEST_TAG", rawData)

    local packedData = TLV:WithdrawData()[1]
local encoded, instances = packedData.packet[1], packedData.packet[2]
    local unpackedData = TLV.Deserialize(encoded, instances)[1].data
    if unpackedData[3] and unpackedData[3][2] then
        unpackedData[3][2] = math.round(unpackedData[3][2] * 1000) / 1000
    end

    return rawData, unpackedData
end
function TLVDeepSparseCondition(rawData, unpackedData)
    local condition = Condition.new()

    condition:AddCheck("Input Output Equivalence", rawData)

    condition:RunChecks({unpackedData})

    return condition:GetResults()
end
TestClass.new("TLV Deep Sparse Test", TLVDeepSparseAction, TLVDeepSparseCondition)

function TLVMultiTagAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local TLV = TLVLayer.new(8192)
    local Series = require(BitWorkerModule.TLV.Series)
    Series._AddTag("MULTI_SPARSE_TEST_TAG", {"SPARSE", "string", "string", {"SPARSE", "f32", "f32"}})
    Series._AddTag("MULTI_GENERAL_TEST_TAG", {"string", "string", {"f32", "f32"}})


    local rawData1 = {nil, "NewSound", {nil, 2.3}}
    TLV:AddData("MULTI_SPARSE_TEST_TAG", rawData1)

    local rawData2 = {HttpService:GenerateGUID(false), "NewSound", {2.4, 2.3}}
    TLV:AddData("MULTI_GENERAL_TEST_TAG", rawData2)

    local packedData = TLV:WithdrawData()[1]
    local unpackedPackets = TLV.Deserialize(packedData.packet[1], packedData.packet[2])
    local unpackedData1 = unpackedPackets[1].data
    local unpackedData2 = unpackedPackets[2].data
    if unpackedData1[3] and unpackedData1[3][2] then
        unpackedData1[3][2] = math.round(unpackedData1[3][2] * 1000) / 1000
    end
    if unpackedData2[3][1] then
        unpackedData2[3][1] = math.round(unpackedData2[3][1] * 1000) / 1000 -- resolves floating point error from f32 to f64 default conversion
    end
    if unpackedData2[3][2] then
        unpackedData2[3][2] = math.round(unpackedData2[3][2] * 1000) / 1000 -- resolves floating point error from f32 to f64 default conversion
    end


    return rawData1, rawData2, unpackedData1, unpackedData2
end
function TLVMultiTagCondition(rawData1, rawData2, unpackedData1, unpackedData2)
    local condition = Condition.new()

    condition:AddCheck("Input Output Equivalence Packet 1", rawData1)
    condition:AddCheck("Input Output Equivalence Packet 2", rawData2)

    condition:RunChecks({unpackedData1, unpackedData2})

    return condition:GetResults()
end
TestClass.new("TLV Multi-Tag Test", TLVMultiTagAction, TLVMultiTagCondition)


function TLVTagReuseAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local TLV = TLVLayer.new(8192)
    local Series = require(BitWorkerModule.TLV.Series)
    Series._AddTag("REUSE_GENERAL_TEST_TAG", {"guid", "string", {"f32", "f32"}})

    local rawData1 = {HttpService:GenerateGUID(false), "NewSound", {2.4, 2.3}}

    local b1, instances1 = TLVLayer.SerializeOnce("REUSE_GENERAL_TEST_TAG", rawData1)
    local unpackedData1 = TLV.Deserialize(b1, instances1)[1].data

    local rawData2 = {HttpService:GenerateGUID(false), "NewSound3", {1.5, 7.1}}

    local b2, instances2 = TLVLayer.SerializeOnce("REUSE_GENERAL_TEST_TAG", rawData2)
    local unpackedData2 = TLV.Deserialize(b2, instances2)[1].data

    if unpackedData1[3][1] then
        unpackedData1[3][1] = math.round(unpackedData1[3][1] * 1000) / 1000 -- resolves floating point error from f32 to f64 default conversion
    end
    if unpackedData1[3][2] then
        unpackedData1[3][2] = math.round(unpackedData1[3][2] * 1000) / 1000 -- resolves floating point error from f32 to f64 default conversion
    end
    if unpackedData2[3][1] then
        unpackedData2[3][1] = math.round(unpackedData2[3][1] * 1000) / 1000 -- resolves floating point error from f32 to f64 default conversion
    end
    if unpackedData2[3][2] then
        unpackedData2[3][2] = math.round(unpackedData2[3][2] * 1000) / 1000 -- resolves floating point error from f32 to f64 default conversion
    end

    return rawData1, rawData2, unpackedData1, unpackedData2
end
function TLVTagReuseCondition(rawData1, rawData2, unpackedData1, unpackedData2)
    local condition = Condition.new()

    condition:AddCheck("Input Output Equivalence Packet 1", rawData1)
    condition:AddCheck("Input Output Equivalence Packet 2", rawData2)

    condition:RunChecks({unpackedData1, unpackedData2})

    return condition:GetResults()
end
TestClass.new("TLV Tag Reuse Test", TLVTagReuseAction, TLVTagReuseCondition)


function GuidCompressionAction()
    local strEncode = require(BitWorkerModule.TLV.Compressor._StringCompressor)
    local HttpService = game:GetService("HttpService")
    local raw = HttpService:GenerateGUID(false)
    local encoded = strEncode.Compress(raw, true)
    local decoded = strEncode.Decompress(encoded, true)
    return raw, encoded, decoded
end

function GuidCompressionCondition(raw, encoded, decoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)

    condition:RunChecks({raw ~= encoded, decoded})

    return condition:GetResults()
end
TestClass.new("Guid Compression Test", GuidCompressionAction, GuidCompressionCondition)

function CurlyGuidCompressionAction()
    local strEncode = require(BitWorkerModule.TLV.Compressor._StringCompressor)
    local HttpService = game:GetService("HttpService")
    local raw = HttpService:GenerateGUID(true)
    local encoded = strEncode.Compress(raw, true)
    local decoded = strEncode.Decompress(encoded, true)

    return raw, encoded, decoded
end

function CurlyGuidCompressionCondition(raw, encoded, decoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)

    condition:RunChecks({raw ~= encoded, decoded})

    return condition:GetResults()
end
TestClass.new("Curly Guid Compression Test", CurlyGuidCompressionAction, CurlyGuidCompressionCondition)


function TLVGuidAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local TLV = TLVLayer.new(8192)
    local Series = require(BitWorkerModule.TLV.Series)

    Series._AddTag("GUID_TEST_TAG", {"guid", "guid"})
    local guid = HttpService:GenerateGUID(false)
    local curlyGuid = HttpService:GenerateGUID(true)
    local rawData = {guid, curlyGuid}

    TLV:AddData("GUID_TEST_TAG", rawData)
    
    local packedData = TLV:WithdrawData()[1]
    local encoded, instances = packedData.packet[1], packedData.packet[2]
    local unpackedData = TLV.Deserialize(encoded, instances)[1].data

    return guid, curlyGuid, unpackedData
end

function TLVGuidCondition(guid, curlyGuid, unpackedData)
    local condition = Condition.new()

    condition:AddCheck("GUID Input Output Equivalence", guid)
    condition:AddCheck("Curly GUID Input Output Equivalence", curlyGuid)

    condition:RunChecks({unpackedData[1], unpackedData[2]})

    return condition:GetResults()
end
TestClass.new("TLV Guid Test", TLVGuidAction, TLVGuidCondition)


function TLVInstanceAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local TLV = TLVLayer.new(8192)
    local Series = require(BitWorkerModule.TLV.Series)

    local instance = Instance.new("Part", workspace)

    Series._AddTag("INSTANCE_TEST_TAG", {"u8", "string", "instance", "u8"})

    local raw = {14, "Hello World!", instance, 27}

    TLV:AddData("INSTANCE_TEST_TAG", raw)

    local packedData = TLV:WithdrawData()[1]
    local encoded, instances = packedData.packet[1], packedData.packet[2]
    local decoded = TLV.Deserialize(encoded, instances)[1].data

    return instance, raw, decoded, encoded
end

function TLVInstanceCondition(instance, raw, decoded, encoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)
    condition:AddCheck("Instance Input Output Equivalence", instance)

    condition:RunChecks({raw ~= encoded, decoded, decoded[3]})

    return condition:GetResults()
end
TestClass.new("TLV Instance Test", TLVInstanceAction, TLVInstanceCondition)


function TLVBooleanAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local TLV = TLVLayer.new(8192)
    local Series = require(BitWorkerModule.TLV.Series)

    Series._AddTag("BOOLEAN_TEST_TAG", {"u8", "string", "boolean", "u8"})

    local bool = false
    local raw = {14, "Hello World!", bool, 27}

    TLV:AddData("BOOLEAN_TEST_TAG", raw)

    local packedData = TLV:WithdrawData()[1]
    local encoded, instances = packedData.packet[1], packedData.packet[2]
    local decoded = TLV.Deserialize(encoded, instances)[1].data

    return bool, raw, decoded, encoded
end

function TLVBooleanCondition(bool, raw, decoded, encoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)
    condition:AddCheck("Boolean Input Output Equivalence", bool)

    condition:RunChecks({raw ~= encoded, decoded, decoded[3]})

    return condition:GetResults()
end
TestClass.new("TLV Boolean Test", TLVBooleanAction, TLVBooleanCondition)


function TLVRepetitionAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local TLV = TLVLayer.new(8192)
    local Series = require(BitWorkerModule.TLV.Series)

    Series._AddTag("REPETITION_TEST_TAG", {"u8", "string", "u8", "u8", "..."})

    local raw = {14, "Hello World!", 15, 27, 32, "Hello Moon!", 32, 15}

    TLV:AddData("REPETITION_TEST_TAG", raw)

    local packedData = TLV:WithdrawData()[1]
    local encoded, instances = packedData.packet[1], packedData.packet[2]
    local decoded = TLV.Deserialize(encoded, instances)[1].data

    return raw, decoded, encoded
end

function TLVRepetitionCondition(raw, decoded, encoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)

    condition:RunChecks({raw ~= encoded, decoded})

    return condition:GetResults()
end
TestClass.new("TLV Repitition Test", TLVRepetitionAction, TLVRepetitionCondition)

function TLVNestedRepetitionAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local TLV = TLVLayer.new(8192)
    local Series = require(BitWorkerModule.TLV.Series)

    Series._AddTag("NESTED_REPETITION_TEST_TAG", {"u8", "string", {"u8", "u32", "..."}, "u8", "..."})

    local raw = {14, "Hello World!", {32, 8301209, 188, 993123}, 27, 32, "Hello Moon!", {32, 8301209, 188, 993123, 32, 8301209}, 15}

    TLV:AddData("NESTED_REPETITION_TEST_TAG", raw)

    local packedData = TLV:WithdrawData()[1]
    local encoded, instances = packedData.packet[1], packedData.packet[2]
    local decoded = TLV.Deserialize(encoded, instances)[1].data

    return raw, decoded, encoded
end

function TLVNestedRepetitionCondition(raw, decoded, encoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)

    condition:RunChecks({raw ~= encoded, decoded})

    return condition:GetResults()
end
TestClass.new("TLV Nested Repetition Test", TLVNestedRepetitionAction, TLVNestedRepetitionCondition)


function TLVSparseRepetitionAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local TLV = TLVLayer.new(8192)
    local Series = require(BitWorkerModule.TLV.Series)

    Series._AddTag("SPARSE_REPETITION_TEST_TAG", {"SPARSE", "u8", "string", "boolean", "u8", "..."})

    local raw = {14, "Hello World!", nil, 27, 32, nil, false, 15}

    TLV:AddData("SPARSE_REPETITION_TEST_TAG", raw)

    local packedData = TLV:WithdrawData()[1]
    local encoded, instances = packedData.packet[1], packedData.packet[2]
    local decoded = TLV.Deserialize(encoded, instances)[1].data

    return raw, decoded, encoded
end

function TLVSparseRepetitionCondition(raw, decoded, encoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)

    condition:RunChecks({raw ~= encoded, decoded})

    return condition:GetResults()
end
TestClass.new("TLV Sparse Repitition Test", TLVSparseRepetitionAction, TLVSparseRepetitionCondition)


function TLVEmptyRepetitionAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local TLV = TLVLayer.new(8192)
    local Series = require(BitWorkerModule.TLV.Series)

    Series._AddTag("EMPTY_REPETITION_TEST_TAG", {"u8", "string", "boolean", "u8", "..."})

    local raw = {}

    TLV:AddData("EMPTY_REPETITION_TEST_TAG", raw)

    local packedData = TLV:WithdrawData()[1]
    local encoded, instances = packedData.packet[1], packedData.packet[2]
    local decoded = TLV.Deserialize(encoded, instances)[1].data

    return raw, decoded, encoded
end
function TLVEmptyRepetitionCondition(raw, decoded, encoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)

    condition:RunChecks({raw ~= encoded, decoded})

    return condition:GetResults()
end
TestClass.new("TLV Empty Repetition Test", TLVEmptyRepetitionAction, TLVEmptyRepetitionCondition)


function TLVSubByteAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local TLV = TLVLayer.new(8192)
    local Series = require(BitWorkerModule.TLV.Series)

    Series._AddTag("SUB_BYTE_TEST_TAG", {"u2", "i16", {"u3", "string", "boolean", "u8", "..."}})

    local raw = {2, -15, {5, "Hello World!", true, 53, 6, "Hello Moon!", false, 15}}

    TLV:AddData("SUB_BYTE_TEST_TAG", raw)

    local packedData = TLV:WithdrawData()[1]
    local encoded, instances = packedData.packet[1], packedData.packet[2]
    local decoded = TLV.Deserialize(encoded, instances)[1].data

    return raw, decoded, encoded
end
function TLVSubByteCondition(raw, decoded, encoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)

    condition:RunChecks({raw ~= encoded, decoded})

    return condition:GetResults()
end
TestClass.new("TLV Sub-Byte Test", TLVSubByteAction, TLVSubByteCondition)

function TLVSerializeOnceAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local Series = require(BitWorkerModule.TLV.Series)

    Series._AddTag("SERIALIZE_ONCE_TEST_TAG", {"u2", "i16", {"u3", "string", "boolean", "u8", "..."}})
    
    local raw = {2, -15, {5, "Hello World!", true, 53, 6, "Hello Moon!", false, 15}}
    local encoded, instances = TLVLayer.SerializeOnce("SERIALIZE_ONCE_TEST_TAG", raw)

    local decoded = TLVLayer.Deserialize(encoded, instances)[1].data

    return raw, decoded, encoded
end
function TLVSerializeOnceCondition(raw, decoded, encoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)

    condition:RunChecks({raw ~= encoded, decoded})

    return condition:GetResults()
end
TestClass.new("TLV Serialize Once Test", TLVSerializeOnceAction, TLVSerializeOnceCondition)



function TLVMultiSubSparseAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local Series = require(BitWorkerModule.TLV.Series)

    Series._AddTag("MULTI_SUB_SPARSE_TEST_TAG", {{"SPARSE", "u8", "u16"}, {"SPARSE", "u32", "string"}})
    
    local raw = {{32}, {1237, "Hello World!"}}
    local encoded, instances = TLVLayer.SerializeOnce("MULTI_SUB_SPARSE_TEST_TAG", raw)

    local decoded = TLVLayer.Deserialize(encoded, instances)[1].data

    return raw, decoded, encoded
end
function TLVMultiSubSparseCondition(raw, decoded, encoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)

    condition:RunChecks({raw ~= encoded, decoded})

    return condition:GetResults()
end
TestClass.new("TLV Multi-Sub-Sparse Test", TLVMultiSubSparseAction, TLVMultiSubSparseCondition)



function TLVMultiSubSparseRepeatingAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local Series = require(BitWorkerModule.TLV.Series)

    Series._AddTag("MULTI_SUB_SPARSE_REPEATING_TEST_TAG", {{"SPARSE", "u8", "u16", "..."}, {"SPARSE", "u32", "string", "..."}})
    
    local raw = {{32}, {1237, "Hello World!", 23151}}
    local encoded, instances = TLVLayer.SerializeOnce("MULTI_SUB_SPARSE_REPEATING_TEST_TAG", raw)

    local decoded = TLVLayer.Deserialize(encoded, instances)[1].data

    return raw, decoded, encoded
end
function TLVMultiSubSparseRepeatingCondition(raw, decoded, encoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)

    condition:RunChecks({raw ~= encoded, decoded})

    return condition:GetResults()
end
TestClass.new("TLV Multi-Sub-Sparse and Repeating Test", TLVMultiSubSparseRepeatingAction, TLVMultiSubSparseRepeatingCondition)


function TLVMultiEmptySparseAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local Series = require(BitWorkerModule.TLV.Series)

    Series._AddTag("MULTI_EMPTY_SPARSE_TEST_TAG", {{"SPARSE", "u8", "u16"}, {"SPARSE", "u32", "string"}})
    
    local raw = {{}, {}}
    local encoded, instances = TLVLayer.SerializeOnce("MULTI_EMPTY_SPARSE_TEST_TAG", raw)

    local decoded = TLVLayer.Deserialize(encoded, instances)[1].data

    return raw, decoded, encoded
end
function TLVMultiEmptySparseCondition(raw, decoded, encoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)

    condition:RunChecks({raw ~= encoded, decoded})

    return condition:GetResults()
end
TestClass.new("TLV Multi-Empty Sparse Test", TLVMultiEmptySparseAction, TLVMultiEmptySparseCondition)



function TLVSparseSubByteAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local Series = require(BitWorkerModule.TLV.Series)

    Series._AddTag("SPARSE_SUB_BYTE_TEST_TAG", {"SPARSE", "u2", "u8"})
    
    local raw = {nil, 15}
    local encoded, instances = TLVLayer.SerializeOnce("SPARSE_SUB_BYTE_TEST_TAG", raw)

    local decoded = TLVLayer.Deserialize(encoded, instances)[1].data

    return raw, decoded, encoded
end
function TLVSparseSubByteCondition(raw, decoded, encoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)

    condition:RunChecks({raw ~= encoded, decoded})

    return condition:GetResults()
end
TestClass.new("TLV Sparse Sub-Byte Test", TLVSparseSubByteAction, TLVSparseSubByteCondition)



function TLVSnapshotAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local Series = require(BitWorkerModule.TLV.Series)
    --                                                                                                                             NOT fine                                     fine                                        fine                                                    fine
    Series._AddTag("SNAPSHOT_TEST_TAG", {"u16", "boolean", "u2", {"u8", "string", "f64", "f32", "f32", {"SPARSE", "boolean", "f32", "f32", "u2", "boolean", "u16", "u16"}, {"u16", "..."}, {"SPARSE", "u16", "u16", "u16", "u16", "u16", "u16", "f32", "f32"}, "..."}, {"SPARSE", "u8", "u16", "f64"}})
    
    local raw = {182, false, 2, {15, "TestSound", 15.32, 23.12, 18.5, {}, {}, {}}, {}}
    local encoded, instances = TLVLayer.SerializeOnce("SNAPSHOT_TEST_TAG", raw)

    local decoded = TLVLayer.Deserialize(encoded, instances)[1].data

    if decoded[4] and decoded[4][4] then
        decoded[4][4] = math.round(decoded[4][4] * 1000) / 1000
    end
    if decoded[4] and decoded[4][5]then
        decoded[4][5] = math.round(decoded[4][5] * 1000) / 1000
    end

    return raw, decoded, encoded
end
function TLVSnapshotCondition(raw, decoded, encoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)

    condition:RunChecks({raw ~= encoded, decoded})

    return condition:GetResults()
end
TestClass.new("TLV Mock Snapshot Test", TLVSnapshotAction, TLVSnapshotCondition)


function TLVEmptyTagAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local Series = require(BitWorkerModule.TLV.Series)

    Series._AddTag("EMPTY_TEST_TAG", {})
    
    local raw = {}
    local encoded, instances = TLVLayer.SerializeOnce("EMPTY_TEST_TAG", raw)

    local decoded = TLVLayer.Deserialize(encoded, instances)[1].data

    return raw, decoded, encoded
end
function TLVEmptyTagCondition(raw, decoded, encoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)

    condition:RunChecks({raw ~= encoded, decoded})

    return condition:GetResults()
end
TestClass.new("TLV Empty Tag Test", TLVEmptyTagAction, TLVEmptyTagCondition)

function TLVNilTagAction()
    local TLVLayer = require(BitWorkerModule.TLV)
    local Series = require(BitWorkerModule.TLV.Series)

    local TLV = TLVLayer.new(8192)

    Series._AddTag("NIL_TEST_TAG")
    TLV:AddData("NIL_TEST_TAG")
    local packetData = TLV:WithdrawData()[1].packet
    local encoded, instances = packetData[1], packetData[2]

    local decoded = TLVLayer.Deserialize(encoded, instances)[1].data

    return nil, decoded, encoded
end
function TLVNilTagCondition(raw, decoded, encoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)

    condition:RunChecks({raw ~= encoded, decoded})

    return condition:GetResults()
end
TestClass.new("TLV Nil Tag Test", TLVNilTagAction, TLVNilTagCondition)


function TLVGeneralAction2()
    local TLVLayer = require(BitWorkerModule.TLV)
    local Series = require(BitWorkerModule.TLV.Series)

    local TLV = TLVLayer.new(8192)

    Series._AddTag("GENERAL_TEST_TAG_2", {"u16", "u16", "boolean"})
    local raw = {0, 3815, true}
    TLV:AddData("GENERAL_TEST_TAG_2", raw)
    local packetData = TLV:WithdrawData()[1].packet
    local encoded, instances = packetData[1], packetData[2]

    local decoded = TLVLayer.Deserialize(encoded, instances)[1].data

    return raw, decoded, encoded
end
function TLVGeneralCondition2(raw, decoded, encoded)
    local condition = Condition.new()

    condition:AddCheck("Compression", true)
    condition:AddCheck("Input Output Equivalence", raw)

    condition:RunChecks({raw ~= encoded, decoded})

    return condition:GetResults()
end
TestClass.new("TLV General Test 2", TLVGeneralAction2, TLVGeneralCondition2)

-- TLV TESTS --



-- NETWORKER TESTS --









-------------------------- HANDLING OUTPUT --------------------------
resultDict = {}
for _, testName in ipairs(testNumLookup) do
    local test = tests[testName]
    test:Execute()

    resultDict[testName] = {test._hasPassed, test._execTime, test._failReason, test._error}
end

return resultDict