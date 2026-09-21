Config = Config or {}

Config.Debug = false
Config.Locale = 'en'
Config.PhoneItem = 'phone'
Config.RequirePhoneItem = true
Config.PhoneNumber = {
    Prefix = '555',
    SubscriberDigits = 7,
    DisplayPattern = '(%s) %s-%s'
}

Config.Limits = {
    ContactName = 64,
    MessageBody = 2000,
    ConversationTitle = 80,
    PageSizeDefault = 30,
    PageSizeMaximum = 100
}

