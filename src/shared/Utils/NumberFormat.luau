--!strict
--[[
	NumberFormat
	Display formatting for big numbers. Pure — safe to unit test.

		NumberFormat.Short(1234)      --> "1.23K"
		NumberFormat.Short(5.5e15)    --> "5.50Qa"
		NumberFormat.Short(1e40)      --> "1.00e40"
		NumberFormat.Commas(1234567)  --> "1,234,567"
]]

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local NumberFormat = {}

-- Locale separators. Default "." / ","; the client switches to its locale
-- (pt-BR: "2,54K", "1.234.567") via SetSeparators. Server logs keep defaults.
local decimalSep = "."
local thousandsSep = ","

function NumberFormat.SetSeparators(decimal: string, thousands: string)
	decimalSep = decimal
	thousandsSep = thousands
end

local function localize(text: string): string
	if decimalSep == "." then
		return text
	end
	return (string.gsub(text, "%.", decimalSep))
end

local function trim(text: string): string
	-- "1.50" -> "1.5", "2.00" -> "2"
	local trimmed = string.gsub(text, "(%.%d-)0+$", "%1")
	trimmed = string.gsub(trimmed, "%.$", "")
	return trimmed
end

function NumberFormat.Short(value: number): string
	if value ~= value then
		return "0"
	end
	if value == math.huge then
		return "∞"
	end
	local sign = if value < 0 then "-" else ""
	local absolute = math.abs(value)
	if absolute < 1000 then
		if absolute % 1 == 0 then
			return sign .. string.format("%d", absolute)
		end
		return sign .. localize(trim(string.format("%.2f", absolute)))
	end

	local tier = math.floor(math.log10(absolute) / 3)
	if tier >= #SUFFIXES then
		local exponent = math.floor(math.log10(absolute))
		return sign .. localize(string.format("%.2fe%d", absolute / 10 ^ exponent, exponent))
	end
	local scaled = absolute / 10 ^ (tier * 3)
	-- Rounding can push 999.995K up to "1000K": move to the next tier instead.
	if scaled >= 999.995 and tier + 1 < #SUFFIXES then
		tier += 1
		scaled = absolute / 10 ^ (tier * 3)
	end
	return sign .. localize(trim(string.format("%.2f", scaled))) .. SUFFIXES[tier + 1]
end

function NumberFormat.Commas(value: number): string
	local text = string.format("%d", math.floor(math.abs(value)))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	formatted = string.gsub(formatted, "^,", "")
	if thousandsSep ~= "," then
		formatted = string.gsub(formatted, ",", thousandsSep)
	end
	return (if value < 0 then "-" else "") .. formatted
end

-- "1:05", "12:00", "1:00:00"
function NumberFormat.Duration(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local hours = total // 3600
	local minutes = (total % 3600) // 60
	local secs = total % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%d:%02d", minutes, secs)
end

return NumberFormat
