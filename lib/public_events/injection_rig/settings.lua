-- Injection Rig content parameters and reconstructed policy; state keys remain host-scoped.
-- "Reference" values are read from retail recordings of this event and remain reconstructed
-- family timing policy.
local c = {}

-- Retained keys preserve a running attempt across script reloads; "r" is the event prefix.
c.KEY = "r"
c.SHIP_KEY, c.SPIRE_KEY, c.PYLON_KEY = "r.sd", "r.sp", "r.py"
c.SHIELD_KEY, c.SHIELD_LARGE_KEY = "r.sh", "r.sl"
c.RIG_REQUEST_KEY = "r.qr"
-- Psions killed, the placed Psion's request, the tier now open and the tiers hit.
c.PSIONS_KEY, c.PSION_KEY, c.OPEN_KEY, c.VENT_KEY = "r.pn", "r.ps", "r.op", "r.v"
-- Spawn generation that last ended, per squad. Host events carry the retained generation, so a
-- late count report of an ended generation changes nothing.
c.PSION_ENDED_KEY, c.VALUS_ENDED_KEY = "r.pe", "r.ve"
-- Attempt count choosing the lone bottom vent; hop-on revision shared by every vent control.
c.ATTEMPT_KEY, c.HOP_ON_REVISION_KEY = "r.at", "r.hr"
c.WAVE_KEY, c.HEROIC_WAVE_KEY, c.COMMANDER_KEY = "r.w", "r.hw", "r.cm"
-- Normal play reached its Valus. Reconstructed from guides that describe a Valus after the third
-- Psion; no recording of a normal ending has been watched.
c.FINAL_KEY = "r.fn"
-- The Valus is dead; its counter reads 1 through the ending.
c.VALUS_DEAD_KEY = "r.vd"

-- Family timers remain distinct from the shared lifecycle and incoming timers.
c.PSION_TIMER, c.BURN_TIMER, c.COUNT_TIMER, c.SHIELD_TIMER = "rp", "rb", "rc", "rd"

-- Reference HUD counts three Psions; each opens one vent tier, top then middle then bottom.
c.PSION_COUNT = 3
-- The bottom tier opens one of its three vents; the others open all three.
c.LONE_VENT_TIER = 3

-- Reference clock on Mars: 3:58 about two seconds after joining.
c.EVENT_SECONDS = 240
-- Seconds each Psion kill adds, by kill; timed the same in the Mars and EDZ recordings. The total
-- stays the row's cap: reconstructed, so the clock never reads above its total.
c.KILL_SECONDS = {15, 13, 13}
-- Heroic holds at least this long: Mars kept 3:06 across the switch, EDZ rose from 0:31 to 2:00.
-- Reconstructed from those two readings.
c.HEROIC_MIN_SECONDS = 120

-- The existing freeroam service owns this zone clock and must match its cadence.
c.TICK_SECONDS = 5

-- Reference Mars arrival: alert row about 12 s after the rally ends, the rig falling about 16 s
-- later, joined about 14 s after that with the rig standing.
c.ALERT_AFTER_LEAVE_MS, c.DEPLOY_AFTER_ALERT_MS, c.START_AFTER_DEPLOY_MS = 12000, 16000, 14000
-- Reconstructed Psion delays inside the reference: first dead within 23 s of joining, the next
-- within 18 s of a burn ending.
c.FIRST_PSION_MS, c.NEXT_PSION_MS = 10000, 8000
-- Reference counter stays up about 2 s after a Psion dies before the burn takes the row.
c.COUNT_ROW_MS = 2000
-- Reference dome fades over about 3 s after the Evacuate row ends.
c.SHIELD_CLEAR_MS = 3000
-- Burn length by tier. Both recordings time the first at about 18 s and the second at 13-14 s,
-- which fits the authored 13 s pylon branch. Heroic cuts the third short in both, so it is assumed.
c.BURN_MS = {18000, 13000, 13000}

-- Authored carrier position ranges, class 80BEF691: 0.10 flies in, 0.30 departs.
c.SHIP_ARRIVAL, c.SHIP_DEPARTURE = 0.10, 0.30
-- The spire graph is a continuous lane ending at 1: 80F6509F keys its stages to rising positions,
-- so it is requested without a snap. Its travel time is unverified.
c.SPIRE_DEPLOYED = 1.0
-- Authored pylon ranges, graph 80C00987: 0.1-0.2 idle, 0.2-0.3 13 s burn, 0.3-0.4 exit.
-- The idle and exit roles are inferred from the branch contents.
c.PYLON_IDLE, c.PYLON_BURN, c.PYLON_EXIT = 0.15, 0.25, 0.35
-- Authored shield ranges, graph 80F651A4: 0.15-0.2 and 0.29-0.3; up versus down is unverified.
c.SHIELD_UP, c.SHIELD_DOWN = 0.17, 0.295

-- Reconstructed music section selections.
c.MUSIC_ACTIVE, c.MUSIC_HEROIC = 0, 1

return c
