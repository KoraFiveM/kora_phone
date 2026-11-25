local bind = KoraPhone.Routes.handle
local Social = KoraPhone.Services.Social
local Moderation = KoraPhone.Services.Moderation

bind('social:createAccount', Social.createAccount)
bind('social:getFeed', Social.getFeed)
bind('social:getProfile', Social.getProfile)
bind('social:createPost', Social.createPost)
bind('social:deletePost', Social.deletePost)
bind('social:toggleLike', Social.toggleLike)
bind('social:follow', function(source, payload) return Social.follow(source, payload, true) end)
bind('social:unfollow', function(source, payload) return Social.follow(source, payload, false) end)
bind('social:createComment', Social.createComment)
bind('social:deleteComment', Social.deleteComment)
bind('social:getComments', Social.getComments)
bind('social:block', Social.setBlock)
bind('social:report', Moderation.report)


