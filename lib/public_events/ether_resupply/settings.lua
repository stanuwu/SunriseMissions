-- Ether Resupply encounter settings.
local c = {}

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

-- The existing freeroam service owns this zone clock and must match its cadence.
c.TICK_SECONDS = 5

-- The authored music sections have no role names; the selections are reconstructed.
c.MUSIC_ACTIVE, c.MUSIC_HEROIC = 0, 1

return c
