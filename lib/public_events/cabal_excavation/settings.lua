-- Cabal Excavation content parameters and reconstructed policy; state keys remain host-scoped.
-- Timings marked "reference" are read from a retail recording of this event and remain
-- reconstructed family timing policy. The shared skeleton
-- (lib.public_events.event) owns the lifecycle, membership, heroic, reward and incoming keys
-- under the same prefix.
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

-- Reference incoming timing: the sky darkens and the carrier appears about 5 s after the
-- countdown and the alert follows about 9 s later. The lander's arrival branch cuts its
-- thrusters 7.7 s after activation; the ring and clock appeared about 2 s after that, 34 s after
-- the flag left. The lander therefore activates 24 s after the flag and the event 10 s later.
c.SHIP_AFTER_LEAVE_MS, c.ALERT_AFTER_SHIP_MS = 4000, 9000
c.LAND_AFTER_ALERT_MS, c.START_AFTER_LAND_MS = 11000, 10000

-- Authored lander position ranges: arrival is the default state, 0.05 mines, 0.10 withdraws and
-- 0.20 destroys it after 11 s. The first two commanded values were observed in play; the
-- reference shows the destruction about 11 s after the Valus dies.
c.LANDER_MINING, c.LANDER_WITHDRAWAL, c.LANDER_DESTRUCTION = 0.05, 0.10, 0.20

-- Authored carrier position ranges: 0.10 flies in and hovers with a ten-second effect, 0.20 is
-- a separate ten-second effect pass, 0.30 departs and destroys the ship after 13.9 seconds.
-- The reference shows the carrier overhead and firing after the event joins, so it stays until
-- the ending; the 0.20 pass is read as its bombardment and remains unverified in play.
c.SHIP_ARRIVAL, c.SHIP_BOMBARDMENT, c.SHIP_DEPARTURE = 0.10, 0.20, 0.30

-- Reference bombardment: targeting lines about 5 s after joining, the carrier firing at about
-- 10 s and ground impacts at about 15 s. This revision drives one effect pass and the first
-- authored barrage group; the repeat seen at about 36-45 s waits for the first observation.
c.BOMBARD_MS = 8000

-- The plate and the separate ring object each draw a circle on construction; the plate alone
-- carries the capture producer, so the ring object stays down.
c.RING_WITH_ZONE = false

-- Reconstructed normal duration; the reference clock reads 3:56 four seconds after joining.
c.EVENT_SECONDS = 240

-- No sequence-end report is exposed; the active sequence delay remains reconstructed.
c.INTRO_MS = 8000

-- The existing freeroam service owns this zone clock and must match its cadence.
c.TICK_SECONDS = 5

-- Reference wave cadence: three pods of one group land together, and their infantry jump to the
-- plate about 6 s later. Infantry reached it about 21 s and 38 s after the start, so pods land
-- at 14 s and then every 17 s. The drop count and later spacing are reconstructed.
c.FIRST_WAVE_MS, c.WAVE_INTERVAL_MS = 14000, 17000
-- Wave drops in order, repeating; a wave still alive at its turn is skipped, so at most one
-- generation of each authored squad stands at a time.
local EASY_1, EASY_2, MEDIUM_1, MEDIUM_2, HARD_1, HARD_2 = 1, 2, 3, 4, 5, 6
c.WAVE_ORDER = {EASY_1, EASY_2, MEDIUM_1, MEDIUM_2, EASY_1, EASY_2,
    HARD_1, HARD_2, MEDIUM_1, MEDIUM_2, EASY_1, EASY_2}

-- Reference Thresher arrival: the gunship appears about 55 s after joining.
c.THRESHER_MS = 55000
-- The Thresher spawned within 50 ms of its placement in play; its path command follows after
-- this reconstructed margin.
c.THRESHER_PATH_MS = 2000

-- Reference heroic clock: the heroic row showed about 2:55 shortly after the switch.
c.HEROIC_SECONDS = 180
-- Reconstructed heroic eligibility requires time left for the Valus fight.
c.HEROIC_MIN_REMAINING_SECONDS = 30

-- Cue indexes in the authored dialogue sensor; roles follow the authored lines and the
-- reference recording (alert with the carrier, start when joined, "Ship down!" on the Thresher).
c.CUE_ALERT, c.CUE_START, c.CUE_SHIP_DOWN, c.CUE_FAILED = 0, 1, 2, 3
c.CUE_SUCCESS, c.CUE_HEROIC_SUCCESS, c.CUE_HEROIC_FAILED = 5, 8, 9

-- Reconstructed music section selections.
c.MUSIC_ACTIVE, c.MUSIC_HEROIC = 0, 1

-- The plate reports occupancy as a 16-player mask.
c.OCCUPANT_BITS = 16

return c
