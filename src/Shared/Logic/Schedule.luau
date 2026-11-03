-- Server-time schedules shared with the client so countdowns match the server.
local ScheduleConfig = require(script.Parent.Parent.Config.ScheduleConfig)

local Schedule = {}

function Schedule.DayIndex(Now: number): number
	return Now // ScheduleConfig.DaySeconds
end

function Schedule.NextDayAt(Now: number): number
	return (Schedule.DayIndex(Now) + 1) * ScheduleConfig.DaySeconds
end

function Schedule.WeekIndex(Now: number): number
	return (Now + ScheduleConfig.WeekOffsetSeconds) // ScheduleConfig.WeekSeconds
end

function Schedule.NextWeekAt(Now: number): number
	return (Schedule.WeekIndex(Now) + 1) * ScheduleConfig.WeekSeconds - ScheduleConfig.WeekOffsetSeconds
end

function Schedule.ActiveFeatured(Now: number)
	local Slot = Now // ScheduleConfig.FeaturedRotationSeconds
	local Entry = ScheduleConfig.FeaturedThemes[(Slot % #ScheduleConfig.FeaturedThemes) + 1]
	return Entry, (Slot + 1) * ScheduleConfig.FeaturedRotationSeconds
end

function Schedule.IsFeaturedPoolActive(PoolId: string, Now: number): boolean
	local Entry = Schedule.ActiveFeatured(Now)
	return Entry.Pool == PoolId
end

-- The same week always yields the same challenges on every server.
function Schedule.WeeklyChallenges(WeekIndex: number)
	local Generator = Random.new(WeekIndex)
	local Pool = table.clone(ScheduleConfig.WeeklyChallenges)
	local Chosen = {}
	for _ = 1, math.min(ScheduleConfig.WeeklyChallengeCount, #Pool) do
		table.insert(Chosen, table.remove(Pool, Generator:NextInteger(1, #Pool)))
	end
	return Chosen
end

return Schedule
