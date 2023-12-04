import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:charcode/charcode.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:watcher/watcher.dart';

const String _kVmServiceUrl = 'ws://127.0.0.1:8181/ws';

/// Encapsulates Hot reloader path
class HotReloaderPath {
  /// [HotReloader] the path belongs to
  final HotReloader reloader;

  /// [path] being watched
  String get path => watcher.path;

  /// The watcher
  final Watcher watcher;

  /// Subscription
  StreamSubscription<WatchEvent>? _sub;

  HotReloaderPath._(this.reloader, String path) : watcher = Watcher(path);

  /// Is this path being watched
  bool get isWatching => _sub != null;

  /// Stops watching
  Future _stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}

/// Hot reloader
///
///     final reloader = new HotReloader();
///     reloader.addPath('.');
///     await reloader.go();
///
/// ## VM services
/// Hot reloading requires that VM service is enabled! VM services can be
/// started by passing `--enable-vm-service` or `--observe` command line flags
/// while starting the application.
///
/// `--enable-vm-service=<port>/<IP address>` and `--enable-vm-service=<port>`
/// can be used to start VM services at desired address.
///
/// More information can be found at:
/// https://www.dartlang.org/dart-vm/tools/dart-vm
class HotReloader {
  /// The URL of the Dart VM service.
  ///
  /// This is used to connect to Dart VM service to request hot reloading.
  ///
  /// Hot reloading requires that VM service is enabled! VM services can be
  /// started by passing `--enable-vm-service` or `--observe` command line flags
  /// while starting the application.
  ///
  /// `--enable-vm-service=<port>/<IP address>` and `--enable-vm-service=<port>`
  /// can be used to start VM services at desired address.
  ///
  /// More information can be found at:
  /// https://www.dartlang.org/dart-vm/tools/dart-vm
  final String vmServiceUrl;

  /// Debounce interval for [onChange] event
  final Duration debounceInterval;

  /// If `true` (default), then developers can `press 'r' to reload` the application on-the-fly.
  ///
  /// This option triggers printing a Flutter-like output to the terminal.
  final bool enableHotkeys;

  /// Stream controller to fire events when any of the file being listened to
  /// changes
  final StreamController<WatchEvent> _onChange =
      StreamController<WatchEvent>.broadcast();

  /// Stream that is fired when any of the file being listened to changes
  Stream<WatchEvent> get onChange => _onChange.stream;

  /// Stream controller to fire events when the application is reloaded
  final StreamController<DateTime> _onReload =
      StreamController<DateTime>.broadcast();

  /// Stream that is fired after the application is reloaded
  Stream<DateTime> get onReload => _onReload.stream;

  /// Stream subscription for [_onChange]
  StreamSubscription? _onChangeSub;

  /// Private variable to track if the hot reloader is running
  final bool _isRunning = false;

  /// Is the hot reloader running?
  bool get isRunning => _isRunning;

  /// Store for registered paths
  final Set<String> _registeredPaths = <String>{};

  /// Store for built [HotReloaderPath]s
  final Map<String, HotReloaderPath> _builtPaths = <String, HotReloaderPath>{};

  /// Creates a [HotReloader] with given [vmServiceUrl]
  ///
  /// By default, [vmServiceUrl] uses `ws://localhost:8181/ws`
  HotReloader(
      {this.vmServiceUrl = _kVmServiceUrl,
      this.enableHotkeys = true,
      this.debounceInterval = const Duration(seconds: 1)}) {
    if (!isHotReloadable) throw notHotReloadable;

    _onChangeSub = onChange
        .transform(_FoldedDebounce(debounceInterval))
        .listen((events) async {
      final sb = StringBuffer()
        ..write('Paths ')
        ..write(events.map((event) => event.path).join(', '))
        ..write(' changed!');
      print(sb.toString());
      await go();
    });
  }

  /// Is the application hot reloadable?
  ///
  /// Hot reloading requires that VM service is enabled! VM services can be
  /// started by passing `--enable-vm-service` or `--observe` command line flags
  /// while starting the application.
  ///
  /// `--enable-vm-service=<port>/<IP address>` and `--enable-vm-service=<port>`
  /// can be used to start VM services at desired address.
  ///
  /// More information can be found at:
  /// https://www.dartlang.org/dart-vm/tools/dart-vm
  static bool get isHotReloadable =>
      Platform.executableArguments.contains('--observe') ||
      Platform.executableArguments
          .any((arg) => arg.startsWith('--enable-vm-service'));

