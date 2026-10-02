--!strict
--[[
	Build
	Small helpers to create UI instances in code (no Studio-authored GUIs, so
	the whole UI lives in source control).

		local label = Build.new("TextLabel", { Text = "Hi", Parent = frame })
		Build.corner(frame) ; Build.stroke(frame)
		local button = Build.button({ Text = "Buy", Size = ... })
]]

local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Build = {}

--[[
	Light panels: UIController marks a modal with the "LightPanel" attribute
	and everything built inside it gets the dark palette swapped for the light
	one (Theme.TextOnLight / SurfaceOnLight). Controllers keep using
	Theme.Colors as before — the swap happens here, in one place.
]]
local LIGHT_ATTRIBUTE = "LightPanel"

local function inLightPanel(parent: any): boolean
	local node: Instance? = if typeof(parent) == "Instance" then parent else nil
	while node do
		if node:GetAttribute(LIGHT_ATTRIBUTE) == true then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Creates an instance, applies props (Parent last) and parents children.
function Build.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent: Instance? = nil
	local light = props ~= nil and inLightPanel(props.Parent)
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			elseif light and typeof(value) == "Color3" then
				local mapped = if key == "TextColor3" then Theme.TextOnLight(value) else Theme.SurfaceOnLight(value)
				;(instance :: any)[key] = mapped
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Build.corner(parent: Instance, radius: UDim?): UICorner
	return Build.new("UICorner", { CornerRadius = radius or Theme.Corner, Parent = parent })
end

function Build.stroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return Build.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or Theme.Colors.Stroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Build.textStroke(parent: Instance, thickness: number?): UIStroke
	return Build.new("UIStroke", {
		Thickness = thickness or 2,
		Color = Theme.Colors.Stroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = parent,
	})
end

function Build.padding(parent: Instance, pixels: number): UIPadding
	local p = UDim.new(0, pixels)
	return Build.new("UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p, Parent = parent })
end

function Build.gradient(parent: Instance, top: Color3, bottom: Color3): UIGradient
	return Build.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = 90,
		Parent = parent,
	})
end

function Build.label(props: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextColor3 = Theme.Colors.Text,
		TextSize = 22,
	}
	for key, value in props do
		defaults[key] = value
	end
	local label: TextLabel = Build.new("TextLabel", defaults)
	local stroke = Build.textStroke(label)
	if inLightPanel(props.Parent) then
		-- Dark text on white needs no outline; an outline only muddies it.
		stroke.Transparency = 1
	end
	return label
end

-- True for a usable uploaded image ("rbxassetid://<digits>").
function Build.isAsset(value: any): boolean
	return type(value) == "string" and string.match(value, "^rbxassetid://%d+$") ~= nil
end

-- Icon element for an emoji from Theme.Icons. Uses Theme.IconImages[key]
-- (an uploaded image) when configured, otherwise the emoji as text.
-- `props` are applied to either kind (TextSize is ignored for images).
function Build.icon(emoji: string, props: { [string]: any }): GuiObject
	local key: string? = nil
	for name, value in Theme.Icons :: { [string]: string } do
		if value == emoji then
			key = name
			break
		end
	end
	local image = if key then Theme.IconImages[key] else nil
	if image and image ~= "" then
		local imageProps: { [string]: any } = {
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
		}
		for name, value in props do
			if name ~= "TextSize" and name ~= "Text" and name ~= "TextColor3" then
				imageProps[name] = value
			end
		end
		local label: ImageLabel = Build.new("ImageLabel", imageProps)
		--[[
			If Roblox cannot deliver the picture (moderation still pending, a
			bad connection, a blocked CDN), an ImageLabel just stays blank and
			the player faces an empty HUD. PreloadAsync reports the real
			outcome — IsLoaded alone would lie, because Roblox only downloads an
			image when it is about to be drawn, so anything inside a closed
			panel would look "failed" forever.
		]]
		task.spawn(function()
			local ok, status = pcall(function()
				local result: Enum.AssetFetchStatus = Enum.AssetFetchStatus.Failure
				ContentProvider:PreloadAsync({ label }, function(_id: string, fetched: Enum.AssetFetchStatus)
					result = fetched
				end)
				return result
			end)
			if ok and status == Enum.AssetFetchStatus.Success then
				return
			end
			local parent = label.Parent
			if not parent then
				return
			end
			local fallback: { [string]: any } = { Text = emoji }
			for name, value in props do
				fallback[name] = value
			end
			fallback.Parent = parent
			Build.label(fallback)
			label:Destroy()
		end)
		return label
	end
	local textProps: { [string]: any } = { Text = emoji }
	for name, value in props do
		textProps[name] = value
	end
	return Build.label(textProps)
