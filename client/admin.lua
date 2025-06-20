function RegisterBettingAdminMenus()
  lib.registerContext({
    id = 'Bet64_bet_admin_main',
    title = 'Bet64 Administration',
    options = {
      {
        title = 'Udsend Reklame',
        description = 'Udsend en reklame til spillere!',
        icon = 'bullhorn',
        onSelect = function()
          CreateAd()
        end
      },



      {
        title = 'Opret Nyt Væddemål',
        description = 'Opret et nyt væddemål i systemet',
        icon = 'plus',
        onSelect = function()
          CreateNewBettingEvent()
        end
      },
      {
        title = 'Administrer Væddemål',
        description = 'Se og administrer eksisterende væddemål',
        icon = 'list',
        onSelect = function()
          LoadAndShowBettingEvents()
        end
      },
      {
        title = 'Aktive Odds',
        description = 'Se detaljeret odds for aktive væddemål',
        icon = 'ticket',
        onSelect = function()
          LoadAndShowAllBets()
        end
      },
      {
        title = 'Søg Spiller',
        description = 'Find en spiller ved hjælp af deres ID',
        icon = 'search',
        onSelect = function()
          PromptAndHandlePlayerById()
        end
      },
      {
        title = 'Økonomisk Oversigt',
        description = 'Se detaljeret økonomisk statistik',
        icon = 'chart-line',
        onSelect = function()
          ShowEconomicOverview()
        end
      },

      {
        title = 'Profit/Tab Analyse',
        description = 'Analysér profit og tab over tid',
        icon = 'chart-pie',
        onSelect = function()
          ShowProfitLossAnalysis()
        end
      },
      {
        title = 'Top Spillere',
        description = 'Se de mest aktive spillere og største vindere/tabere',
        icon = 'trophy',
        onSelect = function()
          ShowTopPlayers()
        end
      }
    }
  })
end

function PromptAndHandlePlayerById()
  local input = lib.inputDialog('Indtast Spiller ID', {
    {
      type = 'number',
      label = 'Server ID',
      description = 'Skriv spillerens server ID',
      required = true,
      min = 1
    }
  })

  if input then
    local targetId = tonumber(input[1])
    if targetId and targetId > 0 then
      local success, playerInfo = lib.callback.await('Bet64-bet:getPlayerInfo', false, targetId)

      if not success then
        lib.notify({
          title = Config.AppName,
          description = Config.Notifications.PlayerNotFound,
          type = 'error'
        })
        return
      end

      RegisterPlayerManagementMenus(targetId, playerInfo)
    else
      lib.notify({
        title = Config.AppName,
        description = Config.Notifications.InvalidID,
        type = 'error'
      })
    end
  end
end

function CreateNewBettingEvent()
  local input = lib.inputDialog('Opret Nyt Væddemål', {
    {type = 'select', label = 'Sport', options = Config.SportTypes, required = true},
    {type = 'input', label = 'Hjemmehold', required = true},
    {type = 'input', label = 'Udehold', required = true},
    {type = 'slider', label = 'Hjemmehold Odds', min = 0.5, max = 10.0, step = 0.1, default = 1.8, required = true},
    {type = 'slider', label = 'Uafgjort Odds', min = 0.5, max = 10.0, step = 0.1, default = 3.0, required = true},
    {type = 'slider', label = 'Udehold Odds', min = 0.5, max = 10.0, step = 0.1, default = 1.8, required = true},
    {type = 'color', label = 'Hjemmehold Farve', default = Config.DefaultColors.HomeTeam, format = 'hex'},
    {type = 'color', label = 'Udehold Farve', default = Config.DefaultColors.AwayTeam, format = 'hex'},
    {type = 'date', label = 'Dato', format = 'DD-MM-YYYY', returnString = true, required = true},
    {type = 'input', label = 'Tid (F.eks. 13:55)', required = true}
  })

  if input then
    local sportKey = input[1]
    local homeTeam = input[2]
    local awayTeam = input[3]
    local homeOdds = tonumber(input[4])
    local drawOdds = tonumber(input[5])
    local awayOdds = tonumber(input[6])
    local homeColor = input[7]
    local awayColor = input[8]
    local dateStr = input[9] 
    local timeStr = input[10] 

    if not timeStr:match("^%d%d:%d%d$") then
      lib.notify({
        title = Config.AppName,
        description = Config.Notifications.InvalidTimeFormat,
        type = 'error'
      })
      return
    end

    local day, month, year = dateStr:match("(%d+)%-(%d+)%-(%d+)")
    if not (day and month and year) then
      lib.notify({
        title = Config.AppName,
        description = Config.Notifications.InvalidDateFormat,
        type = 'error'
      })
      return
    end

    local formattedDateTime = string.format("%s-%s-%s %s:00", year, month, day, timeStr)

    local success, message = lib.callback.await('Bet64-bet:createBettingEvent', false, {
      sport_key = sportKey,
      home_team = homeTeam,
      away_team = awayTeam,
      home_odds = homeOdds,
      draw_odds = drawOdds,
      away_odds = awayOdds,
      home_color = homeColor,
      away_color = awayColor,
      commence_time = formattedDateTime  
    })

    lib.notify({
      title = Config.AppName,
      description = message,
      type = success and 'success' or 'error'
    })

    if success then
      Wait(500)
      LoadAndShowBettingEvents()
    end
  end
end

function LoadAndShowBettingEvents()
  local bettingEvents = lib.callback.await('Bet64-bet:getBettingEvents', false)
  print(json.encode(bettingEvents))
  if not bettingEvents or #bettingEvents == 0 then
    lib.notify({
      title = 'Bet64',
      description = 'Ingen væddemål fundet',
      type = 'info'
    })
    return
  end

  local options = {}

  for _, event in ipairs(bettingEvents) do
    local formattedTime = nil
    if event.commence_time then
       formattedTime = event.event_formatted_time or "Dato ikke tilgængelig"
    end
    
    table.insert(options, {
      title = event.home_team .. ' vs ' .. event.away_team,
      icon = 'trophy',
      iconColor = event.statusColour,
      metadata = {
        {label = 'Sport', value = event.sport_key},
        {label = 'Tidspunkt', value = formattedTime},
        {label = 'Hjemmehold Odds', value = event.home_odds},
        {label = 'Udehold Odds', value = event.away_odds}
      },
      onSelect = function()
        ShowEventManagementMenu(event)
      end
    })
  end

  lib.registerContext({
    id = 'Bet64_bet_events_list',
    title = 'Væddemål',
    menu = 'Bet64_bet_admin_main',
    options = options
  })

  lib.showContext('Bet64_bet_events_list')
end

function ShowEventManagementMenu(event)
  lib.registerContext({
    id = 'Bet64_bet_event_management',
    title = event.home_team .. ' vs ' .. event.away_team,
    menu = 'Bet64_bet_events_list',
    options = {
      {
        title = 'Rediger Odds',
        description = 'Opdater odds for dette væddemål',
        icon = 'edit',
        onSelect = function()
          EditEventOdds(event)
        end
      },

      {
        title = 'Sæt Vinder',
        description = 'Afslut væddemålet og angiv vinderholdet',
        icon = 'trophy',
        onSelect = function()
          SetEventWinner(event)
        end
      },
      {
        title = 'Slet Væddemål',
        description = 'Fjern dette væddemål fra systemet',
        icon = 'trash',
        onSelect = function()
          DeleteEvent(event)
        end
      }
    }
  })
  
  lib.showContext('Bet64_bet_event_management')
end

