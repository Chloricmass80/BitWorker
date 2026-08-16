-- a tag is formatted as such: {"networkType", {"subTableType"}, "networkType"}
--[[
Valid Network Types:
- "u8" (1 byte)
- "u16" (2 bytes)
- "u32" (4 bytes)
- "i8" (1 byte)
- "i16" (2 bytes)
- "i32" (4 bytes)
- "f32" (4 bytes)
- "f64" (8 bytes)
- "guid" (17 bytes)
- "string" (1 byte/char + 1 byte overhead)
- "boolean" (1 byte)
- "instance" (~4 bytes, + 2 bytes overhead for including an instance in the tag config, paid once. For example: 2 instances in the same tag, ~10 bytes.)

Network Flags:
- "SPARSE" (marks the table it sits in as being sparse, AKA being able to have nil slots, tells serializer to create a bitmask for it.)
- "..." (Marks the table it sits in as being able to have a variable amount of arguments, allows the passed values to repeat the network types of the table this flag sits in over and over.)
]]

-- u16 (communicate network Id)
-- boolean (looped)
-- u8 (timing model)

--     transmit sounds under CustomSound (repeating)
------- u8 (give server's soundId to agree)
------- string (sound name)
------- f64 (sound AssetId)
------- f32 (weight)
------- f32 (cooldown time)

------- sound Properties (just a table, nothing special)
------------ boolean (PlayOnRemove)
------------ f32 (RollOffMaxDistance)
------------ f32 (RollOffMinDistance)
------------ u8 (RollOffMode)
------------ boolean (Playback Regions Enabled)
------------ f32 (Playback Speed)
------------ f32 (volume)

-------   transmit SoundEffects under sound (repeating)
------------ u16 (sound effect NetId)

------- f32 (min playback variance)
------- f32 (max playback variance)
------- f32 (min volume variance)
------- f32 (max volume variance)
------- f32 (min starting pos variance)
------- f32 (max starting pos variance)
------- f32 (min delay variance)
------- f32 (max delay variance)


local tags = {
    ClientConnected = {}; -- Client fires this when they connect to let the server know they exist and are listening
    -- RECURSE Instance tags (first u16 is the RECURSE Instance NetworkID so that it can be identified by the receiver.)
    SoundInstanceChangeName = {"u16", "string"};
    SoundInstanceAddTag = {"u16", "string"}; -- optimize reused tags to be u16s later
    SoundInstanceRemoveTag = {"u16", "string"}; -- optimize reused tags to be u16s later
    -- Custom Sound Tags (first u16 is the RECURSE Instance NetworkID so that it can be identified by the receiver.)
    --                      netId  looped  timing sndId  soundName assetId weight cooldown
    CustomSoundSnapshot = {"u16", "boolean", "u2", {"u8", "string", "f64", "f32", "f32", {"SPARSE", "boolean", "f32", "f32", "u2", "boolean", "u16", "u16"}, {"u16", "..."}, {"SPARSE", "u16", "u16", "u16", "u16", "u16", "u16", "f32", "f32"}, "..."}, {"SPARSE", "u8", "u16", "f64"}};
    CustomSoundCreate = {"SPARSE", "u16", "string", "instance"};
    CustomSoundAddSound = {"u16", "string", "f64", "f32", "f32"};
    CustomSoundRemoveSound = {"u16", "u8"};
    CustomSoundSoundProperties = {"SPARSE", "u16", {"SPARSE", "boolean", "f32", "f32", "u2", "boolean", "u16", "u16"}, "u8"}; -- u2 used as a token to represent rolloff mode, volume quantized via u16, playBackspeed quantized via u16
    CustomSoundSoundParameters = {"SPARSE", "u16", "f32", "f32", "u8"};
    CustomSoundEffectAdded = {"SPARSE", "u16", "u16", "u8"};
    CustomSoundEffectRemoved = {"SPARSE", "u16", "u16", "u8"};
    CustomSoundParentChanged = {"u16", "instance"};
    CustomSoundEnableLooped = {"u16"};
    CustomSoundDisableLooped = {"u16"};
    CustomSoundPlaybackVariance = {"SPARSE", "u16", "u16", "u16", "u8"}; -- playback speed quantized via u16
    CustomSoundVolumeVariance =  {"SPARSE", "u16", "u16", "u16", "u8"}; -- volume quantized via u16
    CustomSoundStartingPosVariance =  {"SPARSE", "f32", "f32", "u16", "u8"};
    CustomSoundDelayVariance =  {"SPARSE", "u16", "f32", "f32", "u8"};
    CustomSoundTimingModel =  {"u16", "u2"}; -- u2 used as a token to represent timing model
    CustomSoundImmediatePlay =  {"u16", "u16"};
    CustomSoundDestroy =  {"u16"};
    CustomSoundPlay =  {"u16", "u16", "boolean"};
    CustomSoundStop =  {"u16"};
    CustomSoundPause =  {"u16"};
    CustomSoundResume =  {"u16"};
}

return tags