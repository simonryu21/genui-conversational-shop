// SSE 파서 — 조각난 청크 재조립, 멀티라인 data, ping 코멘트 무시 검증.

import 'package:flutter_test/flutter_test.dart';
import 'package:genui_agent/agent/sse_parser.dart';

void main() {
  test('완성된 이벤트 하나를 파싱한다', () {
    final p = SseParser();
    final events = p.addChunk('event: chunk\ndata: 안녕하세요\n\n');
    expect(events, hasLength(1));
    expect(events[0].event, 'chunk');
    expect(events[0].data, '안녕하세요');
  });

  test('임의 위치에서 잘린 청크를 재조립한다', () {
    final p = SseParser();
    expect(p.addChunk('event: ch'), isEmpty);
    expect(p.addChunk('unk\ndata: 부분'), isEmpty);
    final events = p.addChunk('데이터\n\nevent: done\ndata: {"points": 1}\n\n');
    expect(events, hasLength(2));
    expect(events[0].data, '부분데이터');
    expect(events[1].event, 'done');
  });

  test('멀티라인 data를 개행으로 합친다 (A2UI JSON 펜스 전달용)', () {
    final p = SseParser();
    final events =
        p.addChunk('event: chunk\ndata: ```json\ndata: {"a":1}\ndata: ```\n\n');
    expect(events.single.data, '```json\n{"a":1}\n```');
  });

  test('코멘트(ping)는 무시한다', () {
    final p = SseParser();
    expect(p.addChunk(': ping\n\n'), isEmpty);
    final events = p.addChunk(': ping\nevent: chunk\ndata: x\n\n');
    expect(events.single.data, 'x');
  });

  test('CRLF 개행도 처리한다', () {
    final p = SseParser();
    final events = p.addChunk('event: chunk\r\ndata: x\r\n\r\n');
    expect(events.single.data, 'x');
  });
}