function EditEventOdds(event)
  local input = lib.inputDialog('Rediger Odds', {
    {type = 'slider', label = 'Hjemmehold Odds', default = event.home_odds, min = 1.1, max = 10.0, step = 0.1, required = true},
    {type = 'slider', label = 'Uafgjort Odds', default = event.draw_odds or 3.0, min = 1.1, max = 10.0, step = 0.1, required = true},
    {type = 'slider', label = 'Udehold Odds', default = event.away_odds, min = 1.1, max = 10.0, step = 0.1, required = true}
  })
  
  if input then
    local homeOdds = tonumber(input[1])
    local drawOdds = tonumber(input[2])
    local awayOdds = tonumber(input[3])
    
    local success, message = lib.callback.await('Bet64-bet:updateEventOdds', false, event.id, homeOdds, drawOdds, awayOdds)
    
    lib.notify({
      title = Config.AppName,
      description = message,
      type = success and 'success' or 'error'
    })
    
    if success then
      Wait(500)
      LoadAndShowBettingEvents()
    end
  end
end

function ToggleEventStatus(event)
  local success, message = lib.callback.await('Bet64-bet:toggleEventStatus', false, event.id, event.is_active == 0)
  
  lib.notify({
    title = Config.AppName,
    description = message,
    type = success and 'success' or 'error'
  })
  
  if success then
    Wait(500)
    LoadAndShowBettingEvents()
  end
end

function SetEventWinner(event)
  local winnerOptions = {
    {value = event.home_team, label = event.home_team},
    {value = event.away_team, label = event.away_team},
    {value = 'draw', label = 'Uafgjort'},
    {value = 'cancelled', label = 'Aflyst Kamp'}
  }
  
  local input = lib.inputDialog('Sæt Vinder', {
    {type = 'select', label = 'Vinderhold', options = winnerOptions, required = true}
  })
  
  if input then
    local winner = input[1]
    
    local success, message = lib.callback.await('Bet64-bet:setEventWinner', false, event.id, winner)
    
    lib.notify({
      title = Config.AppName,
      description = message,
      type = success and 'success' or 'error'
    })
    
    if success then
      Wait(500)
      LoadAndShowBettingEvents()
    end
  end
end

function DeleteEvent(event)
  local confirm = lib.alertDialog({
    header = 'Bekræft Sletning',
    content = 'Er du sikker på, at du vil slette dette væddemål? Alle aktive væddemål vil blive refunderet.',
    centered = true,
    cancel = true
  })
  
  if confirm == 'confirm' then
    local success, message = lib.callback.await('Bet64-bet:deleteEvent', false, event.id)
    
    lib.notify({
      title = Config.AppName,
      description = message,
      type = success and 'success' or 'error'
    })
    
    if success then
      Wait(500)
      LoadAndShowBettingEvents()
    end
  end
end

function LoadAndShowAllBets()
  local allBets = lib.callback.await('Bet64-bet:getAllBets', false)
  
  if not allBets or #allBets == 0 then
    lib.notify({
      title = Config.AppName,
      description = 'Ingen væddemål fundet',
      type = 'info'
    })
    return
  end
  
  local options = {}
  
  for _, bet in ipairs(allBets) do
    local statusColor = 'gray'
    if bet.status == 'active' then
      statusColor = 'yellow'
    elseif bet.status == 'won' then
      statusColor = 'green'
    elseif bet.status == 'lost' then
      statusColor = 'red'
    elseif bet.status == 'cashed_out' then
      statusColor = 'blue'
    elseif bet.status == 'refunded' then
      statusColor = 'purple'
    end
    
    local selectionsText = ''
    for i, selection in ipairs(bet.selections) do
      selectionsText = selectionsText .. selection.team .. ' (' .. selection.odds .. ')'
      if i < #bet.selections then
        selectionsText = selectionsText .. ', '
      end
    end
    
    table.insert(options, {
      title = 'Væddemål #' .. bet.id .. ' - ' .. bet.player_name,
      icon = 'money-bill',
      iconColor = statusColor,
      metadata = {
        {label = 'Status', value = bet.status_text},
        {label = 'Beløb', value = bet.amount .. ' DKK'},
        {label = 'Potentiel Gevinst', value = bet.potential_win .. ' DKK'},
        {label = 'Dato', value = bet.formatted_date},
        {label = 'Hold', value = selectionsText}
      },
      onSelect = function()
        ShowBetDetailsMenu(bet)
      end
    })
  end
  
  lib.registerContext({
    id = 'Bet64_bet_all_bets_list',
    title = 'Alle Væddemål',
    menu = 'Bet64_bet_admin_main',
    options = options
  })
  
  lib.showContext('Bet64_bet_all_bets_list')
end

function ShowBetDetailsMenu(bet)
  local options = {
    {
      title = 'Væddemål Detaljer',
      description = 'Status: ' .. bet.status_text,
      disabled = true
    },
    {
      title = 'Spiller: ' .. bet.player_name,
      description = 'ID: ' .. bet.player_identifier,
      disabled = true
    },
    {
      title = 'Beløb: ' .. bet.amount .. ' DKK',
      description = 'Potentiel Gevinst: ' .. bet.potential_win .. ' DKK',
      disabled = true
    },
    {
      title = 'Dato: ' .. bet.formatted_date,
      disabled = true
    }
  }
  
  for i, selection in ipairs(bet.selections) do
    table.insert(options, {
      title = 'Hold: ' .. selection.team,
      description = 'Odds: ' .. selection.odds .. ' | Kamp: ' .. selection.game,
      disabled = true
    })
  end
  

    table.insert(options, {
      title = 'Marker som Vundet',
      description = 'Ændrer status til vundet og tillader udbetaling',
      icon = 'trophy',
      onSelect = function()
        ChangeBetStatus(bet, 'won')
      end
    })

    table.insert(options, {
      title = 'Marker som Tabt',
      description = 'Ændrer status til tabt',
      icon = 'times-circle',
      onSelect = function()
        ChangeBetStatus(bet, 'lost')
      end
    })
    if bet.status == 'active' then 
    table.insert(options, {
      title = 'Annuller Væddemål',
      description = 'Refunder indsatsen til spilleren',
      icon = 'ban',
      onSelect = function()
        CancelBet(bet)
      end
    })
  end
  
  lib.registerContext({
    id = 'Bet64_bet_details',
    title = 'Væddemål #' .. bet.id,
    menu = 'Bet64_bet_all_bets_list',
    options = options
  })
  
  lib.showContext('Bet64_bet_details')
end

function ChangeBetStatus(bet, newStatus)
  local statusText = ""
  if newStatus == "won" then
    statusText = "vundet"
  elseif newStatus == "lost" then
    statusText = "tabt"
  end
  
  local confirm = lib.alertDialog({
    header = 'Bekræft Statusændring',
    content = 'Er du sikker på, at du vil ændre dette væddemål til ' .. statusText .. '?',
    centered = true,
    cancel = true
  })
  
  if confirm == 'confirm' then
    local success, message = lib.callback.await('Bet64-bet:changeBetStatus', false, bet.id, newStatus)
    
    lib.notify({
      title = Config.AppName,
      description = message,
      type = success and 'success' or 'error'
    })
    
    if success then
      Wait(500)
      LoadAndShowAllBets()
    end
  end
end

