import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

const ink = Color(0xff24252b);
const muted = Color(0xff868893);
const accent = Color(0xff4d659b);
const canvas = Color(0xfff6f6fa);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.protocolWhitelist = const ['file'];
  JustAudioMediaKit.ensureInitialized(linux: true, windows: false);
  runApp(const SonataApp());
}

class SonataApp extends StatelessWidget {
  const SonataApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Sonata',
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(seedColor: accent, surface: canvas),
      fontFamily: 'Inter',
    ),
    home: const SonataHome(),
  );
}

class Song {
  Song(
    this.title,
    this.artist,
    this.album,
    this.duration, {
    this.path,
    this.color = const Color(0xffd3e0dc),
  });
  final String title, artist, album, duration;
  final String? path;
  final Color color;
}

final demoSongs = <Song>[
  Song(
    'Lodi When',
    'Zach Bryan',
    'Young Manhood and Other Donatable Organs',
    '3:42',
    color: const Color(0xffbbc9c4),
  ),
  Song(
    'Robot Killed The Working Man',
    'Zach Bryan',
    'Young Manhood and Other Donatable Organs',
    '4:06',
    color: const Color(0xffc9d1c9),
  ),
  Song(
    'Lies (feat. Lana Del Rey)',
    'Zach Bryan',
    'Young Manhood and Other Donatable Organs',
    '3:21',
    color: const Color(0xffe4c9c3),
  ),
  Song(
    'Dog Days',
    'Zach Bryan',
    'Young Manhood and Other Donatable Organs',
    '3:54',
    color: const Color(0xffd7d0bc),
  ),
  Song(
    'Backwards',
    'Zach Bryan',
    'Young Manhood and Other Donatable Organs',
    '2:57',
    color: const Color(0xffbfc9d6),
  ),
  Song(
    'expectations',
    'Olivia Rodrigo & Chappell Roan',
    'expectations · Single',
    '3:44',
    color: const Color(0xffd9aa53),
  ),
  Song(
    'making the bed',
    'Olivia Rodrigo',
    'GUTS',
    '3:18',
    color: const Color(0xffc5cce3),
  ),
  Song(
    'Pink + White',
    'Frank Ocean',
    'Blonde',
    '3:04',
    color: const Color(0xffbccfc7),
  ),
  Song(
    'My Love Mine All Mine',
    'Mitski',
    'The Land Is Inhospitable and So Are We',
    '2:17',
    color: const Color(0xffd7b8a9),
  ),
];

class SonataHome extends StatefulWidget {
  const SonataHome({super.key});
  @override
  State<SonataHome> createState() => _SonataHomeState();
}

class _SonataHomeState extends State<SonataHome> {
  final AudioPlayer _audio = AudioPlayer();
  final TextEditingController _search = TextEditingController();
  final Set<String> _folders = {};
  final List<Song> _library = [...demoSongs];
  String _page = 'Home';
  int _selected = 5;
  int _active = 5;
  bool _playing = false;
  bool _lyrics = true;
  bool _queue = false;
  bool _fullPlayer = false;
  bool _shuffle = false;
  bool _repeat = false;
  bool _watching = false;
  String _sort = 'Title';
  double _volume = .84;
  Duration _position = const Duration(seconds: 38);
  Duration _length = const Duration(minutes: 3, seconds: 44);
  Timer? _folderPoll;

  Song get current => _library.isEmpty
      ? demoSongs[_active % demoSongs.length]
      : _library[_active.clamp(0, _library.length - 1).toInt()];

  @override
  void initState() {
    super.initState();
    _audio.positionStream.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _audio.durationStream.listen((value) {
      if (mounted && value != null) setState(() => _length = value);
    });
    _audio.playerStateStream.listen((state) {
      if (mounted) setState(() => _playing = state.playing);
    });
    _audio.volume = _volume;
  }

  @override
  void dispose() {
    _folderPoll?.cancel();
    _audio.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _chooseFolder() async {
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose a music folder',
    );
    if (folder == null) return;
    _folders.add(folder);
    await _scanFolder(folder);
    _folderPoll ??= Timer.periodic(const Duration(seconds: 15), (_) async {
      for (final path in _folders) {
        await _scanFolder(path, quiet: true);
      }
    });
    if (mounted) setState(() => _watching = true);
  }

