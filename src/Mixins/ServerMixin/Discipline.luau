local Players = game:GetService("Players")


local BitWorkerModule = script.Parent.Parent.Parent

local Settings = require(BitWorkerModule.Settings)
local InfractionTypes = require(script.Parent.InfractionTypes)

type Infraction = InfractionTypes.Infraction

local Discipline = {
    _plyrHeat = {};
    _plyrsWithHeat = {};
    _blackList = {};
    _blackListHistory = {};
    _onHeatAddedFunc = nil
}

function Discipline:AddHeatAddedFunc(func : (plyr: Player, infraction: string) -> (...any))
    self._onHeatAddedFunc = func
end

function Discipline:OnPlayerLeft(plyr: Player)
    self._plyrHeat[plyr] = nil
    self._blackList[plyr] = nil
    self._plyrsWithHeat[plyr] = nil
end

function Discipline:BlacklistPlayer(plyr: Player, blackListTime: number?)
    if self._blackListHistory[plyr] and self._blackListHistory[plyr] == Settings.DisciplineMaxBlacklistHistory and Settings.CanDisciplineKick then
        plyr:Kick("RECURSE: Suspicious network interactions.")
        Discipline:OnPlayerLeft(plyr)
    end
    self._blackList[plyr] = true
    if blackListTime then
        local calculatedHeat = (Settings.DisciplineCooloffRate * blackListTime) + Settings.DisciplineTrustHeat
        self._plyrHeat[plyr] = calculatedHeat
    else
        self._plyrHeat[plyr] = Settings.MaxDisciplineHeat
    end
    self._blackListHistory[plyr] = (self._blackListHistory[plyr] or 0) + 1
end

function Discipline:AddHeat(plyr: Player, infraction: Infraction)
    if self._onHeatAddedFunc then self._onHeatAddedFunc(plyr, infraction.name) end
    self._plyrHeat[plyr] = (self._plyrHeat[plyr] or 0) + infraction.heat
    self._plyrsWithHeat[plyr] = true

    if self._plyrHeat[plyr] >= Settings.MaxDisciplineHeat then
        self:BlacklistPlayer(plyr)
    end
    warn(string.format("Discipline added a %s infraction to %s.\nHeat Added: %s.\nTotal Plyr Heat: %s.", infraction.name, plyr.Name, tostring(infraction.heat), tostring(self._plyrHeat[plyr])))
end

function Discipline:GetBlackList() : {[Player] : boolean?}
    return self._blackList
end

function Discipline:Update(dt: number)
    local frameHeatRemoval = dt * Settings.DisciplineCooloffRate
    for _, plyr in ipairs(Players:GetPlayers()) do
        if not self._plyrHeat[plyr] then continue end

        self._plyrHeat[plyr] = math.max(self._plyrHeat[plyr] - frameHeatRemoval, 0)

        if self._plyrHeat[plyr] == 0 then
            self._plyrHeat[plyr] = nil
        elseif self._plyrHeat <= Settings.DisciplineTrustHeat and self._blackList[plyr] then
            self._blackList[plyr] = nil
        end
    end
end


return Discipline