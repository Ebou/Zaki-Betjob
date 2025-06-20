local oddsData = {}

Citizen.CreateThread(function()
  while GetResourceState("lb-phone") ~= "started" do
    Wait(500)
  end

  local function addApp()
    local added, errorMessage = exports["lb-phone"]:AddCustomApp({
      identifier = Config.Identifier,
      name = Config.AppName,
      description = Config.AppDescription,
      developer = Config.AppDeveloper,
      defaultApp = false,
      keepOpen = true,

      size = Config.AppSize,
      onUse = function() 
        TriggerServerEvent('Bet64-bet:fetchBettingData')
      end,
      ui = GetCurrentResourceName() .. "/ui/dist/index.html",
      icon = "https://cfx-nui-" .. GetCurrentResourceName() .. Config.AppIcon,
      fixBlur = true
    })

    if not added then
      print("Could not add " .. Config.AppName .. " app:", errorMessage)
    end
  end

  addApp()

  AddEventHandler("onResourceStart", function(resource)
    if resource == "lb-phone" then
      addApp()
    end
  end)
  
  TriggerServerEvent('Bet64-bet:fetchBettingData')
end)

RegisterNetEvent('Bet64-bet:receiveBettingData')
AddEventHandler('Bet64-bet:receiveBettingData', function(data)
  if data and #data > 0 then
    oddsData = data
    
    exports["lb-phone"]:SendCustomAppMessage(Config.Identifier, {
      action = "UpdateOdds",
      data = {
        odds = oddsData
      }
    })
  else
    local sampleData = {}
    oddsData = sampleData
    
    exports["lb-phone"]:SendCustomAppMessage(Config.Identifier, {
      action = "UpdateOdds",
      data = {
        odds = oddsData
      }
    })
  end
end)

local function isGameLive(game)
  if game.is_live == true then
    return true
  end
  return false
end

local function hasGameEnded(game)
  return false
end

RegisterNUICallback("CloseUi", function(data, cb)
  exports["lb-phone"]:CloseApp()
  cb("ok")
end)

RegisterNUICallback("FetchBets", function(data, cb)

  TriggerServerEvent('Bet64-bet:fetchBettingData')
  playerBets = lib.callback.await('Bet64-bet:getBets', false)
  print(json.encode(playerBets))
  cb(playerBets)
end)


RegisterCommand("admin:fetchOdds", function()
  print(json.encode(oddsData))
end)


RegisterNUICallback("FetchBalance", function(data, cb)
  playerBalance = lib.callback.await('Bet64-bet:getBalance', false)
  cb(playerBalance)
end)

RegisterNUICallback("FetchOdds", function(data, cb)
  if not oddsData or #oddsData == 0 then
    TriggerServerEvent('Bet64-bet:fetchBettingData')
    Wait(500)
  end

  if not oddsData or #oddsData == 0 then
    local sampleData = {}
    oddsData = sampleData
    cb(sampleData)
  else
    cb(oddsData)
  end
end)

RegisterNUICallback("FetchStats", function(data, cb)
  local stats = lib.callback.await('Bet64-bet:getStats', false)
  cb(stats)
end)

RegisterNUICallback("ShowNotification", function(data, cb)
  exports["lb-phone"]:SendNotification({
    app = Config.Identifier,
    title = Config.AppName,
    content = data.description,
  })
  
  cb('ok')
end)

RegisterNUICallback("PlaceBet", function(data, cb)
  -- Check if account is frozen
  print(data)
  local isFrozen = lib.callback.await('Bet64-bet:isAccountFrozen', false)
  if isFrozen then
    exports["lb-phone"]:SendNotification({
      app = Config.Identifier,
      title = Config.AppName,
      content = Config.Notifications.AccountFrozen,
    })
    cb({ success = false, message = Config.Notifications.AccountFrozen })
    return
  end
  
  local gameId = data.gameId
  local team = data.team
  local betType = data.betType
  local selectedOdds = data.odds or 2.0
  local inputAmount = data.amount
  
  if not inputAmount or inputAmount <= 0 then
    exports["lb-phone"]:SendNotification({
      app = Config.Identifier,
      title = Config.AppName,
      content = Config.Notifications.InvalidAmount,
    })
    cb({ success = false, message = Config.Notifications.InvalidAmount })
    return
  end
  
  local success, message, newBalance = lib.callback.await('Bet64-bet:placeBet', false, 
      gameId, team, betType, selectedOdds, inputAmount)
  
  if success then
    playerBalance = newBalance
    
    exports["lb-phone"]:SendNotification({
      app = Config.Identifier,
      title = Config.AppName,
      content = Config.Notifications.BetPlaced,
    })
    
    cb({
      success = true,
      message = message,
      balance = playerBalance
    })
  else
    exports["lb-phone"]:SendNotification({
      app = Config.Identifier,
      title = Config.AppName,
      content = message,
    })
    
    cb({
      success = false,
      message = message
    })
  end
end)

RegisterNUICallback("CashoutBet", function(data, cb)
  -- Check if account is frozen
  local isFrozen = lib.callback.await('Bet64-bet:isAccountFrozen', false)
  if isFrozen then
    exports["lb-phone"]:SendNotification({
      app = Config.Identifier,
      title = Config.AppName,
      content = Config.Notifications.AccountFrozen,
    })
    cb({ success = false, message = Config.Notifications.AccountFrozen })
    return
  end

  local success, message, newBalance, newBets = lib.callback.await('Bet64-bet:cashoutBet', false, data.betId)
  
  if success then
    playerBalance = newBalance
    playerBets = newBets
    
    exports["lb-phone"]:SendNotification({
      app = Config.Identifier,
      title = Config.AppName,
      content = Config.Notifications.BetCashedOut,
    })
    
    cb({
      success = true,
      message = message,
      balance = playerBalance,
      bets = playerBets
    })
  else
    exports["lb-phone"]:SendNotification({
      app = Config.Identifier,
      title = Config.AppName,
      content = message,
    })
    
    cb({
      success = false,
      message = message
    })
  end
end)

RegisterNUICallback("FetchProfileData", function(data, cb)
  local profileData = lib.callback.await('Bet64-bet:getProfileData', false)
  cb(profileData)
end)







RegisterNUICallback("PlaceParlay", function(data, cb)
  local selections = data.selections
  local inputAmount = data.amount
  print(json.encode(data))
  if not selections or #selections < 2 then
    exports["lb-phone"]:SendNotification({
      app = identifier,
      title = "Bet64",
      content = "En parlay skal indeholde mindst 2 væddemål",
    })
    cb({ success = false, message = "En parlay skal indeholde mindst 2 væddemål" })
    return
  end
  
  if not inputAmount or inputAmount <= 0 then
    exports["lb-phone"]:SendNotification({
      app = identifier,
      title = "Bet64",
      content = "Indtast venligst et gyldigt beløb",
    })
    cb({ success = false, message = "Ugyldigt beløb" })
    return
  end
  
  local success, message, newBalance = lib.callback.await('Bet64-bet:placeParlay', false, selections, inputAmount)
  
  if success then
    playerBalance = newBalance
    
    exports["lb-phone"]:SendNotification({
      app = identifier,
      title = "Bet64",
      content = "Parlay væddemål placeret!",
    })
    
    cb({
      success = true,
      message = message,
      balance = playerBalance
    })
  else
    exports["lb-phone"]:SendNotification({
      app = identifier,
      title = "Bet64",
      content = message,
    })
    
    cb({
      success = false,
      message = message
    })
  end
end)



