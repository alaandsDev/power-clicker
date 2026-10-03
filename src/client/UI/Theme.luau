--!strict
--[[
	Theme
	Visual constants for the UI. Layout is authored at ReferenceSize and
	scaled uniformly by UIController (UIScale), so offsets here are in
	reference pixels.

	Icons: emoji fallbacks; uploaded images (IconImages) win when present.
]]

local AssetIds = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("AssetIds"))

-- Uploaded icon for a Theme.Icons key: AssetIds.icon_<lowercase key>, else "".
local function iconImage(key: string): string
	return AssetIds["icon_" .. string.lower(key)] or ""
end

local Theme = {
	ReferenceSize = Vector2.new(1280, 720),
	MinScale = 0.5,
	MaxScale = 1.6,

	Font = Enum.Font.GothamBold,
	FontRegular = Enum.Font.GothamMedium,
	FontDisplay = Enum.Font.FredokaOne, -- rounded display font (numbers, HUD titles)
	FontMono = Enum.Font.RobotoMono, -- small caps captions on HUD cards

	Corner = UDim.new(0, 14),
	CornerSmall = UDim.new(0, 8),

	Colors = {
		Background = Color3.fromRGB(24, 26, 40),
		Panel = Color3.fromRGB(34, 37, 58),
		PanelLight = Color3.fromRGB(48, 52, 80),
		Stroke = Color3.fromRGB(12, 13, 22),
		Text = Color3.fromRGB(255, 255, 255),
		TextDim = Color3.fromRGB(180, 186, 215),
		Power = Color3.fromRGB(255, 196, 45),
		Gems = Color3.fromRGB(80, 220, 255),
		Good = Color3.fromRGB(70, 210, 110),
		Bad = Color3.fromRGB(235, 80, 80),
		Disabled = Color3.fromRGB(90, 94, 115),
		Accent = Color3.fromRGB(140, 90, 255),
		ClickTop = Color3.fromRGB(255, 120, 60),
		ClickBottom = Color3.fromRGB(255, 60, 120),
		OverdriveTop = Color3.fromRGB(255, 230, 60),
		OverdriveBottom = Color3.fromRGB(255, 70, 20),
		ComboTiers = {
			Color3.fromRGB(255, 255, 255),
			Color3.fromRGB(120, 230, 255),
			Color3.fromRGB(190, 120, 255),
			Color3.fromRGB(255, 90, 160),
		},
	},

	--[[
		Light panels. Modals (pets, eggs, shop, pass...) are white with dark
		text; the HUD over the 3D world stays dark. Build maps the dark colours
		to these automatically for anything created inside a panel, so the
		controllers do not carry two palettes.
	]]
	Panel = {
		Bg = Color3.fromRGB(246, 247, 251),
		Card = Color3.fromRGB(230, 233, 243),
		CardAlt = Color3.fromRGB(214, 219, 235),
		Text = Color3.fromRGB(22, 24, 38),
		TextDim = Color3.fromRGB(88, 94, 118),
		Stroke = Color3.fromRGB(196, 201, 219),
		-- Accents darkened so they still read on white.
		Power = Color3.fromRGB(176, 124, 0),
		Gems = Color3.fromRGB(16, 122, 160),
		Good = Color3.fromRGB(28, 134, 68),
		Bad = Color3.fromRGB(188, 40, 40),
		Accent = Color3.fromRGB(96, 52, 196),
		Disabled = Color3.fromRGB(140, 146, 168),
	},

	Icons = {
		Power = "⚡", -- TODO_ASSET
		Gems = "💎", -- TODO_ASSET
		Upgrades = "⬆️", -- TODO_ASSET
		Rebirth = "🔁", -- TODO_ASSET
		Pets = "🐾", -- TODO_ASSET
		Eggs = "🥚", -- TODO_ASSET
		Worlds = "🌍", -- TODO_ASSET
		Rewards = "🎁", -- TODO_ASSET
		Quests = "📜", -- TODO_ASSET
		Ranking = "🏆", -- TODO_ASSET
		Shop = "🛒", -- TODO_ASSET
		Season = "🎫", -- TODO_ASSET
		Wins = "🏆", -- TODO_ASSET
		Swords = "🗡️", -- TODO_ASSET
		Tower = "⚔️", -- TODO_ASSET (Caminho do Poder)
		Auras = "✨", -- TODO_ASSET
		Runes = "🔮", -- TODO_ASSET
		Settings = "⚙️", -- TODO_ASSET
		Debug = "🛠️", -- Studio test panel toggle
		Equipped = "✅",
		Locked = "🔒",
		Close = "✕",
	},

	--[[
		Custom icon images, filled from Shared/Config/AssetIds (icon_<key>) by
		tools/upload_assets.py; they replace the emoji everywhere (menu, HUD,
		flyers). Empty = emoji.
		Recommended art: 512x512 PNG, transparent background, no text,
		thick outline so it reads at small sizes.
	]]
	IconImages = {
		Power = iconImage("Power"),
		Gems = iconImage("Gems"),
		Upgrades = iconImage("Upgrades"),
		Rebirth = iconImage("Rebirth"),
		Pets = iconImage("Pets"),
		Eggs = iconImage("Eggs"),
		Worlds = iconImage("Worlds"),
		Rewards = iconImage("Rewards"),
		Quests = iconImage("Quests"),
		Ranking = iconImage("Ranking"),
		Shop = iconImage("Shop"),
		Season = iconImage("Season"),
		Wins = iconImage("wins"),
		Swords = iconImage("swords"),
		Tower = iconImage("tower"),
		Auras = iconImage("auras"),
		Runes = iconImage("runes"),
		Settings = iconImage("Settings"),
	} :: { [string]: string },

	-- HUD layout (Art Bible mockup): currencies + goals top-left, menu grid
	-- right, equipped pets bottom-left, egg shortcuts bottom-right, click
	-- button bottom-centre. Reference pixels.
	Hud = {
		Margin = 18,
		TopSafe = 76, -- extra top gap for Roblox's topbar buttons (left corner)
		Gap = 10,
		Surface = Color3.fromRGB(15, 17, 27),
		SurfaceTransparency = 0.2,
		Card = Color3.fromRGB(24, 26, 40),
		CardBorder = Color3.fromRGB(42, 47, 73),
		Border = Color3.fromRGB(58, 65, 102),
		AccentBorderTransparency = 0.45, -- coloured borders are drawn at ~55% alpha
		--[[
			Moedas em UMA fileira horizontal no topo. Passada de UX: tudo aqui
			encolheu ~18%, porque o mapa e o personagem é que têm de ser o foco
			— a UI apoia o jogo, não cobre o jogo.
		]]
		PillSize = Vector2.new(162, 44),
		PillIcon = 30,
		TopBarGap = 8,
		TopBarY = 44, -- below Roblox's own top bar
		-- The click stack at the bottom, shared by ClickController (button,
		-- overdrive, combo) and HudController (level bar) so they never land on
		-- top of each other.
		--[[
			Composição única do rodapé, de baixo para cima:
				barra de nível → botão CLIQUE → ganho por clique
			O botão continua sendo a ação principal, mas menor: era 300x90.
		]]
		--[[
			Polimento do HUD: botão ~17% menor (era 192x58) e o rodapé virou UM
			bloco compacto. Acima do botão fica só uma faixa fina:
				Nv. 12 · COMBO x8 · 🔥 55%
				[========barra de nível========]
			Ganho por clique e ganho automático NÃO têm texto fixo: aparecem
			como números flutuantes temporários ACIMA dessa faixa.
		]]
		ClickBottom = 16,
		ClickHeight = 48,
		ClickWidth = 160,
		ClickTouchExtra = Vector2.new(36, 12),
		-- A barra é do COMPONENTE único: nível + combo + overdrive + progresso.
		-- Teste no Studio: a faixa ficou pequena demais. +~25% (era 270x8 e
		-- texto 15); o botão CLIQUE continua do mesmo tamanho.
		LevelBar = Vector2.new(330, 11),
		LevelGap = 6,
		StatusRow = 22, -- linha "Nv. 12 · COMBO x8 · 🔥 55%"
		-- Faixa central logo abaixo das moedas: buffs, evento, chefe, treino e
		-- a faixa do corredor entram AQUI, empilhados, em vez de cada um
		-- escolher uma posição fixa e cair em cima das moedas ou do vizinho.
		TopStackWidth = 560,
		MenuCell = 54, -- ícone + legenda; era 72 (passada de UX: -25%)
		MenuCaption = 11,
		MenuColumns = 2,
		MenuRows = 3, -- principais: 2 colunas x 3 linhas (4 sistemas + "Mais")
		MenuCenterY = 0.45, -- fraction of the height (clear of the Roblox player list)
		ChipHeight = 34, -- rounded chips (zone, happy hour)
		EggPanelWidth = 330,
		EggCardHeight = 98,
		GoalsWidth = 300,
	},

	Tween = {
		Fast = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Normal = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Float = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	},
}

