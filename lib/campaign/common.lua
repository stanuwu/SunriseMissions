-- Helpers several campaign capabilities share.
local common = {}

--- @return The value as a list: nil is empty, a table is itself, anything else is one entry.
function common.list(value)
    if value == nil then return {} end
    if type(value) == "table" then return value end
    return {value}
end

--- Lists every table that can carry actions: steps, encounters and their sequence items.
--- @return A list of {where = description for errors, holder = the table, item = true for a
--- sequence item}.
function common.holders(content)
    local result = {}
    local function add(where, holder)
        result[#result + 1] = {where = where, holder = holder}
        local items = holder.sequence
        if type(items) == "table" then
            for index = 1, #items do
                if type(items[index]) == "table" then
                    result[#result + 1] = {where = where .. " sequence " .. index,
                        holder = items[index], item = true}
                end
            end
        end
    end
    for _, step in ipairs(content.steps or {}) do add("step " .. tostring(step.id), step) end
    for _, encounter in ipairs(content.encounters or {}) do
        add("encounter " .. tostring(encounter.id), encounter)
    end
    return result
end

-- A filtered line waits in the client until the player enters the filter volume.
local function say(content, context, line)
    context:slot(content.dialogue_sensor):play_dialogue_cue{
        cue = line.cue, filter = line.filter ~= nil and context:slot(line.filter) or nil,
    }
end

--- Plays every line a step or an encounter holds, in list order.
function common.speak(content, context, holder)
    for _, line in ipairs(holder.lines or {}) do say(content, context, line) end
end

return common
