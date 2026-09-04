// lib/services/url_scheme_service.dart
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

class CallRequest {
  final String name;
  final String company;
  final String? todoId;

  const CallRequest({required this.name, required this.company, this.todoId});

  @override
  String toString() => 'CallRequest(name:$name, company:$company, todoId:$todoId)';
}

class UrlSchemeService {
  static final UrlSchemeService instance = UrlSchemeService._internal();
  UrlSchemeService._internal();

  final AppLinks _appLinks = AppLinks();
  Function(CallRequest)? onCallRequest;

  Future<void> initialize() async {
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) _handleUri(initialUri);

    _appLinks.uriLinkStream.listen(
      (Uri uri) => _handleUri(uri),
      onError: (err) => debugPrint('URLスキームエラー: $err'),
    );
  }

  void _handleUri(Uri uri) {
    debugPrint('受信URI: $uri');
    if (uri.scheme != 'namecard') return;
    if (uri.host != 'call') return;

    final name = uri.queryParameters['name'] ?? '';
    final company = uri.queryParameters['company'] ?? '';
    final todoId = uri.queryParameters['todoId'];

    if (name.isEmpty) return;

    final request = CallRequest(name: name, company: company, todoId: todoId);
    debugPrint('CallRequest生成: $request');
    onCallRequest?.call(request);
  }

  static String buildCallUrl({
    required String name, required String company, String? todoId}) {
    final params = <String, String>{
      'name': name, 'company': company,
      if (todoId != null) 'todoId': todoId,
    };
    return Uri(scheme: 'namecard', host: 'call', queryParameters: params).toString();
  }
}
