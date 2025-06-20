lib.callback.register('Bet64-bet:getBalance', function(source)
  local xPlayer = ESX.GetPlayerFromId(source)
  local balance = xPlayer and getPlayerBettingBalance(xPlayer.getIdentifier()) or 0
  DiscordLog("bets", source, "Kontrollerede saldo: " .. balance .. " DKK")
  return balance
end)

lib.callback.register('Bet64-bet:getBets', function(source)
  local xPlayer = ESX.GetPlayerFromId(source)
  local bets = xPlayer and getPlayerBets(xPlayer.getIdentifier()) or {}
  -- DiscordLog("bets", source, "Hentede væddemålshistorik (" .. #bets .. " væddemål)")
  return bets
end)

lib.callback.register('Bet64-bet:getStats', function(source)
  local xPlayer = ESX.GetPlayerFromId(source)
  if xPlayer then
    local stats = getPlayerBettingStats(xPlayer.getIdentifier())
    -- DiscordLog("bets", source, "Hentede statistik - Gevinster: " .. stats.total_winnings .. " DKK, Tab: " .. stats.total_losses .. " DKK")
    return stats
  else
    return { total_winnings = 0, total_losses = 0 }
  end
end)

lib.callback.register('Bet64-bet:getDepositLimitInfo', function(source)
  local xPlayer = ESX.GetPlayerFromId(source)
  if not xPlayer then return { limit = Config.DailyLimit, used = 0, remaining = Config.DailyLimit } end
  
  local identifier = xPlayer.getIdentifier()
  local today = os.date("%Y-%m-%d")
  
  local result = MySQL.query.await('SELECT SUM(amount) as total FROM Bet64_deposits WHERE player_identifier = ? AND deposit_date = ?', 
    { identifier, today })
  
  local totalToday = 0
  if result and result[1] and result[1].total then
    totalToday = result[1].total
  end
  
  local remaining = Config.DailyLimit - totalToday
  if remaining < 0 then remaining = 0 end
  
  
  return {
    limit = Config.DailyLimit,
    used = totalToday,
    remaining = remaining
  }
end)

lib.callback.register('Bet64-bet:isAccountFrozen', function(source)
  local xPlayer = ESX.GetPlayerFromId(source)
  if not xPlayer then return false end
  
  local identifier = xPlayer.getIdentifier()
  return isAccountFrozen(identifier)
end)

lib.callback.register('Bet64-bet:setAccountFrozen', function(source, targetId, frozen)
  local xPlayer = ESX.GetPlayerFromId(source)
  local xTarget = ESX.GetPlayerFromId(targetId)
  
  if not xPlayer or not xTarget then 
    DiscordLog("admin", source, "Forsøgte at ændre frysestatus for ugyldig spiller ID: " .. targetId)
    return false, "Spiller ikke fundet"
  end
  
  local hasPermission = false
  for _, job in pairs(Config.AdminJobs) do
    if xPlayer.getJob().name == job then
      hasPermission = true
      break
    end
  end
  
  if not hasPermission then
    DiscordLog("admin", source, "Forsøgte at ændre frysestatus uden tilladelse")
    return false, "Du har ikke tilladelse til at udføre denne handling"
  end
  
  local targetIdentifier = xTarget.getIdentifier()
  local success = setAccountFrozen(targetIdentifier, frozen)
  
  if success then
    local status = frozen and "frosset" or "aktiveret"
    DiscordLog("account_frozen", source, xTarget.getName() .. "'s konto er blevet " .. status)
    
    TriggerClientEvent('ox_lib:notify', targetId, {
      title = Config.AppName,
      description = frozen and Config.Notifications.AccountFrozen or "Din betting konto er nu aktiv igen",
      type = frozen and "error" or "success"
    })
    
    return true, frozen and Config.Notifications.AccountFrozenSuccess or Config.Notifications.AccountUnfrozenSuccess
  else
    return false, "Fejl ved opdatering af kontostatus"
  end
end)

lib.callback.register('Bet64-bet:placeBet', function(source, gameId, team, betType, odds, amount)
  local xPlayer = ESX.GetPlayerFromId(source)
  if not xPlayer then return false, "Spiller ikke fundet", 0 end

  local identifier = xPlayer.getIdentifier()
  
  if isAccountFrozen(identifier) then
    DiscordLog("bet_placed", source, "Forsøgte at placere væddemål, men kontoen er frosset")
    return false, Config.Notifications.AccountFrozen, getPlayerBettingBalance(identifier)
  end
  
  local balance = getPlayerBettingBalance(identifier)

  if balance < amount then 
    return false, "Ikke nok penge på din betting konto", balance 
  end

  local maxBetLimit = 1500000 -- 500k
  if amount > maxBetLimit then
    DiscordLog("bet_placed", source, "Forsøgte at placere væddemål over max grænsen: " .. amount .. " DKK (Max: " .. maxBetLimit .. " DKK)")
    return false, "Du kan ikke satse mere end " .. maxBetLimit .. " DKK", balance
  end

  local event = MySQL.query.await('SELECT * FROM Bet64_events WHERE id = ?', { gameId })
  if not event or not event[1] then 
    DiscordLog("bet_placed", source, " @everyone Forsøgte at placere væddemål på ikke-eksisterende begivenhed #" .. gameId)
    return false, "Væddemål ikke fundet", balance 
  end
  
  event = event[1]
  
  if not event.is_active or event.is_finished then
    DiscordLog("bet_placed", source, "Forsøgte at placere væddemål på inaktiv begivenhed: " .. event.home_team .. " vs " .. event.away_team)
    return false, "Dette væddemål er ikke længere tilgængeligt", balance
  end
  
  local currentTime = os.time()
  -- print("Current Time:", os.date("%Y-%m-%d %H:%M:%S", currentTime))
  local eventTime
  if type(event.commence_time) == "string" then
    local year, month, day, hour, min, sec = string.match(event.commence_time, "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
    if year and month and day and hour and min and sec then
      eventTime = os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec)
      })
    end
  elseif type(event.commence_time) == "number" then
    eventTime = event.commence_time / 1000
  end
  -- print("Event Time:", event.commence_time, "Parsed Event Time:", eventTime and os.date("%Y-%m-%d %H:%M:%S", eventTime) or "nil")
  if not eventTime or currentTime >= eventTime then
    DiscordLog("bet_placed", source, "Forsøgte at placere væddemål på begivenhed der allerede er startet: " .. event.home_team .. " vs " .. event.away_team)
    return false, "Dette væddemål er allerede startet", balance
  end

  local existingBets = MySQL.query.await('SELECT * FROM Bet64_bets WHERE player_identifier = ? AND status = "active"', { identifier })
  if existingBets then
    for _, bet in ipairs(existingBets) do
      local selections = json.decode(bet.selections)
      for _, selection in ipairs(selections) do
        if selection.event_id == gameId then
          if selection.team == team then
            DiscordLog("bet_placed", source, "Forsøgte at placere væddemål på samme hold i samme kamp igen")
            return false, "Du har allerede et aktivt væddemål på dette hold i denne kamp", balance
          else
            DiscordLog("bet_placed", source, "Forsøgte at placere væddemål på begge hold i samme kamp")
            return false, "Du kan ikke satse på begge hold i samme kamp", balance
          end
        end
      end
    end
  end

  local newBalance = balance - amount
  if not updatePlayerBettingBalance(identifier, newBalance) then 
    DiscordLog("bet_placed", source, "Fejl ved opdatering af saldo ved placering af væddemål")
    return false, "Fejl ved opdatering af saldo", balance 
  end

  local betOdds = 0
  if team == event.home_team then
    betOdds = event.home_odds
  elseif team == event.away_team then
    betOdds = event.away_odds
  elseif team == "Uafgjort" then
    betOdds = event.draw_odds or 3.0
  else
    DiscordLog("bet_placed", source, "Forsøgte at placere væddemål med ugyldigt hold: " .. team)
    return false, "Ugyldigt hold valgt", balance
  end
  
  local potentialWin = amount * betOdds

  local selections = {
    {
      team = team,
      bet = "",
      odds = tostring(betOdds),
      type = "Quick-Odds",
      game = event.home_team .. " vs " .. event.away_team,
      time = os.date("%a %b %d %H:%M", eventTime),
      event_id = gameId
    }
  }

  local betId = addBet(identifier, amount, "Enkelt Væddemål", selections, potentialWin)
  
  if betId then
    DiscordLog("bet_placed", source, "Placerede væddemål #" .. betId .. " på " .. team .. " i " .. event.home_team .. " vs " .. event.away_team .. " for " .. amount .. " DKK med odds " .. betOdds .. " (Potentiel gevinst: " .. potentialWin .. " DKK)")
    return true, "Væddemål placeret", newBalance
  else
    DiscordLog("bet_placed", source, "Fejl ved oprettelse af væddemål")
    return false, "Fejl ved oprettelse af væddemål", balance
  end
end)

lib.callback.register('Bet64-bet:cashoutBet', function(source, betId)
  local xPlayer = ESX.GetPlayerFromId(source)
  if not xPlayer then return false, "Spiller ikke fundet", 0, {} end

  local identifier = xPlayer.getIdentifier()
  
  if isAccountFrozen(identifier) then
    DiscordLog("bet_cashout", source, "Forsøgte at udbetale væddemål, men kontoen er frosset")
    return false, Config.Notifications.AccountFrozen, getPlayerBettingBalance(identifier), getPlayerBets(identifier)
  end
  
  local playerBets = getPlayerBets(identifier)
  local balance = getPlayerBettingBalance(identifier)

  for _, bet in ipairs(playerBets) do
    if bet.id == betId then
      if bet.status ~= "won" then 
        DiscordLog("bet_cashout", source, "Forsøgte at udbetale væddemål #" .. betId .. " som ikke er vundet (Status: " .. bet.status .. ")")
        return false, "Kun vundne væddemål kan udbetales", balance, playerBets 
      end
      
      local cashoutAmount = bet.potential_win
      if updateBetStatus(betId, 'cashed_out') and updatePlayerBettingBalance(identifier, balance + cashoutAmount) then
        local stats = getPlayerBettingStats(identifier)
        local profit = cashoutAmount - bet.amount
        updatePlayerBettingStats(identifier, stats.total_winnings + profit, stats.total_losses)
        
        DiscordLog("bet_cashout", source, "Udbetalte væddemål #" .. betId .. " for " .. cashoutAmount .. " DKK (Profit: " .. profit .. " DKK)")
        
        return true, "Væddemål udbetalt", balance + cashoutAmount, getPlayerBets(identifier)
      else
        DiscordLog("bet_cashout", source, "Fejl ved udbetaling af væddemål #" .. betId)
      end
    end
  end

  DiscordLog("bet_cashout", source, "Forsøgte at udbetale ikke-eksisterende væddemål #" .. betId)
  return false, "Væddemål ikke fundet", balance, playerBets
end)

