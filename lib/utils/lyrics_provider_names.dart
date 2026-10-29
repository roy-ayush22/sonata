/// Display names for the built-in lyrics providers, by backend id.
const builtInLyricsProviderNames = <String, String>{
  'lrclib': 'LRCLIB',
  'netease': 'Netease',
  'musixmatch': 'Musixmatch',
  'apple_music': 'Apple Music',
  'mornye_lyrics': 'Zarz-LRC',
  'qqmusic': 'QQ Music',
  'spotify': 'Spotify',
  'deezer': 'Deezer',
  'youtube': 'YouTube',
  'kugou': 'Kugou',
  'genius': 'Genius',
  'lyricsplus': 'LyricsPlus',
  'lrcred': 'lrc.red',
  'betterlyrics': 'BetterLyrics',
};

/// A built-in lyrics provider's name for display.
String lyricsProviderDisplayName(String provider) =>
    builtInLyricsProviderNames[provider] ?? provider;
