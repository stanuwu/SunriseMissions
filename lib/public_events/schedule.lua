-- Public-event opportunity of a scheduled site, as the client's Director computes it. The runtime
-- owns the schedule table and its arithmetic (context:public_event_schedule); this module turns the
-- host's answer into the start the site takes.
local schedule = {}

-- The rally flag stands this long before a scheduled start and until it: Destiny 2 announces a
-- public event five minutes ahead (Destinypedia). The client's own map lookahead is unrecovered.
schedule.RALLY_LEAD_SECONDS = 300

schedule.state = {incoming = "incoming", active = "active"}

--- Plans a site's start at the host clock. Start now with the rally counting the seconds left, or
--- with the active arm inside the map's window; otherwise wait. A slot whose pick names another
--- entry is that entry's: the plan names the picked site, and the site waits for the window to pass
--- when no site of the zone owns it.
---@param context table Borrowed callback context.
---@param site_key integer Roster key of the site in the client's schedule.
---@return table|nil plan {arrival = EventArrival} or {wait_seconds, reason, selected_site};
--- nil when unscheduled.
function schedule.arrival(context, site_key)
    local occurrence = context:public_event_schedule{site = site_key}
    if occurrence == nil then return nil end
    if not occurrence.selected then
        return {wait_seconds = math.max(1, occurrence.until_finish), reason = "unselected",
            selected_site = occurrence.site, occurrence = occurrence}
    end
    if occurrence.state == schedule.state.active then
        return {arrival = {active = true}, occurrence = occurrence}
    end
    if occurrence.until_start <= schedule.RALLY_LEAD_SECONDS then
        return {arrival = {rally_seconds = occurrence.until_start,
            rally_total = schedule.RALLY_LEAD_SECONDS}, occurrence = occurrence}
    end
    return {wait_seconds = occurrence.until_start - schedule.RALLY_LEAD_SECONDS, reason = "lead",
        occurrence = occurrence}
end

return schedule