  Future<void> _scanFolder(String folder, {bool quiet = false}) async {
    List<Map<String, dynamic>> tracks = [];
    try {
      tracks = await RustLibrary.scan(folder);
    } catch (_) {
      final extensions = {
        '.mp3',
        '.flac',
        '.ogg',
        '.opus',
        '.m4a',
        '.aac',
        '.wav',
        '.aiff',
        '.ape',
        '.wv',
      };
      await for (final entity in Directory(
        folder,
      ).list(recursive: true, followLinks: false)) {
        if (entity is File &&
            extensions.contains(
              '.${entity.path.split('.').last.toLowerCase()}',
            )) {
          tracks.add({
            'path': entity.path,
            'title': _filenameTitle(entity.path),
          });
        }
      }
    }
    if (!mounted) return;
    setState(() {
      final existing = _library.map((s) => s.path).whereType<String>().toSet();
      for (final item in tracks) {
        final path = item['path'] as String;
        if (existing.add(path)) {
          _library.add(
            Song(
              item['title'] as String,
              'Local file',
              'Added from folder',
              '—',
              path: path,
              color: _palette[_library.length % _palette.length],
            ),
          );
        }
      }
    });
    if (!quiet && mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Found ${tracks.length} tracks · watching this folder'),
        ),
      );
  }

  String _filenameTitle(String path) => path
      .split(Platform.pathSeparator)
      .last
      .replaceFirst(RegExp(r'\.[^.]+$'), '')
      .replaceAll(RegExp(r'[_-]+'), ' ');

  Future<void> _play(int index) async {
    if (_library.isEmpty) return;
    if (_audio.playing) await _audio.stop();
    setState(() {
      _active = index;
      _selected = index;
      _position = Duration.zero;
    });
    final song = _library[index];
    if (song.path != null) {
      try {
        await _audio.setFilePath(song.path!);
        await _audio.play();
      } catch (error) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not play this file: $error')),
          );
      }
    } else {
      setState(() => _playing = !_playing);
    }
  }

  Future<void> _togglePlay() async {
    if (current.path != null) {
      if (_audio.playing) {
        await _audio.pause();
      } else {
        await _audio.play();
      }
    } else {
      setState(() => _playing = !_playing);
    }
  }

  void _step(int delta) {
    if (_library.isEmpty) return;
    var next = _active + delta;
    if (_repeat) {
      next %= _library.length;
      if (next < 0) next += _library.length;
    } else {
      next = next.clamp(0, _library.length - 1).toInt();
    }
    _play(next);
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.space): const _ToggleIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            const _SkipIntent(1),
        const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true):
            const _SkipIntent(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            const _SkipIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true):
            const _SkipIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowUp, control: true):
            const _VolumeIntent(.05),
        const SingleActivator(LogicalKeyboardKey.arrowDown, control: true):
            const _VolumeIntent(-.05),
        const SingleActivator(LogicalKeyboardKey.arrowUp, meta: true):
            const _VolumeIntent(.05),
        const SingleActivator(LogicalKeyboardKey.arrowDown, meta: true):
            const _VolumeIntent(-.05),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ToggleIntent: CallbackAction<_ToggleIntent>(
            onInvoke: (_) {
              _togglePlay();
              return null;
            },
          ),
          _SkipIntent: CallbackAction<_SkipIntent>(
            onInvoke: (i) {
              _step(i.direction);
              return null;
            },
          ),
          _VolumeIntent: CallbackAction<_VolumeIntent>(
            onInvoke: (i) {
              setState(
                () => _volume = (_volume + i.delta).clamp(0, 1).toDouble(),
              );
              _audio.setVolume(_volume);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  _WindowBar(
                    onAddFolder: _chooseFolder,
                    onTogglePlay: _togglePlay,
                    onPrevious: () => _step(-1),
                    onNext: () => _step(1),
                    onLyrics: () => setState(() {
                      _lyrics = true;
                      _queue = false;
                    }),
                    onQueue: () => setState(() {
                      _lyrics = false;
                      _queue = true;
                    }),
                    onFocus: () => setState(() => _fullPlayer = !_fullPlayer),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        _sidebar(),
                        Expanded(child: _content()),
                        if (_fullPlayer)
                          Expanded(flex: 5, child: _nowPlaying(expanded: true))
                        else
                          _nowPlaying(expanded: false),
                      ],
                    ),
                  ),
                  _bottomPlayer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sidebar() => Container(
    width: 76,
    color: const Color(0xfff0f0f5),
    child: Column(
      children: [
        const SizedBox(height: 16),
        _nav(Icons.home_rounded, 'Home'),
        _nav(Icons.library_music_outlined, 'Library'),
        _nav(Icons.widgets_outlined, 'Albums'),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          child: Divider(height: 1),
        ),
        _nav(Icons.queue_music_rounded, 'Playlists'),
        const Spacer(),
        if (_watching)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Tooltip(
              message: 'Folder watch is on',
              child: Icon(Icons.circle, size: 7, color: Color(0xff68a879)),
            ),
          ),
        _nav(Icons.settings_outlined, 'Settings'),
        const SizedBox(height: 12),
      ],
    ),
  );

  Widget _nav(IconData icon, String label) {
    final selected = _page == label;
    return InkWell(
      onTap: () => setState(() => _page = label),
      child: SizedBox(
        width: 76,
        height: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? const Color(0xffdce2f6) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 19, color: ink),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                color: selected ? ink : muted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final query = _search.text.trim().toLowerCase();
    var visible = _library
        .where(
          (song) => '${song.title} ${song.artist} ${song.album}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    if (_page == 'Duplicates') visible = visible.take(2).toList();
    visible.sort(
      (a, b) => _sort == 'Artist'
          ? a.artist.compareTo(b.artist)
          : _sort == 'Album'
          ? a.album.compareTo(b.album)
          : a.title.compareTo(b.title),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 16, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.arrow_back_rounded, size: 19),
              ),
              const Spacer(),
              Container(
                width: 230,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xffe9e9ee)),
                ),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: 'Search your library',
                    hintStyle: TextStyle(fontSize: 12, color: muted),
                    prefixIcon: Icon(Icons.search, size: 17),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.only(bottom: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Add music folder',
                onPressed: _chooseFolder,
                icon: const Icon(Icons.create_new_folder_outlined, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Cover(
                song: _library.isNotEmpty ? _library[0] : demoSongs[0],
                size: 150,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _page == 'Duplicates'
                          ? 'Review duplicates'
                          : _page == 'Playlists'
                          ? 'Your playlists'
                          : 'Young Manhood and Other Donatable Organs',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        height: 1.14,
                        letterSpacing: -.55,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _page == 'Duplicates'
                          ? '2 possible matches found'
                          : 'Zach Bryan',
                      style: const TextStyle(
                        fontSize: 14,
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '2026  ·  ✧  Hi-Res Lossless  ·  24-bit',
                      style: const TextStyle(
                        fontSize: 10,
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _roundButton(Icons.favorite_border, () {}),
                        const SizedBox(width: 9),
                        FilledButton.icon(
                          onPressed: () => _play(_active),
                          icon: const Icon(Icons.play_arrow_rounded, size: 17),
                          label: const Text('Play'),
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _chooseFolder,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add music'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ink,
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Icon(Icons.graphic_eq_rounded, size: 15, color: muted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'A collection of songs made to be lived in.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink.withValues(alpha: .72),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${visible.length} songs',
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              const SizedBox(width: 30),
              _sortButton('#', 'Title'),
              _sortButton('TITLE', 'Title'),
              _sortButton('ARTIST', 'Artist'),
              _sortButton('ALBUM', 'Album'),
              const Spacer(),
              IconButton(
                tooltip: 'Edit tags',
                onPressed: () => _showTags(current),
                icon: const Icon(Icons.tune_rounded, size: 17, color: muted),
              ),
            ],
          ),
          const Divider(height: 1, color: Color(0xffe7e7ed)),
          Expanded(
            child: ListView.builder(
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final song = visible[index];
                final actualIndex = _library.indexOf(song);
                final selected = actualIndex == _active;
                return InkWell(
                  onTap: () => _play(actualIndex),
                  onDoubleTap: () => _play(actualIndex),
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xffe9ebf5)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 25,
                          child: Center(
                            child: selected && _playing
                                ? const Icon(
                                    Icons.volume_up_rounded,
                                    size: 14,
                                    color: accent,
                                  )
                                : Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: muted,
                                    ),
                                  ),
                          ),
                        ),
                        Expanded(
                          flex: 5,
                          child: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: ink,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, color: muted),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            song.album,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, color: muted),
                          ),
                        ),
                        SizedBox(
                          width: 38,
                          child: Text(
                            song.duration,
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 10, color: muted),
                          ),
                        ),
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          iconSize: 15,
                          tooltip: 'Track options',
                          onSelected: (v) {
                            if (v == 'tag') _showTags(song);
                            if (v == 'duplicate')
                              setState(() => _page = 'Duplicates');
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'tag',
                              child: Text('Edit tags'),
                            ),
                            PopupMenuItem(
                              value: 'duplicate',
                              child: Text('Find duplicates'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sortButton(String label, String value) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: InkWell(
      onTap: () => setState(() => _sort = value),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8.5,
          letterSpacing: .45,
          color: _sort == value ? ink : muted,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );

  Widget _roundButton(IconData icon, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xffeeeef4),
      ),
      child: Icon(icon, size: 15, color: ink),
    ),
  );

  Widget _nowPlaying({required bool expanded}) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final w = expanded
        ? double.infinity
        : math.min(440, screenWidth * .37).toDouble();
    return Container(
      width: w,
      margin: const EdgeInsets.fromLTRB(0, 8, 10, 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xffded8d6), Color(0xffece7e0), Color(0xfff4edcd)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .13),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -100,
            right: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .26),
              ),
            ),
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 14, 2),
                child: Row(
                  children: [
                    const _TrafficLights(),
                    const SizedBox(width: 10),
                    _roundButton(
                      Icons.close_rounded,
                      () => setState(() => _fullPlayer = false),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.volume_down_rounded,
                      size: 14,
                      color: ink.withValues(alpha: .7),
                    ),
                    SizedBox(
                      width: 100,
                      child: Slider(
                        value: _volume,
                        onChanged: (v) {
                          setState(() => _volume = v);
                          _audio.setVolume(v);
                        },
                        activeColor: accent,
                        inactiveColor: Colors.white.withValues(alpha: .7),
                      ),
                    ),
                    Icon(
                      Icons.volume_up_rounded,
                      size: 15,
                      color: ink.withValues(alpha: .75),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: expanded
                    ? Row(
                        children: [
                          Expanded(child: _albumColumn()),
                          Expanded(child: _lyricsPanel()),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(flex: 5, child: _albumColumn()),
                                Expanded(flex: 4, child: _lyricsPanel()),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Row(
              children: [
                _roundButton(
                  _lyrics ? Icons.lyrics_rounded : Icons.lyrics_outlined,
                  () => setState(() {
                    _lyrics = !_lyrics;
                    _queue = false;
                  }),
                ),
                const SizedBox(width: 5),
                _roundButton(
                  _queue ? Icons.queue_music : Icons.queue_music_outlined,
                  () => setState(() {
                    _queue = !_queue;
                    _lyrics = false;
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _albumColumn() {
    final artSize = math
        .min(300, MediaQuery.sizeOf(context).width * .25)
        .toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 12, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: _Cover(song: current, size: artSize, square: true),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            current.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${current.artist} · ${current.album}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9.5, color: Color(0xff555761)),
          ),
          const SizedBox(height: 9),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2.2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: accent,
              inactiveTrackColor: Colors.white.withValues(alpha: .72),
              thumbColor: accent,
            ),
            child: Slider(
              value: _position.inMilliseconds
                  .toDouble()
                  .clamp(0, math.max(_length.inMilliseconds, 1).toDouble())
                  .toDouble(),
              min: 0,
              max: math.max(_length.inMilliseconds, 1).toDouble(),
              onChanged: (v) {
                setState(() => _position = Duration(milliseconds: v.round()));
                if (current.path != null) _audio.seek(_position);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _fmt(_position),
                  style: const TextStyle(fontSize: 8, color: Color(0xff555761)),
                ),
                const Text(
                  '✧  FLAC  ·  24-bit  ·  48 kHz',
                  style: TextStyle(fontSize: 8, color: Color(0xff555761)),
                ),
                Text(
                  current.duration,
                  style: const TextStyle(fontSize: 8, color: Color(0xff555761)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _transport(
                Icons.shuffle_rounded,
                _shuffle,
                () => setState(() => _shuffle = !_shuffle),
              ),
              _transport(Icons.skip_previous_rounded, false, () => _step(-1)),
              InkWell(
                onTap: _togglePlay,
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  width: 53,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
              _transport(Icons.skip_next_rounded, false, () => _step(1)),
              _transport(
                Icons.repeat_rounded,
                _repeat,
                () => setState(() => _repeat = !_repeat),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _transport(IconData icon, bool active, VoidCallback onTap) =>
      IconButton(
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          icon,
          size: 16,
          color: active ? accent : const Color(0xff393a41),
        ),
      );

  Widget _lyricsPanel() {
    if (!_lyrics) return _upNext();
    final lines = [
      'i met him at a party',
      'i think he was on drugs',
      "he wasn't smart or funny",
      'i convinced myself he was',
      'he had a great apartment',
      'and a car his parents bought',
      'i thought that he was perfect',
      "and now his number's blocked",
      'took a couple months',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 22, 34),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(
                  fontSize: i == 2 ? 14 : 12,
                  fontWeight: i == 2 ? FontWeight.w700 : FontWeight.w500,
                  color: i == 2
                      ? ink
                      : ink.withValues(alpha: i < 2 ? .34 : .63),
                  height: 1.1,
                ),
                child: Text(
                  lines[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _upNext() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 18, 30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Up Next',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: math.min(7, _library.length).toInt(),
            itemBuilder: (_, i) {
              final song = _library[(i + _active + 1) % _library.length];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: _Cover(song: song, size: 36),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  song.artist,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 9),
                ),
                trailing: const Icon(Icons.drag_handle, size: 14),
              );
            },
          ),
        ),
        TextButton.icon(
          onPressed: () => setState(() {
            _lyrics = true;
            _queue = false;
          }),
          icon: const Icon(Icons.lyrics_outlined, size: 15),
          label: const Text('Show lyrics'),
        ),
      ],
    ),
  );

  Widget _bottomPlayer() => Container(
    height: 62,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: const BoxDecoration(
      color: Color(0xfff0f0f5),
      border: Border(top: BorderSide(color: Color(0xffe7e7ed))),
    ),
    child: Row(
      children: [
        _Cover(song: current, size: 40),
        const SizedBox(width: 10),
        SizedBox(
          width: 190,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                current.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              Text(
                current.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9, color: muted),
              ),
            ],
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: () => _step(-1),
          icon: const Icon(Icons.skip_previous_rounded, size: 19),
        ),
        IconButton(
          onPressed: _togglePlay,
          icon: Icon(
            _playing
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_filled_rounded,
            color: accent,
            size: 32,
          ),
        ),
        IconButton(
          onPressed: () => _step(1),
          icon: const Icon(Icons.skip_next_rounded, size: 19),
        ),
        const Spacer(),
        Text(
          _fmt(_position),
          style: const TextStyle(fontSize: 9, color: muted),
        ),
        SizedBox(
          width: 130,
          child: Slider(
            value: _position.inMilliseconds
                .toDouble()
                .clamp(0, math.max(_length.inMilliseconds, 1).toDouble())
                .toDouble(),
            min: 0,
            max: math.max(_length.inMilliseconds, 1).toDouble(),
            onChanged: (v) {
              setState(() => _position = Duration(milliseconds: v.round()));
              if (current.path != null) _audio.seek(_position);
            },
          ),
        ),
        Text(_fmt(_length), style: const TextStyle(fontSize: 9, color: muted)),
        const SizedBox(width: 10),
        IconButton(
          tooltip: 'Focus player',
          onPressed: () => setState(() => _fullPlayer = !_fullPlayer),
          icon: const Icon(Icons.open_in_full_rounded, size: 16),
        ),
      ],
    ),
  );

  Future<void> _showTags(Song song) async {
    final title = TextEditingController(text: song.title),
        artist = TextEditingController(text: song.artist),
        album = TextEditingController(text: song.album);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit track details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: artist,
              decoration: const InputDecoration(labelText: 'Artist'),
            ),
            TextField(
              controller: album,
              decoration: const InputDecoration(labelText: 'Album'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                final index = _library.indexOf(song);
                _library[index] = Song(
                  title.text,
                  artist.text,
                  album.text,
                  song.duration,
                  path: song.path,
                  color: song.color,
                );
              });
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    title.dispose();
    artist.dispose();
    album.dispose();
  }
}

const _palette = [
  Color(0xffcad3d1),
  Color(0xffd8c6ba),
  Color(0xffc5cce0),
  Color(0xffd3d7b6),
  Color(0xffe2c89f),
];

class _Cover extends StatelessWidget {
  const _Cover({required this.song, required this.size, this.square = false});
  final Song song;
  final double size;
  final bool square;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size < 60 ? 6 : 15),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          song.color,
          Color.lerp(song.color, const Color(0xff344847), .58)!,
        ],
      ),
      boxShadow: [
        if (size > 100)
          BoxShadow(
            color: Colors.black.withValues(alpha: .17),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        Positioned(
          right: -size * .08,
          top: size * .17,
          child: Container(
            width: size * .66,
            height: size * .38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .23),
              borderRadius: BorderRadius.circular(size),
            ),
          ),
        ),
        Positioned(
          left: size * .11,
          bottom: size * .09,
          child: Icon(
            Icons.landscape_rounded,
            size: size * .66,
            color: const Color(0xff455958).withValues(alpha: .40),
          ),
        ),
        if (size > 100)
          Positioned(
            left: size * .10,
            top: size * .10,
            right: size * .1,
            child: Text(
              song.album.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: size * .047,
                letterSpacing: 1.2,
                color: Colors.white.withValues(alpha: .87),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (size < 60)
          const Center(
            child: Icon(
              Icons.music_note_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
      ],
    ),
  );
}

class _WindowBar extends StatelessWidget {
  const _WindowBar({
    required this.onAddFolder,
    required this.onTogglePlay,
    required this.onPrevious,
    required this.onNext,
    required this.onLyrics,
    required this.onQueue,
    required this.onFocus,
  });
  final VoidCallback onAddFolder,
      onTogglePlay,
      onPrevious,
      onNext,
      onLyrics,
      onQueue,
      onFocus;
  @override
  Widget build(BuildContext context) => Container(
    height: 31,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        const _TrafficLights(),
        const SizedBox(width: 12),
        _MenuButton('File', const {'Add music folder': 'folder'}, (v) {
          if (v == 'folder') onAddFolder();
        }),
        _MenuButton(
          'Playback',
          const {
            'Play / pause': 'play',
            'Previous track': 'previous',
            'Next track': 'next',
          },
          (v) {
            if (v == 'play') onTogglePlay();
            if (v == 'previous') onPrevious();
            if (v == 'next') onNext();
          },
        ),
        _MenuButton(
          'View',
          const {
            'Lyrics': 'lyrics',
            'Up Next': 'queue',
            'Focus player': 'focus',
          },
          (v) {
            if (v == 'lyrics') onLyrics();
            if (v == 'queue') onQueue();
            if (v == 'focus') onFocus();
          },
        ),
        const Spacer(),
        const Text(
          'sonata',
          style: TextStyle(
            fontSize: 10,
            color: Color(0xff8c8d94),
            letterSpacing: .3,
          ),
        ),
        const Spacer(),
        const SizedBox(width: 34),
      ],
    ),
  );
}

