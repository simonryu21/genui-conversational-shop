/// IO(데스크톱/VM 테스트)용 플랫폼 분기.
library;

import 'dart:io';

import 'package:http/http.dart' as http;

/// 기본 http.Client는 IO에서 응답 스트리밍을 지원한다.
http.Client createStreamingClient() => http.Client();

/// `flutter test`(VM) 실행 여부 — 위젯 테스트는 scripted 모드로 돌아야 한다.
bool get isFlutterTest => Platform.environment.containsKey('FLUTTER_TEST');
