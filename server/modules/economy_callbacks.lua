local bind = KoraPhone.Routes.handle
local Services = KoraPhone.Services

bind('getBankBalance', Services.Banking.balance)
bind('getBankHistory', Services.Banking.history)
bind('transferBankMoney', Services.Banking.transfer)
bind('getWallet', Services.Wallet.get)
bind('showWalletId', Services.Wallet.show)
bind('getJob', Services.Jobs.get)
bind('setJobDuty', Services.Jobs.setDuty)
bind('runJobAction', Services.Jobs.runAction)
