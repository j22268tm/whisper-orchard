import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;
import 'package:whisper_ggml/whisper_ggml.dart';
import 'package:path_provider/path_provider.dart';

class WhisperServer {
  final WhisperModel Function() getModel;
  final String Function() getCustomModelPath;
  final String Function() getSelectedModelName;

  final Function(String) onStatusUpdate;
  final Function() onJobStarted;
  final Function(int timeMs) onJobCompleted;
  final Function(String error) onError;
  final Function(String modelName) onModelPreparationNeeded;

  WhisperServer({
    required this.getModel,
    required this.getCustomModelPath,
    required this.getSelectedModelName,
    required this.onStatusUpdate,
    required this.onJobStarted,
    required this.onJobCompleted,
    required this.onError,
    required this.onModelPreparationNeeded,
  });

  // タイムスタンプ整形用ヘルパー関数
  String _formatTimestamp(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String threeDigits(int n) => n.toString().padLeft(3, '0');

    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    final millis = threeDigits(duration.inMilliseconds.remainder(1000));

    return "$hours:$minutes:$seconds.$millis";
  }

  Future<String> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (var interface in interfaces) {
        if (interface.name.contains('wlan') || interface.name.contains('ap')) {
          return interface.addresses.first.address;
        }
      }
      if (interfaces.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (_) {}
    return "Unknown";
  }

  Future<void> start() async {
    final router = shelf_router.Router();

    router.get('/', (Request request) {
      return Response.ok(
        'Whisper Worker Node Active (Model: ${getSelectedModelName()})',
      );
    });

    router.post('/transcribe', (Request request) async {
      // リクエストIDを生成
      final requestId =
          DateTime.now().millisecondsSinceEpoch.toString() +
          '-' +
          (request.hashCode.abs() % 10000).toString().padLeft(4, '0');
      final serverTime = DateTime.now().toUtc().toIso8601String();

      onJobStarted();
      onStatusUpdate("Receiving audio data...");

      try {
        final currentModel = getModel();
        final currentPath = getCustomModelPath();
        final currentName = getSelectedModelName();

        final payload = await request.read().expand((bit) => bit).toList();
        if (payload.isEmpty) {
          onError("No audio data");
          return Response.badRequest(body: "No audio data");
        }

        onStatusUpdate(
          "Processing (${payload.length} bytes) with $currentName...",
        );

        // モデルファイルの準備確認
        final modelFile = File(currentPath);
        if (!await modelFile.exists()) {
          onStatusUpdate("Preparing model $currentName...");
          await onModelPreparationNeeded(currentName);
        }

        final tempDir = await getTemporaryDirectory();
        final audioPath = '${tempDir.path}/temp_audio';
        final audioFile = File(audioPath);
        await audioFile.writeAsBytes(payload);

        final stopwatch = Stopwatch()..start();

        final whisper = Whisper(model: currentModel);
        final transcription = await whisper.transcribe(
          transcribeRequest: TranscribeRequest(
            audio: audioPath,
            language: 'ja',
            // セグメントのタイムスタンプを有効化
            isNoTimestamps: false,
          ),
          modelPath: currentPath,
        );

        stopwatch.stop();
        final timeMs = stopwatch.elapsedMilliseconds;

        // セグメント情報を整形
        final StringBuffer formattedLog = StringBuffer();
        final List<Map<String, dynamic>> segmentsData = [];
        try {
          final dynamic segments = (transcription as dynamic).segments;
          if (segments is Iterable) {
            // ignore: avoid_print
            try {
              final int count = segments.length;
              print('[whisper_server] segments count: ' + count.toString());
            } catch (_) {}

            for (final seg in segments) {
              final s = seg as dynamic;

              Duration? startDur;
              Duration? endDur;

              dynamic fromVal;
              dynamic toVal;

              // 動的プロパティアクセスが例外を投げる可能性に備えてtryで分岐
              // whisper_ggml exposes Duration as fromTs/toTs
              try {
                fromVal = s.fromTs;
              } catch (_) {}
              if (fromVal == null) {
                try {
                  fromVal = s.from;
                } catch (_) {}
              }
              if (fromVal == null) {
                try {
                  fromVal = s.start;
                } catch (_) {}
              }

              try {
                toVal = s.toTs;
              } catch (_) {}
              if (toVal == null) {
                try {
                  toVal = s.to;
                } catch (_) {}
              }
              if (toVal == null) {
                try {
                  toVal = s.end;
                } catch (_) {}
              }

              if (fromVal is Duration) {
                startDur = fromVal;
              } else if (fromVal is num) {
                startDur = Duration(milliseconds: (fromVal * 1000).round());
              }

              if (toVal is Duration) {
                endDur = toVal;
              } else if (toVal is num) {
                endDur = Duration(milliseconds: (toVal * 1000).round());
              }

              final String startStr = startDur != null
                  ? _formatTimestamp(startDur)
                  : "00:00:00.000";
              final String endStr = endDur != null
                  ? _formatTimestamp(endDur)
                  : "00:00:00.000";

              String text = '';
              try {
                text = (s.text ?? '').toString();
              } catch (_) {
                try {
                  text = s.toString();
                } catch (_) {}
              }
              text = text.trim();

              formattedLog.writeln("[$startStr --> $endStr]  $text");
              segmentsData.add({
                'start': startStr,
                'end': endStr,
                'start_ms': startDur?.inMilliseconds ?? 0,
                'end_ms': endDur?.inMilliseconds ?? 0,
                'text': text,
              });
            }
          }
        } catch (_) {
          // セグメント取得に失敗してもテキストだけ返す
        }

        onJobCompleted(timeMs);
        onStatusUpdate("Success (${timeMs}ms)");

        // Query parameter で formatted_log の同梱を制御
        final includeFormattedLog =
            request.requestedUri.queryParameters['include_formatted_log'] ==
            'true';

        final responseBody = <String, dynamic>{
          'text': (transcription as dynamic).text?.toString() ?? '',
          'time_ms': timeMs,
          'metadata': {
            'model': currentName,
            'language': 'ja',
            'request_id': requestId,
            'server_time': serverTime,
            'segments_count': segmentsData.length,
          },
          'segments': segmentsData,
        };

        if (includeFormattedLog) {
          responseBody['formatted_log'] = formattedLog.toString();
        }

        final body = jsonEncode(responseBody);

        return Response.ok(
          body,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      } catch (e) {
        onError("Error: $e");
        return Response.internalServerError(body: "Error: $e");
      }
    });

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);

    try {
      var server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8080);
      String ip = await getLocalIpAddress();
      onStatusUpdate("Server Ready at $ip:${server.port}");
    } catch (e) {
      onError("Server Start Error: $e");
    }
  }
}