end

--[[
	Sets a colour AFTER creation (state changes: affordable, claimed, locked).
	Use this instead of `gui.BackgroundColor3 = c`, so the light-panel swap
	also applies to colours chosen at runtime. Outside a light panel it is a
	plain assignment.
]]
function Build.paint(gui: Instance, property: string, color: Color3)
	local light = inLightPanel(gui)
	local final = color
	if light then
		final = if property == "TextColor3" then Theme.TextOnLight(color) else Theme.SurfaceOnLight(color)
	end
	;(gui :: any)[property] = final
	if not light or property ~= "BackgroundColor3" or not gui:IsA("TextButton") then
		return
	end
	-- A button that just changed fill also needs readable text: dark on a pale
	-- fill, white (with its outline) on a coloured one.
	local pale = Theme.IsLightSurface(final)
	gui.TextColor3 = if pale then Theme.Panel.Text else Theme.Colors.Text
	for _, child in gui:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			child.Transparency = if pale then 1 else 0
		end
	end
end

-- Dark translucent HUD card (Art Bible style). `accent` tints the border.
function Build.hudSurface(frame: GuiObject, radius: UDim, accent: Color3?): UIStroke
	frame.BackgroundColor3 = Theme.Hud.Surface
	frame.BackgroundTransparency = Theme.Hud.SurfaceTransparency
	Build.corner(frame, radius)
	local stroke = Build.stroke(frame, 2, accent or Theme.Hud.Border)
	stroke.Transparency = if accent then Theme.Hud.AccentBorderTransparency else 0
	return stroke
end

-- TextButton with rounded corners, stroke and a press "bounce".
function Build.button(props: { [string]: any }): TextButton
	local defaults: { [string]: any } = {
		BackgroundColor3 = Theme.Colors.Good,
		Font = Theme.Font,
		TextColor3 = Theme.Colors.Text,
		TextSize = 22,
		AutoButtonColor = true,
	}
	for key, value in props do
		defaults[key] = value
	end
	local button: TextButton = Build.new("TextButton", defaults)
	Build.corner(button, Theme.CornerSmall)
	Build.stroke(button, 2)
	local textStroke = Build.textStroke(button, 1.5)
	if inLightPanel(props.Parent) then
		-- A coloured fill (buy, close, claim) keeps white text with its dark
		-- outline; a pale fill takes the panel's dark text and no outline.
		if Theme.IsLightSurface(button.BackgroundColor3) or button.BackgroundTransparency > 0.5 then
			textStroke.Transparency = 1
		else
			button.TextColor3 = Theme.Colors.Text
		end
	end
	Build.pressEffect(button)
	return button
end

-- Springy press on activation (mouse, touch, gamepad) + hover grow on mouse.
function Build.pressEffect(button: GuiButton, hoverScale: number?): UIScale
	local Anim = require(script.Parent.Anim) -- lazy: Anim depends on DataController
	local scale = Anim.ScaleOf(button)
	local hover = hoverScale or 1.05
	local hovered = false
	button.Activated:Connect(function()
		Anim.Squash(button, if hovered then hover else 1)
	end)
	button.MouseEnter:Connect(function()
		hovered = true
		TweenService:Create(scale, Theme.Tween.Normal, { Scale = hover }):Play()
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		TweenService:Create(scale, Theme.Tween.Normal, { Scale = 1 }):Play()
	end)
	return scale
end

-- Horizontal progress bar. Returns (container, setProgress(0..1)).
function Build.progressBar(props: { [string]: any }, fillColor: Color3): (Frame, (number) -> ())
	local defaults: { [string]: any } = {
		BackgroundColor3 = Theme.Colors.Stroke,
		BorderSizePixel = 0,
	}
	for key, value in props do
		defaults[key] = value
	end
	local container: Frame = Build.new("Frame", defaults)
	Build.corner(container, UDim.new(1, 0))
	local fill: Frame = Build.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = fillColor,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = container,
	})
	Build.corner(fill, UDim.new(1, 0))

	local function set(progress: number)
		local clamped = if progress == progress then math.clamp(progress, 0, 1) else 0
		fill.Size = UDim2.fromScale(clamped, 1)
	end
	return container, set
end

return Build
