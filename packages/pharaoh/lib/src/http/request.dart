import 'dart:io';

import 'package:http_parser/http_parser.dart';

import '../middleware/session_mw.dart';
import '../utils/exceptions.dart';
import 'message.dart';

// ignore: constant_identifier_names
enum HTTPMethod { GET, HEAD, POST, PUT, DELETE, ALL, PATCH, OPTIONS, TRACE }

HTTPMethod getHttpMethod(HttpRequest req) => switch (req.method) {
      'GET' => HTTPMethod.GET,
      'HEAD' => HTTPMethod.HEAD,
      'POST' => HTTPMethod.POST,
      'PUT' => HTTPMethod.PUT,
      'DELETE' => HTTPMethod.DELETE,
      'PATCH' => HTTPMethod.PATCH,
      'OPTIONS' => HTTPMethod.OPTIONS,
      'TRACE' => HTTPMethod.TRACE,
      _ => throw PharaohException('Method ${req.method} not yet supported')
    };

abstract interface class $Request<T> {
  Uri get uri;

  String get path;

  Map<String, dynamic> get query;

  String get ipAddr;

  String? get hostname;

  String get protocol;

  String get protocolVersion;

  dynamic get auth;

  HTTPMethod get method;

  Map<String, dynamic> get params;

  Map<String, dynamic> get headers;

  List<Cookie> get cookies;

  List<Cookie> get signedCookies;

  String? get sessionId;

  Session? get session;

  T? get body;

  Object? operator [](String name);
}

class RequestContext {
  static const String phar = 'phar';
  static const String auth = '$phar.auth';

  /// cookies & session
  static const String cookies = '$phar.cookies';
  static const String signedCookies = '$phar.signedcookies';
  static const String session = '$phar.session.cookie';
  static const String sessionId = '$phar.session.id';
}

class Request extends Message<dynamic> implements $Request<dynamic> {
  final HttpRequest _req;
  final Map<String, dynamic> _params = {};
  final Map<String, dynamic> _context = {};

  Request._(this._req) : super(_req, headers: {}) {
    req.headers.forEach((name, values) => headers[name] = values);
    headers.remove(HttpHeaders.transferEncodingHeader);
  }

  factory Request.from(HttpRequest request) => Request._(request);

  HttpRequest get req => _req;

  void putInContext(String key, Object object) => _context[key] = object;

  void setParams(String key, String value) => _params[key] = value;

  /// If this is non-`null` and the requested resource hasn't been modified
  /// since this date and time, the server should return a 304 Not Modified
  /// response.
  ///
  /// This is parsed from the If-Modified-Since header in [headers]. If
  /// [headers] doesn't have an If-Modified-Since header, this will be `null`.
  ///
  /// Throws [FormatException], if incoming HTTP request has an invalid
  /// If-Modified-Since header.
  DateTime? get ifModifiedSince {
    if (_ifModifiedSinceCache != null) return _ifModifiedSinceCache;
    if (!headers.containsKey('if-modified-since')) return null;
    _ifModifiedSinceCache = parseHttpDate(headers['if-modified-since']!);
    return _ifModifiedSinceCache;
  }

  DateTime? _ifModifiedSinceCache;

  @override
  Uri get uri => _req.uri;

  @override
  String get path => _req.uri.path;

  @override
  String get ipAddr => _req.connectionInfo?.remoteAddress.address ?? 'Unknown';

  @override
  HTTPMethod get method => getHttpMethod(_req);

  @override
  Map<String, dynamic> get params => _params;

  @override
  Map<String, dynamic> get query => _req.uri.queryParameters;

  @override
  String? get hostname => _req.headers.host;

  @override
  String get protocol => _req.requestedUri.scheme;

  @override
  String get protocolVersion => _req.protocolVersion;

  @override
  List<Cookie> get cookies => _context[RequestContext.cookies] ?? [];

  @override
  List<Cookie> get signedCookies => _context[RequestContext.signedCookies] ?? [];

  @override
  Session? get session => _context[RequestContext.session];

  @override
  String? get sessionId => _context[RequestContext.sessionId];

  @override
  Object? operator [](String name) => _context[name];

  void operator []=(String name, dynamic value) {
    _context[name] = value;
  }

  @override
  dynamic get auth => _context[RequestContext.auth];

  set auth(dynamic value) => _context[RequestContext.auth] = value;
}
