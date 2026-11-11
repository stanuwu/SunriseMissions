-- Weapons Exchange content parameters and reconstructed policy; state keys remain host-scoped.
-- Values marked "unread" were not legible in the reviewed recording and remain placeholders.
-- The shared skeleton (lib.public_events.event) owns the lifecycle, membership, heroic, reward
-- and incoming keys under the same prefix.
local c = {}

-- Retained keys preserve a running attempt across script reloads; "w" is the event prefix.
c.KEY = "w"
-- Per-squad keys: a live flag and the placement request; the unit's id completes the key.
c.LIVE_KEY, c.REQUEST_KEY = "w.l", "w.q"
-- Wave flags: the Walker has been called, and the Walker deaths that count toward success.
c.CALLED_KEY, c.WALKER_DEAD_KEY, c.HEROIC_DEAD_KEY = "w.wc", "w.wd", "w.hd"
-- Per-receptacle owner keys and per-array open flags; indexes complete the key.
c.DEPOSIT_KEY, c.OPEN_KEY = "w.dp", "w.op"
-- The dropship's path command waits for its actor; the flag survives a reload in between.
c.PATH_KEY = "w.pp"

-- Family timers remain distinct from the shared lifecycle, incoming and rally timers.
c.PATH_TIMER = "wp"

-- Unobserved incoming timing: the reviewed footage starts after the event has joined.
c.KETCH_AFTER_LEAVE_MS, c.ALERT_AFTER_KETCH_MS, c.START_AFTER_ALERT_MS = 5000, 3000, 12000

-- The dropship spawns at its anchor; its path command follows after this reconstructed margin.
c.PATH_MS = 2000

-- Unread clock totals; the reviewed footage never showed a legible reading.
c.EVENT_SECONDS, c.HEROIC_SECONDS = 300, 240
-- Reconstructed heroic eligibility requires time left for the second Walker.
c.HEROIC_MIN_REMAINING_SECONDS = 30

-- The existing freeroam service owns this zone clock and must match its cadence.
c.TICK_SECONDS = 5

-- Cue indexes in the authored dialogue sensor, assigned from the authored line text: the ketch
-- warning, the stockpile remark, the caches opening, the ketch leaving, the Walker wrecked, both
-- Walkers and the cannons taken, and "one Walker short". Cue 4 ("We did some damage") and
-- cue 8 (the tea invitation) have no evidenced trigger and stay unused.
c.CUE_ALERT, c.CUE_START, c.CUE_CACHES, c.CUE_FAILED = 0, 1, 2, 3
c.CUE_SUCCESS, c.CUE_HEROIC_SUCCESS, c.CUE_HEROIC_FAILED = 5, 6, 7

-- Reconstructed music section selections.
c.MUSIC_ACTIVE, c.MUSIC_HEROIC = 0, 1

return c
