local bind = KoraPhone.Routes.handle
local Media = KoraPhone.Services.Media

-- Uploads and deletes answer later through `reply`, so they bind as async routes.
bind('requestMediaUpload', Media.requestUpload, { async = true })
bind('completeMediaUpload', Media.completeUpload, { async = true })
bind('getGallery', Media.list)
