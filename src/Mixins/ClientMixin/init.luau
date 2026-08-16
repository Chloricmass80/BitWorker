local BitWorkerModule = script.Parent.Parent

local TLV = require(BitWorkerModule.TLV)
local Utils = require(BitWorkerModule.UtilityFuncs)
local ErrMessages = require(BitWorkerModule.ErrorMessages)
local Settings = require(BitWorkerModule.Settings)
--local BitWorker = require(BitWorkerModule)


local remoteEvent:RemoteEvent = BitWorkerModule:WaitForChild("RecurseNetworker")

type CacheValue = {
    size : number; -- the estimated size of the packet going over the wire
    bytes : buffer; -- the buffer that will be sent
    instances : {Instance}; -- the instance references going over the wire
    plyr : {Player} | Player?; -- The player(s) the request is targeting, if nil and on server, means it's meant for all players. Automatically nil on client.
}


local ClientMixin = {}

function ClientMixin.Apply(BitWorker)
    TLV.SetMaxReadSize(Settings.MaximumServerTransmissionUnit)
    ClientMixin._chunkSize = Settings.MaximumServerTransmissionUnit

    BitWorker.TLVObj = TLV.new(BitWorker._chunkSize)
    BitWorker._pendingPackets = {}

    function BitWorker:_CachePacket(bytes: buffer, instances: {Instance}, size: number)
        local seqNum = self:_GetNewSeqNum()
        local cacheValue = {
            size = size;
            bytes = bytes;
            instances = instances;
        }
        
        self.networkCache[seqNum] = cacheValue
    end

    function BitWorker:FireServer(tag: string, value:any?)
        if type(value) ~= "table" then value = {value} end

        self.TLVObj:AddData(tag, value)
    end

    function BitWorker:_SendPacket(packet)
        if not packet then return end
        local b = packet.packet[1]
        local instances = packet.packet[2]

        if not b or not instances then
            warn("Outgoing packet on the client seems to be malformed."..ErrMessages.CallIgnored)
            return
        end

        remoteEvent:FireServer(b, instances)
    end

    function BitWorker:_FlushCache()
        self._currentNetworkTick += 1
        local packets = self.TLVObj:WithdrawData()

        if not packets then return end
        
        if packets[1] then
            BitWorker:_SendPacket(packets[1])
            if packets[2] then
                Utils.ReverseArray(packets)
                table.move(packets, 1, #packets-1, #self._pendingPackets, self._pendingPackets)
            end
        else
            local packet = self._pendingPackets[#self._pendingPackets]
            self:_SendPacket(packet)
            self._pendingPackets[#self._pendingPackets] = nil
        end
    end


    BitWorker:FireServer("ClientConnected")

    remoteEvent.OnClientEvent:Connect(function(...)
        TLV.DeserializeAndExecute(...)
    end)
end

return ClientMixin