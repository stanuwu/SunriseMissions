local site = require("lib.public_events.witches_ritual.site")
local witches_ritual = require("lib.public_events.witches_ritual.encounter")

local events = {}

--- Builds the region 56 Witches' Ritual handler on the shared event skeleton.
function events.witches_ritual(mission)
    return witches_ritual.new(site.bind(mission))
end

return events
