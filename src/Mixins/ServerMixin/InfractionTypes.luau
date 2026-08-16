export type Infraction = {
    name : string;
    heat : number;
}

local InfractionTypes = {
    MalformedPacket = {
        name = "Oversized Packet";
        heat = 3;
    };
    InvalidSendRate = {
        name = "Invalid Send Rate";
        heat = nil; -- nil because this out-right black lists the client for a given amount of time
    };
    RestrictedPacket = {
        name = "Restricted Packet";
        heat = 5
    }
}

return InfractionTypes