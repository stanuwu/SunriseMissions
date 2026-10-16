-- Health gates read from the boss squad's replicated damage state (lane-2 damage component).
-- The client clamp holds the boss at the first ten-bit level at or above each floor (880, 614, 338
-- of 1023 for 86/60/33%), so a gate is "level <= floor level", not "fraction <= floor".
local floors={880,614,338}
local gates={}

-- True when this damage state is the boss squad at or below `phase`'s floor.
function gates.reached(event,phase)
    local floor=floors[phase]
    -- Sense rows report -1 for a level they never observed.
    return floor~=nil and event.registry_key==0xC55749AB and event.slot_type==1 and event.slot_index==0
        and type(event.health)=="number" and event.health>=0
        and math.floor(event.health*1023+0.5)<=floor
end

return gates
