/** What kind of player a station link needs. YouTube and SoundCloud links use their own embeds; anything else is a stream. */
export function parseStation(url) {
    const youtube = /(?:youtube\.com\/(?:watch\?v=|shorts\/|embed\/)|youtu\.be\/)([\w-]{11})/.exec(url || '');
    if (youtube) return { kind: 'youtube', id: youtube[1] };
    if (/soundcloud\.com\//.test(url || '')) return { kind: 'soundcloud' };
    return { kind: 'audio' };
}

/** The frame source for an embed player, or '' when the station is a plain stream. */
export function embedSource(station) {
    const player = parseStation(station.url);
    if (player.kind === 'youtube') return `https://www.youtube-nocookie.com/embed/${player.id}?autoplay=1&rel=0`;
    if (player.kind === 'soundcloud') return `https://w.soundcloud.com/player/?url=${encodeURIComponent(station.url)}&auto_play=true&visual=false`;
    return '';
}
