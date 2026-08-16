local Settings = {
    DebugMode = true; -- Does extra checks on values across RECURSE, even values that should be deterministic and not need validity checks to make sure the engine is running as intended. If false the engine will skip these checks, save a bit of performance, but if something is wrong it's less likely to show up as an explicit error and will usually silently fail. Good to turn this on if the engine is experiencing problems to catch anything going wrong as an explicit error.

    MaximumServerTransmissionUnit = 1024; -- The maximum size (in bytes) that a single packet can take up without counting default Roblox overhead for the RemoteEvent call. If a packet exceeds this size it will be split across multiple networking frames.
    MaximumClientTransmissionUnit = 512;
    NetworkFlushInterval = 30; -- The speed at which the Networker flushes it's request cache and sends data over the network (in hz). This is ultimately limited to however fast heartbeat is fired on the server. So a value like 120 (hz) is naturally capped. It's also worth noting that this operates ontop of Roblox already caching RemoteEvent calls, flushing at ~60 hz (or server heartbeat) so this isn't a perfect science.

    DisciplineCooloffRate = 0.01; -- The rate at which heat is removed from a player. This value is subtracted from each player's value every second.
    MaxDisciplineHeat = 20; -- The maximum heat before Discipline tells the server to ignore the client. Will ignore the client until DisciplineTrustHeat is reached,
    DisciplineTrustHeat = 15;-- The heat that Discipline will wait until trusting the client again after blacklisting it.
    DisciplineMaxBlacklistHistory = 2; -- The maximum amount of times that a player can be blacklisted before their next blacklist will lead to a kick (if able)
    CanDisciplineKick = false -- Allows Discipline to kick clients
}

return Settings