class _MenuButton extends StatelessWidget {
  const _MenuButton(this.label, this.items, this.onSelected);
  final String label;
  final Map<String, String> items;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    onSelected: onSelected,
    tooltip: label,
    itemBuilder: (_) => items.entries
        .map(
          (item) => PopupMenuItem(
            value: item.value,
            child: Text(item.key, style: const TextStyle(fontSize: 12)),
          ),
        )
        .toList(),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xff555761),
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}

class _TrafficLights extends StatelessWidget {
  const _TrafficLights();
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      ColorDot(Color(0xffed6a5e)),
      SizedBox(width: 5),
      ColorDot(Color(0xfff4bd4f)),
      SizedBox(width: 5),
      ColorDot(Color(0xff61c454)),
    ],
  );
}

class ColorDot extends StatelessWidget {
  const ColorDot(this.color);
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class _ToggleIntent extends Intent {
  const _ToggleIntent();
}

class _SkipIntent extends Intent {
  const _SkipIntent(this.direction);
  final int direction;
}

class _VolumeIntent extends Intent {
  const _VolumeIntent(this.delta);
  final double delta;
}

typedef _ScanNative = ffi.IntPtr Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  ffi.UintPtr,
);
typedef _ScanDart = int Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Pointer<ffi.Int8>,
  int,
);

class RustLibrary {
  static List<Map<String, dynamic>> scan(String folder) {
    final candidates = Platform.isLinux
        ? [
            'libsonata_core.so',
            './libsonata_core.so',
            'target/release/libsonata_core.so',
            'rust_core/target/release/libsonata_core.so',
          ]
        : <String>[];
    ffi.DynamicLibrary? library;
    for (final candidate in candidates) {
      try {
        library = ffi.DynamicLibrary.open(candidate);
        break;
      } catch (_) {}
    }
    if (library == null) throw StateError('Rust core is not installed');
    final scan = library.lookupFunction<_ScanNative, _ScanDart>(
      'sonata_scan_json',
    );
    final input = folder.toNativeUtf8().cast<ffi.Int8>();
    final output = calloc<ffi.Int8>(1024 * 1024);
    try {
      final result = scan(input, output, 1024 * 1024);
      if (result < 0) throw StateError('Folder is too large to index');
      final json = output.cast<Utf8>().toDartString();
      return (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    } finally {
      calloc.free(input);
      calloc.free(output);
    }
  }
}
