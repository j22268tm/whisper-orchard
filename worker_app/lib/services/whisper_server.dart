import 'dart:io';
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
          ),
          modelPath: currentPath,
        );

        stopwatch.stop();
        final timeMs = stopwatch.elapsedMilliseconds;

        onJobCompleted(timeMs);
        onStatusUpdate("Success (${timeMs}ms)");

        return Response.ok(
          '{"text": "${transcription.text}", "time_ms": $timeMs}',
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
