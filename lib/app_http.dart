import 'dart:async';
import 'package:http/http.dart' as raw_http;

export 'package:http/http.dart'
    show
        BaseRequest,
        BaseResponse,
        ByteStream,
        Client,
        ClientException,
        MultipartFile,
        MultipartRequest,
        Response,
        StreamedResponse;

const String kAppSecretKey = 'bf_tracker_4b5c6d7e8f9a0b1c';

Future<Map<String, String>> _prepareHeaders(
  Uri url,
  Map<String, String>? headers,
) async {
  final map = headers != null
      ? Map<String, String>.from(headers)
      : <String, String>{};
  if (!map.containsKey('Content-Type')) {
    map['Content-Type'] = 'application/json';
  }
  if (!map.containsKey('x-app-secret')) {
    map['x-app-secret'] = kAppSecretKey;
    map['x-app-key'] = kAppSecretKey;
  }
  return map;
}

Future<raw_http.Response> get(Uri url, {Map<String, String>? headers}) async {
  final resolvedHeaders = await _prepareHeaders(url, headers);
  return raw_http.get(url, headers: resolvedHeaders);
}

Future<raw_http.Response> post(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
}) async {
  final resolvedHeaders = await _prepareHeaders(url, headers);
  return raw_http.post(url, headers: resolvedHeaders, body: body);
}

Future<raw_http.Response> put(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
}) async {
  final resolvedHeaders = await _prepareHeaders(url, headers);
  return raw_http.put(url, headers: resolvedHeaders, body: body);
}

Future<raw_http.Response> patch(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
}) async {
  final resolvedHeaders = await _prepareHeaders(url, headers);
  return raw_http.patch(url, headers: resolvedHeaders, body: body);
}

Future<raw_http.Response> delete(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
}) async {
  final resolvedHeaders = await _prepareHeaders(url, headers);
  return raw_http.delete(url, headers: resolvedHeaders, body: body);
}
