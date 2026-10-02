--!strict
--[[
	LevelConfig
	The level bar under the click button. It is a SHORT-TERM goal, not a second
	progression: the level is read from the Power you have right now, so it
	climbs fast in the first minutes and starts over after a rebirth — exactly
	what the bar is for (something to fill while the real goals are far away).

	Nothing is persisted: LevelFormula derives everything from Currencies.Power,
	so there is no data to migrate and nothing for a client to fake.

		nível n pede BaseStep × Growth^n   (50, 68, 91, 123, ...)

	Growth is what keeps the number sane: with a linear cost the level is the
	square root of your Power, so 2M Power reads "level 298" and the bar means
	nothing. Growing the cost geometrically makes the level a logarithm — it
	climbs fast at the start and then settles into a number a player can carry
	in their head.
]]

return {
	BaseStep = 50,
	Growth = 1.35,
	-- Display cap. Power grows without bound; the number on the bar should not.
	MaxLevel = 100_000,
}
