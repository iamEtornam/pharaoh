import 'package:pharaoh/pharaoh.dart';
import 'package:pharaoh_static/pharaoh_static.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

final app = Pharaoh();

final serveStatic = createStaticHandler(
  'public/web_demo_2',
  defaultDocument: 'index.html',
);

final cors = corsHeaders();

void main() async {
  app.use(logRequests);

  app.use(useShelfMiddleware(cors));

  app.use(serveStatic);

  await app.listen();
}