function CancelBet(bet)
  local confirm = lib.alertDialog({
    header = 'Bekræft Annullering',
    content = 'Er du sikker på, at du vil annullere dette væddemål? Indsatsen vil blive refunderet til spilleren.',
    centered = true,
    cancel = true
  })
  
  if confirm == 'confirm' then
    local success, message = lib.callback.await('Bet64-bet:cancelBet', false, bet.id)
    
    lib.notify({
      title = Config.AppName,
      description = message,
      type = success and 'success' or 'error'
    })
    
    if success then
      Wait(500)
      LoadAndShowAllBets()
    end
  end
end

function RegisterPlayerManagementMenus(targetId, playerInfo)
  local options = {
    {
      title = 'Spiller: ' .. playerInfo.name,
      description = 'Nuværende saldo: $' .. playerInfo.balance,
      disabled = true
    },
    {
      title = '',
    }
  }

  table.insert(options, {
    title = playerInfo.isFrozen and 'SOFUS Status: Medlem' or 'SOFUS Status: Ikke medlem!',
    description = playerInfo.isFrozen and 'Kontoen er frosset og kan ikke bruges' or 'Kontoen er aktiv og kan bruges',
    icon = playerInfo.isFrozen and 'snowflake' or 'check-circle',
    disabled = true
  })

  table.insert(options, {
    title = "",
  })

  table.insert(options, {
    title = playerInfo.isFrozen and 'Afmeld SOFUS' or 'Tilmeld SOFUS',
    description = playerInfo.isFrozen and 'Medlem af Elevates Frivilligt Udelukkede Spillere! \nTryk for at genaktivere denne konto!' or 'Frys denne konto (deaktiverer ind- og udbetalinger)',
    icon = playerInfo.isFrozen and 'sun' or 'snowflake',
    onSelect = function()
      local confirm = lib.alertDialog({
        header = playerInfo.isFrozen and 'Bekræft Aktivering' or 'Bekræft Frysning',
        content = playerInfo.isFrozen 
          and 'Er du sikker på, at du vil aktivere denne konto igen?' 
          or 'Er du sikker på, at du vil fryse denne konto? Spilleren vil ikke kunne indbetale eller udbetale penge.',
        centered = true,
        cancel = true
      })

      if confirm == 'confirm' then
        local success, message = lib.callback.await('Bet64-bet:setAccountFrozen', false, targetId, not playerInfo.isFrozen)

        lib.notify({
          title = Config.AppName,
          description = message,
          type = success and 'success' or 'error'
        })

        if success then
          Wait(500)
          local newSuccess, newPlayerInfo = lib.callback.await('Bet64-bet:getPlayerInfo', false, targetId)
          if newSuccess then
            RegisterPlayerManagementMenus(targetId, newPlayerInfo)
          end
        end
      end
    end
  })

  if not playerInfo.isFrozen then
    table.insert(options, {
      title = 'Indsæt Penge',
      description = 'Indsæt penge på spillerens betting konto',
      icon = 'plus',
      onSelect = function()
        local input = lib.inputDialog('Indsæt Penge', {
          {
            type = 'number', 
            label = 'Beløb', 
            description = 'Vælg beløb at indsætte', 
            icon = 'dollar-sign', 
            min = 100, 
            max = 2500000, 
            default = 500000
          },
          {
            type = 'select',
            label = 'Betalingsmetode',
            description = 'Vælg betalingsmetode for indsættelse',
            options = {
              {value = 'bank', label = 'Bank'},
              {value = 'money', label = 'Kontanter'}
            },
            required = true
          }
        })

        if input then
          local amount = tonumber(input[1])
          local betalingsmetode = input[2]

          if amount and amount > 0 then
            local success, message = lib.callback.await('Bet64-bet:adminDepositMoney', false, targetId, amount, betalingsmetode)

            lib.notify({
              title = Config.AppName,
              description = message,
              type = success and 'success' or 'error'
            })
          end
        end
      end
    })

    table.insert(options, {
      title = 'Hæv Penge',
      description = 'Hæv penge fra spillerens betting konto',
      icon = 'minus',
      onSelect = function()
        local input = lib.inputDialog('Hæv Penge', {
          {
            type = 'slider', 
            label = 'Beløb', 
            description = 'Vælg beløb at hæve', 
            icon = 'dollar-sign', 
            min = 1000, 
            max = playerInfo.balance, 
            step = 500, 
            default = math.min(1000, playerInfo.balance)
          }
        })

        if input then
          local amount = tonumber(input[1])
          if amount and amount > 0 and amount <= playerInfo.balance then
            local success, message = lib.callback.await('Bet64-bet:adminWithdrawMoney', false, targetId, amount)

            lib.notify({
              title = Config.AppName,
              description = message,
              type = success and 'success' or 'error'
            })
          else
            lib.notify({
              title = Config.AppName,
              description = Config.Notifications.InvalidAmountOrFunds,
              type = 'error'
            })
          end
        end
      end
    })
  end
  table.insert(options, {
    title = "",
  })
  table.insert(options, {
    title = 'Se Data',
    description = 'Se detaljeret statistik og væddemålshistorik',
    icon = 'chart-bar',
    onSelect = function()
      ShowPlayerDetailedData(targetId, playerInfo)
    end
  })

  lib.registerContext({
    id = 'Bet64_bet_manage_player',
    title = 'Håndter Betting Konto',
    options = options
  })

  lib.showContext('Bet64_bet_manage_player')
end


function ShowPlayerDetailedData(targetId, playerInfo)
  local playerIdentifier = lib.callback.await('Bet64-bet:getPlayerIdentifier', false, targetId)
  if not playerIdentifier then
    lib.notify({
      title = Config.AppName,
      description = "Kunne ikke hente spiller-ID",
      type = 'error'
    })
    return
  end
  
  local playerData = lib.callback.await('Bet64-bet:getPlayerDetailedData', false, playerIdentifier)
  if not playerData then
    lib.notify({
      title = Config.AppName,
      description = "Kunne ikke hente spillerdata",
      type = 'error'
    })
    return
  end
  
  -- Register the statistics menu
  lib.registerContext({
    id = 'Bet64_bet_player_stats',
    title = 'Statistik for ' .. playerInfo.name,
    menu = 'Bet64_bet_manage_player',
    options = {
      {
        title = 'Generel Statistik',
        description = 'Oversigt over spillerens betting aktivitet',
        disabled = true
      },
      {
        title = 'Total Antal Væddemål',
        description = playerData.stats.totalBets .. ' væddemål',
        disabled = true
      },
      {
        title = 'Vundne Væddemål',
        description = playerData.stats.wonBets .. ' væddemål (' .. math.floor((playerData.stats.wonBets / math.max(playerData.stats.totalBets, 1)) * 100) .. '%)',
        disabled = true
      },
      {
        title = 'Tabte Væddemål',
        description = playerData.stats.lostBets .. ' væddemål (' .. math.floor((playerData.stats.lostBets / math.max(playerData.stats.totalBets, 1)) * 100) .. '%)',
        disabled = true
      },
      {
        title = 'Samlede Gevinster',
        description = playerData.stats.totalWinnings .. ' DKK',
        disabled = true
      },
      {
        title = 'Samlede Tab',
        description = playerData.stats.totalLosses .. ' DKK',
        disabled = true
      },
      {
        title = 'Samlet Profit/Tab',
        description = (playerData.stats.totalWinnings - playerData.stats.totalLosses) .. ' DKK',
        disabled = true
      },
      {
        title = 'Gennemsnitlig Indsats',
        description = playerData.stats.avgBetAmount .. ' DKK',
        disabled = true
      },
      {
        title = 'Største Gevinst',
        description = playerData.stats.biggestWin .. ' DKK',
        disabled = true
      },
      {
        title = '',
        disabled = true
      },
      {
        title = 'Se Væddemålshistorik',
        description = 'Vis alle væddemål for denne spiller',
        icon = 'history',
        onSelect = function()
          ShowPlayerBetHistory(targetId, playerInfo, playerData.bets)
        end
      }
    }
  })
  
  lib.showContext('Bet64_bet_player_stats')
