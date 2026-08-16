local Players = game:GetService("Players")
local BitWorkerModule = script.Parent.Parent

local TLV = require(BitWorkerModule.TLV)
local Discipline = require(script.Discipline)
local InfractionTypes = require(script.InfractionTypes)
local Utils = require(BitWorkerModule.UtilityFuncs)
local Settings = require(BitWorkerModule.Settings)
--ocal BitWorker = require(BitWorkerModule)



local remoteEvent:RemoteEvent = BitWorkerModule.RecurseNetworker


type CacheValue = {
    size : number; -- the estimated size of the packet going over the wire
    bytes : buffer; -- the buffer that will be sent
    instances : {Instance}; -- the instance references going over the wire
    target : {Player} | Player?; -- The player(s) the request is targeting, if nil and on server, means it's meant for all players. Automatically nil on client.
    remaining : number?; -- Used to track when to delete the request in the cache, describes how many players still need to process this request, only a number if the plyr feild is a table.
}

local packetPlyrRelationship = {
    None = 1;
    Broadcast = 2;
    Shared = 3;
    Individual = 4;
}

local MAX_TOKENS = 20
local TOKEN_REFRESH_RATE = 1 -- hz

local networkTicksToRefresh = Settings.NetworkFlushInterval/TOKEN_REFRESH_RATE

local ServerMixin = {}