lib.callback.register('Bet64-bet:getProfileData', function(source)
  local xPlayer = ESX.GetPlayerFromId(source)
  if not xPlayer then return nil end
  
  local identifier = xPlayer.getIdentifier()
  
  local betsResult = MySQL.query.await('SELECT COUNT(*) as total, SUM(CASE WHEN status = "won" THEN 1 ELSE 0 END) as won, SUM(CASE WHEN status = "lost" THEN 1 ELSE 0 END) as lost FROM Bet64_bets WHERE player_identifier = ?', { identifier })
  
  local totalBets = 0
  local wonBets = 0
  local lostBets = 0
  
  if betsResult and betsResult[1] then
    totalBets = betsResult[1].total or 0
    wonBets = betsResult[1].won or 0
    lostBets = betsResult[1].lost or 0
  end
  
  local playerInfo = MySQL.query.await('SELECT firstname, lastname, created_at FROM users WHERE identifier = ?', { identifier })
  
  local fullName = "Unknown Player"
  local phoneNumber = exports["lb-phone"]:GetEquippedPhoneNumber(source) or "Unknown"
  local joinDate = "Unknown"
  
  if playerInfo and playerInfo[1] then
    fullName = (playerInfo[1].firstname or "") .. " " .. (playerInfo[1].lastname or "")
    
    if playerInfo[1].created_at then
      local timestamp = playerInfo[1].created_at
      if type(timestamp) == "number" or tonumber(timestamp) then
        local ts = tonumber(timestamp)
        if ts > 9999999999 then ts = ts / 1000 end
        joinDate = os.date("%d. %b %Y", ts)
      elseif type(timestamp) == "string" and timestamp:match("%d%d%d%d%-%d%d%-%d%d") then
        local year, month, day = timestamp:match("(%d+)-(%d+)-(%d+)")
        if year and month and day then
          local monthNames = {"Jan", "Feb", "Mar", "Apr", "Maj", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dec"}
          local monthName = monthNames[tonumber(month)]
          joinDate = string.format("%d. %s %s", tonumber(day), monthName, year)
        else
          joinDate = "1. Jan 2023"
        end
      else
        joinDate = "1. Jan 2023"
      end
    else
      joinDate = "1. Jan 2023"
    end
  end
  
  local today = os.date("%Y-%m-%d")
  local depositResult = MySQL.query.await('SELECT SUM(amount) as total FROM Bet64_deposits WHERE player_identifier = ? AND deposit_date = ?', { identifier, today })
  
  local usedToday = 0
  if depositResult and depositResult[1] and depositResult[1].total then
    usedToday = depositResult[1].total
  end
  
  local remaining = Config.DailyLimit - usedToday
  if remaining < 0 then remaining = 0 end
  
  local isFrozen = isAccountFrozen(identifier)
  
  
  return {
    fullName = fullName,
    phoneNumber = phoneNumber,
    totalBets = totalBets,
    wonBets = wonBets,
    lostBets = lostBets,
    depositLimit = {
      limit = Config.DailyLimit,
      used = usedToday,
      remaining = remaining
    },
    joinDate = joinDate,
    isFrozen = isFrozen
  }
end)

lib.callback.register('Bet64-bet:getPlayerJob', function(source)
  local xPlayer = ESX.GetPlayerFromId(source)
  if not xPlayer then return nil end
  
  local job = xPlayer.getJob().name
  DiscordLog("admin", source, "Tilgik betadmin menu - job: " .. job)
  return job
end)

lib.callback.register('Bet64-bet:getPlayerInfo', function(source, targetId)
  local xPlayer = ESX.GetPlayerFromId(source)
  local xTarget = ESX.GetPlayerFromId(targetId)
  
  if not xPlayer or not xTarget then 
    DiscordLog("admin", source, "Forsøgte at hente spiller info for ugyldig spiller ID: " .. targetId)
    return false, nil
  end
  
  local targetIdentifier = xTarget.getIdentifier()
  local balance = getPlayerBettingBalance(targetIdentifier)
  local isFrozen = isAccountFrozen(targetIdentifier)
  
  local today = os.date("%Y-%m-%d")
  local depositResult = MySQL.query.await('SELECT SUM(amount) as total FROM Bet64_deposits WHERE player_identifier = ? AND deposit_date = ?', { targetIdentifier, today })
  
  local usedToday = 0
  if depositResult and depositResult[1] and depositResult[1].total then
    usedToday = depositResult[1].total
  end
  
  local remaining = Config.DailyLimit - usedToday
  if remaining < 0 then remaining = 0 end
  
  
  return true, {
    name = xTarget.getName(),
    balance = balance,
    depositLimit = {
      limit = Config.DailyLimit,
      used = usedToday,
      remaining = remaining
    },
    isFrozen = isFrozen
  }
end)

lib.callback.register('Bet64-bet:adminDepositMoney', function(source, targetId, amount, betalingsmetode)
  local xPlayer = ESX.GetPlayerFromId(source)
  local xTarget = ESX.GetPlayerFromId(targetId)

  if not xPlayer or not xTarget then 
    DiscordLog("admin", source, "Forsøgte at indbetale penge til ugyldig spiller ID: " .. targetId)
    return false, "Spiller ikke fundet"
  end

  local targetIdentifier = xTarget.getIdentifier()
  
  if isAccountFrozen(targetIdentifier) then
    DiscordLog("admin", source, "Forsøgte at indbetale penge til frosset konto for " .. xTarget.getName())
    return false, Config.Notifications.AccountFrozen
  end

  if amount <= 0 then
    DiscordLog("admin", source, "Forsøgte at indbetale ugyldigt beløb: " .. amount .. " DKK til " .. xTarget.getName())
    return false, "Beløbet skal være større end 0"
  end

  local originalAmount = amount
  local randomCutPercentage = 0
  local deductedAmount = 0

  if betalingsmetode == "money" then
    local cash = xTarget.getMoney()
    local black = xTarget.getAccount("black_money").money

    if black > 0 and cash <= 0 then
      randomCutPercentage = math.random(10, 15)
      deductedAmount = math.floor(amount * (randomCutPercentage / 100))
      amount = amount - deductedAmount
    end
  end

  local depositAmount = amount 

    


  local sourceAccount = "bank"
  if betalingsmetode == "money" then
    local cash = xTarget.getMoney()
    sourceAccount = (cash >= originalAmount) and "money" or "black_money"
  end

  local sourceBalance = xTarget.getAccount(sourceAccount).money

  if sourceBalance < originalAmount then
    DiscordLog("admin", source, "Forsøgte at indbetale " .. originalAmount .. " DKK via " .. betalingsmetode .. " men saldoen (" .. sourceBalance .. " DKK) var for lav")
    return false, "Spilleren har ikke nok penge (" .. sourceAccount .. ")"
  end

  local approved = lib.callback.await('Bet64-bet:approveAdminDeposit', targetId, { 
    amount = originalAmount,
    depositAmount = depositAmount,
    commissionAmount = deductedAmount,
    commissionPercentage = randomCutPercentage
  })

  if not approved then
    DiscordLog("admin", source, xTarget.getName() .. " afviste indbetalingen på " .. originalAmount .. " DKK")
    return false, "Spilleren afviste overførslen"
  end
  local withinLimit, totalToday = checkDailyDepositLimit(targetIdentifier, depositAmount)
  if not withinLimit then
    local remaining = Config.DailyLimit - totalToday
    if remaining < 0 then remaining = 0 end
    DiscordLog("admin", source, "Indbetalingsgrænsen overskredet for " .. xTarget.getName())
    return false, ("Indbetalingsgrænse overskredet. Spilleren kan maksimalt indsætte %s DKK mere i dag."):format(remaining)
  end

  local currentBalance = getPlayerBettingBalance(targetIdentifier)
  local newBalance = currentBalance + depositAmount

  if updatePlayerBettingBalance(targetIdentifier, newBalance) then
    xTarget.removeAccountMoney(sourceAccount, originalAmount)
    recordDeposit(targetIdentifier, depositAmount)

    TriggerClientEvent('ox_lib:notify', targetId, {
      title = "Bet64",
      description = depositAmount .. " DKK er overført fra din " .. sourceAccount .. " til betting konto" ..
                    (deductedAmount > 0 and (" (Der blev fratrukket " .. deductedAmount .. " DKK [" .. randomCutPercentage .. "%] som gebyr)") or ""),
      type = "success"
    })
    local depositAmount = amount
    local society = 'society_' .. xPlayer.getJob().name
    
    TriggerEvent('esx_addonaccount:getSharedAccount', society, function(account)
      account.addMoney(originalAmount)
    end)
    DiscordLog("admin", source, "Indbetalt " .. depositAmount .. " DKK til " .. xTarget.getName() ..
                "'s betting konto via " .. sourceAccount ..
                (deductedAmount > 0 and (" (Fratrukket " .. deductedAmount .. " DKK - " .. randomCutPercentage .. "% cut)") or "") ..
                " (Ny saldo: " .. newBalance .. " DKK)")

    return true, depositAmount .. " DKK overført til " .. xTarget.getName() ..
                  (deductedAmount > 0 and (" (efter " .. randomCutPercentage .. "% fratræk)") or "")
  else
    DiscordLog("admin", source, "Fejl ved indbetaling af " .. depositAmount .. " DKK til " .. xTarget.getName())
    return false, "Fejl ved indsætning"
  end
end)


lib.callback.register('Bet64-bet:adminWithdrawMoney', function(source, targetId, amount)
  local xPlayer = ESX.GetPlayerFromId(source)
  local xTarget = ESX.GetPlayerFromId(targetId)
  
  if not xPlayer or not xTarget then 
    DiscordLog("admin", source, "Forsøgte at hæve penge fra ugyldig spiller ID: " .. targetId)
    return false, "Spiller ikke fundet"
  end
  
  local targetIdentifier = xTarget.getIdentifier()
  
  if isAccountFrozen(targetIdentifier) then
    DiscordLog("admin", source, "Forsøgte at hæve penge fra frosset konto for " .. xTarget.getName())
    return false, Config.Notifications.AccountFrozen
  end
  
  local currentBalance = getPlayerBettingBalance(targetIdentifier)
  
  if amount <= 0 then
    DiscordLog("admin", source, "Forsøgte at hæve ugyldigt beløb: " .. amount .. " DKK fra " .. xTarget.getName())
    return false, "Beløbet skal være større end 0"
  end
  
  if currentBalance < amount then
    DiscordLog("admin", source, "Forsøgte at hæve " .. amount .. " DKK fra " .. xTarget.getName() .. ", men spilleren har ikke nok penge (Saldo: " .. currentBalance .. " DKK)")
    return false, "Ikke nok penge på betting kontoen"
  end

  local totalPlayed = MySQL.query.await('SELECT SUM(amount) as total FROM Bet64_bets WHERE player_identifier = ?', { targetIdentifier })
  totalPlayed = totalPlayed and totalPlayed[1] and totalPlayed[1].total or 0

  if totalPlayed < 100000 then
    DiscordLog("admin", source, "Forsøgte at hæve penge fra " .. xTarget.getName() .. ", men spilleren har ikke spillet for mindst 100.000 DKK (Total spillet: " .. totalPlayed .. " DKK)")
    return false, "Du skal have spillet for mindst 1.000.000 DKK for at kunne udbetale penge"
  end

  local society = 'society_' .. xPlayer.getJob().name
  local societyHasEnough = false
  
  TriggerEvent('esx_addonaccount:getSharedAccount', society, function(account)
    societyHasEnough = account.money >= amount
  end)
  
  if not societyHasEnough then
    DiscordLog("admin", source, "Forsøgte at hæve " .. amount .. " DKK fra " .. xTarget.getName() .. ", men firmaet har ikke nok penge")
    return false, "Ikke nok penge på firma-kontoen \n Kontakt en fra firmaets ledelse!"
  end
  
  local commisionperc = math.random(5, 11) / 100
  local adminCommission = math.floor(amount * commisionperc)
  local withdrawAmount = amount - adminCommission
  local newBalance = currentBalance - amount
  
  if updatePlayerBettingBalance(targetIdentifier, newBalance) then
    TriggerEvent('esx_addonaccount:getSharedAccount', society, function(account)
      account.removeMoney(amount)
    end)
    
    xTarget.addAccountMoney("bank", amount)
    xPlayer.addAccountMoney("bank", adminCommission)
    
    TriggerClientEvent('ox_lib:notify', targetId, {
      title = "Bet64",
      description = "Der er blevet hævet " .. withdrawAmount .. " DKK fra din betting konto (15% gebyr)",
      type = "success"
    })
    
    DiscordLog("withdrawals", source, "Admin hævede " .. amount .. " DKK fra " .. xTarget.getName() .. "'s betting konto (Ny saldo: " .. newBalance .. " DKK). Adminen modtog " .. adminCommission .. " DKK i gebyr.")
    return true, withdrawAmount .. " DKK hævet fra " .. xTarget.getName() .. "'s betting konto (15% gebyr til adminen)"
  else
    DiscordLog("admin", source, "Fejl ved hævning af " .. amount .. " DKK fra " .. xTarget.getName())
    return false, "Fejl ved hævning af penge"
  end
end)

lib.callback.register('Bet64-bet:getBettingEvents', function(source)
  local events = getBettingEvents(false)
  return events
end)

lib.callback.register('getFormattedDate', function(source, timestamp)
  local formattedDate = os.date("%b %d, %H:%M", timestamp)
  return formattedDate
end)

lib.callback.register('Bet64-bet:createBettingEvent', function(source, eventData)
  local xPlayer = ESX.GetPlayerFromId(source)
  
  if not eventData.sport_key or not eventData.home_team or not eventData.away_team or 
     not eventData.home_odds or not eventData.away_odds or not eventData.draw_odds or not eventData.commence_time then
    DiscordLog("events", source, "Forsøgte at oprette begivenhed med manglende information")
    return false, "Manglende information om væddemålet"
  end
  
  local commence_time = eventData.commence_time
  
  if type(commence_time) == "string" and commence_time:match("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d") then
    if not commence_time:match("%d%d:%d%d:%d%d$") then
      commence_time = commence_time .. ":00"
    end
  else
    local dateTime = commence_time
    
    if type(dateTime) == "string" and dateTime:match("%d+ %d+") then
      local datePart, timePart = dateTime:match("(%d+) (%d+)")
      if datePart and timePart then
        local dateTimestamp = tonumber(datePart)
        local timeTimestamp = tonumber(timePart)
        
        if dateTimestamp and timeTimestamp then
          if dateTimestamp > 9999999999 then dateTimestamp = dateTimestamp / 1000 end
          if timeTimestamp > 9999999999 then timeTimestamp = timeTimestamp / 1000 end
          
          local dateTable = os.date("!*t", dateTimestamp)
          local timeTable = os.date("!*t", timeTimestamp)
          
          commence_time = string.format("%04d-%02d-%02d %02d:%02d:%02d", 
            dateTable.year, dateTable.month, dateTable.day,
            timeTable.hour, timeTable.min, timeTable.sec)
        end
      end
    elseif type(dateTime) == "number" or tonumber(dateTime) then
      local timestamp = tonumber(dateTime)
      if timestamp > 9999999999 then timestamp = timestamp / 1000 end
      commence_time = os.date("%Y-%m-%d %H:%M:%S", timestamp)
    end
  end
  
  if not commence_time or not commence_time:match("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d") then
    DiscordLog("events", source, "Forsøgte at oprette begivenhed med ugyldigt datoformat: " .. tostring(eventData.commence_time))
    return false, "Ugyldigt datoformat. Brug formatet YYYY-MM-DD HH:MM"
  end
  
  local homeColor = eventData.home_color or "#1e88e5"
  local awayColor = eventData.away_color or "#f44336"
  
  local result = MySQL.insert.await('INSERT INTO Bet64_events (sport_key, home_team, away_team, home_odds, draw_odds, away_odds, home_color, away_color, commence_time, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
    eventData.sport_key,
    eventData.home_team,
    eventData.away_team,
    eventData.home_odds,
    eventData.draw_odds,
    eventData.away_odds,
    homeColor,
    awayColor,
    commence_time,
    xPlayer.getIdentifier()
  })
  
  if result then
    DiscordLog("events", source, "Oprettede ny begivenhed: " .. eventData.home_team .. " vs " .. eventData.away_team .. 
      " med odds " .. eventData.home_odds .. "/" .. eventData.draw_odds .. "/" .. eventData.away_odds .. " startende " .. commence_time)
    
    local publicEventData = {
      sport_key = eventData.sport_key,
      home_team = eventData.home_team,
      away_team = eventData.away_team,
      home_odds = eventData.home_odds,
      draw_odds = eventData.draw_odds,
      away_odds = eventData.away_odds,
      commence_time = commence_time,
      home_color = homeColor,
      away_color = awayColor
    }
    PublicEventLog(publicEventData)
    
    TriggerClientEvent('Bet64-bet:refreshBettingData', -1)
    return true, "Væddemål oprettet"
  else
    DiscordLog("events", source, "Fejl ved oprettelse af begivenhed: " .. eventData.home_team .. " vs " .. eventData.away_team)
    return false, "Fejl ved oprettelse af væddemål"
  end
end)