  /// Go! Start listening for changes to files in registered paths
  ///
  /// If already running, restarts the hot reloader
  Future<void> go() async {
    // If already killed, provide an explanation for failure
    if (_onChange.isClosed) throw alreadyKilled;

    // If currently running, restart
    if (_isRunning) {
      await stop();
    }

    final hps = <String, HotReloaderPath>{};

    for (final path in _registeredPaths) {
      final resolvedPath = await _resolvePath(path);
      if (resolvedPath != null) {
        hps[path] = HotReloaderPath._(this, resolvedPath);
      }
    }

    _builtPaths
      ..clear()
      ..addAll(hps);

    print(
        '\n🚀🚀🚀  To hot reload changes while running, press "r". To hot restart (and rebuild state), press "R".');

    for (final hp in _builtPaths.values) {
      // ignore: avoid_types_on_closure_parameters
      hp._sub = hp.watcher.events.listen(_onChange.add, onError: (Object e) {
        stderr.writeln('Error listening to file changes at ${hp.path}: $e');
      });
      print('Listening for file changes at ${hp.path}/');
    }

    // Listen for hotkeys
      // Listen for hotkeys
    try {
      stdin.lineMode = stdin.echoMode = false;
    } catch (_) {}

    late StreamSubscription<int> sub;

    try {
      sub = stdin.expand((l) => l).listen((ch) async {
        if (ch == $R || ch == $r) {
          print('🛠️🔥 Manually hot reloading server...\n');
          await go();
        } else if (ch == $q) {
          stdin.echoMode = stdin.lineMode = true;
          await sub.cancel();
          await kill();
          exit(0);
        } else if (ch == $h) {
          print(
              'Press "r" or "R" to hot reload the Dart VM, and restart the active server.');
          print('Press "q" to quit the server.');
          print('Press "h" to display this help information.');
          stdout.writeln();
        }
      });
    } catch (error) {
      print('🚫 Error hot reloading server: $error');
      rethrow;
    }
  }

  /// Stops listening for file system changes
  Future<void> stop() async {
    for (final hp in _builtPaths.values) {
      await hp._stop();
    }

    _builtPaths.clear();
  }

  /// Completely kills the hot reloader. Shall not be used, once it is killed!
  Future<void> kill() async {
    if (_onChange.isClosed) return;

    await _onChange.close();
    await _onChangeSub?.cancel();
    _onChangeSub = null;

    await _onReload.close();

    await stop();
  }

  /// Registers a [path] to watch
  ///
  ///    main() async {
  ///      final reloader = new HotReloader();
  ///      reloader.addPath('lib/');
  ///      await reloader.go();
  ///
  ///      // Your code goes here
  ///    }
  void addPath(String path) => _registeredPaths.add(path);

  /// Registers [glob] to watch
  ///
  ///    main() async {
  ///      final reloader = new HotReloader();
  ///      reloader.addGlob(new Glob('pharaoh_*/lib'));
  ///      await reloader.go();
  ///
  ///      // Your code goes here
  ///    }
  void addGlob(Glob glob) {
    glob.listSync().forEach(addFile);
  }

  /// Registers [FileSystemEntity] to watch
  ///
  ///    main() async {
  ///      final reloader = new HotReloader();
  ///      reloader.addFile(new File('pubspec.yaml'));
  ///      await reloader.go();
  ///
  ///      // Your code goes here
  ///    }
  void addFile(FileSystemEntity entity) => addPath(entity.path);

  /// Registers [Uri] to watch
  ///
  ///    main() async {
  ///      final reloader = new HotReloader();
  ///      reloader.addUri(new Uri(scheme: 'file', path: '/usr/lib/dart'));
  ///      await reloader.go();
  ///
  ///      // Your code goes here
  ///    }
  void addUri(Uri uri) => addPath(uri.toFilePath());