function ServerMixin.Apply(BitWorker)
    BitWorker._registeredPlayers = {}
    BitWorker._inboundTokens = {}
    BitWorker._chunkSize = Settings.MaximumServerTransmissionUnit
    BitWorker._playerSeqCursors = {}
    BitWorker._largestSeqNum = nil;
    BitWorker._lastGeneratedSeqNum = -1;
    BitWorker._smallestSeqNum = nil;
    BitWorker._seqCursorCounts = {} -- Keeps track of how many player seqCursors lie on a given seqNum. Formatted as {115 = 2, 223 = 1, ...}
    BitWorker._pendingTargetsByPlayer = {} -- Keeps track of which player has which seqNums as targets. Formatted as: {plyr = {115 = true, 223 = true ...} ...}
    BitWorker._currentTLV = {tlv = TLV.new(BitWorker._chunkSize), target = nil}

    TLV.SetMaxReadSize(Settings.MaximumClientTransmissionUnit)

    function BitWorker:_UpdateSmallestSeqNum(oldSeq)
        local counts = self._seqCursorCounts
        if oldSeq == self._smallestSeqNum and counts[oldSeq] == 0 then
            counts[oldSeq] = nil
            local s = oldSeq
            while (counts[s] == nil or counts[s] == 0) and s <= self._largestSeqNum do
                s += 1
            end
            if s > self._largestSeqNum then
                self._smallestSeqNum = nil
                self._largestSeqNum = nil
            else
                self._smallestSeqNum = s
            end
        end
    end

    function BitWorker:_CachePacket(bytes: buffer, instances: {Instance}, size: number, plyrs:{Player} | Player?, isTargetATable:boolean?)
        local seqNum = self:_GetNewSeqNum()
        local remaining = nil

        if isTargetATable then
            remaining = #plyrs
            local lookUp = {}
            for i = 1, #plyrs do
                local plyr = plyrs[i]
                self._pendingTargetsByPlayer[plyr][seqNum] = true
                lookUp[plyr] = true
            end

            plyrs = lookUp
        elseif plyrs ~= nil then
            self._pendingTargetsByPlayer[plyrs][seqNum] = true
        end

        local cacheValue = {
            size = size;
            bytes = bytes;
            instances = instances;
            target = plyrs;
            remaining = remaining
        }
        
        self._networkCache[seqNum] = cacheValue
    end

    function BitWorker:_AdvancePlayerCursor(plyr: Player, newSeq: number)
        local oldSeq = self._playerSeqCursors[plyr]

        self._playerSeqCursors[plyr] = newSeq

        local counts = self._seqCursorCounts
        counts[oldSeq] -= 1
        counts[newSeq] = (counts[newSeq] or 0) + 1

        self:_UpdateSmallestSeqNum(oldSeq)
    end

    function BitWorker:_UpdateCursorsOnPlyrLeave(plyr: Player)
        local oldSeq = self._playerSeqCursors[plyr]
        local mySeqs = self._pendingTargetsByPlayer[plyr]

        if oldSeq == nil and mySeqs == nil then return end

        self._playerSeqCursors[plyr] = nil
        self._pendingTargetsByPlayer[plyr] = nil

        for seq, _ in pairs(mySeqs) do
            local packet:CacheValue? = self._networkCache[seq]
            if packet then
                if packet.remaining then
                    packet.remaining -= 1
                    packet.target[plyr] = nil
                    if packet.remaining == 0 then self._networkCache[seq] = nil end
                else
                    self._networkCache[seq] = nil
                end
            end
        end

        local counts = self._seqCursorCounts
        counts[oldSeq] -= 1

        self:_UpdateSmallestSeqNum(oldSeq)
    end

    function BitWorker:_UpdateCursorsOnPlyrJoin(plyr: Player)
        local seqNum = self._largestSeqNum or (self._lastGeneratedSeqNum + 1)
        self._playerSeqCursors[plyr] = seqNum
        self._pendingTargetsByPlayer[plyr] = {}

        local counts = self._seqCursorCounts
        counts[seqNum] = (counts[seqNum] or 0) + 1
    end

    function BitWorker:_WithdrawAndCacheCurrentTLV(isTargetATable: boolean?)
        local withdrawn = self._currentTLV.tlv:WithdrawData()
        if withdrawn == nil then return end

        for i=1, #withdrawn do
            local packet = withdrawn[i]
            local size = packet.packetSize
            local b = packet.packet[1]
            local instances = packet.packet[2]
            self:_CachePacket(b, instances, size, self._currentTLV.target, isTargetATable)
        end
    end

    function BitWorker:_TryConsumeToken(plyr: Player) : boolean
        local tokens = self._inboundTokens[plyr] or MAX_TOKENS
        if tokens <= 0 then return false end
        self._inboundTokens[plyr] = tokens - 1
        return true
    end

    function BitWorker:_RefillTokens()
        for plyr: Player, _ in pairs(self._inboundTokens) do
            self._inboundTokens[plyr] = MAX_TOKENS
        end
    end

    function BitWorker:_FireCommon(tag: string, value: any, plyrs:{Player} | Player?, isTargetATable:boolean?)
        print("Outgoing packet:", tag)
        if #Players:GetPlayers() == 0 then return end -- Don't have to do nothing if the game is dead!
        if type(value) ~= "table" then value = {value} end

        local commonWithLastRequest = false

        if isTargetATable then
            commonWithLastRequest = Utils.MultisetEqual(plyrs, self._currentTLV.target)
        else
            commonWithLastRequest = plyrs == self._currentTLV.target
        end

        if commonWithLastRequest then
            self._currentTLV.tlv:AddData(tag, value)
        else
            self:_WithdrawAndCacheCurrentTLV(isTargetATable)
        end
    end

    function BitWorker:FireAllClients(tag: string, value: any)
        self:_FireCommon(tag, value)
    end

    function BitWorker:FireClient(plyr: Player, tag: string, value: any)
        self:_FireCommon(tag, value, plyr)
    end

    function BitWorker:FireMultipleClients(plyrs: {Player}, tag: string, value: any)
        self:_FireCommon(tag, value, plyrs, true)
    end

    function BitWorker:MarkInstanceDirty(instance:{any}|number, tag:string, value:any?)
        if tag == nil then return end -- Edge cases may cause the passed tag to be nil
        local id = nil
        if type(instance) == "number" then
            id = instance
        else
            id = instance._networkId
        end

        if not id then
            warn("BitWorker could not find a network Id associated with object:", instance)
        end

        if value == nil then
            value = {}
        elseif type(value) ~= "table" then
            value = {value}
        end

        table.insert(value, 1, id)
        self:FireAllClients(tag, value)
    end

    function BitWorker:_GetNewSeqNum() : number
        self._lastGeneratedSeqNum += 1
        if self._largestSeqNum ~= nil then
            self._largestSeqNum += 1
        else
            self._largestSeqNum = self._lastGeneratedSeqNum
            self._smallestSeqNum = self._lastGeneratedSeqNum
        end
        return self._lastGeneratedSeqNum
    end


    function BitWorker:_OnClientJoined(plyr:Player)
        if self._registeredPlayers[plyr] == true then
            Discipline:AddHeat(plyr, InfractionTypes.RestrictedPacket)
            return
        end

        self._registeredPlayers[plyr] = true
        self:_UpdateCursorsOnPlyrJoin(plyr)
        local snapShotTLV = TLV.new(self._chunkSize) -- add on client join func support
    end

    function BitWorker:_OnClientDestroyed(plyr)
        self:_UpdateCursorsOnPlyrLeave(plyr)
    end

    local function getPacketPlyrRelationship(plyr: Player, packet:CacheValue) : number
        if packet == nil then return packetPlyrRelationship.None end
        if packet.target then
            if packet.remaining ~= nil then
                if not packet.target[plyr] then return packetPlyrRelationship.None else return packetPlyrRelationship.Shared end
            else
                if packet.target ~= plyr then return packetPlyrRelationship.None else return packetPlyrRelationship.Individual end
            end
        end

        return packetPlyrRelationship.Broadcast
    end

    function BitWorker:_BuildPlayerPacket(plyr: Player, seqCursor: number) : (number, buffer?, {Instance}?)
        local bufferSize = 0
        local totalSize = 0
        local destinedPackets = {}
        local instances = {}
        local newSeqCursor = seqCursor

        for i = seqCursor, self._largestSeqNum do
            local packet = self._networkCache[i]
            local packetRelationship = getPacketPlyrRelationship(plyr, packet)
            newSeqCursor = i

            if packetRelationship == packetPlyrRelationship.None then
                continue
            end

            if totalSize + packet.size > self._chunkSize then break end 

            table.insert(destinedPackets, packet)
            Utils.MergeArrayIntoArray(packet.instances, instances)
            bufferSize += buffer.len(packet.bytes)
            totalSize += packet.size

            if packetRelationship == packetPlyrRelationship.Shared then
                packet.remaining -= 1
                if packet.remaining == 0 then self._networkCache[i] = nil end
            elseif packetRelationship == packetPlyrRelationship.Individual then
                self._networkCache[i] = nil
            end

            if self._pendingTargetsByPlayer[plyr][i] then self._pendingTargetsByPlayer[plyr][i] = nil end
        end

        if #destinedPackets == 0 then return newSeqCursor end

        local b = nil
        if bufferSize ~= 0 then
            b = buffer.create(bufferSize)
            local pos = 0
            
            for i=1, #destinedPackets do
                local packet:CacheValue = destinedPackets[i]
                Utils.MergeBufferIntoBuffer(packet.bytes, b, pos)
                pos += buffer.len(packet.bytes)
            end
        end

        newSeqCursor += 1
        return newSeqCursor, b, instances
    end

    function BitWorker:_FlushCache()
        self._currentNetworkTick += 1
        if self._currentNetworkTick % networkTicksToRefresh == 0 then self:_RefillTokens() end
        self:_WithdrawAndCacheCurrentTLV(type(self._currentTLV.target) == "table")
        if self._smallestSeqNum == nil and self._largestSeqNum == nil then return end -- no requests to send

        local oldSmallestSeq = self._smallestSeqNum

        for plyr:Player, seqCursor:number in pairs(self._playerSeqCursors) do
            local newSeq, b, instances = self:_BuildPlayerPacket(plyr, seqCursor)

            if b or instances then
                remoteEvent:FireClient(plyr, b, instances)
            end

            self:_AdvancePlayerCursor(plyr, newSeq)
        end

        for i=oldSmallestSeq, self._smallestSeqNum or self._lastGeneratedSeqNum do
            self._networkCache[i] = nil
        end 
    end

    function BitWorker:ClientPacketReceived(plyr: Player, b: buffer, instances: {Instance})
        if not TLV.ValidateIncomingPacket(b, instances) then
            Discipline:AddHeat(plyr, InfractionTypes.MalformedPacket)
        end
        if Discipline:GetBlackList()[plyr] then return end -- Don't listen to blacklisted clients

        if not self:_TryConsumeToken(plyr) then
            Discipline:BlacklistPlayer(plyr, 10)
            return
        end

        TLV.DeserializeAndExecute(b, instances)
    end

    TLV.AddHandler("ClientConnected", function(plyr)
        BitWorker:_OnClientJoined(plyr)
    end)

    remoteEvent.OnServerEvent:Connect(function(...)
        TLV.DeserializeAndExecute(...)
    end)
end



return ServerMixin