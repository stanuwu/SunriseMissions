-- Step chain shared by the campaign mission drafts.
-- A mission is one content declaration. Capabilities in lib/campaign/ each own some of its fields
-- and build their part of the program; campaign.new assembles them in list order.
local lib = require("lib.mission_lib")
local builder = require("lib.campaign.builder")

local campaign = {}

--- Names one squad and the type-1 slot that carries it.
--- @param squad Generated squad identity.
--- @param source Generated slot identity for the same squad.
--- @param group Optional extracted task group for the encounter objective.
--- @param count Optional member count placed in every lane, instead of the package default.
function campaign.unit(squad, source, group, count)
    return {squad = lib.one(squad, "squad"), source = lib.one(source, "squad slot"), group = group,
        count = count}
end

--- A dialogue cue and the volume the client holds it for.
function campaign.line(cue, filter)
    return {cue = lib.one(cue, "dialogue cue"), filter = filter}
end

--- A generator seed that changes with the attempt and never reaches zero.
--- The sandbox has no random source, so the attempt the host owns is the only varying number.
--- @param context Callback context.
--- @return A positive 31-bit integer.
function campaign.run_seed(context)
    local attempt = tonumber(context.attempt_generation) or 1
    local seed = attempt % 0x7FFFFFFF
    if seed == 0 then return 1 end
    return seed
end

--- Moves each device slot with one transition.
function campaign.move(context, slots, transition)
    for _, slot in ipairs(slots) do
        context:slot(slot):transition{transition = context.sdk.device_transitions[transition]}
    end
end

--- Capabilities every campaign mission is built from, in check, declare and build order.
campaign.capabilities = {
    require("lib.campaign.intro"),
    require("lib.campaign.core"),
    require("lib.campaign.encounters"),
    require("lib.campaign.pathing"),
    require("lib.campaign.scenes"),
    require("lib.campaign.actions"),
    require("lib.campaign.sequence"),
    require("lib.campaign.cutscenes"),
    require("lib.campaign.checkpoints"),
    require("lib.campaign.dialogue"),
}

--- Builds the mission table from a content declaration.
--- @param content Table with key, sensors, legs with their trigger and monitor lists, steps and
--- encounters, an optional intro list of {state, cinematic} cutscenes played before the first
--- leg, and an optional spawn_set naming the launch points the client filters its spawn by. Each
--- capability's header lists the further fields it reads.
--- @return The table the runtime loads: initial_state, on_start, on_load and event handlers.
function campaign.new(content)
    return builder.assemble(content, campaign.capabilities)
end

return campaign