  /// Registers package [uri] to watch
  ///
  /// If schema of the [uri] is not `'package'`, throws [notPackageUri]
  /// If package uri cannot be resolved, throws [packageNotFound]
  ///
  ///    main() async {
  ///      final reloader = HotReloader();
  ///      await reloader.addPackagePath(new Uri(scheme: 'package', path: 'pharaoh/'));
  ///      await reloader.go();
  ///
  ///      // Your code goes here
  ///    }
  Future addPackagePath(Uri uri) async {
    if (!uri.isScheme('package')) throw notPackageUri;
    final packageUri = await Isolate.resolvePackageUri(uri);
    if (packageUri == null) throw packageNotFound;
    addPath(packageUri.toFilePath());
  }

  /// Registers all packages the `.packages` file contains
  ///
  ///    main() async {
  ///      final reloader = HotReloader();
  ///      await reloader.addPackageDependencies();
  ///      await reloader.go();
  ///
  ///      // Your code goes here
  ///    }
  Future addPackageDependencies([String packageFilePath = '.packages']) async {
    final file = File(packageFilePath);
    if (!file.existsSync()) throw Exception('Packages file not found!');
    final lines = await file.readAsLines();
    final packages = lines
        .where((line) => !line.startsWith('#'))
        .map((line) => line.split(':').first)
        .toList();

    for (final package in packages) {
      await addPackagePath(Uri(scheme: 'package', path: '$package/'));
    }
  }

  /// Exception thrown when supplied package uri is not a package uri
  static final Exception notPackageUri = Exception('Not a package Uri!');

  /// Exception thrown when package is not found
  static final Exception packageNotFound = Exception('Package not found!');

  /// Exception thrown when hot reloader is already killed
  static final Exception alreadyKilled =
      Exception('Hot reloader killed! Create new one!');

  static final Exception notHotReloadable = Exception(_msg);

  static const String _msg = '''
Hot reloading requires `--enable-vm-service` or `--observe` command line flags to the Dart VM!
More information can be found at: https://www.dartlang.org/dart-vm/tools/dart-vm
  ''';

  /// Returns all the registered paths
  List<String> get registeredPaths => _registeredPaths.toList();

  /// Returns all the paths being listened to
  ///
  /// Returns empty list, when the hot reloader is not listening
  List<String> get listeningPaths => _builtPaths.keys.toList();

  /// Returns if [path] is being listened to
  bool isListeningTo(String path) => _builtPaths.containsKey(path);

  /// Resolves the given path
  ///
  /// If [path] is link, it resolves the link
  /// If the [path] is not found, `null` is returned
  Future<String?> _resolvePath(String path) async {
    try {
      final stat = await FileStat.stat(path);
      if (stat.type == FileSystemEntityType.link) {
        final lnk = Link(path);
        final p = await lnk.resolveSymbolicLinks();
        return await _resolvePath(p);
      } else if (stat.type == FileSystemEntityType.file) {
        final file = File(path);
        if (!file.existsSync()) return null;
      } else if (stat.type == FileSystemEntityType.directory) {
        final dir = Directory(path);
        if (!await dir.exists()) return null;
      } else {
        return null;
      }
      return path;
    } catch (e) {
      if (e is! FileSystemException) rethrow;
    }

    return null;
  }
}

/// Debouncer to combine all [WatchEvent]s between [interval] into one event
class _FoldedDebounce
    extends StreamTransformerBase<WatchEvent, List<WatchEvent>> {
  final Duration interval;

  _FoldedDebounce(this.interval);

  @override
  Stream<List<WatchEvent>> bind(Stream<WatchEvent> stream) {
    // List to hold items between intervals
    var values = <WatchEvent>[];
    // Tracks when next interval ends
    var next = DateTime.now().subtract(interval);

    return stream.map((e) {
      values.add(e);
      return values;
    }).where((value) {
      final now = DateTime.now();
      if (now.isBefore(next)) {
        return false;
      }

      next = now.add(interval);
      values = <WatchEvent>[];
      return true;
    }).timeout(interval, onTimeout: (sink) {
      if (values.isEmpty) return;
      next = DateTime.now().add(interval);
      final tempValues = values;
      values = <WatchEvent>[];
      sink.add(tempValues);
    });
  }
}