end

function ShowPlayerBetHistory(targetId, playerInfo, bets)
  if not bets or #bets == 0 then
    lib.notify({
      title = Config.AppName,
      description = "Ingen væddemål fundet for denne spiller",
      type = 'info'
    })
    return
  end
  
  local options = {
    {
      title = 'Væddemålshistorik',
      description = 'Alle væddemål for ' .. playerInfo.name,
      disabled = true
    },
    {
      title = '',
      disabled = true
    }
  }
  
  for _, bet in ipairs(bets) do
    local statusColor = 'gray'
    if bet.status == 'active' then
      statusColor = 'yellow'
    elseif bet.status == 'won' then
      statusColor = 'green'
    elseif bet.status == 'lost' then
      statusColor = 'red'
    elseif bet.status == 'cashed_out' then
      statusColor = 'blue'
    elseif bet.status == 'refunded' then
      statusColor = 'purple'
    end
    
    local selectionsText = ''
    for i, selection in ipairs(bet.selections) do
      selectionsText = selectionsText .. selection.team .. ' (' .. selection.odds .. ')'
      if i < #bet.selections then
        selectionsText = selectionsText .. ', '
      end
    end
    
    table.insert(options, {
      title = 'Væddemål #' .. bet.id .. ' - ' .. bet.status_text,
      icon = 'money-bill',
      iconColor = statusColor,
      metadata = {
        {label = 'Beløb', value = bet.amount .. ' DKK'},
        {label = 'Potentiel Gevinst', value = bet.potential_win .. ' DKK'},
        {label = 'Dato', value = bet.formatted_date},
        {label = 'Hold', value = selectionsText}
      },
      onSelect = function()
        ShowBetDetailsForPlayer(bet, playerInfo)
      end
    })
  end
  
  lib.registerContext({
    id = 'Bet64_bet_player_history',
    title = 'Væddemålshistorik',
    menu = 'Bet64_bet_player_stats',
    options = options
  })
  
  lib.showContext('Bet64_bet_player_history')
end

function ShowBetDetailsForPlayer(bet, playerInfo)
  local options = {
    {
      title = 'Væddemål Detaljer',
      description = 'Status: ' .. bet.status_text,
      disabled = true
    },
    {
      title = 'Beløb: ' .. bet.amount .. ' DKK',
      description = 'Potentiel Gevinst: ' .. bet.potential_win .. ' DKK',
      disabled = true
    },
    {
      title = 'Dato: ' .. bet.formatted_date,
      disabled = true
    }
  }
  
  for i, selection in ipairs(bet.selections) do
    table.insert(options, {
      title = 'Hold: ' .. selection.team,
      description = 'Odds: ' .. selection.odds .. ' | Kamp: ' .. selection.game,
      disabled = true
    })
  end
  
  if bet.status == 'active' then
    table.insert(options, {
      title = 'Annuller Væddemål',
      description = 'Refunder indsatsen til spilleren',
      icon = 'ban',
      onSelect = function()
        CancelPlayerBet(bet, playerInfo)
      end
    })
  end
  
  lib.registerContext({
    id = 'Bet64_bet_player_bet_details',
    title = 'Væddemål #' .. bet.id,
    menu = 'Bet64_bet_player_history',
    options = options
  })
  
  lib.showContext('Bet64_bet_player_bet_details')
end

function CancelPlayerBet(bet, playerInfo)
  local confirm = lib.alertDialog({
    header = 'Bekræft Annullering',
    content = 'Er du sikker på, at du vil annullere dette væddemål? Indsatsen vil blive refunderet til spilleren.',
    centered = true,
    cancel = true
  })
  
  if confirm == 'confirm' then
    local success, message = lib.callback.await('Bet64-bet:cancelBet', false, bet.id)
    
    lib.notify({
      title = Config.AppName,
      description = message,
      type = success and 'success' or 'error'
    })
    
    if success then
      Wait(500)
      -- Refresh the player data
      local targetId = lib.callback.await('Bet64-bet:getPlayerIdFromIdentifier', false, bet.player_identifier)
      if targetId then
        local success, playerInfo = lib.callback.await('Bet64-bet:getPlayerInfo', false, targetId)
        if success then
          ShowPlayerDetailedData(targetId, playerInfo)
        end
      end
    end
  end
end

lib.callback.register('Bet64-bet:approveAdminDeposit', function(data)
  local commissionText = ""
  if data.commissionAmount and data.commissionAmount > 0 then
    commissionText = "\n\nBemærk: " .. data.commissionPercentage .. "% gebyr (" .. data.commissionAmount .. " DKK) vil blive fratrukket."
  end
  
  local depositText = data.depositAmount and data.depositAmount ~= data.amount 
    and "\nDu vil modtage " .. data.depositAmount .. " DKK på din betting konto." 
    or ""
  
  local confirm = lib.alertDialog({
    header = 'Bet64',
    content = 'En administrator vil indsætte ' .. data.amount .. ' DKK fra din bank til din betting konto.' .. 
              depositText .. commissionText,
    centered = true,
    cancel = true
  })

  return confirm == 'confirm'
end)

CreateThread(function()
  while not lib do Wait(100) end

  RegisterBettingAdminMenus()

  exports.ox_target:addGlobalPlayer({
    {
      name = 'Bet64_bet_manage',
      icon = 'fas fa-money-bill',
      label = 'Håndter Betting Konto',
      groups = Config.AdminJobs,
      distance = 2.0,
      onSelect = function(data)
        local targetId = GetPlayerServerId(NetworkGetEntityOwner(data.entity))

        local success, playerInfo = lib.callback.await('Bet64-bet:getPlayerInfo', false, targetId)

        if not success then
          lib.notify({
            title = Config.AppName,
            description = Config.Notifications.PlayerInfoError,
            type = 'error'
          })
          return
        end

        RegisterPlayerManagementMenus(targetId, playerInfo)
      end
    }
  })

  exports.ox_target:addBoxZone({
    coords = Config.BetAdminZone.coords,
    size = Config.BetAdminZone.size,
    rotation = Config.BetAdminZone.rotation,
    debug = false,
    options = {
      {
        name = 'Bet64_bet_admin',
        icon = Config.BetAdminZone.icon,
        label = Config.BetAdminZone.label,
        groups = Config.BetAdminZone.groups,
        distance = Config.BetAdminZone.distance,
        onSelect = function()
          local playerJob = lib.callback.await('Bet64-bet:getPlayerJob', false)

          if not Config.AdminJobs == playerJob then
            lib.notify({
              title = Config.AppName,
              description = Config.Notifications.NoAccess,
              type = 'error'
            })
            return
          end

          lib.showContext('Bet64_bet_admin_main')
        end
      }
    }
  })
end)


-- RegisterCommand("admin:betjob", function()
--   local playerJob = lib.callback.await('Bet64-bet:getPlayerJob', false)

--   if not Config.AdminJobs == playerJob then
--     lib.notify({
--       title = Config.AppName,
--       description = Config.Notifications.NoAccess,
--       type = 'error'
--     })
--     return
--   end

--   lib.showContext('Bet64_bet_admin_main')
-- end, false)




