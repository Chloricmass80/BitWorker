local Series = require(script.Series)

type TLVSerializeOnceFunc = (tag: string, value: {any}, request: {any}?) -> (buffer?, {Instance}?)
type TLVDeserializeFunc = (b : buffer, instances : {Instance}) -> ({Packet});
type TLVDeserializeAndExecuteFunc = (b : buffer, instances : {Instance}) -> ();

type Packet = {
    tagName : string;
    data : {any}
}
type TLVObj = {
    AddData : (TLVObj, tagName : string, value : {any}?, request : {any}?) -> ();
    GetCurrentPayloadSize : (TLVObj) -> (number);
    WithdrawData : (TLVObj) -> ({PacketData});
    SerializeOnce : TLVSerializeOnceFunc;
    Deserialize : TLVDeserializeFunc;
    DeserializeAndExecute : TLVDeserializeAndExecuteFunc;
}
type PacketData = {
    packetSize : number;
    packet : {buffer | {Instance}}
}


local TLVLayer = {
    _tags = {};
    _handlerCount = 0;
    _maxReadSize = 512;
    _debugMode = false;
}

TLVLayer.__index = TLVLayer

function TLVLayer.SetDebugMode(isDebugMode: boolean)
    TLVLayer._debugMode = isDebugMode
    Series.debugMode = isDebugMode
end

function TLVLayer.AddHandler(tagName: string, handler: ({any}) -> ())
    Series.AddHandler(tagName, handler)
    TLVLayer._handlerCount += 1
end

function TLVLayer.AddTag(tagName: string, tagConfig : {string | {string}})
    Series._AddTag(tagName, tagConfig)
end

function TLVLayer.SetMaxReadSize(maxPacketSize: number)
    TLVLayer._maxReadSize = maxPacketSize
end

function TLVLayer.new(maxPacketSize: number) : TLVObj
    if not maxPacketSize then
        warn("Passed max packet size was not set, defaulting to 1024 bytes.")
    end
    local self = setmetatable({
        _seriesList = {};
        _maxPacketSize = maxPacketSize or 1024;
    }, TLVLayer)

    return self :: TLVObj
end

function TLVLayer:_GrabSeries()
    local currentSeriesIndex = self._seriesList[#self._seriesList]
    if currentSeriesIndex and currentSeriesIndex.maxed == false then 
        return currentSeriesIndex.series
    else
        local series = Series.new()
        local seriesIndex = {maxed = false, series = series}
        table.insert(self._seriesList, seriesIndex)
        return series, #self._seriesList
    end
end

function TLVLayer:AddData(tagName: string, value: {any}?) : any
    local series, seriesIndex = self:_GrabSeries()


    series:AddRequest(tagName, value)
    if series:EstimateSize() > self._maxPacketSize  then
        self._seriesList[seriesIndex].maxed = true
        local request = series:RemoveLastRequest()
        local newSeries = self:_GrabSeries()
        newSeries:AddRequest(tagName, value, request)
    end
end

function TLVLayer:GetCurrentPayloadSize() : number
    if #self._seriesList ~= 0 then
        local totalSize = 0
        for i = 1, #self._seriesList do
            local series = self._seriesList[i].series
            totalSize += series:EstimateSize()
        end
        return totalSize
    else
        return 0
    end
end

type DeserializeFunc = (b: buffer, instances: {Instance}) -> () & (plyr: Player, b: buffer, instances: {Instance}) -> ()

function TLVLayer:WithdrawData() : ({PacketData})
    if #self._seriesList == 0 then return end

    local packets = {}
    for i=1, #self._seriesList do
        local series = self._seriesList[i].series
        table.insert(packets, {packet = {series:Serialize()}, packetSize = series:EstimateSize()})
    end

    self._seriesList = {}

    return packets
end

TLVLayer.SerializeOnce = Series.SerializeOnce

function TLVLayer.Deserialize(...) : DeserializeFunc
    local n = select("#", ...)

    if n == 3 then
        return Series.Deserialize(...)
    elseif n == 2 then
        local _, packet = Series.Deserialize(nil, ...)
        return packet
    else
        error(string.format("Invalid arguments. Got arguments (%s), expected (b: buffer, instances: {Instance}) OR (plyr: Player, b: buffer, instances: {Instance})", table.concat({...}, ", ")))
    end
end

function TLVLayer.ValidateIncomingPacket(_, b, instances) : boolean
    if typeof(b) ~= "buffer" then
        warn("Incoming packet does not include a valid buffer.")
        return false
    end
    if instances ~= nil and type(instances) ~= "table" then
        warn("Incoming packet does not include a valid instance array.")
        return false 
    end
    if Series.GetPacketSize(b, nil, instances) > TLVLayer._maxReadSize then
        warn("Incoming packet's size is too large.")
        return false
    end
    
    return true
end

function TLVLayer.DeserializeAndExecute(...) : DeserializeFunc -- plyr: Player, b: buffer, instances: {Instance} OR b: buffer, instances: {Instance} 
    if TLVLayer._handlerCount == 0 then return end
    local n = select("#", ...)


    if n == 3 then
        TLVLayer.ValidateIncomingPacket(...)
        Series.ExecuteHandlers(Series.Deserialize(...))
    elseif n == 2 then
        TLVLayer.ValidateIncomingPacket(nil, ...)
        Series.ExecuteHandlers(Series.Deserialize(nil, ...))
    else
        error(string.format("Invalid arguments. Got arguments (%s), expected (b: buffer, instances: {Instance}) OR (plyr: Player, b: buffer, instances: {Instance})", table.concat({...}, ", ")))
    end

end
return TLVLayer