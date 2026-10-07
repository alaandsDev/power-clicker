--!strict
--[[
	EventConfig
	Live-world events (Phase 10):

	Pickups — Power orbs that pop up around the plaza and the unlocked zones.
	          First player to touch one takes it. Worth a few seconds of that
	          player's own clicking, so they stay relevant at every stage.

	Boss    — every BossIntervalSeconds a boss appears on the plaza. Everyone
	          damages it by clicking near it; when it dies each participant is
	          paid for their share of the damage and the WHOLE server gets a
	          Power boost. Its HP scales with who is actually online, so a
	          full server and a lone player both get a fair fight.
]]

return {
	Pickup = {
		IntervalSeconds = 22, -- one orb per interval, per world with players
		MaxAlive = 10,
		LifetimeSeconds = 45,
		-- Orb value = the player's Power per click × this (so it never goes stale).
		ClicksWorth = 25,
		-- Minimum value, for a brand-new player whose click is tiny.
		MinValue = 50,
		SpawnRadius = 120, -- around the world origin
		TouchCooldownSeconds = 0.5,
	},

	Boss = {
		IntervalSeconds = 420, -- 7 min between bosses
		FightSeconds = 120, -- it leaves if nobody finishes it
		-- HP = (sum of online players' Power per click) × ClicksToKill,
		-- floored at MinHp so an empty server still has a real fight.
		ClicksToKill = 220,
		MinHp = 25_000,
		-- The whole damage pool is paid out: a player's share of the damage is
		-- their share of Hp × RewardRatio.
		RewardRatio = 0.75,
		-- Server-wide reward when it dies.
		VictoryBoostId = "Power2x",
		--[[
			C2-E: era 1 stack (15 min) para TODO o mundo — com um boss a cada
			7 min o Power2x ficava permanente. Agora só quem causou dano real
			ao boss (BossService.damageBy) recebe, e só 5 min.
		]]
		VictoryBoostSeconds = 5 * 60,
		Height = 14, -- studs above the plaza
	},
}
