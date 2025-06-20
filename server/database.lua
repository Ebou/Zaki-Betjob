CreateThread(function()
  MySQL.query([[
    CREATE TABLE IF NOT EXISTS Bet64_bets (
      id INT AUTO_INCREMENT PRIMARY KEY,
      player_identifier VARCHAR(50) NOT NULL,
      amount FLOAT NOT NULL,
      bet_type VARCHAR(50) NOT NULL,
      status VARCHAR(20) NOT NULL,
      selections JSON NOT NULL,
      potential_win FLOAT NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ]])

  MySQL.query([[
    CREATE TABLE IF NOT EXISTS Bet64_balances (
      player_identifier VARCHAR(50) PRIMARY KEY,
      balance FLOAT NOT NULL DEFAULT 0,
      frozen BOOLEAN NOT NULL DEFAULT FALSE,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  ]])

  MySQL.query([[
    CREATE TABLE IF NOT EXISTS Bet64_stats (
      player_identifier VARCHAR(50) PRIMARY KEY,
      total_winnings FLOAT NOT NULL DEFAULT 0,
      total_losses FLOAT NOT NULL DEFAULT 0,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  ]])

  MySQL.query([[
    CREATE TABLE IF NOT EXISTS Bet64_deposits (
      id INT AUTO_INCREMENT PRIMARY KEY,
      player_identifier VARCHAR(50) NOT NULL,
      amount FLOAT NOT NULL,
      deposit_date DATE NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_player_date (player_identifier, deposit_date)
    )
  ]])

  MySQL.query([[
    CREATE TABLE IF NOT EXISTS Bet64_events (
      id INT AUTO_INCREMENT PRIMARY KEY,
      sport_key VARCHAR(50) NOT NULL,
      home_team VARCHAR(100) NOT NULL,
      away_team VARCHAR(100) NOT NULL,
      home_odds FLOAT NOT NULL,
      away_odds FLOAT NOT NULL,
      home_color VARCHAR(20) DEFAULT '#1e88e5',
      away_color VARCHAR(20) DEFAULT '#f44336',
      commence_time TIMESTAMP NOT NULL,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      is_finished BOOLEAN NOT NULL DEFAULT FALSE,
      winner VARCHAR(100),
      created_by VARCHAR(50) NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  ]])

  
  MySQL.query([[
    SELECT COUNT(*) as count FROM information_schema.columns 
    WHERE table_schema = DATABASE() 
    AND table_name = 'Bet64_events' 
    AND column_name = 'home_color'
  ]], {}, function(result)
    if result[1].count == 0 then
      MySQL.query([[
        ALTER TABLE Bet64_events 
        ADD COLUMN home_color VARCHAR(20) DEFAULT '#1e88e5',
        ADD COLUMN away_color VARCHAR(20) DEFAULT '#f44336'
      ]])
    end
  end)
  
  
  
  MySQL.query([[
    SELECT COUNT(*) as count FROM information_schema.columns 
    WHERE table_schema = DATABASE() 
    AND table_name = 'Bet64_balances' 
    AND column_name = 'frozen'
  ]], {}, function(result)
    if result[1].count == 0 then
      MySQL.query([[
        ALTER TABLE Bet64_balances 
        ADD COLUMN frozen BOOLEAN NOT NULL DEFAULT FALSE
      ]])
    end
  end)
  MySQL.query([[
    SELECT COUNT(*) as count FROM information_schema.columns 
    WHERE table_schema = DATABASE() 
    AND table_name = 'Bet64_events' 
    AND column_name = 'draw_odds'
  ]], {}, function(result)
    if result[1].count == 0 then
      MySQL.query([[
        ALTER TABLE Bet64_events 
        ADD COLUMN draw_odds FLOAT DEFAULT 3.0
        AFTER away_odds
      ]])
    end
  end)
 
end)

function getPlayerBets(identifier)
  local result = MySQL.query.await('SELECT * FROM Bet64_bets WHERE player_identifier = ? ORDER BY created_at DESC', { identifier })
  if result then
    for _, bet in ipairs(result) do
      bet.selections = json.decode(bet.selections)
    end
    return result
  else
    return {}
  end
end


function getPlayerBettingBalance(identifier)
  local result = MySQL.query.await('SELECT balance FROM Bet64_balances WHERE player_identifier = ?', { identifier })
  if result and result[1] then
    return result[1].balance
  else
    MySQL.insert.await('INSERT INTO Bet64_balances (player_identifier, balance, frozen) VALUES (?, ?, ?)', { identifier, 0, false })
    return 0
  end
end

function updatePlayerBettingBalance(identifier, newBalance)
  local result = MySQL.update.await('UPDATE Bet64_balances SET balance = ? WHERE player_identifier = ?', { newBalance, identifier })
  return result > 0
end

function isAccountFrozen(identifier)
  local result = MySQL.query.await('SELECT frozen FROM Bet64_balances WHERE player_identifier = ?', { identifier })
  if result and result[1] then
    return result[1].frozen == 1 or result[1].frozen == true
  else
    MySQL.insert.await('INSERT INTO Bet64_balances (player_identifier, balance, frozen) VALUES (?, ?, ?)', { identifier, 0, false })
    return false
  end
end

function setAccountFrozen(identifier, frozen)
  local frozenValue = frozen and 1 or 0
  local result = MySQL.update.await('UPDATE Bet64_balances SET frozen = ? WHERE player_identifier = ?', { frozenValue, identifier })
  return result > 0
end

function getPlayerBettingStats(identifier)
  local result = MySQL.query.await('SELECT total_winnings, total_losses FROM Bet64_stats WHERE player_identifier = ?', { identifier })
  if result and result[1] then
    return result[1]
  else
    MySQL.insert.await('INSERT INTO Bet64_stats (player_identifier, total_winnings, total_losses) VALUES (?, ?, ?)', { identifier, 0, 0 })
    return { total_winnings = 0, total_losses = 0 }
  end
end

function updatePlayerBettingStats(identifier, totalWinnings, totalLosses)
  local result = MySQL.update.await('UPDATE Bet64_stats SET total_winnings = ?, total_losses = ? WHERE player_identifier = ?', { totalWinnings, totalLosses, identifier })
  return result > 0
end

function addBet(identifier, amount, betType, selections, potentialWin)
  local betId = MySQL.insert.await('INSERT INTO Bet64_bets (player_identifier, amount, bet_type, status, selections, potential_win) VALUES (?, ?, ?, ?, ?, ?)', {
    identifier,
    amount,
    betType,
    'active',
    json.encode(selections),
    potentialWin
  })
  
  local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
  if xPlayer and betId then
    DiscordLog("bet_placed", xPlayer.source, "Placerede et væddemål (#" .. betId .. ") på " .. amount .. " DKK med potentiel gevinst på " .. potentialWin .. " DKK")
  end
  
  return betId
end

function updateBetStatus(betId, status)
  local result = MySQL.update.await('UPDATE Bet64_bets SET status = ? WHERE id = ?', { status, betId })
  return result > 0
end

function checkDailyDepositLimit(identifier, amount)
  print(amount)
  local today = os.date("%Y-%m-%d")
  
  local result = MySQL.query.await('SELECT SUM(amount) as total FROM Bet64_deposits WHERE player_identifier = ? AND deposit_date = ?', 
    { identifier, today })
  
  local totalToday = 0
  if result and result[1] and result[1].total then
    totalToday = result[1].total
  end
  print(amount, totalToday)
  if amount then
    amount = 0
  end

  if (totalToday + amount) > Config.DailyLimit then
    return false, totalToday
  end
  
  return true, totalToday
end

function recordDeposit(identifier, amount)
  local today = os.date("%Y-%m-%d")
  
  local result = MySQL.insert.await('INSERT INTO Bet64_deposits (player_identifier, amount, deposit_date) VALUES (?, ?, ?)',
    { identifier, amount, today })
  
  local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
  if xPlayer and result then
    DiscordLog("deposits", xPlayer.source, "Indbetalt " .. amount .. " DKK til betting konto")
  end
  
  return result
end


function getBettingEvents(activeOnly)
  local query = 'SELECT * FROM Bet64_events WHERE winner IS NULL'
  if activeOnly then
    query = query .. ' AND is_active = 1 AND is_finished = 0'
  end
  query = query .. ' ORDER BY commence_time ASC'
  
  local result = MySQL.query.await(query)
  
  if result then
    for _, event in ipairs(result) do
      local currentTime = os.time()
      local eventTime = math.floor(event.commence_time / 1000) 
      local timeDiff = eventTime - currentTime

      if timeDiff > 0 then
        local days = math.floor(timeDiff / (24 * 3600))
        local hours = math.floor((timeDiff % (24 * 3600)) / 3600)
        local minutes = math.floor((timeDiff % 3600) / 60)
        if days > 0 then
          event.event_formatted_time = string.format("Om %d dage, %d timer og %d minutter", days, hours, minutes)
        elseif hours > 0 then
          event.event_formatted_time = string.format("Om %d timer og %d minutter", hours, minutes)
        else
          event.event_formatted_time = string.format("Om %d minutter", minutes)
        end
        event.statusColour = "green"
      else
        local timeDiffAbs = math.abs(timeDiff)
        local days = math.floor(timeDiffAbs / (24 * 3600))
        local hours = math.floor((timeDiffAbs % (24 * 3600)) / 3600)
        local minutes = math.floor((timeDiffAbs % 3600) / 60)
        if days > 0 then
          event.event_formatted_time = string.format("For %d dage, %d timer og %d minutter siden", days, hours, minutes)
        elseif hours > 0 then
          event.event_formatted_time = string.format("For %d timer og %d minutter siden", hours, minutes)
        else
          event.event_formatted_time = string.format("For %d minutter siden", minutes)
        end
        event.statusColour = "red"
      end
    end
  end
  
  return result or {}
end

function formatBettingEvent(event)
  local dbTimestamp = event.commence_time
  local formattedTime = "TBA"

  if dbTimestamp then
    local eventTime
    if type(dbTimestamp) == "string" then
      local year, month, day, hour, min, sec = string.match(dbTimestamp, "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
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
    elseif type(dbTimestamp) == "number" then
      eventTime = math.floor(dbTimestamp / 1000)
    end

    if eventTime then
      local days, hours, minutes = formatTimeDifference(eventTime)
      if days > 0 then
        formattedTime = string.format("%d dage, %d timer, %d minutter", days, hours, minutes)
      elseif hours > 0 then
        formattedTime = string.format("%d timer, %d minutter", hours, minutes)
      elseif minutes > 0 then
        formattedTime = string.format("%d minutter", minutes)
      else
        formattedTime = "Allerede startet"
      end
    end
  end

  local isoDateTime = dbTimestamp
  if type(dbTimestamp) == "string" then
    isoDateTime = dbTimestamp:gsub(" ", "T")
  end
  
  local drawOdds = event.draw_odds
  -- print(drawOdds)
  return {
    id = event.id,
    sport_key = event.sport_key,
    home_team = event.home_team,
    away_team = event.away_team,
    commence_time = isoDateTime,
    formatted_time = formattedTime,
    is_active = event.is_active == 1,
    is_finished = event.is_finished == 1,
    is_live = event.is_live == 1,
    winner = event.winner,
    home_odds = event.home_odds,
    away_odds = event.away_odds,
    draw_odds = drawOdds,
    teams = {
      home = {
        colors = {
          primary = event.home_color or Config.DefaultColors.HomeTeam
        }
      },
      away = {
        colors = {
          primary = event.away_color or Config.DefaultColors.AwayTeam
        }
      }
    },
    bookmakers = {
      {
        title = Config.AppName,
        markets = {
          {
            key = "h2h",
            outcomes = {
              { name = event.home_team, price = event.home_odds },
              { name = "Uafgjort", price = drawOdds },
              { name = event.away_team, price = event.away_odds }
            }
          }
        }
      }
    }
  }
end


function getDrawOdds(event)
  return event.draw_odds or 1.1
end
function formatTimeDifference(eventTime)
  local currentTime = os.time()
  local timeDiff = eventTime - currentTime

  if timeDiff > 0 then
    local days = math.floor(timeDiff / (24 * 3600))
    local hours = math.floor((timeDiff % (24 * 3600)) / 3600)
    local minutes = math.floor((timeDiff % 3600) / 60)
    return days, hours, minutes
  else
    return 0, 0, 0
  end
end




function updateParlayStatus(betId)
  local bet = MySQL.query.await('SELECT * FROM Bet64_bets WHERE id = ?', { betId })
  if not bet or not bet[1] then return end
  
  bet = bet[1]
  
  if bet.bet_type ~= "Parlay Væddemål" then return end
  
  local selections = json.decode(bet.selections)
  local allWon = true
  local anyLost = false
  
  for _, selection in ipairs(selections) do
      if selection.event_id then
          local event = MySQL.query.await('SELECT * FROM Bet64_events WHERE id = ?', { selection.event_id })
          if event and event[1] then
              if event[1].is_finished and event[1].winner then
                -- print(event[1].winner, selection.team)
                  if event[1].winner == "cancelled" then
                      updateBetStatus(betId, "refunded")
                      
                      local playerIdentifier = bet.player_identifier
                      local playerBalance = getPlayerBettingBalance(playerIdentifier)
                      updatePlayerBettingBalance(playerIdentifier, playerBalance + bet.amount)
                      
                      return
                  elseif selection.team ~= event[1].winner and not (selection.team == "Uafgjort" and event[1].winner == "draw") then
                      updateBetStatus(betId, "lost")
                      
                      local playerIdentifier = bet.player_identifier
                      local stats = getPlayerBettingStats(playerIdentifier)
                      updatePlayerBettingStats(playerIdentifier, stats.total_winnings, stats.total_losses + bet.amount)
                      
                      return
                  end
              else
                  allWon = false
              end
          end
      end
  end
  
  if allWon then
      updateBetStatus(betId, "won")
      
      local playerIdentifier = bet.player_identifier
      local stats = getPlayerBettingStats(playerIdentifier)
      local profit = bet.potential_win - bet.amount
      updatePlayerBettingStats(playerIdentifier, stats.total_winnings + profit, stats.total_losses)
      
      local xPlayer = ESX.GetPlayerFromIdentifier(playerIdentifier)
      if xPlayer then
          TriggerClientEvent('ox_lib:notify', xPlayer.source, {
              title = Config.AppName,
              description = "Din parlay har vundet! Du kan nu udbetale " .. bet.potential_win .. " DKK.",
              type = "success"
          })
      end
  end
end