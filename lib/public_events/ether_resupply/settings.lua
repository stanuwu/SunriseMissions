-- Ether Resupply parameters and reconstructed policy; state keys remain host-scoped. The shared
-- skeleton (lib.public_events.event) owns the lifecycle, membership, heroic, reward and
-- incoming keys under the same prefix.
local c = {}

-- Retained keys preserve a running attempt across script reloads; "er" is the event prefix.
c.KEY = "er"
c.PRIME_KEY = "er.pr"
-- The skeleton-crew Skiff and its three Vandals; the crew key takes the Vandal's index.
c.SKIFF_KEY, c.CREW_KEY = "er.sk", "er.cr"
-- The intro timer and the stage it is in.
c.INTRO_TIMER, c.INTRO_STAGE_KEY = "eri", "er.ist"
c.INTRO_CREW, c.INTRO_DONE = 1, 2

-- Normal duration: the clock read 4:00 at the join banner and ran on through heroic without a
-- reset in launch-era EDZ footage (Gladd, 2017-09-27). One policy for every site of the family.
c.EVENT_SECONDS = 240

-- Intro beats, reconstructed from the same footage: the drop craft is overhead at 00:19, the Prime
-- materializes under it at 00:21, the join banner follows at 00:22, the clock starts at 00:24, and
-- the crew drops as the Prime appears. The Ketch is the user's report of what comes first.
c.KETCH_AFTER_LEAVE_MS = 1000
c.SKIFF_AFTER_KETCH_MS = 3000
c.START_AFTER_SKIFF_MS = 5000
c.CREW_AFTER_START_MS = 3000
-- The communion and the beam end, the Skiff is retired and the active behavior begins.
c.INTRO_MS = 8000

-- The existing freeroam service owns this zone clock and must match its cadence.
c.TICK_SECONDS = 5

-- Reconstructed music sections, as at the other families. The authored sections of this
-- registry are unmapped.
c.MUSIC_ACTIVE, c.MUSIC_HEROIC = 0, 1

return c