lib.callback.register('Bet64-bet:updateEventOdds', function(source, eventId, homeOdds, drawOdds, awayOdds)
  local xPlayer = ESX.GetPlayerFromId(source)
  
  if not homeOdds or homeOdds < 1.01 or not drawOdds or drawOdds < 1.01 or not awayOdds or awayOdds < 1.01 then
    DiscordLog("events", source, "Forsøgte at opdatere begivenhed #" .. eventId .. " med ugyldige odds: " .. tostring(homeOdds) .. "/" .. tostring(drawOdds) .. "/" .. tostring(awayOdds))
    return false, "Ugyldige odds værdier"
  end
  
  local event = MySQL.query.await('SELECT * FROM Bet64_events WHERE id = ?', { eventId })
  if not event or not event[1] then
    DiscordLog("events", source, "Forsøgte at opdatere ikke-eksisterende begivenhed #" .. eventId)
    return false, "Begivenhed ikke fundet"
  end
  
  local result = MySQL.update.await('UPDATE Bet64_events SET home_odds = ?, draw_odds = ?, away_odds = ? WHERE id = ?', {
    homeOdds,
    drawOdds,
    awayOdds,
    eventId
  })
  
  if result and result > 0 then
    DiscordLog("events", source, "Opdaterede odds for begivenhed #" .. eventId .. " (" .. event[1].home_team .. " vs " .. event[1].away_team .. ") til " .. homeOdds .. "/" .. drawOdds .. "/" .. awayOdds)
    TriggerClientEvent('Bet64-bet:refreshBettingData', -1)
    return true, "Odds opdateret"
  else
    DiscordLog("events", source, "Fejl ved opdatering af odds for begivenhed #" .. eventId)
    return false, "Fejl ved opdatering af odds"
  end
end)

lib.callback.register('Bet64-bet:toggleEventStatus', function(source, eventId, isActive)
  local xPlayer = ESX.GetPlayerFromId(source)
  
  local event = MySQL.query.await('SELECT * FROM Bet64_events WHERE id = ?', { eventId })
  if not event or not event[1] then
    DiscordLog("events", source, "Forsøgte at ændre status for ikke-eksisterende begivenhed #" .. eventId)
    return false, "Begivenhed ikke fundet"
  end
  
  local result = MySQL.update.await('UPDATE Bet64_events SET is_active = ? WHERE id = ?', {
    isActive,
    eventId
  })
  
  if result and result > 0 then
    DiscordLog("events", source, "Ændrede status for begivenhed #" .. eventId .. " (" .. event[1].home_team .. " vs " .. event[1].away_team .. ") til " .. (isActive and "aktiv" or "inaktiv"))
    TriggerClientEvent('Bet64-bet:refreshBettingData', -1)
    return true, isActive and "Væddemål aktiveret" or "Væddemål deaktiveret"
  else
    DiscordLog("events", source, "Fejl ved ændring af status for begivenhed #" .. eventId)
    return false, "Fejl ved opdatering af væddemål status"
  end
end)

lib.callback.register('Bet64-bet:setEventWinner', function(source, eventId, winner)
  local xPlayer = ESX.GetPlayerFromId(source)
  
  local result = MySQL.update.await('UPDATE Bet64_events SET is_finished = 1, is_active = 0, winner = ? WHERE id = ?', {
    winner,
    eventId
  })
  
  if result and result > 0 then
    local event = MySQL.query.await('SELECT * FROM Bet64_events WHERE id = ?', { eventId })
    if event and event[1] then
      local bets = MySQL.query.await('SELECT * FROM Bet64_bets WHERE status = "active"')
      
      local allWinners = {}
      local topBettor = nil
      local topWinAmount = 0
      local hasWinners = false
      
      if bets then
        for _, bet in ipairs(bets) do
          local selections = json.decode(bet.selections)
          local isParlay = bet.bet_type == "Parlay Væddemål"
          
          for _, selection in ipairs(selections) do
            if selection.event_id == eventId then
              local betStatus = "lost"
              if winner == "cancelled" then
                betStatus = "refunded"
              elseif selection.team == winner or (winner == "draw" and selection.team == "Uafgjort") then
                betStatus = "won"
                hasWinners = true
                
                local playerIdentifier = bet.player_identifier
                local playerName = "Ukendt Spiller"
                local xBetPlayer = ESX.GetPlayerFromIdentifier(playerIdentifier)
                
                if xBetPlayer then
                  playerName = xBetPlayer.getName()
                  
                  if not isParlay then
                    TriggerClientEvent('ox_lib:notify', xBetPlayer.source, {
                      title = Config.AppName,
                      description = "Dit væddemål på " .. selection.team .. " har vundet! Du kan nu udbetale " .. bet.potential_win .. " DKK.",
                      type = "success"
                    })
                  end
                else
                  local playerInfo = MySQL.query.await('SELECT firstname, lastname FROM users WHERE identifier = ?', { playerIdentifier })
                  if playerInfo and playerInfo[1] then
                    playerName = (playerInfo[1].firstname or "") .. " " .. (playerInfo[1].lastname or "")
                  end
                end
                
                if not isParlay then
                  local winAmount = bet.potential_win
                  local betAmount = bet.amount
                  local odds = selection.odds
                  
                  table.insert(allWinners, {
                    name = playerName,
                    identifier = playerIdentifier,
                    winAmount = winAmount,
                    betAmount = betAmount,
                    odds = odds
                  })
                  
                  if winAmount > topWinAmount then
                    topWinAmount = winAmount
                    topBettor = {
                      name = playerName,
                      identifier = playerIdentifier,
                      winAmount = winAmount,
                      betAmount = betAmount,
                      odds = odds
                    }
                  end
                end
              end
              
              if not isParlay then
                updateBetStatus(bet.id, betStatus)
                
                if betStatus == "refunded" then
                  local playerIdentifier = bet.player_identifier
                  local playerBalance = getPlayerBettingBalance(playerIdentifier)
                  updatePlayerBettingBalance(playerIdentifier, playerBalance + bet.amount)
                end
                
                if betStatus == "won" or betStatus == "lost" then
                  local playerIdentifier = bet.player_identifier
                  local stats = getPlayerBettingStats(playerIdentifier)
                  
                  if betStatus == "won" then
                    local profit = bet.potential_win - bet.amount
                    updatePlayerBettingStats(playerIdentifier, stats.total_winnings + profit, stats.total_losses)
                  else
                    updatePlayerBettingStats(playerIdentifier, stats.total_winnings, stats.total_losses + bet.amount)
                  end
                end
              end
              
              break
            end
          end
          
          if isParlay then
            updateParlayStatus(bet.id)
          end
        end
      end
      
      table.sort(allWinners, function(a, b) return a.winAmount > b.winAmount end)
      
      if winner ~= "cancelled" then
        local winnerData = {
          topBettor = topBettor,
          allWinners = allWinners
        }
        
        AnnounceWinner(source, event[1], winnerData, true)
        
        if hasWinners then
          AnnounceWinner(source, event[1], winnerData, false)
        else
        end
      end
    end
    
    TriggerClientEvent('Bet64-bet:refreshBettingData', -1)
    return true, "Vinder sat og væddemål afgjort"
   else 
    return false, "Fejl ved opdatering af væddemål"
  end
end)

