-- Ether Resupply encounter settings.
local c = {}
c.NAME = "Ether Resupply"

-- Retained keys preserve a running attempt across script reloads; "er" is the event prefix.
c.KEY = "er"
c.PRIME_KEY = "er.pr"
-- The skeleton-crew Skiff and its three Vandals; the crew key takes the Vandal's index.
c.SKIFF_KEY, c.CREW_KEY = "er.sk", "er.cr"
-- The intro timer and the stage it is in.
c.INTRO_TIMER, c.INTRO_STAGE_KEY = "eri", "er.ist"
c.INTRO_CREW, c.INTRO_DONE = 1, 2

-- Heroic retains the normal event's four-minute deadline.
c.EVENT_SECONDS = 240

-- Reconstructed arrival order: Ketch, Skiff, Prime and crew, then the join banner.
c.KETCH_AFTER_LEAVE_MS = 1000
c.SKIFF_AFTER_KETCH_MS = 3000
c.START_AFTER_SKIFF_MS = 5000
c.CREW_AFTER_START_MS = 3000
-- The communion and the beam end, the Skiff is retired and the active behavior begins.
c.INTRO_MS = 8000

-- Reconstructed Prime health fractions and time before the Transports withdraw.
c.LONE_HEALTH, c.TRIO_HEALTH = 0.75, 0.50
c.TRANSPORT_WINDOW_MS = 20000
-- The lone and trio windows have separate timers so a late expiry cannot close the next wave.
c.LONE_TIMER, c.TRIO_TIMER = "erl", "ert"
c.TRANSPORT_STAGE = "er.ts"
c.LONE_START_HEALTH = "er.lh" -- A repeated low health sample cannot start both waves.
c.WITHDRAWN = "er.wd" -- A Transport reported removed during this wave.
c.WINDOW_CLOCK = "erwc" -- Samples the host tick when the last Transport falls.
-- Transport placement, last falling generation and support placement keys, indexed by squad.
c.TRANSPORT_KEY, c.FALL_KEY, c.SUPPORT_KEY = "er.tr", "er.tf", "er.su"
-- Reconstructed reinforcement cadence; the third wave brings the Scorch Captain.
c.SUPPORT_INTERVAL_MS = 40000
c.SUPPORT_TIMER, c.SUPPORT_WAVE, c.HEROIC_SHANKS = "erw", "er.sw", "er.hs"

-- Watcher's Grave dialogue cues: arrival, feeding, anger, departure and destruction.
c.CUE_INCOMING, c.CUE_START, c.CUE_HEROIC = 0, 1, 2
c.CUE_FAILED, c.CUE_HEROIC_FAILED = 3, 4
c.CUE_SUCCESS, c.CUE_HEROIC_SUCCESS = 5, 6

-- The existing freeroam service owns this zone clock and must match its cadence.
c.TICK_SECONDS = 5

-- The authored music sections have no role names; the selections are reconstructed.
c.MUSIC_ACTIVE, c.MUSIC_HEROIC = 0, 1

return c