-- Dark colour -> its light-panel counterpart. Anything not listed is a strong
-- accent that already reads on white (button fills), so it is kept as is.
local TEXT_ON_LIGHT: { [Color3]: Color3 } = {
	[Theme.Colors.Text] = Theme.Panel.Text,
	[Theme.Colors.TextDim] = Theme.Panel.TextDim,
	[Theme.Colors.Power] = Theme.Panel.Power,
	[Theme.Colors.Gems] = Theme.Panel.Gems,
	[Theme.Colors.Good] = Theme.Panel.Good,
	[Theme.Colors.Bad] = Theme.Panel.Bad,
	[Theme.Colors.Accent] = Theme.Panel.Accent,
	[Theme.Colors.Disabled] = Theme.Panel.Disabled,
	[Theme.Colors.PanelLight] = Theme.Panel.Text,
	[Theme.Colors.Panel] = Theme.Panel.Text,
}

local SURFACE_ON_LIGHT: { [Color3]: Color3 } = {
	[Theme.Colors.Background] = Theme.Panel.Bg,
	[Theme.Colors.Panel] = Theme.Panel.Bg,
	[Theme.Colors.PanelLight] = Theme.Panel.Card,
	[Theme.Colors.Stroke] = Theme.Panel.Stroke,
	[Theme.Colors.Disabled] = Theme.Panel.Disabled,
}

-- Text colour to use for `color` inside a light panel.
function Theme.TextOnLight(color: Color3): Color3
	return TEXT_ON_LIGHT[color] or color
end

-- Background colour to use for `color` inside a light panel.
function Theme.SurfaceOnLight(color: Color3): Color3
	return SURFACE_ON_LIGHT[color] or color
end

local LIGHT_SURFACES: { [Color3]: boolean } = {
	[Theme.Panel.Bg] = true,
	[Theme.Panel.Card] = true,
	[Theme.Panel.CardAlt] = true,
	[Theme.Panel.Stroke] = true,
	[Theme.Panel.Disabled] = true,
}

-- True when `color` is one of the pale panel fills (dark text belongs on it).
function Theme.IsLightSurface(color: Color3): boolean
	return LIGHT_SURFACES[color] == true
end

return Theme
