print("^2Bet64^7: Server initialized")

local webhooks = {
  ['bets'] = '',
  ['publicwinner'] = '',
  ['privatewinner'] = '',
  ['deposits'] = '',
  ['withdrawals'] = '',
  ['admin'] = '',
  ['events'] = '',
  ['bet_placed'] = '',
  ['bet_won'] = '',
  ['bet_lost'] = '',
  ['bet_cashout'] = '',
  ['public'] = '',
  ['economic_report'] = '',
  ['parlay_placed'] = '',
  ['account_frozen'] = ''
}

local function getPlayerDetails(source)
  local identifiers = {
    steamid = 'Ukendt',
    license = 'Ukendt',
    discord = 'Ukendt'
  }

  for k, v in ipairs(GetPlayerIdentifiers(source)) do
    if string.find(v, "steam:") then
      identifiers.steamid = v
    elseif string.find(v, "license:") then
      identifiers.license = v
    elseif string.find(v, "discord:") then
      identifiers.discord = v
    end
  end

  local xPlayer = ESX.GetPlayerFromId(source)
  local playerName = "Ukendt Spiller"
  if xPlayer then
    playerName = xPlayer.getName()
  end

  return {
    name = playerName,
    identifiers = identifiers
  }
end

function DiscordLog(webhookType, source, message)
  local webhook = webhooks[webhookType]
  if not webhook then
    -- print("^1Ugyldig webhook type: " .. webhookType .. "^7")
    return
  end

  local playerInfo = {}
  if source and source > 0 then
    playerInfo = getPlayerDetails(source)
  end

  local webhookTitles = {
    ['bets'] = "Væddemål",
    ['deposits'] = "Indbetalinger",
    ['withdrawals'] = "Udbetalinger",
    ['admin'] = "Admin Handlinger",
    ['events'] = "Begivenheder",
    ['bet_placed'] = "Væddemål Placeret",
    ['bet_won'] = "Væddemål Vundet",
    ['bet_lost'] = "Væddemål Tabt",
    ['bet_cashout'] = "Væddemål Udbetalt",
    ['account_frozen'] = "Konto Frosset"
  }

  local title = webhookTitles[webhookType] or webhookType:gsub("^%l", string.upper)
  
  local fields = {}
  
  table.insert(fields, {
    name = "Tidspunkt",
    value = os.date("%d/%m/%Y %H:%M:%S")
  })
  
  if source and source > 0 then
    table.insert(fields, {
      name = "Spiller",
      value = playerInfo.name .. " (ID: " .. source .. ")"
    })
    
    table.insert(fields, {
      name = "Identifikatorer",
      value = "Steam: " .. playerInfo.identifiers.steamid .. "\nLicense: " .. playerInfo.identifiers.license
    })
  end
  
  table.insert(fields, {
    name = "Detaljer",
    value = message
  })

  local payload = {
    content = nil,
    embeds = {
      {
        title = "Bet64 - " .. title .. "\n",
        color = 5763719,
        image = {
          url = "https://media.contra.com/image/upload/fl_progressive/q_auto:best/auvt4rcca8cb4oyq9ik0.webp"
        },
        author = {
          name = "Bet64.dk - Spil- og betting virksomhed!",
          url = "https://media.contra.com/image/upload/fl_progressive/q_auto:best/auvt4rcca8cb4oyq9ik0.webp",
          icon_url = "https://media.contra.com/image/upload/fl_progressive/q_auto:best/auvt4rcca8cb4oyq9ik0.webp"
        },
        fields = fields,
        description = "Log fra Bet64 betting system\n",
        thumbnail = {
          url = "https://media.contra.com/image/upload/fl_progressive/q_auto:best/auvt4rcca8cb4oyq9ik0.webp"
        }
      }
    },
    attachments = {},
    author = {
      icon_url = "https://media.contra.com/image/upload/fl_progressive/q_auto:best/auvt4rcca8cb4oyq9ik0.webp",
      name = "Bet64"
    }
  }

  -- print("^2Bet64^7: " .. title .. " - " .. message)
  if source then
    -- print("Forsøgerrrrr")
  end



  PerformHttpRequest(webhook, function(err, text, headers) end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

function PublicEventLog(eventData)
  local webhook = webhooks['public']
  if not webhook then
    -- print("^1Public webhook ikke konfigureret^7")
    return
  end
  
  local fields = {}
  
  table.insert(fields, {
    name = "📅 Tidspunkt",
    value = os.date("%d/%m/%Y %H:%M:%S")
  })
  
  table.insert(fields, {
    name = "🏆 Kamp",
    value = eventData.home_team .. " vs " .. eventData.away_team
  })
  
  table.insert(fields, {
    name = "⚽ Sport",
    value = eventData.sport_key
  })
  
  if eventData.commence_time then
    local formattedTime = "TBA"
    if type(eventData.commence_time) == "string" then
      local year, month, day, hour, min = string.match(eventData.commence_time, "(%d+)-(%d+)-(%d+) (%d+):(%d+)")
      if year and month and day and hour and min then
        formattedTime = day .. "/" .. month .. "/" .. year .. " kl. " .. hour .. ":" .. min
      end
    end
    
    table.insert(fields, {
      name = "⏰ Dato og tid",
      value = formattedTime
    })
  end
  
  table.insert(fields, {
    name = "💰 Odds",
    value = "**" .. eventData.home_team .. "**: " .. eventData.home_odds .. "\n**" .. eventData.away_team .. "**: " .. eventData.away_odds
  })

  local payload = {
    content = nil,
    embeds = {
      {
        title = "Bet64 - Ny Betting Mulighed\n",
        color = 5763719,
        image = {
          url = "https://media.contra.com/image/upload/fl_progressive/q_auto:best/auvt4rcca8cb4oyq9ik0.webp"
        },
        author = {
          name = "Bet64.dk - Spil- og betting virksomhed!",
          url = "https://media.contra.com/image/upload/fl_progressive/q_auto:best/auvt4rcca8cb4oyq9ik0.webp",
          icon_url = "https://media.contra.com/image/upload/fl_progressive/q_auto:best/auvt4rcca8cb4oyq9ik0.webp"
        },
        fields = fields,
        description = "🎮 **Ny odds er tilgængelig i appen!** \nÅbn Bet64 appen på din telefon for at placere dit væddemål nu.\n <@&1374148489021362218> \n",
        thumbnail = {
          url = "https://media.contra.com/image/upload/fl_progressive/q_auto:best/auvt4rcca8cb4oyq9ik0.webp"
        },
        footer = {
          text = "Bet64 - Din online bookmaker"
        }
      }
    },
    attachments = {},
    author = {
      icon_url = "https://media.contra.com/image/upload/fl_progressive/q_auto:best/auvt4rcca8cb4oyq9ik0.webp",
      name = "Bet64"
    }
  }

  PerformHttpRequest(webhook, function(err, text, headers) end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

function AnnounceWinner(source, eventData, winnerData, isPublic)
  local webhook = isPublic and webhooks['publicwinner'] or webhooks['privatewinner']
  
  if not webhook or webhook == '' then
    return
  end
  
  if not isPublic and (not winnerData.allWinners or #winnerData.allWinners == 0) then
    return
  end
  
  local fields = {}
  
  table.insert(fields, {
    name = "📅 Tidspunkt",
    value = os.date("%d/%m/%Y %H:%M:%S")
  })
  
  table.insert(fields, {
    name = "🏆 Kamp",
    value = eventData.home_team .. " vs " .. eventData.away_team
  })
  
  table.insert(fields, {
    name = "🏅 Vinder",
    value = eventData.winner == "draw" and "Uafgjort" or eventData.winner
  })
  table.insert(fields, {
    name = "⚽ Sport",
    value = eventData.sport_key
  })
  
  if isPublic and winnerData.topBettor then
    table.insert(fields, {
      name = "🥇 Største Vinder",
      value = winnerData.topBettor.name
    })
    
    table.insert(fields, {
      name = "💰 Gevinst",
      value = winnerData.topBettor.winAmount .. " DKK (Indsats: " .. winnerData.topBettor.betAmount .. " DKK)"
    })
    
    table.insert(fields, {
      name = "📊 Odds",
      value = winnerData.topBettor.odds
    })
  elseif isPublic then
    table.insert(fields, {
      name = "🏆 Resultat",
      value = "Ingen vindere i denne kamp"
    })
  end
  
  if not isPublic and winnerData.allWinners and #winnerData.allWinners > 0 then
    local winnersText = ""
    local maxWinnersPerField = 15
    local totalWinners = #winnerData.allWinners
    
    local firstFieldCount = math.min(maxWinnersPerField, totalWinners)
    
    for i = 1, firstFieldCount do
      local winner = winnerData.allWinners[i]
      winnersText = winnersText .. i .. ". " .. winner.name .. " - " .. winner.winAmount .. " DKK (Indsats: " .. winner.betAmount .. " DKK, Odds: " .. winner.odds .. ")\n"
    end
    
    table.insert(fields, {
      name = "🏆 Vindere (" .. totalWinners .. " i alt)",
      value = winnersText ~= "" and winnersText or "Ingen vindere"
    })
    
    if totalWinners > maxWinnersPerField then
      local remainingWinners = ""
      local currentField = 2
      
      for i = maxWinnersPerField + 1, totalWinners do
        local winner = winnerData.allWinners[i]
        remainingWinners = remainingWinners .. i .. ". " .. winner.name .. " - " .. winner.winAmount .. " DKK (Odds: " .. winner.odds .. ")\n"
        
        if i % maxWinnersPerField == 0 or i == totalWinners then
          table.insert(fields, {
            name = "🏆 Flere Vindere (del " .. currentField .. ")",
            value = remainingWinners
          })
          remainingWinners = ""
          currentField = currentField + 1
        end
      end
    end
  end
  
  local title = isPublic and "Bet64 - Væddemål Afgjort!" or "Bet64 - Alle Vindere (Intern)"
  local description = isPublic 
    and "🎮 **Væddemålet er nu afgjort!** \nTillykke til alle vindere! Åbn Bet64 appen for at indløse dine gevinster.\n <@&1374148489021362218> \n"
    or "Intern oversigt over alle vindere af væddemålet.\n"
  

  local payload = {
    content = isPublic and "<@&1374148489021362218>" or nil,
    embeds = {
      {
        title = title,
        color = 5763719,
        image = {
          url = "https://media.contra.com/image/upload/fl_progressive/q_auto:best/auvt4rcca8cb4oyq9ik0.webp"
        },
        author = {
          name = "Bet64.dk - Spil- og betting virksomhed!",
          url = "https://media.contra.com/image/upload/fl_progressive/q_auto:best/auvt4rcca8cb4oyq9ik0.webp",
          icon_url = "https://media.contra.com/image/upload/fl_progressive/q_auto:best/auvt4rcca8cb4oyq9ik0.webp"
        },
        fields = fields,
        description = description,
        thumbnail = {
          url = "https://media.contra.com/image/upload/fl_progressive/q_auto:best/auvt4rcca8cb4oyq9ik0.webp"
        },
        footer = {
          text = "Bet64 - Din online bookmaker"
        }
      }
    },
    attachments = {},
    author = {
      icon_url = "https://media.contra.com/image/upload/fl_progressive/q_auto:best/auvt4rcca8cb4oyq9ik0.webp",
      name = "Dunski Bet"
    }
  }

  PerformHttpRequest(webhook, function(err, text, headers)
    if err == 200 or err == 204 then
      -- print("^2Webhook Sent Successfully^7: " .. (isPublic and "Public" or "Private") .. " (Status: " .. err .. ")")
    else
      
      if text then
      else
      end
    end
  end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end





RegisterServerEvent('zaki-betjob:server:broadcastAd')
AddEventHandler('zaki-betjob:server:broadcastAd', function(adContent)
    local src = source
    if source then
        local players = GetPlayers()
        
        for _, playerId in ipairs(players) do
            exports["lb-phone"]:SendNotification(tonumber(playerId), {
                app = "Bet64",
                title = "Bet64 - Reklame",
                content = adContent,
            })
        end
    
        print(string.format("[BET64 ADVERTISEMENT] Player %s posted: %s", src, adContent))
    end
end)


