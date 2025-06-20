RegisterNetEvent('Bet64-bet:fetchBettingData')
AddEventHandler('Bet64-bet:fetchBettingData', function()
  local source = source
  local events = getBettingEvents(true)
  local formattedEvents = {}
  
  for _, event in ipairs(events) do
    table.insert(formattedEvents, formatBettingEvent(event))
  end
  
  TriggerClientEvent('Bet64-bet:receiveBettingData', source, formattedEvents)
  -- DiscordLog("events", source, "Hentede betting data")
end)

RegisterNetEvent('Bet64-bet:refreshBettingData')
AddEventHandler('Bet64-bet:refreshBettingData', function()
  local source = source
  TriggerEvent('Bet64-bet:fetchBettingData')
  -- DiscordLog("events", source, "Opdaterede betting data")
end)

RegisterNetEvent('ox_lib:notify')
AddEventHandler('ox_lib:notify', function(data)
  if data then
    lib.notify({
      title = data.title,
      description = data.description,
      type = data.type
    })
  end
end)
