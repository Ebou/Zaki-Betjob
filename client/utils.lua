function convertTimestampToDateTime(ms)
  local totalSeconds = math.floor(ms / 1000)

  local days = math.floor(totalSeconds / 86400)
  local remaining = totalSeconds % 86400

  local hour = math.floor(remaining / 3600)
  remaining = remaining % 3600

  local minute = math.floor(remaining / 60)
  local second = remaining % 60

  local base = {
    year = 1970,
    month = 1,
    day = 1
  }

  local function isLeapYear(year)
    return (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
  end

  local daysInMonth = {
    31, 28, 31, 30, 31, 30,
    31, 31, 30, 31, 30, 31
  }

  while days > 0 do
    local dim = daysInMonth[base.month]
    if base.month == 2 and isLeapYear(base.year) then
      dim = dim + 1
    end

    if days >= dim then
      days = days - dim
      base.month = base.month + 1
      if base.month > 12 then
        base.month = 1
        base.year = base.year + 1
      end
    else
      base.day = base.day + days
      days = 0
    end
  end

  return string.format("%04d-%02d-%02d %02d:%02d:%02d", base.year, base.month, base.day, hour, minute, second)
end