-- Function to show economic overview
function ShowEconomicOverview()
  local economicData = lib.callback.await('Bet64-bet:getEconomicOverview', false)
  
  if not economicData then
    lib.notify({
      title = 'Bet64',
      description = 'Kunne ikke hente økonomisk data',
      type = 'error'
    })
    return
  end
  
  local options = {
    {
      title = 'Økonomisk Oversigt',
      description = 'Samlet økonomisk status for betting systemet',
      disabled = true
    },
    {
      title = '',
      disabled = true
    },
    {
      title = 'Total Omsætning',
      description = economicData.totalRevenue .. ' DKK',
      icon = 'money-bill-wave',
      iconColor = 'green',
      disabled = true
    },
    {
      title = 'Total Udbetalt',
      description = economicData.totalPayout .. ' DKK',
      icon = 'hand-holding-dollar',
      iconColor = 'red',
      disabled = true
    },
    {
      title = 'Netto Profit',
      description = economicData.netProfit .. ' DKK',
      icon = 'balance-scale',
      iconColor = economicData.netProfit >= 0 and 'green' or 'red',
      disabled = true
    },
    {
      title = '',
      disabled = true
    },
    {
      title = 'Aktive Væddemål Værdi',
      description = economicData.activeBetsValue .. ' DKK',
      icon = 'hourglass-half',
      disabled = true
    },
    {
      title = 'Potentiel Udbetaling (Aktive)',
      description = economicData.potentialPayout .. ' DKK',
      icon = 'exclamation-triangle',
      iconColor = 'yellow',
      disabled = true
    },
    {
      title = 'Risiko Eksponering',
      description = economicData.riskExposure .. ' DKK',
      icon = 'radiation',
      iconColor = 'orange',
      disabled = true
    },
    {
      title = '',
      disabled = true
    },
    {
      title = 'Daglig Statistik',
      description = 'Se statistik for i dag',
      icon = 'calendar-day',
      onSelect = function()
        ShowDailyStatistics()
      end
    },
    {
      title = 'Månedlig Statistik',
      description = 'Se statistik for denne måned',
      icon = 'calendar-alt',
      onSelect = function()
        ShowMonthlyStatistics()
      end
    }
  }
  
  lib.registerContext({
    id = 'Bet64_bet_economic_overview',
    title = 'Økonomisk Oversigt',
    menu = 'Bet64_bet_admin_main',
    options = options
  })
  
  lib.showContext('Bet64_bet_economic_overview')
end

-- Function to show daily statistics
function ShowDailyStatistics()
  local dailyStats = lib.callback.await('Bet64-bet:getDailyStatistics', false)
  
  if not dailyStats then
    lib.notify({
      title = 'Bet64',
      description = 'Kunne ikke hente daglig statistik',
      type = 'error'
    })
    return
  end
  
  local options = {
    {
      title = 'Daglig Statistik',
      description = 'Statistik for ' .. dailyStats.date,
      disabled = true
    },
    {
      title = '',
      disabled = true
    },
    {
      title = 'Antal Væddemål Placeret',
      description = dailyStats.betsPlaced .. ' væddemål',
      icon = 'ticket-alt',
      disabled = true
    },
    {
      title = 'Total Indsat',
      description = dailyStats.totalDeposited .. ' DKK',
      icon = 'arrow-down',
      iconColor = 'green',
      disabled = true
    },
    {
      title = 'Total Udbetalt',
      description = dailyStats.totalWithdrawn .. ' DKK',
      icon = 'arrow-up',
      iconColor = 'red',
      disabled = true
    },
    {
      title = 'Netto Indkomst',
      description = dailyStats.netIncome .. ' DKK',
      icon = 'balance-scale',
      iconColor = dailyStats.netIncome >= 0 and 'green' or 'red',
      disabled = true
    },
    {
      title = '',
      disabled = true
    },
    {
      title = 'Vundne Væddemål',
      description = dailyStats.wonBets .. ' væddemål (' .. dailyStats.wonAmount .. ' DKK)',
      icon = 'check-circle',
      iconColor = 'green',
      disabled = true
    },
    {
      title = 'Tabte Væddemål',
      description = dailyStats.lostBets .. ' væddemål (' .. dailyStats.lostAmount .. ' DKK)',
      icon = 'times-circle',
      iconColor = 'red',
      disabled = true
    },
    {
      title = 'Refunderede Væddemål',
      description = dailyStats.refundedBets .. ' væddemål (' .. dailyStats.refundedAmount .. ' DKK)',
      icon = 'undo',
      disabled = true
    }
  }
  
  lib.registerContext({
    id = 'Bet64_bet_daily_statistics',
    title = 'Daglig Statistik',
    menu = 'Bet64_bet_economic_overview',
    options = options
  })
  
  lib.showContext('Bet64_bet_daily_statistics')
end

-- Function to show monthly statistics
function ShowMonthlyStatistics()
  local monthlyStats = lib.callback.await('Bet64-bet:getMonthlyStatistics', false)
  
  if not monthlyStats then
    lib.notify({
      title = 'Bet64',
      description = 'Kunne ikke hente månedlig statistik',
      type = 'error'
    })
    return
  end
  
  local options = {
    {
      title = 'Månedlig Statistik',
      description = 'Statistik for ' .. monthlyStats.month,
      disabled = true
    },
    {
      title = '',
      disabled = true
    },
    {
      title = 'Antal Væddemål Placeret',
      description = monthlyStats.betsPlaced .. ' væddemål',
      icon = 'ticket-alt',
      disabled = true
    },
    {
      title = 'Total Indsat',
      description = monthlyStats.totalDeposited .. ' DKK',
      icon = 'arrow-down',
      iconColor = 'green',
      disabled = true
    },
    {
      title = 'Total Udbetalt',
      description = monthlyStats.totalWithdrawn .. ' DKK',
      icon = 'arrow-up',
      iconColor = 'red',
      disabled = true
    },
    {
      title = 'Netto Indkomst',
      description = monthlyStats.netIncome .. ' DKK',
      icon = 'balance-scale',
      iconColor = monthlyStats.netIncome >= 0 and 'green' or 'red',
      disabled = true
    },
    {
      title = '',
      disabled = true
    },
    {
      title = 'Vundne Væddemål',
      description = monthlyStats.wonBets .. ' væddemål (' .. monthlyStats.wonAmount .. ' DKK)',
      icon = 'check-circle',
      iconColor = 'green',
      disabled = true
    },
    {
      title = 'Tabte Væddemål',
      description = monthlyStats.lostBets .. ' væddemål (' .. monthlyStats.lostAmount .. ' DKK)',
      icon = 'times-circle',
      iconColor = 'red',
      disabled = true
    },
    {
      title = 'Refunderede Væddemål',
      description = monthlyStats.refundedBets .. ' væddemål (' .. monthlyStats.refundedAmount .. ' DKK)',
      icon = 'undo',
      disabled = true
    }
  }
  
  if monthlyStats.dailyBreakdown and #monthlyStats.dailyBreakdown > 0 then
    table.insert(options, {
      title = '',
      disabled = true
    })
    table.insert(options, {
      title = 'Se Daglig Fordeling',
      description = 'Se statistik fordelt på dage',
      icon = 'calendar-week',
      onSelect = function()
        ShowMonthlyBreakdown(monthlyStats)
      end
    })
  end
  
  lib.registerContext({
    id = 'Bet64_bet_monthly_statistics',
    title = 'Månedlig Statistik',
    menu = 'Bet64_bet_economic_overview',
    options = options
  })
  
  lib.showContext('Bet64_bet_monthly_statistics')
