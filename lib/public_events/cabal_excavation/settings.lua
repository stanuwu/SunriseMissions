-- Cabal Excavation encounter settings.
local c = {}

-- Retained keys preserve a running attempt across script reloads; "c" is the event prefix.
c.KEY = "c"
c.LANDER_KEY, c.SHIP_KEY = "c.lp", "c.sp"
c.LANDER_REQUEST_KEY, c.ZONE_REQUEST_KEY, c.WAVE_REQUEST_KEY = "c.ql", "c.qz", "c.qw"
-- Wave keys: sent drop count, one live flag per wave index, deaths, and one standing flag per
-- pod group.
c.WAVE_COUNT_KEY, c.WAVE_LIVE_KEY, c.DEAD_KEY, c.POD_GROUP_KEY = "c.n", "c.w", "c.d", "c.pg"
c.SNIPER_KEY, c.THRESHER_KEY, c.VALUS_KEY, c.GUARD_KEY = "c.sn", "c.th", "c.vl", "c.g"
-- Spawn generation last counted as ended; a late report of it changes nothing.
c.ENDED_WAVE_KEY, c.ENDED_THRESHER_KEY, c.ENDED_VALUS_KEY = "c.eg", "c.et", "c.ev"
-- The Thresher's path command waits for its actor; the flag survives a reload in between.
c.THRESHER_PATH_KEY = "c.tp"
c.OCCUPANTS_KEY = "c.o"
c.CAPTURED_KEY = "c.cp"

-- Family timers remain distinct from the shared lifecycle, incoming and rally timers.
c.INTRO_TIMER, c.WAVE_TIMER, c.THRESHER_TIMER, c.BOMBARD_TIMER = "ci", "cw", "ct", "cb"

-- Reconstructed arrival cadence. Allow the lander to finish its 7.7-second thruster sequence
-- before starting the clock.
c.SHIP_AFTER_LEAVE_MS, c.ALERT_AFTER_SHIP_MS = 4000, 9000
c.LAND_AFTER_ALERT_MS, c.START_AFTER_LAND_MS = 11000, 10000

-- Lander graph: arrival is the default, 0.05 mines, 0.10 withdraws and 0.20 destroys it.
c.LANDER_MINING, c.LANDER_WITHDRAWAL, c.LANDER_DESTRUCTION = 0.05, 0.10, 0.20

-- Carrier graph: arrival and the second effect last 10 seconds. Departure removes the ship
-- after 13.9 seconds. The bombardment assignment is reconstructed.
c.SHIP_ARRIVAL, c.SHIP_BOMBARDMENT, c.SHIP_DEPARTURE = 0.10, 0.20, 0.30

-- Schedule one bombardment with the first authored barrage group.
c.BOMBARD_MS = 8000

-- The plate and the separate ring object each draw a circle on construction; the plate alone
-- carries the capture producer, so the ring object stays down.
c.RING_WITH_ZONE = false

-- The normal override has a four-minute deadline.
c.EVENT_SECONDS = 240

-- No sequence-end report is exposed; the active sequence delay remains reconstructed.
c.INTRO_MS = 8000

-- The existing freeroam service owns this zone clock and must match its cadence.
c.TICK_SECONDS = 5

-- Three pods land together before their infantry enter the plate. Drop spacing is reconstructed.
c.FIRST_WAVE_MS, c.WAVE_INTERVAL_MS = 14000, 17000
-- Wave drops in order, repeating; a wave still alive at its turn is skipped, so at most one
-- generation of each authored squad stands at a time.
local EASY_1, EASY_2, MEDIUM_1, MEDIUM_2, HARD_1, HARD_2 = 1, 2, 3, 4, 5, 6
c.WAVE_ORDER = {EASY_1, EASY_2, MEDIUM_1, MEDIUM_2, EASY_1, EASY_2,
    HARD_1, HARD_2, MEDIUM_1, MEDIUM_2, EASY_1, EASY_2}

-- Reconstructed delay from the join to the Thresher.
c.THRESHER_MS = 55000
-- Allow the Thresher actor to spawn before issuing its flight path.
c.THRESHER_PATH_MS = 2000

-- Heroic starts a fresh clock for the Valus.
c.HEROIC_SECONDS = 180
-- Reconstructed heroic eligibility requires time left for the Valus fight.
c.HEROIC_MIN_REMAINING_SECONDS = 30

-- Dialogue sensor indexes follow the authored lines for the carrier, Thresher and Valus.
c.CUE_ALERT, c.CUE_START, c.CUE_SHIP_DOWN, c.CUE_FAILED = 0, 1, 2, 3
c.CUE_SUCCESS, c.CUE_HEROIC_SUCCESS, c.CUE_HEROIC_FAILED = 5, 8, 9

-- Reconstructed music section selections.
c.MUSIC_ACTIVE, c.MUSIC_HEROIC = 0, 1

-- The plate reports occupancy as a 16-player mask.
c.OCCUPANT_BITS = 16

return c
