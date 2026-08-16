local RecurseModule = script.Parent.Parent

local RecurseEnum = require(RecurseModule.RecurseEnum)

local tokens = {
    RollOffMode = {
        [0] = Enum.RollOffMode.Inverse;
        [1] = Enum.RollOffMode.InverseTapered;
        [2] = Enum.RollOffMode.Linear;
        [3] = Enum.RollOffMode.LinearSquare
    };
    CustomSoundTimingModel = {
        [0] = RecurseEnum.TimingModels.CustomSound.Immediate;
        [1] = RecurseEnum.TimingModels.CustomSound.Playbacked;
        [2] = RecurseEnum.TimingModels.CustomSound.Timestamped;
    }
}

local tokenLookup = {}

for key, array in pairs(tokens) do
    local lookUp = {}
    tokenLookup[key] = lookUp
    for i=0, #array do
        val = array[i]
        lookUp[val] = i
    end
end

return {Tokens = tokens, TokenLookup = tokenLookup}