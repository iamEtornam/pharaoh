import 'package:logging/logging.dart';
import 'package:pharaoh/pharaoh.dart';
import 'package:pharaoh_hotreload/src/with_hotreload.dart';

void main() async {
  final app = Pharaoh();

  // final reloader = HotReloader()..addPath('.');
  // reloader.go();
  // print('reloader : ${reloader.vmServiceUrl}');
  // print('reloader : ${reloader.enableHotkeys}');
  // print('reloader : ${reloader.debounceInterval}');
  // print('reloader : ${reloader.isRunning}');
  // print('reloader : ${reloader.registeredPaths}');
  // print('reloader : ${reloader.listeningPaths}');

  app.get('/', (req, res) => res.ok("Hurray 🚀"));

  app.get('/home', (req, res) => res.ok("This goes to the home 🚀"));

  app.get('/about', (req, res) => res.ok("This goes to the about 🚀"));

  withHotreload(
    () => app.listen(),
    logLevel: Level.ALL,
  );
}