end

-- Function to show monthly breakdown by day
function ShowMonthlyBreakdown(monthlyStats)
  if not monthlyStats or not monthlyStats.dailyBreakdown or #monthlyStats.dailyBreakdown == 0 then
    lib.notify({
      title = 'Bet64',
      description = 'Ingen daglig fordeling tilgængelig',
      type = 'error'
    })
    return
  end
  
  local options = {
    {
      title = 'Daglig Fordeling',
      description = 'Statistik fordelt på dage for ' .. monthlyStats.month,
      disabled = true
    },
    {
      title = '',
      disabled = true
    }
  }
  
  for _, day in ipairs(monthlyStats.dailyBreakdown) do
    table.insert(options, {
      title = day.date,
      description = 'Netto: ' .. day.netIncome .. ' DKK',
      icon = 'calendar-day',
      iconColor = day.netIncome >= 0 and 'green' or 'red',
      metadata = {
        {label = 'Væddemål', value = day.betsPlaced},
        {label = 'Indsat', value = day.totalDeposited .. ' DKK'},
        {label = 'Udbetalt', value = day.totalWithdrawn .. ' DKK'},
        {label = 'Vundne', value = day.wonBets .. ' (' .. day.wonAmount .. ' DKK)'},
        {label = 'Tabte', value = day.lostBets .. ' (' .. day.lostAmount .. ' DKK)'}
      }
    })
  end
  
  lib.registerContext({
    id = 'Bet64_bet_monthly_breakdown',
    title = 'Daglig Fordeling',
    menu = 'Bet64_bet_monthly_statistics',
    options = options
  })
  
  lib.showContext('Bet64_bet_monthly_breakdown')
end

-- Function to show profit/loss analysis
function ShowProfitLossAnalysis()
  local profitLossData = lib.callback.await('Bet64-bet:getProfitLossAnalysis', false)
  
  if not profitLossData then
    lib.notify({
      title = 'Bet64',
      description = 'Kunne ikke hente profit/tab analyse',
      type = 'error'
    })
    return
  end
  
  local options = {
    {
      title = 'Profit/Tab Analyse',
      description = 'Detaljeret analyse af profit og tab',
      disabled = true
    },
    {
      title = '',
      disabled = true
    },
    {
      title = 'Samlet Profit/Tab',
      description = profitLossData.totalProfit .. ' DKK',
      icon = 'balance-scale',
      iconColor = profitLossData.totalProfit >= 0 and 'green' or 'red',
      disabled = true
    },
    {
      title = 'Profit Margin',
      description = profitLossData.profitMargin .. '%',
      icon = 'percentage',
      iconColor = profitLossData.profitMargin >= 0 and 'green' or 'red',
      disabled = true
    }
  }
  
  if profitLossData.bySport and #profitLossData.bySport > 0 then
    table.insert(options, {
      title = '',
      disabled = true
    })
    table.insert(options, {
      title = 'Profit/Tab pr. Sport',
      description = 'Se fordeling af profit/tab på sportsgrene',
      icon = 'futbol',
      onSelect = function()
        ShowProfitBySport(profitLossData.bySport)
      end
    })
  end
  
  if profitLossData.byDay and #profitLossData.byDay > 0 then
    table.insert(options, {
      title = 'Profit/Tab pr. Dag',
      description = 'Se fordeling af profit/tab på ugedage',
      icon = 'calendar-day',
      onSelect = function()
        ShowProfitByDay(profitLossData.byDay)
      end
    })
  end
  
  if profitLossData.byHour and #profitLossData.byHour > 0 then
    table.insert(options, {
      title = 'Profit/Tab pr. Time',
      description = 'Se fordeling af profit/tab på timer',
      icon = 'clock',
      onSelect = function()
        ShowProfitByHour(profitLossData.byHour)
      end
    })
  end
  
  if profitLossData.byOdds and #profitLossData.byOdds > 0 then
    table.insert(options, {
      title = 'Profit/Tab pr. Odds Interval',
      description = 'Se fordeling af profit/tab på odds intervaller',
      icon = 'chart-line',
      onSelect = function()
        ShowProfitByOdds(profitLossData.byOdds)
      end
    })
  end
  
  lib.registerContext({
    id = 'Bet64_bet_profit_loss_analysis',
    title = 'Profit/Tab Analyse',
    menu = 'Bet64_bet_admin_main',
    options = options
  })
  
  lib.showContext('Bet64_bet_profit_loss_analysis')
end

-- Function to show profit by sport
function ShowProfitBySport(sportData)
  if not sportData or #sportData == 0 then
    lib.notify({
      title = 'Bet64',
      description = 'Ingen sport data tilgængelig',
      type = 'error'
    })
    return
  end
  
  local options = {
    {
      title = 'Profit/Tab pr. Sport',
      description = 'Fordeling af profit/tab på sportsgrene',
      disabled = true
    },
    {
      title = '',
      disabled = true
    }
  }
  
  for _, sport in ipairs(sportData) do
    table.insert(options, {
      title = sport.name,
      description = sport.profit .. ' DKK',
      icon = 'trophy',
      iconColor = sport.profit >= 0 and 'green' or 'red',
      metadata = {
        {label = 'Antal Væddemål', value = sport.betCount},
        {label = 'Total Indsats', value = sport.totalStake .. ' DKK'},
        {label = 'Vundne Væddemål', value = sport.wonBets},
        {label = 'Tabte Væddemål', value = sport.lostBets},
        {label = 'Profit Margin', value = sport.profitMargin .. '%'}
      }
    })
  end
  
  lib.registerContext({
    id = 'Bet64_bet_profit_by_sport',
    title = 'Profit pr. Sport',
    menu = 'Bet64_bet_profit_loss_analysis',
    options = options
  })
  
  lib.showContext('Bet64_bet_profit_by_sport')
end

-- Function to show profit by day of week
function ShowProfitByDay(dayData)
  if not dayData or #dayData == 0 then
    lib.notify({
      title = 'Bet64',
      description = 'Ingen ugedag data tilgængelig',
      type = 'error'
    })
    return
  end
  
  local options = {
    {
      title = 'Profit/Tab pr. Ugedag',
      description = 'Fordeling af profit/tab på ugedage',
      disabled = true
    },
    {
      title = '',
      disabled = true
    }
  }
  
  for _, day in ipairs(dayData) do
    table.insert(options, {
      title = day.name,
      description = day.profit .. ' DKK',
      icon = 'calendar-day',
      iconColor = day.profit >= 0 and 'green' or 'red',
      metadata = {
        {label = 'Antal Væddemål', value = day.betCount},
        {label = 'Total Indsats', value = day.totalStake .. ' DKK'},
        {label = 'Vundne Væddemål', value = day.wonBets},
        {label = 'Tabte Væddemål', value = day.lostBets},
        {label = 'Profit Margin', value = day.profitMargin .. '%'}
      }
    })
  end
  
  lib.registerContext({
    id = 'Bet64_bet_profit_by_day',
    title = 'Profit pr. Ugedag',
    menu = 'Bet64_bet_profit_loss_analysis',
    options = options
  })
  
  lib.showContext('Bet64_bet_profit_by_day')
end

