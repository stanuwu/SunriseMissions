-- Injection Rig encounter settings.
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
-- Attempt count choosing the lone bottom vent.
c.ATTEMPT_KEY = "r.at"
c.WAVE_KEY, c.HEROIC_WAVE_KEY, c.COMMANDER_KEY = "r.w", "r.hw", "r.cm"
-- The normal route calls the Valus after the third Psion.
c.FINAL_KEY = "r.fn"
-- The Valus is dead; its counter reads 1 through the ending.
c.VALUS_DEAD_KEY = "r.vd"

-- Family timers remain distinct from the shared lifecycle and incoming timers.
c.PSION_TIMER, c.BURN_TIMER, c.COUNT_TIMER, c.SHIELD_TIMER = "rp", "rb", "rc", "rd"

-- Each Psion opens one vent tier in order: top, middle, bottom.
c.PSION_COUNT = 3
-- The bottom tier opens one of its three vents; the others open all three.
c.LONE_VENT_TIER = 3

-- The normal encounter has a four-minute clock.
c.EVENT_SECONDS = 240
-- Each Psion kill extends the clock, up to the row's total duration.
c.KILL_SECONDS = {15, 13, 13}
-- Heroic sets a minimum time left; a longer remaining deadline carries through.
c.HEROIC_MIN_SECONDS = 120

-- The existing freeroam service owns this zone clock and must match its cadence.
c.TICK_SECONDS = 5

-- Reconstructed intervals between flag withdrawal, the alert, the falling rig and the join.
c.ALERT_AFTER_LEAVE_MS, c.DEPLOY_AFTER_ALERT_MS, c.START_AFTER_DEPLOY_MS = 12000, 16000, 14000
-- Reconstructed Psion arrival delays after the join and each burn.
c.FIRST_PSION_MS, c.NEXT_PSION_MS = 10000, 8000
-- Keep the Psion counter visible before switching to the burn objective.
c.COUNT_ROW_MS = 2000
-- The dome fades after the Evacuate objective ends.
c.SHIELD_CLEAR_MS = 3000
-- Burn durations by tier. The middle pylon has a 13-second branch; the final tier reuses it.
c.BURN_MS = {18000, 13000, 13000}

-- Authored carrier position ranges, class 80BEF691: 0.10 flies in, 0.30 departs.
c.SHIP_ARRIVAL, c.SHIP_DEPARTURE = 0.10, 0.30
-- Graph 80F6509F enters its stages in order as the spire rises, so deployment must not snap.
c.SPIRE_DEPLOYED = 1.0
-- Authored pylon ranges, graph 80C00987: 0.1-0.2 idle, 0.2-0.3 13 s burn, 0.3-0.4 exit.
-- The idle and exit roles are inferred from the branch contents.
c.PYLON_IDLE, c.PYLON_BURN, c.PYLON_EXIT = 0.15, 0.25, 0.35
-- Graph 80F651A4 uses the 0.15-0.2 and 0.29-0.3 bands. Their shield roles are inferred.
c.SHIELD_UP, c.SHIELD_DOWN = 0.17, 0.295

-- Reconstructed music section selections.
c.MUSIC_ACTIVE, c.MUSIC_HEROIC = 0, 1

return c
