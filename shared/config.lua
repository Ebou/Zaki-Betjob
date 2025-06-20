Config = {}

Config.Minutes = function(minutes) return minutes * 60 * 1000 end
Config.Hours = function(hours) return hours * 60 * 60 * 1000 end
Config.Days = function(days) return days * 24 * 60 * 60 * 1000 end

Config.Identifier = "Bet64"
Config.AppName = "Bet64"
Config.AppDescription = "Sports betting app"
Config.AppDeveloper = "Zaki Richh"
Config.AppSize = 59812
Config.AppIcon = "/ui/dist/bet64.png"

Config.DailyLimit = 2500000 
Config.MaxCommissionPercentage = 15
Config.DefaultCommissionPercentage = 10


Config.MinCommissionPercentage = 0

Config.AdminJobs = {
    "betting",
}

Config.DefaultColors = {
    HomeTeam = "#1e88e5",
    AwayTeam = "#f44336"
}


Config.BetAdminZone = {
    coords = vector3(-1828.2491, 797.9785, 138.1839),
    size = vector3(1.5, 1.5, 2.0),
    rotation = 1.0,
    label = 'Tilgå Bet Panel',
    icon = 'fas fa-ticket',
    groups = Config.AdminJobs, 
    distance = 2.0
}



Config.SportTypes = {
    {value = 'BASKETBALL', label = 'Basketball'},
    {value = 'SOCCER', label = 'Fodbold'},
    {value = 'BASEBALL', label = 'Baseball'},
    {value = 'HOCKEY', label = 'Ishockey'},
    {value = 'FOOTBALL', label = 'Amerikansk Fodbold'},
    {value = 'TENNIS', label = 'Tennis'},
    {value = 'GOLF', label = 'Golf'},
    {value = 'MMA', label = 'MMA'},
    {value = 'OTHER', label = 'Andet'}
}

Config.Notifications = {
    InvalidAmount = "Indtast venligst et gyldigt beløb",
    BetPlaced = "Væddemål placeret!",
    BetCashedOut = "Væddemål udbetalt!",
    BetsUpdated = "Væddemål opdateret",
    
    NoAccess = "Du har ikke adgang til denne funktion",
    InvalidID = "Ugyldigt ID",
    PlayerNotFound = "Spiller ikke fundet",
    InvalidTimeFormat = "Tid skal være i formatet HH:MM",
    InvalidDateFormat = "Datoformat er forkert",
    EventCreated = "Væddemål oprettet",
    EventCreateError = "Fejl ved oprettelse af væddemål",
    NoEventsFound = "Ingen væddemål fundet",
    OddsUpdated = "Odds opdateret",
    OddsUpdateError = "Fejl ved opdatering af odds",
    EventActivated = "Væddemål aktiveret",
    EventDeactivated = "Væddemål deaktiveret",
    EventStatusError = "Fejl ved opdatering af væddemål status",
    WinnerSet = "Vinder sat og væddemål afgjort",
    WinnerSetError = "Fejl ved opdatering af væddemål",
    EventDeleted = "Væddemål slettet og aktive væddemål refunderet",
    EventDeleteError = "Fejl ved sletning af væddemål",
    
    DepositSuccess = "DKK er overført fra din bank til betting konto",
    DepositError = "Fejl ved indsætning",
    WithdrawSuccess = "Der er blevet hævet DKK fra din betting konto",
    WithdrawError = "Fejl ved hævning af penge",
    InsufficientFunds = "Ikke nok penge på betting kontoen",
    InvalidAmountOrFunds = "Ugyldigt beløb eller ikke nok penge på kontoen",
    AccountFrozen = 'Denne konto er frosset og kan ikke bruges',
    AccountFrozenSuccess = 'Kontoen er nu frosset',
    AccountUnfrozenSuccess = 'Kontoen er nu aktiv igen',
    PlayerInfoError = "Kunne ikke hente spiller information"
}