-- Function to show profit by hour
function ShowProfitByHour(hourData)
  if not hourData or #hourData == 0 then
    lib.notify({
      title = 'Bet64',
      description = 'Ingen time data tilgængelig',
      type = 'error'
    })
    return
  end
  
  local options = {
    {
      title = 'Profit/Tab pr. Time',
      description = 'Fordeling af profit/tab på timer',
      disabled = true
    },
    {
      title = '',
      disabled = true
    }
  }
  
  for _, hour in ipairs(hourData) do
    table.insert(options, {
      title = hour.hour .. ':00 - ' .. hour.hour .. ':59',
      description = hour.profit .. ' DKK',
      icon = 'clock',
      iconColor = hour.profit >= 0 and 'green' or 'red',
      metadata = {
        {label = 'Antal Væddemål', value = hour.betCount},
        {label = 'Total Indsats', value = hour.totalStake .. ' DKK'},
        {label = 'Vundne Væddemål', value = hour.wonBets},
        {label = 'Tabte Væddemål', value = hour.lostBets},
        {label = 'Profit Margin', value = hour.profitMargin .. '%'}
      }
    })
  end
  
  lib.registerContext({
    id = 'Bet64_bet_profit_by_hour',
    title = 'Profit pr. Time',
    menu = 'Bet64_bet_profit_loss_analysis',
    options = options
  })
  
  lib.showContext('Bet64_bet_profit_by_hour')
end

-- Function to show profit by odds range
function ShowProfitByOdds(oddsData)
  if not oddsData or #oddsData == 0 then
    lib.notify({
      title = 'Bet64',
      description = 'Ingen odds data tilgængelig',
      type = 'error'
    })
    return
  end
  
  local options = {
    {
      title = 'Profit/Tab pr. Odds Interval',
      description = 'Fordeling af profit/tab på odds intervaller',
      disabled = true
    },
    {
      title = '',
      disabled = true
    }
  }
  
  for _, odds in ipairs(oddsData) do
    table.insert(options, {
      title = odds.range,
      description = odds.profit .. ' DKK',
      icon = 'percentage',
      iconColor = odds.profit >= 0 and 'green' or 'red',
      metadata = {
        {label = 'Antal Væddemål', value = odds.betCount},
        {label = 'Total Indsats', value = odds.totalStake .. ' DKK'},
        {label = 'Vundne Væddemål', value = odds.wonBets},
        {label = 'Tabte Væddemål', value = odds.lostBets},
        {label = 'Profit Margin', value = odds.profitMargin .. '%'}
      }
    })
  end
  
  lib.registerContext({
    id = 'Bet64_bet_profit_by_odds',
    title = 'Profit pr. Odds Interval',
    menu = 'Bet64_bet_profit_loss_analysis',
    options = options
  })
  
  lib.showContext('Bet64_bet_profit_by_odds')
end

-- Function to show top players
function ShowTopPlayers()
  local topPlayersData = lib.callback.await('Bet64-bet:getTopPlayers', false)
  
  if not topPlayersData then
    lib.notify({
      title = 'Bet64',
      description = 'Kunne ikke hente top spillere data',
      type = 'error'
    })
    return
  end
  
  local options = {
    {
      title = 'Top Spillere',
      description = 'Oversigt over de mest aktive spillere',
      disabled = true
    },
    {
      title = '',
      disabled = true
    }
  }
  
  if topPlayersData.mostActive and #topPlayersData.mostActive > 0 then
    table.insert(options, {
      title = 'Mest Aktive Spillere',
      description = 'Spillere med flest væddemål',
      icon = 'users',
      onSelect = function()
        ShowMostActivePlayers(topPlayersData.mostActive)
      end
    })
  end
  
  if topPlayersData.biggestWinners and #topPlayersData.biggestWinners > 0 then
    table.insert(options, {
      title = 'Største Vindere',
      description = 'Spillere med størst samlet gevinst',
      icon = 'trophy',
      iconColor = 'green',
      onSelect = function()
        ShowBiggestWinners(topPlayersData.biggestWinners)
      end
    })
  end
  
  if topPlayersData.biggestLosers and #topPlayersData.biggestLosers > 0 then
    table.insert(options, {
      title = 'Største Tabere',
      description = 'Spillere med størst samlet tab',
      icon = 'thumbs-down',
      iconColor = 'red',
      onSelect = function()
        ShowBiggestLosers(topPlayersData.biggestLosers)
      end
    })
  end
  
  if topPlayersData.highestWinRate and #topPlayersData.highestWinRate > 0 then
    table.insert(options, {
      title = 'Højeste Vinderprocent',
      description = 'Spillere med højest vinderprocent',
      icon = 'percentage',
      iconColor = 'green',
      onSelect = function()
        ShowHighestWinRate(topPlayersData.highestWinRate)
      end
    })
  end
  
  if topPlayersData.biggestSingleWins and #topPlayersData.biggestSingleWins > 0 then
    table.insert(options, {
      title = 'Største Enkelt Gevinster',
      description = 'Spillere med de største enkelt gevinster',
      icon = 'money-bill-wave',
      iconColor = 'green',
      onSelect = function()
        ShowBiggestSingleWins(topPlayersData.biggestSingleWins)
      end
    })
  end
  
  lib.registerContext({
    id = 'Bet64_bet_top_players',
    title = 'Top Spillere',
    menu = 'Bet64_bet_admin_main',
    options = options
  })
  
  lib.showContext('Bet64_bet_top_players')
end

-- Function to show most active players
function ShowMostActivePlayers(players)
  if not players or #players == 0 then
    lib.notify({
      title = 'Bet64',
      description = 'Ingen spiller data tilgængelig',
      type = 'error'
    })
    return
  end
  
  local options = {
    {
      title = 'Mest Aktive Spillere',
      description = 'Spillere med flest væddemål',
      disabled = true
    },
    {
      title = '',
      disabled = true
    }
  }
  
  for i, player in ipairs(players) do
    table.insert(options, {
      title = i .. '. ' .. player.name,
      description = player.betCount .. ' væddemål',
      icon = 'user',
      metadata = {
        {label = 'Total Indsats', value = player.totalStake .. ' DKK'},
        {label = 'Vundne Væddemål', value = player.wonBets},
        {label = 'Tabte Væddemål', value = player.lostBets},
        {label = 'Vinderprocent', value = player.winRate .. '%'},
        {label = 'Netto Profit', value = player.netProfit .. ' DKK'}
      },
      onSelect = function()
        local targetId = lib.callback.await('Bet64-bet:getPlayerIdFromIdentifier', false, player.identifier)
        if targetId then
          local success, playerInfo = lib.callback.await('Bet64-bet:getPlayerInfo', false, targetId)
          if success then
            RegisterPlayerManagementMenus(targetId, playerInfo)
          else
            lib.notify({
              title = 'Bet64',
              description = 'Kunne ikke hente spiller information',
              type = 'error'
            })
          end
        else
          lib.notify({
            title = 'Bet64',
            description = 'Spilleren er ikke online',
            type = 'error'
          })
        end
      end
    })
  end
  
  lib.registerContext({
    id = 'Bet64_bet_most_active_players',
    title = 'Mest Aktive Spillere',
    menu = 'Bet64_bet_top_players',
    options = options
  })
  
  lib.showContext('Bet64_bet_most_active_players')
end

