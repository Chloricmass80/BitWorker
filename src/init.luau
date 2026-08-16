local RunService = game:GetService("RunService")
local TLV = require(script.TLV)
local Settings = require(script.Settings)

type AgnosticBitWorker = {
    AddTag : (tagName : string, tagConfig: {string | {string}}) -> ();
    AddHandler : (tagName: string, handler: ({any}) -> ()) -> ();
}
type ServerBitWorker = {
    FireAllClients : (tag: string, value: any) -> ();
    FireClient : (tag: string, value: any) -> ();
    FireMultipleClients : (plyrs: {Player}, tag: string, value: any) -> ()
} & AgnosticBitWorker
type ClientBitWorker = {
    FireServer : (tag: string, value: any) -> ();
} & AgnosticBitWorker


local BitWorker = {
    _networkCache = {};
    _chunkSize = Settings.MaximumClientTransmissionUnit; -- bytes
    _currentNetworkTick = 0;
}

TLV.SetDebugMode(Settings.DebugMode)

-- Mixin functions

function BitWorker:_OnClientJoined()
    
end

function BitWorker:_OnClientDestroyed()
    
end

function BitWorker:_GetNewSeqNum()

end

function BitWorker:_FlushCache()
    
end

function BitWorker.AddTag(tagName: string, tagConfig: {string | {string}})
    TLV.AddTag(tagName, tagConfig)
end

function BitWorker.AddHandler(tagName: string, handler: ({any}) -> ())
    TLV.AddHandler(tagName, handler)
end

local cacheHeat = 0
local flushHeat = 1/Settings.NetworkFlushInterval
function BitWorker:_Update(dt: number)
    cacheHeat += dt
    if cacheHeat >= flushHeat then
        cacheHeat -= flushHeat
        self:_FlushCache()
    end
end

TLV.AddTag("ClientConnected", {})

RunService.Heartbeat:Connect(function(deltaTime)
    BitWorker:_Update(deltaTime)
end)

if RunService:IsServer() then
    require(script.Mixins.ServerMixin).Apply(BitWorker)
    return BitWorker :: ServerBitWorker
else
    require(script.Mixins.ClientMixin).Apply(BitWorker)
    return BitWorker :: ClientBitWorker
end