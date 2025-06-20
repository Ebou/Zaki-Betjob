local playerBets = {}
local playerBalance = 0

RegisterNetEvent('Bet64-bet:refreshBettingData')
AddEventHandler('Bet64-bet:refreshBettingData', function()
  TriggerServerEvent('Bet64-bet:fetchBettingData')
end)

RegisterCommand('refreshbets', function()
  TriggerServerEvent('Bet64-bet:fetchBettingData')
  lib.notify({
    title = Config.AppName,
    description = Config.Notifications.BetsUpdated,
    type = 'success'
  })
end)
