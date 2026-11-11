-- Witches' Ritual presentation: wizard shields, the portal and crystals, and scenery removal.
local c = require("lib.public_events.witches_ritual.settings")
local devices = require("lib.public_events.devices")

local module = {}

--- Binds the site's authored objects; no callback context or mutable state is retained.
---@param definition table Authored site references.
---@return table visuals Bound presentation operations.
function module.new(definition)
    local visuals = {}

    --- Selects the sigil state through the shared position control. Off and the first vacant
    --- value snap; the charge and the wind-down from a held plate glide at the authored rate.
    function visuals.plate(context, scope, index, value)
        local previous = scope:variable(c.PLATE_KEYS[index])
        local snap = value == c.PLATE_OFF
            or (value == c.PLATE_VACANT and previous ~= c.PLATE_OCCUPIED)
        devices.set_position(context, scope, definition.plates[index], c.PLATE_KEYS[index], value,
            snap)
    end

    --- Shows one pillar's charge: its artifact position and the runes lit from the first.
    function visuals.pillar(context, scope, index, lit, fraction)
        devices.set_position(context, scope, definition.artifacts[index],
            c.ARTIFACT_KEYS[index], fraction, true)
        for rune = 1, c.RUNES_PER_ARTIFACT do
            devices.set_position(context, scope, definition.runes[index][rune],
                c.RUNE_KEY .. index .. "." .. rune, rune <= lit and c.RUNE_LIT or c.RUNE_OFF, true)
        end
    end

    --- Leaves the gateway at its standing value; position 1 plays its close and destroy.
    function visuals.gateway(context, scope)
        devices.set_position(context, scope, definition.gateway, c.GATEWAY_KEY, c.GATEWAY_STANDING,
            true)
    end

    --- Returns the next revision for wizard and crystal shield controls.
    local function next_revision(scope)
        local revision = (scope:variable(c.HOP_REVISION_KEY) or 0) + 1
        scope:set_variable(c.HOP_REVISION_KEY, revision)
        return revision
    end

    --- The crystal's first authored output is "immune"; the other outputs stay untouched.
    function visuals.crystal_shield(context, scope, index, protected)
        local key = c.CRYSTAL_SHIELD_KEY .. index
        if scope:variable(key) == protected then return end
        local request = context:slot(definition.crystal_channels[index]):set_output_channels{
            values = {context.sdk.unit(protected and 1 or 0)}, revision = next_revision(scope),
        }
        devices.retain(scope, key, protected, request)
    end

    --- Starts the intro sequence and the objects that stand from the first moment.
    function visuals.begin(context)
        context:activate_objects{slots = {definition.startup}, active = true}
        context:slot(definition.intro):play_sequence{}
    end

    --- Starts the authored active sequence after the intro window.
    function visuals.finish_intro(context)
        context:slot(definition.active):play_sequence{}
    end

    --- Protects one wizard: the filter selects its squad before the hop-on spawns the shield.
    function visuals.raise_shield(context, scope, index)
        local filter = context:slot(definition.shield_filters[index])
        filter:set_object_filter{squad = context:slot(definition.wizards[index].slot)}
        context:slot(definition.shield_hop_ons[index]):set_hop_on{
            filter = filter, revision = next_revision(scope),
        }
    end

    --- Removes one wizard's shield; an absent filter removes the hop-on's objects.
    function visuals.drop_shield(context, scope, index)
        return context:slot(definition.shield_hop_ons[index]):set_hop_on{
            revision = next_revision(scope),
        }
    end

    --- Plays the authored sequence that marks one charge step on a held plate.
    function visuals.play_increment(context, index)
        context:slot(definition.increment[index]):play_sequence{}
    end

    --- Plays the authored sequence that marks one shield changing state.
    function visuals.play_shield_change(context, index, restored)
        local list = restored and definition.restore or definition.disrupt
        context:slot(list[index]):play_sequence{}
    end

    --- Opens the portal and exposes both crystals.
    function visuals.open_portal(context)
        context:activate_objects{slots = definition.portal, active = true}
        context:activate_objects{slots = definition.crystals, active = true}
    end

    --- Objects removed with the chest at cleanup.
    ---@return string[] slots
    function visuals.scenery()
        local slots = {definition.startup}
        for _, slot in ipairs(definition.portal) do slots[#slots + 1] = slot end
        for _, slot in ipairs(definition.crystals) do slots[#slots + 1] = slot end
        return slots
    end

    --- Removes both shields; repeatable cleanup returns the queued requests.
    ---@return table requests
    function visuals.cleanup(context, scope)
        local requests = {}
        for index = 1, #definition.shield_hop_ons do
            requests[#requests + 1] = visuals.drop_shield(context, scope, index)
            requests[#requests + 1] = context:slot(definition.plates[index]):set_channel{
                channel = context.sdk.device_channels.position,
                value = context.sdk.unit(c.PLATE_OFF), snap = true,
            }
            scope:clear_variable(c.CIRCLE_KEY .. index)
            scope:clear_variable(c.CRYSTAL_SHIELD_KEY .. index)
            local pillar = {definition.artifacts[index], table.unpack(definition.runes[index])}
            for _, device in ipairs(pillar) do
                requests[#requests + 1] = context:slot(device):set_channel{
                    channel = context.sdk.device_channels.position,
                    value = context.sdk.unit(c.PILLAR_OFF), snap = true,
                }
            end
        end
        requests[#requests + 1] = context:slot(definition.gateway):set_channel{
            channel = context.sdk.device_channels.position,
            value = context.sdk.unit(c.GATEWAY_STANDING), snap = true,
        }
        return requests
    end

    return visuals
end

return module
