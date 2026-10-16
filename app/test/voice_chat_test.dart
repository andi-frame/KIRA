import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/features/chat/chat_screen.dart';
import 'package:kira/features/chat/media.dart';

import 'support/fakes.dart';

class FakeRecorder implements VoiceRecorder {
  int starts = 0, stops = 0, cancels = 0;
  bool allowed = true, failStart = false;
  PickedMedia? media = PickedMedia(Uint8List.fromList([1, 2, 3]), 'suara.m4a');
  Completer<bool>? starting;
  Completer<PickedMedia?>? stopping;

  @override
  Future<bool> start() async {
    starts++;
    if (failStart) throw StateError('microphone unavailable');
    return starting == null ? allowed : await starting!.future;
  }

  @override
  Future<PickedMedia?> stop() async {
    stops++;
    return stopping == null ? media : await stopping!.future;
  }

  @override
  Future<void> cancel() async { cancels++; }
}

Future<void> pumpChat(WidgetTester tester, FakeRecorder recorder) async {
  await tester.pumpWidget(testApp(const ChatScreen(), overrides: [
    voiceRecorderProvider.overrideWithValue(recorder),
  ]));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tap starts, releasing keeps recording, next tap stops and sends', (tester) async {
    final recorder = FakeRecorder();
    await pumpChat(tester, recorder);
    await tester.tap(find.byKey(const Key('mic_button')));
    await tester.pumpAndSettle();
    expect(recorder.starts, 1);
    expect(recorder.stops, 0);
    expect(find.textContaining('ketuk stop'), findsOneWidget);
    expect(find.text('Suara diterima.'), findsNothing);
    await tester.tap(find.byKey(const Key('mic_button')));
    await tester.pumpAndSettle();
    expect(recorder.stops, 1);
    expect(find.text('tadi makan nasi padang'), findsOneWidget);
    expect(find.text('Suara diterima.'), findsOneWidget);
  });

  testWidgets('rapid taps cannot start twice or stop twice during transitions', (tester) async {
    final recorder = FakeRecorder()..starting = Completer<bool>()..stopping = Completer<PickedMedia?>();
    await pumpChat(tester, recorder);
    final mic = find.byKey(const Key('mic_button'));
    await tester.tap(mic);
    await tester.pump();
    await tester.tap(mic);
    expect(recorder.starts, 1);
    recorder.starting!.complete(true);
    await tester.pumpAndSettle();
    await tester.tap(mic);
    await tester.pump();
    await tester.tap(mic);
    expect(recorder.stops, 1);
    recorder.stopping!.complete(recorder.media);
    await tester.pumpAndSettle();
    expect(find.text('Suara diterima.'), findsOneWidget);
  });

  testWidgets('permission denied leaves recorder idle', (tester) async {
    final recorder = FakeRecorder()..allowed = false;
    await pumpChat(tester, recorder);
    await tester.tap(find.byKey(const Key('mic_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Izin mikrofon'), findsOneWidget);
    expect(find.textContaining('ketuk stop'), findsNothing);
    expect(recorder.stops, 0);
  });

  testWidgets('empty recording does not send invented user text', (tester) async {
    final recorder = FakeRecorder()..media = null;
    await pumpChat(tester, recorder);
    await tester.tap(find.byKey(const Key('mic_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mic_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('tidak terdengar jelas'), findsOneWidget);
    expect(find.text('Suara diterima.'), findsNothing);
  });

  testWidgets('start failure recovers and leaving screen cancels recording', (tester) async {
    final recorder = FakeRecorder()..failStart = true;
    await pumpChat(tester, recorder);
    await tester.tap(find.byKey(const Key('mic_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Rekaman gagal'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    recorder.failStart = false;
    await tester.tap(find.byKey(const Key('mic_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ketuk stop'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(recorder.cancels, 2);
  });

  testWidgets('leaving during start cancels recording once permission resolves', (tester) async {
    final recorder = FakeRecorder()..starting = Completer<bool>();
    await pumpChat(tester, recorder);
    await tester.tap(find.byKey(const Key('mic_button')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    recorder.starting!.complete(true);
    await tester.pumpAndSettle();
    expect(recorder.cancels, 1);
    expect(tester.takeException(), isNull);
  });
}