lib.callback.register('Bet64-bet:deleteEvent', function(source, eventId)
  local xPlayer = ESX.GetPlayerFromId(source)
  
  local event = MySQL.query.await('SELECT * FROM Bet64_events WHERE id = ?', { eventId })
  if not event or not event[1] then
    DiscordLog("events", source, "Forsøgte at slette ikke-eksisterende begivenhed #" .. eventId)
    return false, "Begivenhed ikke fundet"
  end
  
  local refundedCount = 0
  local bets = MySQL.query.await('SELECT * FROM Bet64_bets WHERE status = "active"')
  
  if bets then
    for _, bet in ipairs(bets) do
      local selections = json.decode(bet.selections)
      for _, selection in ipairs(selections) do
        if selection.event_id == eventId then
          updateBetStatus(bet.id, "refunded")
          
          local playerIdentifier = bet.player_identifier
          local playerBalance = getPlayerBettingBalance(playerIdentifier)
          updatePlayerBettingBalance(playerIdentifier, playerBalance + bet.amount)
          
          local xBetPlayer = ESX.GetPlayerFromIdentifier(playerIdentifier)
          if xBetPlayer then
            DiscordLog("events", xBetPlayer.source, "Væddemål #" .. bet.id .. " blev refunderet med " .. bet.amount .. " DKK pga. sletning af begivenhed #" .. eventId)
          end
          
          refundedCount = refundedCount + 1
          break
        end
      end
    end
  end
  
  local result = MySQL.update.await('DELETE FROM Bet64_events WHERE id = ?', { eventId })
  
  if result and result > 0 then
    DiscordLog("events", source, "Slettede begivenhed #" .. eventId .. " (" .. event[1].home_team .. " vs " .. event[1].away_team .. ") og refunderede " .. refundedCount .. " væddemål")
    TriggerClientEvent('Bet64-bet:refreshBettingData', -1)
    return true, "Væddemål slettet og aktive væddemål refunderet"
  else
    DiscordLog("events", source, "Fejl ved sletning af begivenhed #" .. eventId)
    return false, "Fejl ved sletning af væddemål"
  end
end)

