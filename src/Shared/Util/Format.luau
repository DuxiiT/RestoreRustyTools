local Format = {}

function Format.Money(Amount: number): string
	local Whole = tostring(math.floor(math.abs(Amount)))
	local Grouped = string.reverse((string.gsub(string.reverse(Whole), "(%d%d%d)", "%1,")))
	if string.sub(Grouped, 1, 1) == "," then
		Grouped = string.sub(Grouped, 2)
	end
	return (if Amount < 0 then "-$" else "$") .. Grouped
end

function Format.Percent(Fraction: number, Decimals: number?): string
	return string.format(`%.{Decimals or 1}f%%`, Fraction * 100)
end

function Format.Duration(Seconds: number): string
	Seconds = math.max(0, math.floor(Seconds))
	local Hours = Seconds // 3600
	local Minutes = (Seconds % 3600) // 60
	local Remaining = Seconds % 60
	if Hours > 0 then
		return string.format("%dh %02dm", Hours, Minutes)
	elseif Minutes > 0 then
		return string.format("%dm %02ds", Minutes, Remaining)
	end
	return `{Remaining}s`
end

return Format
