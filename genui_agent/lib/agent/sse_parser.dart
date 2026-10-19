/// 표준 SSE(text/event-stream) 파서 — 순수 Dart (VM 테스트 가능).
///
/// 바이트/문자 청크가 임의 위치에서 잘려 도착해도 이벤트 경계(빈 줄)로 재조립한다.
/// `:`로 시작하는 코멘트 라인(keepalive ping)은 무시한다.
library;

class SseEvent {
  SseEvent(this.event, this.data);

  final String event;
  final String data;
}

class SseParser {
  final StringBuffer _buffer = StringBuffer();

  /// 수신 텍스트 조각을 넣고, 완성된 이벤트들을 반환한다.
  List<SseEvent> addChunk(String chunk) {
    _buffer.write(chunk);
    final text = _buffer.toString().replaceAll('\r\n', '\n');
    final events = <SseEvent>[];

    var start = 0;
    while (true) {
      final sep = text.indexOf('\n\n', start);
      if (sep < 0) break;
      final block = text.substring(start, sep);
      start = sep + 2;

      String event = 'message';
      final dataLines = <String>[];
      for (final line in block.split('\n')) {
        if (line.startsWith(':')) continue; // 코멘트(ping)
        if (line.startsWith('event:')) {
          event = line.substring(6).trimLeft();
        } else if (line.startsWith('data:')) {
          var v = line.substring(5);
          if (v.startsWith(' ')) v = v.substring(1);
          dataLines.add(v);
        }
      }
      if (dataLines.isNotEmpty || event != 'message') {
        events.add(SseEvent(event, dataLines.join('\n')));
      }
    }

    _buffer
      ..clear()
      ..write(text.substring(start));
    return events;
  }
}
