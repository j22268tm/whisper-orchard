import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;
import 'package:whisper_ggml/whisper_ggml.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _statusLog = "初期化中...";
  String _ipAddress = "取得中...";

  final WhisperController _whisperController = WhisperController();
  WhisperModel _model = WhisperModel.base;
  List<WhisperModel> _availableModels = [];
  bool _isModelLoaded = false;

  @override
  void initState() {
    super.initState();
    _initWhisper();
  }

  // モデル準備（assets から配置 or ダウンロード）
  Future<void> _initWhisper() async {
    try {
      setState(() => _statusLog = "モデル準備中...");

      // 利用可能なモデルを assets から検出し、既定を選択
      _availableModels = await _discoverAvailableModels();
      if (_availableModels.isNotEmpty) {
        _model = _availableModels.contains(WhisperModel.base)
            ? WhisperModel.base
            : _availableModels.first;
      }

      // 選択中モデルを準備
      await _prepareModel(_model);

      // バージョン確認（任意）
      try {
        final w = Whisper(model: _model);
        final version = await w.getVersion();
        debugPrint("Whisper Version: $version");
      } catch (e) {
        debugPrint("Version check skipped: $e");
      }

      setState(() {
        _isModelLoaded = true;
        _statusLog = "モデルロード完了\nサーバー起動待機...";
      });

      // サーバー起動
      _startServer();
    } catch (e) {
      setState(() {
        _statusLog = "モデル読込エラー";
      });
      debugPrint(e.toString());
    }
  }

  Future<List<WhisperModel>> _discoverAvailableModels() async {
    final List<WhisperModel> found = [];
    for (final m in WhisperModel.values) {
      try {
        await rootBundle.load('assets/ggml-${m.modelName}.bin');
        found.add(m);
      } catch (_) {
        // ignore
      }
    }
    return found;
  }

  Future<void> _prepareModel(WhisperModel model) async {
    try {
      final bytes = await rootBundle.load('assets/ggml-${model.modelName}.bin');
      final modelPath = await _whisperController.getPath(model);
      final file = File(modelPath);
      await file.create(recursive: true);
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      debugPrint('Model placed from assets: $modelPath');
    } catch (_) {
      final path = await _whisperController.downloadModel(model);
      debugPrint('Model downloaded to: $path');
    }
  }

  // IPアドレス取得
  Future<String> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (var interface in interfaces) {
        // Wi-Fiを優先させる
        if (interface.name.contains('wlan') || interface.name.contains('ap')) {
          for (var addr in interface.addresses) {
            return addr.address;
          }
        }
      }
      if (interfaces.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (e) {
      debugPrint("IP取得エラー: $e");
    }
    return "不明";
  }

  // Webサーバー
  Future<void> _startServer() async {
    final router = shelf_router.Router();

    router.get('/', (Request request) {
      return Response.ok('Whisper Worker (New Lib) is Active.');
    });

    // 推論エンドポイント
    router.post('/transcribe', (Request request) async {
      if (!_isModelLoaded) {
        return Response.internalServerError(body: "Model not ready");
      }

      try {
        // 音声データの受信
        final payload = await request.read().expand((bit) => bit).toList();
        if (payload.isEmpty) {
          return Response.badRequest(body: "No audio data");
        }

        setState(() => _statusLog = "音声受信 (${payload.length} bytes)...");

        // 一時ファイルに保存
        final tempDir = await getTemporaryDirectory();
        final audioPath = '${tempDir.path}/temp_audio';
        final audioFile = File(audioPath);
        await audioFile.writeAsBytes(payload);

        setState(() => _statusLog = "推論中...");
        final stopwatch = Stopwatch()..start();

        // Whisper実行（whisper_ggml のコントローラを使用）
        final result = await _whisperController.transcribe(
          model: _model,
          audioPath: audioPath,
          lang: 'ja',
        );

        stopwatch.stop();
        final time = stopwatch.elapsedMilliseconds;

        if (result == null) {
          setState(() => _statusLog = "エラー: 変換に失敗");
          return Response.internalServerError(body: "Transcription failed");
        }

        final String textResult = result.transcription.text;

        setState(() => _statusLog = "完了 (${time}ms)\n$textResult");

        return Response.ok(
          '{"text": "$textResult", "time_ms": $time}',
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      } catch (e) {
        setState(() => _statusLog = "エラー: $e");
        debugPrint(e.toString());
        return Response.internalServerError(body: "Error: $e");
      }
    });

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);

    try {
      var server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8080);
      String ip = await _getLocalIpAddress();

      setState(() {
        _ipAddress = ip;
        _statusLog = "待機中...\n$ip:${server.port}";
      });
    } catch (e) {
      setState(() => _statusLog = "サーバー起動エラー: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Whisper Worker Node'),
          backgroundColor: Colors.orange,
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                if (_availableModels.isNotEmpty)
                  Row(
                    children: [
                      const Text('モデル選択:'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<WhisperModel>(
                          isExpanded: true,
                          value: _model,
                          items: _availableModels
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m,
                                  child: Text('ggml-${m.modelName}.bin'),
                                ),
                              )
                              .toList(),
                          onChanged: (m) async {
                            if (m == null) return;
                            setState(() {
                              _model = m;
                              _isModelLoaded = false;
                              _statusLog = 'モデル切替中...';
                            });
                            await _prepareModel(m);
                            setState(() {
                              _isModelLoaded = true;
                              _statusLog = 'モデルロード完了 (ggml-${m.modelName}.bin)';
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                Icon(
                  _isModelLoaded ? Icons.speaker_notes : Icons.hourglass_empty,
                  size: 80,
                  color: _isModelLoaded ? Colors.green : Colors.grey,
                ),
                const SizedBox(height: 20),
                Text(
                  "IP: $_ipAddress",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),

                // ElevatedButton(
                //   onPressed: _isModelLoaded
                //       ? () async {
                //           final Directory appSupportDir =
                //               await getApplicationSupportDirectory();
                //           await _deleteModelFiles(
                //               WhisperModel.base, appSupportDir.path);
                //         }
                //       : null,
                //   child: const Text("Delete Model Files"),
                // ),
                const SizedBox(height: 20),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  color: Colors.black12,
                  child: Text(_statusLog),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
