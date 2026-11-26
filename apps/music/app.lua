-- Saved stations: YouTube and SoundCloud links play in their own player, anything else as a direct HTTPS stream.
-- `embeds` lists the only hosts the page may put in a frame (the style check and the page's CSP both use it).
Phone.app('music', {
    name = 'Sound',
    description = 'Save YouTube, SoundCloud, or stream links and play them from your phone.',
    icon = 'icon.svg',
    category = 'tools',
    embeds = { 'www.youtube-nocookie.com', 'w.soundcloud.com' },
    defaultInstalled = true,
})
