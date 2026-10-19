/// 웹용 플랫폼 분기.
library;

import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;

/// 기본 BrowserClient(XHR)는 응답 바디 스트리밍이 안 되므로
/// fetch + ReadableStream 기반 FetchClient를 사용한다.
http.Client createStreamingClient() => FetchClient(mode: RequestMode.cors);

bool get isFlutterTest => false;