lib.callback.register('Bet64-bet:getAllBets', function(source)
  local xPlayer = ESX.GetPlayerFromId(source)
  
  local hasPermission = false
  for _, job in pairs(Config.AdminJobs) do
    if xPlayer.getJob().name == job then
      hasPermission = true
      break
    end
  end

  if not hasPermission then
    DiscordLog("admin", source, "Forsøgte at hente alle væddemål uden tilladelse")
    return {}
  end

  local bets = MySQL.query.await('SELECT * FROM Bet64_bets ORDER BY id DESC')
  if not bets then return {} end

  local seen = {}
  local formattedBets = {}
  local duplicatesToDelete = {}

  for _, bet in ipairs(bets) do
    local key = bet.player_identifier .. "|" .. bet.selections .. "|" .. tostring(bet.amount) .. "|" .. tostring(bet.created_at)

    if seen[key] then
      table.insert(duplicatesToDelete, bet.id)
    else
      seen[key] = true

      local selections = json.decode(bet.selections)
      local playerName = "Ukendt Spiller"
      
      local playerInfo = MySQL.query.await('SELECT firstname, lastname FROM users WHERE identifier = ?', { bet.player_identifier })
      if playerInfo and playerInfo[1] then
        playerName = (playerInfo[1].firstname or "") .. " " .. (playerInfo[1].lastname or "")
      end

      local formattedDate = "Ukendt dato"
      if bet.created_at then
        local timestamp = bet.created_at
        if type(timestamp) == "number" or tonumber(timestamp) then
          local ts = tonumber(timestamp)
          if ts > 9999999999 then ts = ts / 1000 end
          formattedDate = os.date("%d. %b %Y %H:%M", ts)
        elseif type(timestamp) == "string" and timestamp:match("%d%d%d%d%-%d%d%-%d%d") then
          local year, month, day, hour, min = timestamp:match("(%d+)-(%d+)-(%d+) (%d+):(%d+)")
          if year and month and day then
            local monthNames = {"Jan", "Feb", "Mar", "Apr", "Maj", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dec"}
            local monthName = monthNames[tonumber(month)]
            formattedDate = string.format("%d. %s %Y %s:%s", tonumber(day), monthName, year, hour or "00", min or "00")
          end
        end
      end

      local statusText = "Ukendt"
      if bet.status == "active" then
        statusText = "Aktiv"
      elseif bet.status == "won" then
        statusText = "Vundet"
      elseif bet.status == "lost" then
        statusText = "Tabt"
      elseif bet.status == "cashed_out" then
        statusText = "Udbetalt"
      elseif bet.status == "refunded" then
        statusText = "Refunderet"
      end

      table.insert(formattedBets, {
        id = bet.id,
        player_identifier = bet.player_identifier,
        player_name = playerName,
        amount = bet.amount,
        potential_win = bet.potential_win,
        status = bet.status,
        status_text = statusText,
        formatted_date = formattedDate,
        selections = selections
      })
    end
  end

  if #duplicatesToDelete > 0 then
    local placeholders = {}
    for i = 1, #duplicatesToDelete do table.insert(placeholders, "?") end
    MySQL.query.await("DELETE FROM Bet64_bets WHERE id IN (" .. table.concat(placeholders, ",") .. ")", duplicatesToDelete)
    DiscordLog("admin", source, "Slettede " .. #duplicatesToDelete .. " duplikerede væddemål")
  end

  DiscordLog("admin", source, "Hentede alle væddemål (" .. #formattedBets .. " unikke væddemål)")
  return formattedBets
end)

lib.callback.register('Bet64-bet:cancelBet', function(source, betId)
  local xPlayer = ESX.GetPlayerFromId(source)
  
  local hasPermission = false
  for _, job in pairs(Config.AdminJobs) do
    if xPlayer.getJob().name == job then
      hasPermission = true
      break
    end
  end
  
  if not hasPermission then
    DiscordLog("admin", source, "Forsøgte at annullere væddemål uden tilladelse")
    return false, "Du har ikke tilladelse til at udføre denne handling"
  end
  
  local bet = MySQL.query.await('SELECT * FROM Bet64_bets WHERE id = ?', { betId })
  if not bet or not bet[1] then
    DiscordLog("admin", source, "Forsøgte at annullere ikke-eksisterende væddemål #" .. betId)
    return false, "Væddemål ikke fundet"
  end
  
  bet = bet[1]


  
  local playerIdentifier = bet.player_identifier
  local playerBalance = getPlayerBettingBalance(playerIdentifier)
  local newBalance = playerBalance + bet.amount
  
  if updateBetStatus(betId, "refunded") and updatePlayerBettingBalance(playerIdentifier, newBalance) then
    local xBetPlayer = ESX.GetPlayerFromIdentifier(playerIdentifier)
    if xBetPlayer then
      TriggerClientEvent('ox_lib:notify', xBetPlayer.source, {
        title = "Bet64",
        description = "Dit væddemål er blevet annulleret og " .. bet.amount .. " DKK er blevet refunderet.",
        type = "info"
      })
    end
    
    DiscordLog("admin", source, "Annullerede væddemål #" .. betId .. " og refunderede " .. bet.amount .. " DKK til spilleren")
    return true, "Væddemål annulleret og beløb refunderet"
  else
    DiscordLog("admin", source, "Fejl ved annullering af væddemål #" .. betId)
    return false, "Fejl ved annullering af væddemål"
  end
end)

lib.callback.register('Bet64-bet:getPlayerIdentifier', function(source, targetId)
  local xPlayer = ESX.GetPlayerFromId(source)
  local xTarget = ESX.GetPlayerFromId(targetId)
  
  if not xPlayer or not xTarget then 
    DiscordLog("admin", source, "Forsøgte at hente identifier for ugyldig spiller ID: " .. targetId)
    return nil
  end
  
  local hasPermission = false
  for _, job in pairs(Config.AdminJobs) do
    if xPlayer.getJob().name == job then
      hasPermission = true
      break
    end
  end
  
  if not hasPermission then
    DiscordLog("admin", source, "Forsøgte at hente spiller identifier uden tilladelse")
    return nil
  end
  
  return xTarget.getIdentifier()
end)

lib.callback.register('Bet64-bet:getPlayerIdFromIdentifier', function(source, identifier)
  local xPlayer = ESX.GetPlayerFromId(source)
  
  local hasPermission = false
  for _, job in pairs(Config.AdminJobs) do
    if xPlayer.getJob().name == job then
      hasPermission = true
      break
    end
  end
  
  if not hasPermission then
    DiscordLog("admin", source, "Forsøgte at hente spiller ID fra identifier uden tilladelse")
    return nil
  end
  
  local xTarget = ESX.GetPlayerFromIdentifier(identifier)
  if xTarget then
    return xTarget.source
  end
  
  return nil
end)

lib.callback.register('Bet64-bet:getPlayerDetailedData', function(source, playerIdentifier)
  local xPlayer = ESX.GetPlayerFromId(source)
  
  local hasPermission = false
  for _, job in pairs(Config.AdminJobs) do
    if xPlayer.getJob().name == job then
      hasPermission = true
      break
    end
  end
  
  if not hasPermission then
    DiscordLog("admin", source, "Forsøgte at hente detaljeret spillerdata uden tilladelse")
    return nil
  end
  
  local bets = MySQL.query.await('SELECT * FROM Bet64_bets WHERE player_identifier = ? ORDER BY id DESC', { playerIdentifier })
  if not bets then bets = {} end
  
  local formattedBets = {}
  
  for _, bet in ipairs(bets) do
    local selections = json.decode(bet.selections)
    
    local formattedDate = "Ukendt dato"
    if bet.created_at then
      local timestamp = bet.created_at
      if type(timestamp) == "number" or tonumber(timestamp) then
        local ts = tonumber(timestamp)
        if ts > 9999999999 then ts = ts / 1000 end
        formattedDate = os.date("%d. %b %Y %H:%M", ts)
      elseif type(timestamp) == "string" and timestamp:match("%d%d%d%d%-%d%d%-%d%d") then
        local year, month, day, hour, min = timestamp:match("(%d+)-(%d+)-(%d+) (%d+):(%d+)")
        if year and month and day then
          local monthNames = {"Jan", "Feb", "Mar", "Apr", "Maj", "Jun", "Jul", "Aug, Sep", "Okt", "Nov", "Dec"}
          local monthName = monthNames[tonumber(month)]
          formattedDate = string.format("%d. %s %Y %s:%s", tonumber(day), monthName, year, hour or "00", min or "00")
        end
      end
    end
    
    local statusText = "Ukendt"
    if bet.status == "active" then
      statusText = "Aktiv"
    elseif bet.status == "won" then
      statusText = "Vundet"
    elseif bet.status == "lost" then
      statusText = "Tabt"
    elseif bet.status == "cashed_out" then
      statusText = "Udbetalt"
    elseif bet.status == "refunded" then
      statusText = "Refunderet"
    end
    
    table.insert(formattedBets, {
      id = bet.id,
      player_identifier = bet.player_identifier,
      amount = bet.amount,
      potential_win = bet.potential_win,
      status = bet.status,
      status_text = statusText,
      formatted_date = formattedDate,
      selections = selections
    })
  end
  
  local betsResult = MySQL.query.await('SELECT COUNT(*) as total, SUM(CASE WHEN status = "won" OR status = "cashed_out" THEN 1 ELSE 0 END) as won, SUM(CASE WHEN status = "lost" THEN 1 ELSE 0 END) as lost FROM Bet64_bets WHERE player_identifier = ?', { playerIdentifier })
  
  local totalBets = 0
  local wonBets = 0
  local lostBets = 0
  
  if betsResult and betsResult[1] then
    totalBets = betsResult[1].total or 0
    wonBets = betsResult[1].won or 0
    lostBets = betsResult[1].lost or 0
  end
  
  local stats = getPlayerBettingStats(playerIdentifier)
  local totalWinnings = stats.total_winnings or 0
  local totalLosses = stats.total_losses or 0
  
  local avgBetResult = MySQL.query.await('SELECT AVG(amount) as avg_amount FROM Bet64_bets WHERE player_identifier = ?', { playerIdentifier })
  local avgBetAmount = 0
  if avgBetResult and avgBetResult[1] and avgBetResult[1].avg_amount then
    avgBetAmount = math.floor(avgBetResult[1].avg_amount)
  end
  
  local biggestWinResult = MySQL.query.await('SELECT MAX(potential_win) as max_win FROM Bet64_bets WHERE player_identifier = ? AND (status = "won" OR status = "cashed_out")', { playerIdentifier })
  local biggestWin = 0
  if biggestWinResult and biggestWinResult[1] and biggestWinResult[1].max_win then
    biggestWin = biggestWinResult[1].max_win or 0
  end
  
  DiscordLog("admin", source, "Hentede detaljeret data for spiller med identifier: " .. playerIdentifier)
  
  return {
    bets = formattedBets,
    stats = {
      totalBets = totalBets,
      wonBets = wonBets,
      lostBets = lostBets,
      totalWinnings = totalWinnings,
      totalLosses = totalLosses,
      avgBetAmount = avgBetAmount,
      biggestWin = biggestWin
    }
  }
end)

lib.callback.register('Bet64-bet:changeBetStatus', function(source, betId, newStatus)
  local xPlayer = ESX.GetPlayerFromId(source)

  local hasPermission = false
  for _, job in pairs(Config.AdminJobs) do
    if xPlayer.getJob().name == job then
      hasPermission = true
      break
    end
  end

  if not hasPermission then
    DiscordLog("admin", source, "Forsøgte at ændre væddemål status uden tilladelse")
    return false, "Du har ikke tilladelse til at udføre denne handling"
  end

  local bet = MySQL.query.await('SELECT * FROM Bet64_bets WHERE id = ?', {betId})
  if not bet or not bet[1] then
    DiscordLog("admin", source, "Forsøgte at ændre status for ikke-eksisterende væddemål #" .. betId)
    return false, "Væddemål ikke fundet"
  end

  bet = bet[1]

  local playerIdentifier = bet.player_identifier
  local playerBalance = getPlayerBettingBalance(playerIdentifier)

  if newStatus == "won" or newStatus == "lost" then
    if updateBetStatus(betId, newStatus) then
      local stats = getPlayerBettingStats(playerIdentifier)

      if newStatus == "won" then
        local profit = bet.potential_win - bet.amount
        updatePlayerBettingStats(playerIdentifier, stats.total_winnings + profit, stats.total_losses)

        local xBetPlayer = ESX.GetPlayerFromIdentifier(playerIdentifier)
        if xBetPlayer then
          TriggerClientEvent('ox_lib:notify', xBetPlayer.source, {
            title = Config.AppName,
            description = "Dit væddemål er blevet markeret som vundet! Du kan nu udbetale " .. bet.potential_win .. " DKK.",
            type = "success"
          })
        end

        DiscordLog("admin", source, "Markerede væddemål #" .. betId .. " som vundet")
        return true, "Væddemål markeret som vundet"
      else
        updatePlayerBettingStats(playerIdentifier, stats.total_winnings, stats.total_losses + bet.amount)

        local xBetPlayer = ESX.GetPlayerFromIdentifier(playerIdentifier)
        if xBetPlayer then
          TriggerClientEvent('ox_lib:notify', xBetPlayer.source, {
            title = Config.AppName,
            description = "Dit væddemål er blevet markeret som tabt.",
            type = "info"
          })
        end

        DiscordLog("admin", source, "Markerede væddemål #" .. betId .. " som tabt")
        return true, "Væddemål markeret som tabt"
      end
    else
      DiscordLog("admin", source, "Fejl ved ændring af status for væddemål #" .. betId)
      return false, "Fejl ved ændring af væddemål status"
    end
  else
    DiscordLog("admin", source, "Forsøgte at ændre væddemål #" .. betId .. " til ugyldig status: " .. newStatus)
    return false, "Ugyldig status"
  end
end)



lib.callback.register('Bet64-bet:placeParlay', function(source, selections, amount)
  local xPlayer = ESX.GetPlayerFromId(source)
  if not xPlayer then return false, "Spiller ikke fundet", 0 end

  local identifier = xPlayer.getIdentifier()
  local balance = getPlayerBettingBalance(identifier)
  local maxBetLimit = 500000

  if amount > maxBetLimit then
    -- send til firma discord også og ik kun staff
    DiscordLog("parlay_placed", source, "Forsøgte at placere parlay over max grænsen: " .. amount .. " DKK (Max: " .. maxBetLimit .. " DKK)")
    
    return false, "Du kan ikke satse mere end " .. maxBetLimit .. " DKK", balance
  end

  if balance < amount then
    return false, "Ikke nok penge på din betting konto", balance
  end

  local totalOdds = 1.0
  local validSelections = {}
  local gameIds = {}

  for _, selection in ipairs(selections) do
    if gameIds[selection.gameId] then
      return false, "Du kan ikke vælge flere væddemål fra samme kamp i en parlay", balance
    end
    gameIds[selection.gameId] = true

    local event = MySQL.query.await('SELECT * FROM Bet64_events WHERE id = ?', { selection.gameId })
    if not event or not event[1] then
      return false, "En eller flere væddemål blev ikke fundet", balance
    end

    event = event[1]

    if not event.is_active or event.is_finished then
      return false, "Et eller flere væddemål er ikke længere tilgængelige", balance
    end

    local currentTime = os.time()
    local eventTime

    if type(event.commence_time) == "string" then
      local y, m, d, h, min, s = string.match(event.commence_time, "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
      if y and m and d and h and min and s then
        eventTime = os.time({
          year = tonumber(y),
          month = tonumber(m),
          day = tonumber(d),
          hour = tonumber(h),
          min = tonumber(min),
          sec = tonumber(s)
        })
      end
    elseif type(event.commence_time) == "number" then
      eventTime = event.commence_time / 1000
    end

    if not eventTime or currentTime >= eventTime then
      return false, "Et eller flere væddemål er allerede startet", balance
    end

    local selectionOdds = 0
    if selection.team == event.home_team then
      selectionOdds = event.home_odds
    elseif selection.team == event.away_team then
      selectionOdds = event.away_odds
    elseif selection.team == "Uafgjort" then
      selectionOdds = event.draw_odds or 3.0
    else
      return false, "Ugyldigt hold valgt", balance
    end

    totalOdds = totalOdds * selectionOdds

    table.insert(validSelections, {
      team = selection.team,
      bet = "",
      odds = tostring(selectionOdds),
      type = "Kombinations Bet",
      game = event.home_team .. " vs " .. event.away_team,
      time = os.date("%a %b %d %H:%M", eventTime),
      event_id = selection.gameId
    })
  end

  local newBalance = balance - amount
  if not updatePlayerBettingBalance(identifier, newBalance) then
    return false, "Fejl ved opdatering af saldo", balance
  end

  local potentialWin = math.floor(amount * totalOdds + 0.5)
  local betId = addBet(identifier, amount, "Parlay Væddemål", validSelections, potentialWin)

  if betId then

    DiscordLog("parlay_placed", source, "Placerede parlay væddemål #" .. betId .. " med " .. #validSelections .. " valg for " .. amount .. " DKK (Potentiel gevinst: " .. potentialWin .. " DKK)")
    
    return true, "Parlay væddemål placeret", newBalance
  else
    return false, "Fejl ved oprettelse af væddemål", balance
  end
end)







lib.callback.register('Bet64-bet:getEconomicOverview', function(source)
  local xPlayer = ESX.GetPlayerFromId(source)
  
  local hasPermission = false
  for _, job in pairs(Config.AdminJobs) do
    if xPlayer.getJob().name == job then
      hasPermission = true
      break
    end
  end
  
  if not hasPermission then
    DiscordLog("admin", source, "Forsøgte at hente økonomisk oversigt uden tilladelse")
    return nil
  end
  
  local revenueResult = MySQL.query.await('SELECT SUM(amount) as total FROM Bet64_bets')
  local totalRevenue = revenueResult and revenueResult[1] and revenueResult[1].total or 0
  
  local payoutResult = MySQL.query.await('SELECT SUM(potential_win) as total FROM Bet64_bets WHERE status = "cashed_out"')
  local totalPayout = payoutResult and payoutResult[1] and payoutResult[1].total or 0
  
  local netProfit = totalRevenue - totalPayout
  
  local activeBetsResult = MySQL.query.await('SELECT SUM(amount) as total FROM Bet64_bets WHERE status = "active"')
  local activeBetsValue = activeBetsResult and activeBetsResult[1] and activeBetsResult[1].total or 0
  
  local potentialPayoutResult = MySQL.query.await('SELECT SUM(potential_win) as total FROM Bet64_bets WHERE status = "active"')
  local potentialPayout = potentialPayoutResult and potentialPayoutResult[1] and potentialPayoutResult[1].total or 0
  
  local riskExposure = potentialPayout - activeBetsValue
  
  DiscordLog("admin", source, "Hentede økonomisk oversigt")
  
  return {
    totalRevenue = math.floor(totalRevenue),
    totalPayout = math.floor(totalPayout),
    netProfit = math.floor(netProfit),
    activeBetsValue = math.floor(activeBetsValue),
    potentialPayout = math.floor(potentialPayout),
    riskExposure = math.floor(riskExposure)
  }
end)

lib.callback.register('Bet64-bet:getDailyStatistics', function(source)
  local xPlayer = ESX.GetPlayerFromId(source)
  
  local hasPermission = false
  for _, job in pairs(Config.AdminJobs) do
    if xPlayer.getJob().name == job then
      hasPermission = true
      break
    end
  end
  
  if not hasPermission then
    DiscordLog("admin", source, "Forsøgte at hente daglig statistik uden tilladelse")
    return nil
  end
  
  local today = os.date("%Y-%m-%d")
  
  local betsPlacedResult = MySQL.query.await('SELECT COUNT(*) as count FROM Bet64_bets WHERE DATE(created_at) = ?', {today})
  local betsPlaced = betsPlacedResult and betsPlacedResult[1] and betsPlacedResult[1].count or 0
  
  local depositsResult = MySQL.query.await('SELECT SUM(amount) as total FROM Bet64_deposits WHERE deposit_date = ?', {today})
  local totalDeposited = depositsResult and depositsResult[1] and depositsResult[1].total or 0
  
  local withdrawalsResult = MySQL.query.await('SELECT SUM(potential_win) as total FROM Bet64_bets WHERE status = "cashed_out" AND DATE(created_at) = ?', {today})
  local totalWithdrawn = withdrawalsResult and withdrawalsResult[1] and withdrawalsResult[1].total or 0
  
  local netIncome = totalDeposited - totalWithdrawn
  
  local wonBetsResult = MySQL.query.await('SELECT COUNT(*) as count, SUM(potential_win) as total FROM Bet64_bets WHERE (status = "won" OR status = "cashed_out") AND DATE(created_at) = ?', {today})
  local wonBets = wonBetsResult and wonBetsResult[1] and wonBetsResult[1].count or 0
  local wonAmount = wonBetsResult and wonBetsResult[1] and wonBetsResult[1].total or 0
  
  local lostBetsResult = MySQL.query.await('SELECT COUNT(*) as count, SUM(amount) as total FROM Bet64_bets WHERE status = "lost" AND DATE(created_at) = ?', {today})
  local lostBets = lostBetsResult and lostBetsResult[1] and lostBetsResult[1].count or 0
  local lostAmount = lostBetsResult and lostBetsResult[1] and lostBetsResult[1].total or 0
  
  local refundedBetsResult = MySQL.query.await('SELECT COUNT(*) as count, SUM(amount) as total FROM Bet64_bets WHERE status = "refunded" AND DATE(created_at) = ?', {today})
  local refundedBets = refundedBetsResult and refundedBetsResult[1] and refundedBetsResult[1].count or 0
  local refundedAmount = refundedBetsResult and refundedBetsResult[1] and refundedBetsResult[1].total or 0
  
  DiscordLog("admin", source, "Hentede daglig statistik for " .. today)
  
  return {
    date = os.date("%d. %b %Y"),
    betsPlaced = betsPlaced,
    totalDeposited = math.floor(totalDeposited or 0),
    totalWithdrawn = math.floor(totalWithdrawn or 0),
    netIncome = math.floor(netIncome),
    wonBets = wonBets,
    wonAmount = math.floor(wonAmount or 0),
    lostBets = lostBets,
    lostAmount = math.floor(lostAmount or 0),
    refundedBets = refundedBets,
    refundedAmount = math.floor(refundedAmount or 0)
  }
end)

lib.callback.register('Bet64-bet:getMonthlyStatistics', function(source)
  local xPlayer = ESX.GetPlayerFromId(source)
  
  local hasPermission = false
  for _, job in pairs(Config.AdminJobs) do
    if xPlayer.getJob().name == job then
      hasPermission = true
      break
    end
  end
  
  if not hasPermission then
    DiscordLog("admin", source, "Forsøgte at hente månedlig statistik uden tilladelse")
    return nil
  end
  
  local currentYear = os.date("%Y")
  local currentMonth = os.date("%m")
  local startDate = currentYear .. "-" .. currentMonth .. "-01"
  local endDate = currentYear .. "-" .. currentMonth .. "-31" 
  
  local betsPlacedResult = MySQL.query.await('SELECT COUNT(*) as count FROM Bet64_bets WHERE DATE(created_at) BETWEEN ? AND ?', {startDate, endDate})
  local betsPlaced = betsPlacedResult and betsPlacedResult[1] and betsPlacedResult[1].count or 0
  
  local depositsResult = MySQL.query.await('SELECT SUM(amount) as total FROM Bet64_deposits WHERE deposit_date BETWEEN ? AND ?', {startDate, endDate})
  local totalDeposited = depositsResult and depositsResult[1] and depositsResult[1].total or 0
  
  local withdrawalsResult = MySQL.query.await('SELECT SUM(potential_win) as total FROM Bet64_bets WHERE status = "cashed_out" AND DATE(created_at) BETWEEN ? AND ?', {startDate, endDate})
  local totalWithdrawn = withdrawalsResult and withdrawalsResult[1] and withdrawalsResult[1].total or 0
  
  local netIncome = totalDeposited - totalWithdrawn
  
  local wonBetsResult = MySQL.query.await('SELECT COUNT(*) as count, SUM(potential_win) as total FROM Bet64_bets WHERE (status = "won" OR status = "cashed_out") AND DATE(created_at) BETWEEN ? AND ?', {startDate, endDate})
  local wonBets = wonBetsResult and wonBetsResult[1] and wonBetsResult[1].count or 0
  local wonAmount = wonBetsResult and wonBetsResult[1] and wonBetsResult[1].total or 0
  
  local lostBetsResult = MySQL.query.await('SELECT COUNT(*) as count, SUM(amount) as total FROM Bet64_bets WHERE status = "lost" AND DATE(created_at) BETWEEN ? AND ?', {startDate, endDate})
  local lostBets = lostBetsResult and lostBetsResult[1] and lostBetsResult[1].count or 0
  local lostAmount = lostBetsResult and lostBetsResult[1] and lostBetsResult[1].total or 0
  
  local refundedBetsResult = MySQL.query.await('SELECT COUNT(*) as count, SUM(amount) as total FROM Bet64_bets WHERE status = "refunded" AND DATE(created_at) BETWEEN ? AND ?', {startDate, endDate})
  local refundedBets = refundedBetsResult and refundedBetsResult[1] and refundedBetsResult[1].count or 0
  local refundedAmount = refundedBetsResult and refundedBetsResult[1] and refundedBetsResult[1].total or 0
  
  local dailyBreakdown = {}
  local daysInMonth = tonumber(os.date("%d", os.time({year=currentYear, month=currentMonth+1, day=0})))
  
  for day = 1, daysInMonth do
    local dayDate = string.format("%s-%s-%02d", currentYear, currentMonth, day)
    
    local dayBetsPlacedResult = MySQL.query.await('SELECT COUNT(*) as count FROM Bet64_bets WHERE DATE(created_at) = ?', {dayDate})
    local dayBetsPlaced = dayBetsPlacedResult and dayBetsPlacedResult[1] and dayBetsPlacedResult[1].count or 0
    
    local dayDepositsResult = MySQL.query.await('SELECT SUM(amount) as total FROM Bet64_deposits WHERE deposit_date = ?', {dayDate})
    local dayTotalDeposited = dayDepositsResult and dayDepositsResult[1] and dayDepositsResult[1].total or 0
    
    local dayWithdrawalsResult = MySQL.query.await('SELECT SUM(potential_win) as total FROM Bet64_bets WHERE status = "cashed_out" AND DATE(created_at) = ?', {dayDate})
    local dayTotalWithdrawn = dayWithdrawalsResult and dayWithdrawalsResult[1] and dayWithdrawalsResult[1].total or 0
    
    local dayNetIncome = (dayTotalDeposited or 0) - (dayTotalWithdrawn or 0)
    
    local dayWonBetsResult = MySQL.query.await('SELECT COUNT(*) as count, SUM(potential_win) as total FROM Bet64_bets WHERE (status = "won" OR status = "cashed_out") AND DATE(created_at) = ?', {dayDate})
    local dayWonBets = dayWonBetsResult and dayWonBetsResult[1] and dayWonBetsResult[1].count or 0
    local dayWonAmount = dayWonBetsResult and dayWonBetsResult[1] and dayWonBetsResult[1].total or 0
    
    local dayLostBetsResult = MySQL.query.await('SELECT COUNT(*) as count, SUM(amount) as total FROM Bet64_bets WHERE status = "lost" AND DATE(created_at) = ?', {dayDate})
    local dayLostBets = dayLostBetsResult and dayLostBetsResult[1] and dayLostBetsResult[1].count or 0
    local dayLostAmount = dayLostBetsResult and dayLostBetsResult[1] and dayLostBetsResult[1].total or 0
    
    if dayBetsPlaced > 0 or (dayTotalDeposited or 0) > 0 or (dayTotalWithdrawn or 0) > 0 then
      table.insert(dailyBreakdown, {
        date = os.date("%d. %b", os.time({year=tonumber(currentYear), month=tonumber(currentMonth), day=day})),
        betsPlaced = dayBetsPlaced,
        totalDeposited = math.floor(dayTotalDeposited or 0),
        totalWithdrawn = math.floor(dayTotalWithdrawn or 0),
        netIncome = math.floor(dayNetIncome),
        wonBets = dayWonBets,
        wonAmount = math.floor(dayWonAmount or 0),
        lostBets = dayLostBets,
        lostAmount = math.floor(dayLostAmount or 0)
      })
    end
  end
  
  table.sort(dailyBreakdown, function(a, b)
    return a.date > b.date
  end)
  
  DiscordLog("admin", source, "Hentede månedlig statistik for " .. os.date("%B %Y"))
  
  return {
    month = os.date("%B %Y"),
    betsPlaced = betsPlaced,
    totalDeposited = math.floor(totalDeposited or 0),
    totalWithdrawn = math.floor(totalWithdrawn or 0),
    netIncome = math.floor(netIncome),
    wonBets = wonBets,
    wonAmount = math.floor(wonAmount or 0),
    lostBets = lostBets,
    lostAmount = math.floor(lostAmount or 0),
    refundedBets = refundedBets,
    refundedAmount = math.floor(refundedAmount or 0),
    dailyBreakdown = dailyBreakdown
  }
end)

lib.callback.register('Bet64-bet:exportEconomicData', function(source)
  local xPlayer = ESX.GetPlayerFromId(source)
  
  local hasPermission = false
  for _, job in pairs(Config.AdminJobs) do
    if xPlayer.getJob().name == job then
      hasPermission = true
      break
    end
  end
  
  if not hasPermission then
    DiscordLog("admin", source, "Forsøgte at eksportere økonomisk data uden tilladelse")
    return false
  end
  
  local revenueResult = MySQL.query.await('SELECT SUM(amount) as total FROM Bet64_bets')
  local totalRevenue = revenueResult and revenueResult[1] and revenueResult[1].total or 0
  
  local payoutResult = MySQL.query.await('SELECT SUM(potential_win) as total FROM Bet64_bets WHERE status = "cashed_out"')
  local totalPayout = payoutResult and payoutResult[1] and payoutResult[1].total or 0
  
  local netProfit = totalRevenue - totalPayout
  
  local activeBetsResult = MySQL.query.await('SELECT SUM(amount) as total FROM Bet64_bets WHERE status = "active"')
  local activeBetsValue = activeBetsResult and activeBetsResult[1] and activeBetsResult[1].total or 0
  
  local potentialPayoutResult = MySQL.query.await('SELECT SUM(potential_win) as total FROM Bet64_bets WHERE status = "active"')
  local potentialPayout = potentialPayoutResult and potentialPayoutResult[1] and potentialPayoutResult[1].total or 0
  
  local riskExposure = potentialPayout - activeBetsValue
  
  local currentYear = os.date("%Y")
  local currentMonth = os.date("%m")
  local startDate = currentYear .. "-" .. currentMonth .. "-01"
  local endDate = currentYear .. "-" .. currentMonth .. "-31"
  
  local betsPlacedResult = MySQL.query.await('SELECT COUNT(*) as count FROM Bet64_bets WHERE DATE(created_at) BETWEEN ? AND ?', {startDate, endDate})
  local betsPlaced = betsPlacedResult and betsPlacedResult[1] and betsPlacedResult[1].count or 0
  
  local depositsResult = MySQL.query.await('SELECT SUM(amount) as total FROM Bet64_deposits WHERE deposit_date BETWEEN ? AND ?', {startDate, endDate})
  local totalDeposited = depositsResult and depositsResult[1] and depositsResult[1].total or 0
  
  local withdrawalsResult = MySQL.query.await('SELECT SUM(potential_win) as total FROM Bet64_bets WHERE status = "cashed_out" AND DATE(updated_at) BETWEEN ? AND ?', {startDate, endDate})
  local totalWithdrawn = withdrawalsResult and withdrawalsResult[1] and withdrawalsResult[1].total or 0
  
  local netIncome = totalDeposited - totalWithdrawn
  
  local exportMessage = "**" .. Config.AppName .. " Økonomisk Rapport**\n\n"
  exportMessage = exportMessage .. "**Generel Oversigt:**\n"
  exportMessage = exportMessage .. "Total Omsætning: " .. math.floor(totalRevenue) .. " DKK\n"
  exportMessage = exportMessage .. "Total Udbetalt: " .. math.floor(totalPayout) .. " DKK\n"
  exportMessage = exportMessage .. "Netto Profit: " .. math.floor(netProfit) .. " DKK\n\n"
  
  exportMessage = exportMessage .. "**Aktive Væddemål:**\n"
  exportMessage = exportMessage .. "Aktive Væddemål Værdi: " .. math.floor(activeBetsValue) .. " DKK\n"
  exportMessage = exportMessage .. "Potentiel Udbetaling: " .. math.floor(potentialPayout) .. " DKK\n"
  exportMessage = exportMessage .. "Risiko Eksponering: " .. math.floor(riskExposure) .. " DKK\n\n"
  
  exportMessage = exportMessage .. "**Månedlig Statistik (" .. os.date("%B %Y") .. "):**\n"
  exportMessage = exportMessage .. "Antal Væddemål: " .. betsPlaced .. "\n"
  exportMessage = exportMessage .. "Total Indsat: " .. math.floor(totalDeposited) .. " DKK\n"
  exportMessage = exportMessage .. "Total Udbetalt: " .. math.floor(totalWithdrawn) .. " DKK\n"
  exportMessage = exportMessage .. "Netto Indkomst: " .. math.floor(netIncome) .. " DKK\n\n"
  
  exportMessage = exportMessage .. "Rapport genereret af: " .. xPlayer.getName() .. " (" .. os.date("%d/%m/%Y %H:%M:%S") .. ")"
  
  DiscordLog("economic_report", source, exportMessage)
  
  return true
end)

lib.callback.register('Bet64-bet:getProfitLossAnalysis', function(source)
  local xPlayer = ESX.GetPlayerFromId(source)
  
  local hasPermission = false
  for _, job in pairs(Config.AdminJobs) do
    if xPlayer.getJob().name == job then
      hasPermission = true
      break
    end
  end
  
  if not hasPermission then
    DiscordLog("admin", source, "Forsøgte at hente profit/tab analyse uden tilladelse")
    return nil
  end
  
  local revenueResult = MySQL.query.await('SELECT SUM(amount) as total FROM Bet64_bets')
  local totalRevenue = revenueResult and revenueResult[1] and revenueResult[1].total or 0
  
  local payoutResult = MySQL.query.await('SELECT SUM(potential_win) as total FROM Bet64_bets WHERE status = "cashed_out"')
  local totalPayout = payoutResult and payoutResult[1] and payoutResult[1].total or 0
  
  totalRevenue = tonumber(totalRevenue) or 0
  totalPayout = tonumber(totalPayout) or 0
  
  local totalProfit = totalRevenue - totalPayout
  
  local profitMargin = 0
  if totalRevenue > 0 then
    profitMargin = math.floor((totalProfit / totalRevenue) * 100)
  end
  
  local sportProfitQuery = [[
    SELECT 
      e.sport_key,
      COUNT(b.id) as bet_count,
      SUM(b.amount) as total_stake,
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN 1 ELSE 0 END) as won_bets,
      SUM(CASE WHEN b.status = 'lost' THEN 1 ELSE 0 END) as lost_bets,
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN b.potential_win ELSE 0 END) as total_payout,
      SUM(b.amount) - SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN b.potential_win ELSE 0 END) as profit
    FROM 
      Bet64_bets b
    JOIN 
      Bet64_events e ON JSON_EXTRACT(b.selections, '$[0].event_id') = e.id
    WHERE 
      b.status IN ('won', 'lost', 'cashed_out')
    GROUP BY 
      e.sport_key
    ORDER BY 
      profit DESC
  ]]
  
  local sportProfitResult = MySQL.query.await(sportProfitQuery)
  local bySport = {}
  
  if sportProfitResult then
    for _, sport in ipairs(sportProfitResult) do
      local sportName = sport.sport_key or "Unknown"
      local totalStake = tonumber(sport.total_stake) or 0
      local profit = tonumber(sport.profit) or 0
      local profitMargin = 0
      
      if totalStake > 0 then
        profitMargin = math.floor((profit / totalStake) * 100)
      end
      
      table.insert(bySport, {
        name = sportName,
        betCount = tonumber(sport.bet_count) or 0,
        totalStake = math.floor(totalStake),
        wonBets = tonumber(sport.won_bets) or 0,
        lostBets = tonumber(sport.lost_bets) or 0,
        profit = math.floor(profit),
        profitMargin = profitMargin
      })
    end
  end
  
  local dayProfitQuery = [[
    SELECT 
      DAYOFWEEK(b.created_at) as day_of_week,
      COUNT(b.id) as bet_count,
      SUM(b.amount) as total_stake,
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN 1 ELSE 0 END) as won_bets,
      SUM(CASE WHEN b.status = 'lost' THEN 1 ELSE 0 END) as lost_bets,
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN b.potential_win ELSE 0 END) as total_payout,
      SUM(b.amount) - SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN b.potential_win ELSE 0 END) as profit
    FROM 
      Bet64_bets b
    WHERE 
      b.status IN ('won', 'lost', 'cashed_out')
    GROUP BY 
      DAYOFWEEK(b.created_at)
    ORDER BY 
      day_of_week
  ]]
  
  local dayProfitResult = MySQL.query.await(dayProfitQuery)
  local byDay = {}
  
  if dayProfitResult then
    local dayNames = {"Søndag", "Mandag", "Tirsdag", "Onsdag", "Torsdag", "Fredag", "Lørdag"}
    
    for _, day in ipairs(dayProfitResult) do
      local dayIndex = tonumber(day.day_of_week) or 1
      local dayName = dayNames[dayIndex] or "Unknown"
      local totalStake = tonumber(day.total_stake) or 0
      local profit = tonumber(day.profit) or 0
      local profitMargin = 0
      
      if totalStake > 0 then
        profitMargin = math.floor((profit / totalStake) * 100)
      end
      
      table.insert(byDay, {
        name = dayName,
        betCount = tonumber(day.bet_count) or 0,
        totalStake = math.floor(totalStake),
        wonBets = tonumber(day.won_bets) or 0,
        lostBets = tonumber(day.lost_bets) or 0,
        profit = math.floor(profit),
        profitMargin = profitMargin
      })
    end
  end
  
  local hourProfitQuery = [[
    SELECT 
      HOUR(b.created_at) as hour,
      COUNT(b.id) as bet_count,
      SUM(b.amount) as total_stake,
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN 1 ELSE 0 END) as won_bets,
      SUM(CASE WHEN b.status = 'lost' THEN 1 ELSE 0 END) as lost_bets,
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN b.potential_win ELSE 0 END) as total_payout,
      SUM(b.amount) - SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN b.potential_win ELSE 0 END) as profit
    FROM 
      Bet64_bets b
    WHERE 
      b.status IN ('won', 'lost', 'cashed_out')
    GROUP BY 
      HOUR(b.created_at)
    ORDER BY 
      hour
  ]]
  
  local hourProfitResult = MySQL.query.await(hourProfitQuery)
  local byHour = {}
  
  if hourProfitResult then
    for _, hour in ipairs(hourProfitResult) do
      local totalStake = tonumber(hour.total_stake) or 0
      local profit = tonumber(hour.profit) or 0
      local profitMargin = 0
      
      if totalStake > 0 then
        profitMargin = math.floor((profit / totalStake) * 100)
      end
      
      table.insert(byHour, {
        hour = tonumber(hour.hour) or 0,
        betCount = tonumber(hour.bet_count) or 0,
        totalStake = math.floor(totalStake),
        wonBets = tonumber(hour.won_bets) or 0,
        lostBets = tonumber(hour.lost_bets) or 0,
        profit = math.floor(profit),
        profitMargin = profitMargin
      })
    end
  end
  
  local oddsRanges = {
    {min = 1.0, max = 1.5, name = "1.00 - 1.50"},
    {min = 1.5, max = 2.0, name = "1.51 - 2.00"},
    {min = 2.0, max = 3.0, name = "2.01 - 3.00"},
    {min = 3.0, max = 5.0, name = "3.01 - 5.00"},
    {min = 5.0, max = 10.0, name = "5.01 - 10.00"},
    {min = 10.0, max = 999999, name = "10.01+"}
  }
  
  local byOdds = {}
  
  for _, range in ipairs(oddsRanges) do
    local oddsQuery = [[
      SELECT 
        COUNT(b.id) as bet_count,
        SUM(b.amount) as total_stake,
        SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN 1 ELSE 0 END) as won_bets,
        SUM(CASE WHEN b.status = 'lost' THEN 1 ELSE 0 END) as lost_bets,
        SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN b.potential_win ELSE 0 END) as total_payout,
        SUM(b.amount) - SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN b.potential_win ELSE 0 END) as profit
      FROM 
        Bet64_bets b
      JOIN 
        Bet64_events e ON JSON_EXTRACT(b.selections, '$[0].event_id') = e.id
      WHERE 
        b.status IN ('won', 'lost', 'cashed_out')
        AND (
          (JSON_EXTRACT(b.selections, '$[0].team') = e.home_team AND e.home_odds BETWEEN ? AND ?)
          OR
          (JSON_EXTRACT(b.selections, '$[0].team') = e.away_team AND e.away_odds BETWEEN ? AND ?)
        )
    ]]
    
    local oddsResult = MySQL.query.await(oddsQuery, {range.min, range.max, range.min, range.max})
    
    if oddsResult and oddsResult[1] then
      local odds = oddsResult[1]
      local totalStake = tonumber(odds.total_stake) or 0
      local profit = tonumber(odds.profit) or 0
      local profitMargin = 0
      
      if totalStake > 0 then
        profitMargin = math.floor((profit / totalStake) * 100)
      end
      
      table.insert(byOdds, {
        range = range.name,
        betCount = tonumber(odds.bet_count) or 0,
        totalStake = math.floor(totalStake),
        wonBets = tonumber(odds.won_bets) or 0,
        lostBets = tonumber(odds.lost_bets) or 0,
        profit = math.floor(profit),
        profitMargin = profitMargin
      })
    end
  end
  
  DiscordLog("admin", source, "Hentede profit/tab analyse")
  
  return {
    totalProfit = math.floor(totalProfit),
    profitMargin = profitMargin,
    bySport = bySport,
    byDay = byDay,
    byHour = byHour,
    byOdds = byOdds
  }
