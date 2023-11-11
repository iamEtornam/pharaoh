import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'http/request.dart';

HTTPMethod getHttpMethod(HttpRequest req) {
  switch (req.method) {
    case 'GET' || 'HEAD':
      return HTTPMethod.GET;
    case 'POST':
      return HTTPMethod.POST;
    case 'PUT':
      return HTTPMethod.PUT;
    case 'DELETE':
      return HTTPMethod.DELETE;
    default:
      throw Exception('Method ${req.method} not yet supported');
  }
}

String encodeJson(dynamic data) {
  if (data == null) {
    return 'null';
  } else if (data is Map) {
    return jsonEncode(data);
  }
  return data;
}

/// Run [callback] and capture any errors that would otherwise be top-leveled.
///
/// If `this` is called in a non-root error zone, it will just run [callback]
/// and return the result. Otherwise, it will capture any errors using
/// [runZoned] and pass them to [onError].
void catchTopLevelErrors(void Function() callback,
    void Function(dynamic error, StackTrace) onError) {
  if (Zone.current.inSameErrorZone(Zone.root)) {
    return runZonedGuarded(callback, onError);
  } else {
    return callback();
  }
}