-- Function to show biggest winners
function ShowBiggestWinners(players)
  if not players or #players == 0 then
    lib.notify({
      title = 'Bet64',
      description = 'Ingen spiller data tilgængelig',
      type = 'error'
    })
    return
  end
  
  local options = {
    {
      title = 'Største Vindere',
      description = 'Spillere med størst samlet gevinst',
      disabled = true
    },
    {
      title = '',
      disabled = true
    }
  }
  
  for i, player in ipairs(players) do
    table.insert(options, {
      title = i .. '. ' .. player.name,
      description = player.totalWinnings .. ' DKK',
      icon = 'user',
      iconColor = 'green',
      metadata = {
        {label = 'Antal Væddemål', value = player.betCount},
        {label = 'Vundne Væddemål', value = player.wonBets},
        {label = 'Tabte Væddemål', value = player.lostBets},
        {label = 'Vinderprocent', value = player.winRate .. '%'},
        {label = 'Netto Profit', value = player.netProfit .. ' DKK'}
      },
      onSelect = function()
        local targetId = lib.callback.await('Bet64-bet:getPlayerIdFromIdentifier', false, player.identifier)
        if targetId then
          local success, playerInfo = lib.callback.await('Bet64-bet:getPlayerInfo', false, targetId)
          if success then
            RegisterPlayerManagementMenus(targetId, playerInfo)
          else
            lib.notify({
              title = 'Bet64',
              description = 'Kunne ikke hente spiller information',
              type = 'error'
            })
          end
        else
          lib.notify({
            title = 'Bet64',
            description = 'Spilleren er ikke online',
            type = 'error'
          })
        end
      end
    })
  end
  
  lib.registerContext({
    id = 'Bet64_bet_biggest_winners',
    title = 'Største Vindere',
    menu = 'Bet64_bet_top_players',
    options = options
  })
  
  lib.showContext('Bet64_bet_biggest_winners')
end

-- Function to show biggest losers
function ShowBiggestLosers(players)
  if not players or #players == 0 then
    lib.notify({
      title = 'Bet64',
      description = 'Ingen spiller data tilgængelig',
      type = 'error'
    })
    return
  end
  
  local options = {
    {
      title = 'Største Tabere',
      description = 'Spillere med størst samlet tab',
      disabled = true
    },
    {
      title = '',
      disabled = true
    }
  }
  
  for i, player in ipairs(players) do
    table.insert(options, {
      title = i .. '. ' .. player.name,
      description = player.totalLosses .. ' DKK',
      icon = 'user',
      iconColor = 'red',
      metadata = {
        {label = 'Antal Væddemål', value = player.betCount},
        {label = 'Vundne Væddemål', value = player.wonBets},
        {label = 'Tabte Væddemål', value = player.lostBets},
        {label = 'Vinderprocent', value = player.winRate .. '%'},
        {label = 'Netto Tab', value = player.netLoss .. ' DKK'}
      },
      onSelect = function()
        local targetId = lib.callback.await('Bet64-bet:getPlayerIdFromIdentifier', false, player.identifier)
        if targetId then
          local success, playerInfo = lib.callback.await('Bet64-bet:getPlayerInfo', false, targetId)
          if success then
            RegisterPlayerManagementMenus(targetId, playerInfo)
          else
            lib.notify({
              title = 'Bet64',
              description = 'Kunne ikke hente spiller information',
              type = 'error'
            })
          end
        else
          lib.notify({
            title = 'Bet64',
            description = 'Spilleren er ikke online',
            type = 'error'
          })
        end
      end
    })
  end
  
  lib.registerContext({
    id = 'Bet64_bet_biggest_losers',
    title = 'Største Tabere',
    menu = 'Bet64_bet_top_players',
    options = options
  })
  
  lib.showContext('Bet64_bet_biggest_losers')
end

-- Function to show highest win rate
function ShowHighestWinRate(players)
  if not players or #players == 0 then
    lib.notify({
      title = 'Bet64',
      description = 'Ingen spiller data tilgængelig',
      type = 'error'
    })
    return
  end
  
  local options = {
    {
      title = 'Højeste Vinderprocent',
      description = 'Spillere med højest vinderprocent',
      disabled = true
    },
    {
      title = '',
      disabled = true
    }
  }
  
  for i, player in ipairs(players) do
    table.insert(options, {
      title = i .. '. ' .. player.name,
      description = player.winRate .. '%',
      icon = 'user',
      iconColor = 'green',
      metadata = {
        {label = 'Antal Væddemål', value = player.betCount},
        {label = 'Vundne Væddemål', value = player.wonBets},
        {label = 'Tabte Væddemål', value = player.lostBets},
        {label = 'Total Gevinst', value = player.totalWinnings .. ' DKK'},
        {label = 'Netto Profit', value = player.netProfit .. ' DKK'}
      },
      onSelect = function()
        local targetId = lib.callback.await('Bet64-bet:getPlayerIdFromIdentifier', false, player.identifier)
        if targetId then
          local success, playerInfo = lib.callback.await('Bet64-bet:getPlayerInfo', false, targetId)
          if success then
            RegisterPlayerManagementMenus(targetId, playerInfo)
          else
            lib.notify({
              title = 'Bet64',
              description = 'Kunne ikke hente spiller information',
              type = 'error'
            })
          end
        else
          lib.notify({
            title = 'Bet64',
            description = 'Spilleren er ikke online',
            type = 'error'
          })
        end
      end
    })
  end
  
  lib.registerContext({
    id = 'Bet64_bet_highest_win_rate',
    title = 'Højeste Vinderprocent',
    menu = 'Bet64_bet_top_players',
    options = options
  })
  
  lib.showContext('Bet64_bet_highest_win_rate')
end

-- Function to show biggest single wins
function ShowBiggestSingleWins(wins)
  if not wins or #wins == 0 then
    lib.notify({
      title = 'Bet64',
      description = 'Ingen væddemål data tilgængelig',
      type = 'error'
    })
    return
  end
  
  local options = {
    {
      title = 'Største Enkelt Gevinster',
      description = 'De største enkelt gevinster',
      disabled = true
    },
    {
      title = '',
      disabled = true
    }
  }
  
  for i, win in ipairs(wins) do
    table.insert(options, {
      title = i .. '. ' .. win.playerName,
      description = win.winAmount .. ' DKK',
      icon = 'money-bill-wave',
      iconColor = 'green',
      metadata = {
        {label = 'Væddemål ID', value = win.betId},
        {label = 'Dato', value = win.date},
        {label = 'Indsats', value = win.stake .. ' DKK'},
        {label = 'Odds', value = win.odds},
        {label = 'Hold', value = win.team},
        {label = 'Kamp', value = win.match}
      },
      onSelect = function()
        local targetId = lib.callback.await('Bet64-bet:getPlayerIdFromIdentifier', false, win.playerIdentifier)
        if targetId then
          local success, playerInfo = lib.callback.await('Bet64-bet:getPlayerInfo', false, targetId)
          if success then
            RegisterPlayerManagementMenus(targetId, playerInfo)
          else
            lib.notify({
              title = 'Bet64',
              description = 'Kunne ikke hente spiller information',
              type = 'error'
            })
          end
        else
          lib.notify({
            title = 'Bet64',
            description = 'Spilleren er ikke online',
            type = 'error'
          })
        end
      end
    })
  end
  
  lib.registerContext({
    id = 'Bet64_bet_biggest_single_wins',
    title = 'Største Enkelt Gevinster',
    menu = 'Bet64_bet_top_players',
    options = options
  })
  
  lib.showContext('Bet64_bet_biggest_single_wins')
end



 function CreateAd()
    local input = lib.inputDialog('Udsend Reklame', {
        {
            type = 'input',
            label = 'Reklame',
            placeholder = 'Hvad vil du skrive?',
            required = true
        },
       
    })
    
    if input then
        local adContent = input[1]
        
        if adContent then
          TriggerServerEvent('zaki-betjob:server:broadcastAd', adContent)
         
        else
          
        end
    end
end