end)

lib.callback.register('Bet64-bet:getTopPlayers', function(source)
  local xPlayer = ESX.GetPlayerFromId(source)
  
  local hasPermission = false
  for _, job in pairs(Config.AdminJobs) do
    if xPlayer.getJob().name == job then
      hasPermission = true
      break
    end
  end
  
  if not hasPermission then
    DiscordLog("admin", source, "Forsøgte at hente top spillere uden tilladelse")
    return nil
  end
  
  local mostActiveQuery = [[
    SELECT 
      b.player_identifier,
      COUNT(b.id) as bet_count,
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN 1 ELSE 0 END) as won_bets,
      SUM(CASE WHEN b.status = 'lost' THEN 1 ELSE 0 END) as lost_bets,
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN b.potential_win - b.amount ELSE 0 END) as total_winnings,
      SUM(CASE WHEN b.status = 'lost' THEN b.amount ELSE 0 END) as total_losses,
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN b.potential_win - b.amount ELSE -b.amount END) as net_profit
    FROM 
      Bet64_bets b
    GROUP BY 
      b.player_identifier
    ORDER BY 
      bet_count DESC
    LIMIT 10
  ]]
  
  local mostActiveResult = MySQL.query.await(mostActiveQuery)
  local mostActive = {}
  
  if mostActiveResult then
    for _, player in ipairs(mostActiveResult) do
      local playerName = "Ukendt Spiller"
      local playerInfo = MySQL.query.await('SELECT firstname, lastname FROM users WHERE identifier = ?', {player.player_identifier})
      if playerInfo and playerInfo[1] then
        playerName = (playerInfo[1].firstname or "") .. " " .. (playerInfo[1].lastname or "")
      end
      
      local winRate = 0
      local totalBets = (player.won_bets or 0) + (player.lost_bets or 0)
      if totalBets > 0 then
        winRate = math.floor(((player.won_bets or 0) / totalBets) * 100)
      end
      
      table.insert(mostActive, {
        identifier = player.player_identifier,
        name = playerName,
        betCount = player.bet_count or 0,
        totalStake = math.floor(player.total_stake or 0),
        wonBets = player.won_bets or 0,
        lostBets = player.lost_bets or 0,
        winRate = winRate,
        netProfit = math.floor(player.net_profit or 0)
      })
    end
  end
  
  local biggestWinnersQuery = [[
    SELECT 
      b.player_identifier,
      COUNT(b.id) as bet_count,
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN 1 ELSE 0 END) as won_bets,
      SUM(CASE WHEN b.status = 'lost' THEN 1 ELSE 0 END) as lost_bets,
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN b.potential_win - b.amount ELSE 0 END) as total_winnings,
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN b.potential_win - b.amount ELSE -b.amount END) as net_profit
    FROM 
      Bet64_bets b
    GROUP BY 
      b.player_identifier
    HAVING 
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN b.potential_win - b.amount ELSE 0 END) > 0
    ORDER BY 
      total_winnings DESC
    LIMIT 10
  ]]
  
  local biggestWinnersResult = MySQL.query.await(biggestWinnersQuery)
  local biggestWinners = {}
  
  if biggestWinnersResult then
    for _, player in ipairs(biggestWinnersResult) do
      local playerName = "Ukendt Spiller"
      local playerInfo = MySQL.query.await('SELECT firstname, lastname FROM users WHERE identifier = ?', {player.player_identifier})
      if playerInfo and playerInfo[1] then
        playerName = (playerInfo[1].firstname or "") .. " " .. (playerInfo[1].lastname or "")
      end
      
      local winRate = 0
      local totalBets = (player.won_bets or 0) + (player.lost_bets or 0)
      if totalBets > 0 then
        winRate = math.floor(((player.won_bets or 0) / totalBets) * 100)
      end
      
      table.insert(biggestWinners, {
        identifier = player.player_identifier,
        name = playerName,
        betCount = player.bet_count or 0,
        wonBets = player.won_bets or 0,
        lostBets = player.lost_bets or 0,
        winRate = winRate,
        totalWinnings = math.floor(player.total_winnings or 0),
        netProfit = math.floor(player.net_profit or 0)
      })
    end
  end
  
  local biggestLosersQuery = [[
    SELECT 
      b.player_identifier,
      COUNT(b.id) as bet_count,
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN 1 ELSE 0 END) as won_bets,
      SUM(CASE WHEN b.status = 'lost' THEN 1 ELSE 0 END) as lost_bets,
      SUM(CASE WHEN b.status = 'lost' THEN b.amount ELSE 0 END) as total_losses,
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN b.potential_win - b.amount ELSE -b.amount END) as net_profit
    FROM 
      Bet64_bets b
    GROUP BY 
      b.player_identifier
    HAVING 
      SUM(CASE WHEN b.status = 'lost' THEN b.amount ELSE 0 END) > 0
    ORDER BY 
      total_losses DESC
    LIMIT 10
  ]]
  
  local biggestLosersResult = MySQL.query.await(biggestLosersQuery)
  local biggestLosers = {}
  
  if biggestLosersResult then
    for _, player in ipairs(biggestLosersResult) do
      local playerName = "Ukendt Spiller"
      local playerInfo = MySQL.query.await('SELECT firstname, lastname FROM users WHERE identifier = ?', {player.player_identifier})
      if playerInfo and playerInfo[1] then
        playerName = (playerInfo[1].firstname or "") .. " " .. (playerInfo[1].lastname or "")
      end
      
      local winRate = 0
      local totalBets = (player.won_bets or 0) + (player.lost_bets or 0)
      if totalBets > 0 then
        winRate = math.floor(((player.won_bets or 0) / totalBets) * 100)
      end
      
      table.insert(biggestLosers, {
        identifier = player.player_identifier,
        name = playerName,
        betCount = player.bet_count or 0,
        wonBets = player.won_bets or 0,
        lostBets = player.lost_bets or 0,
        winRate = winRate,
        totalLosses = math.floor(player.total_losses or 0),
        netLoss = math.floor(-(player.net_profit or 0))
      })
    end
  end
  
  local highestWinRateQuery = [[
    SELECT 
      b.player_identifier,
      COUNT(b.id) as bet_count,
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN 1 ELSE 0 END) as won_bets,
      SUM(CASE WHEN b.status = 'lost' THEN 1 ELSE 0 END) as lost_bets,
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN b.potential_win - b.amount ELSE 0 END) as total_winnings,
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN b.potential_win - b.amount ELSE -b.amount END) as net_profit
    FROM 
      Bet64_bets b
    GROUP BY 
      b.player_identifier
    HAVING 
      (SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN 1 ELSE 0 END) + SUM(CASE WHEN b.status = 'lost' THEN 1 ELSE 0 END)) >= 10
    ORDER BY 
      SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN 1 ELSE 0 END) / 
      (SUM(CASE WHEN b.status = 'won' OR b.status = 'cashed_out' THEN 1 ELSE 0 END) + SUM(CASE WHEN b.status = 'lost' THEN 1 ELSE 0 END)) DESC
    LIMIT 10
  ]]
  
  local highestWinRateResult = MySQL.query.await(highestWinRateQuery)
  local highestWinRate = {}
  
  if highestWinRateResult then
    for _, player in ipairs(highestWinRateResult) do
      local playerName = "Ukendt Spiller"
      local playerInfo = MySQL.query.await('SELECT firstname, lastname FROM users WHERE identifier = ?', {player.player_identifier})
      if playerInfo and playerInfo[1] then
        playerName = (playerInfo[1].firstname or "") .. " " .. (playerInfo[1].lastname or "")
      end
      
      local winRate = 0
      local totalBets = (player.won_bets or 0) + (player.lost_bets or 0)
      if totalBets > 0 then
        winRate = math.floor(((player.won_bets or 0) / totalBets) * 100)
      end
      
      table.insert(highestWinRate, {
        identifier = player.player_identifier,
        name = playerName,
        betCount = player.bet_count or 0,
        wonBets = player.won_bets or 0,
        lostBets = player.lost_bets or 0,
        winRate = winRate,
        totalWinnings = math.floor(player.total_winnings or 0),
        netProfit = math.floor(player.net_profit or 0)
      })
    end
  end
  
  local biggestSingleWinsQuery = [[
    SELECT 
      b.id as bet_id,
      b.player_identifier,
      b.amount as stake,
      b.potential_win as win_amount,
      b.created_at as date,
      JSON_EXTRACT(b.selections, '$[0].team') as team,
      JSON_EXTRACT(b.selections, '$[0].odds') as odds,
      JSON_EXTRACT(b.selections, '$[0].game') as game_match
    FROM 
      Bet64_bets b
    WHERE 
      b.status = 'cashed_out'
    ORDER BY 
      b.potential_win DESC
    LIMIT 10
  ]]
  
  local biggestSingleWinsResult = MySQL.query.await(biggestSingleWinsQuery)
  local biggestSingleWins = {}
  
  if biggestSingleWinsResult then
    for _, win in ipairs(biggestSingleWinsResult) do
      local playerName = "Ukendt Spiller"
      local playerInfo = MySQL.query.await('SELECT firstname, lastname FROM users WHERE identifier = ?', {win.player_identifier})
      if playerInfo and playerInfo[1] then
        playerName = (playerInfo[1].firstname or "") .. " " .. (playerInfo[1].lastname or "")
      end
      
      local formattedDate = "Ukendt dato"
      if win.date then
        local timestamp = win.date
        if type(timestamp) == "number" or tonumber(timestamp) then
          local ts = tonumber(timestamp)
          if ts > 9999999999 then ts = ts / 1000 end
          formattedDate = os.date("%d. %b %Y %H:%M", ts)
        elseif type(timestamp) == "string" and timestamp:match("%d%d%d%d%-%d%d%-%d%d") then
          local year, month, day, hour, min = timestamp:match("(%d+)-(%d+)-(%d+) (%d+):(%d+)")
          if year and month and day then
            local monthNames = {"Jan", "Feb", "Mar", "Apr", "Maj", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dec"}
            local monthName = monthNames[tonumber(month)]
            formattedDate = string.format("%d. %s %Y %s:%s", tonumber(day), monthName, year, hour or "00", min or "00")
          end
        end
      end
      
      local team = win.team and win.team:gsub('"', '') or "Unknown"
      local odds = win.odds and win.odds:gsub('"', '') or "1.0"
      local match = win.game_match and win.game_match:gsub('"', '') or "Unknown Match"
      
      table.insert(biggestSingleWins, {
        betId = win.bet_id,
        playerIdentifier = win.player_identifier,
        playerName = playerName,
        stake = math.floor(win.stake or 0),
        winAmount = math.floor(win.win_amount or 0),
        date = formattedDate,
        odds = odds,
        team = team,
        match = match
      })
    end
  end
  
  DiscordLog("admin", source, "Hentede top spillere data")
  
  return {
    mostActive = mostActive,
    biggestWinners = biggestWinners,
    biggestLosers = biggestLosers,
    highestWinRate = highestWinRate,
    biggestSingleWins = biggestSingleWins
  }
end)