import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:whisper_ggml/whisper_ggml.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';

import 'screens/dashboard_screen.dart';
import 'screens/model_management_screen.dart';
import 'services/whisper_server.dart';

Future<void> main() async {
  debugPrint('[main] Initializing Flutter bindings...');
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('[main] Pre-initializing path_provider...');
  try {
    await getApplicationSupportDirectory();
    debugPrint('[main] path_provider initialized successfully');
  } catch (e) {
    debugPrint(
      '[main] path_provider pre-initialization failed (will retry later): $e',
    );
  }

  debugPrint('[main] Starting app...');
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with SingleTickerProviderStateMixin {
  // タブコントローラー
  late TabController _tabController;

  // システム状態
  String _statusLog = "初期化中...";
  String _ipAddress = "取得中...";
  bool _isModelLoaded = false;

  // Whisper関連
  WhisperModel _model = WhisperModel.base;
  String _customModelPath = '';
  String _selectedModelName = 'base';
  List<String> _availableModelNames = [];

  // ダッシュボード用メトリクス
  int _jobsServed = 0;
  int _pendingJobs = 0;
  int _avgLatency = 0;
  DateTime? _lastRequestTime;
  List<int> _latencyHistory = [];

  // ダウンロード進捗管理
  Map<String, double> _downloadProgress = {};
  Set<String> _downloadedModels = {};
  Set<String> _downloadCompleted = {};

  // グラフ用データ
  List<FlSpot> _graphSpots = [];
  Timer? _graphTimer;

  @override
  void initState() {
    super.initState();
    debugPrint('[initState] Starting initialization...');
    _tabController = TabController(length: 2, vsync: this);
    _startGraphTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[initState] PostFrameCallback executed');
      _initWhisper();
      _checkDownloadedModels();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _graphTimer?.cancel();
    super.dispose();
  }

  // ダウンロード済みモデルをチェック
  Future<void> _checkDownloadedModels() async {
    debugPrint('[_checkDownloadedModels] Checking downloaded models...');
    try {
      final dir = await WhisperController.getModelDir();
      debugPrint('[_checkDownloadedModels] Model dir: $dir');

      final allModels = [
        ...WhisperModel.values.map((m) => m.modelName),
        'tiny-q5_1',
        'tiny-q8_0',
        'tiny.en-q5_1',
        'tiny.en-q8_0',
        'base-q5_1',
        'base-q8_0',
        'base.en-q5_1',
        'base.en-q8_0',
        'small-q5_1',
        'small-q8_0',
        'small.en-q5_1',
        'small.en-q8_0',
        'small.en-tdrz',
        'medium-q5_0',
        'medium-q8_0',
        'medium.en-q5_0',
        'medium.en-q8_0',
        'large-v1',
        'large-v2',
        'large-v2-q5_0',
        'large-v2-q8_0',
        'large-v3-q5_0',
        'large-v3-turbo',
        'large-v3-turbo-q5_0',
        'large-v3-turbo-q8_0',
      ];

      for (final modelName in allModels) {
        final file = File('$dir/ggml-$modelName.bin');
        if (await file.exists()) {
          setState(() => _downloadedModels.add(modelName));
        }
      }
    } catch (e) {
      debugPrint(
        '[_checkDownloadedModels] WhisperController.getModelDir() failed: $e',
      );
    }
    debugPrint(
      '[_checkDownloadedModels] Downloaded models: $_downloadedModels',
    );
  }

  // グラフを定期更新するタイマー
  void _startGraphTimer() {
    for (int i = 0; i < 20; i++) {
      _graphSpots.add(FlSpot(i.toDouble(), 0));
    }

    _graphTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) return;
      setState(() {
        _graphSpots.removeAt(0);
        double load = _pendingJobs.toDouble() * 5 + (Random().nextDouble() * 2);
        List<FlSpot> newSpots = [];
        for (int i = 0; i < _graphSpots.length; i++) {
          newSpots.add(FlSpot(i.toDouble(), _graphSpots[i].y));
        }
        newSpots.add(FlSpot(19.0, load));
        _graphSpots = newSpots;
      });
    });
  }

  // Whisper初期化
  Future<void> _initWhisper() async {
    debugPrint('[_initWhisper] Starting Whisper initialization...');

    bool pathProviderReady = false;
    for (int i = 0; i < 10; i++) {
      try {
        debugPrint(
          '[_initWhisper] Attempting to access model dir (attempt ${i + 1}/10)...',
        );
        await WhisperController.getModelDir();
        debugPrint('[_initWhisper] Model dir accessible!');
        pathProviderReady = true;
        break;
      } catch (e) {
        debugPrint(
          '[_initWhisper] Model dir not ready yet (attempt ${i + 1}/10): $e',
        );
        if (i < 9) {
          await Future.delayed(Duration(milliseconds: 200 * (i + 1)));
        }
      }
    }

    if (!pathProviderReady) {
      debugPrint(
        '[_initWhisper] path_provider failed to initialize after 10 attempts',
      );
      if (mounted) {
        setState(() => _statusLog = "初期化エラー: path_provider未対応");
      }
      return;
    }

    try {
      debugPrint('[_initWhisper] Discovering model files...');
      if (mounted) {
        setState(() => _statusLog = "モデル検出中...");
      }

      _availableModelNames = await _discoverModelFiles();
      debugPrint(
        '[_initWhisper] Found ${_availableModelNames.length} models: $_availableModelNames',
      );

      if (_availableModelNames.isNotEmpty) {
        _selectedModelName = _availableModelNames.first;
        debugPrint('[_initWhisper] Selected model: $_selectedModelName');

        final dir = await WhisperController.getModelDir();
        _customModelPath = '$dir/ggml-$_selectedModelName.bin';
        debugPrint('[_initWhisper] Model path: $_customModelPath');

        final matchingEnum = WhisperModel.values
            .cast<WhisperModel?>()
            .firstWhere(
              (m) => m?.modelName == _selectedModelName,
              orElse: () => null,
            );
        if (matchingEnum != null) {
          _model = matchingEnum;
          debugPrint('[_initWhisper] Model enum: ${_model.modelName}');
        }
      } else {
        debugPrint('[_initWhisper] No models found!');
      }

      if (mounted) {
        setState(() {
          _isModelLoaded = true;
          _statusLog = "Ready. Waiting for requests...";
        });
      }

      debugPrint('[_initWhisper] Starting server...');
      _startServer();
      debugPrint('[_initWhisper] Initialization complete!');
    } catch (e, stackTrace) {
      debugPrint('[_initWhisper] Error during initialization: $e');
      debugPrint('[_initWhisper] Stack trace: $stackTrace');
      if (mounted) {
        setState(() => _statusLog = "モデル読込エラー: $e");
      }
    }
  }

  Future<List<String>> _discoverModelFiles() async {
    debugPrint('[_discoverModelFiles] Discovering model files...');
    final Set<String> modelNames = {};

    try {
      debugPrint('[_discoverModelFiles] Loading asset manifest...');
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest.listAssets();
      final modelFiles = assets.where((path) {
        return path.contains('ggml-') && path.endsWith('.bin');
      }).toList();

      for (final path in modelFiles) {
        final name = path.replaceAll('assets/ggml-', '').replaceAll('.bin', '');
        modelNames.add(name);
      }
      debugPrint(
        '[_discoverModelFiles] Found ${modelFiles.length} models in assets',
      );
    } catch (e) {
      debugPrint('[_discoverModelFiles] モデルファイルの検索に失敗: $e');
    }

    try {
      debugPrint('[_discoverModelFiles] Checking downloaded models...');
      final dir = await WhisperController.getModelDir();
      final directory = Directory(dir);
      debugPrint('[_discoverModelFiles] Download dir: $dir');

      if (await directory.exists()) {
        final files = await directory.list().toList();
        for (final file in files) {
          if (file is File &&
              file.path.contains('ggml-') &&
              file.path.endsWith('.bin')) {
            final fileName = file.path.split(Platform.pathSeparator).last;
            final name = fileName
                .replaceAll('ggml-', '')
                .replaceAll('.bin', '');
            modelNames.add(name);
          }
        }
      }
    } catch (e) {
      debugPrint('[_discoverModelFiles] ダウンロード済みモデルの検索に失敗: $e');
    }

    final result = modelNames.toList()..sort();
    debugPrint(
      '[_discoverModelFiles] Total models discovered: ${result.length}',
    );
    return result;
  }

  Future<void> _prepareModelByName(String modelName) async {
    debugPrint('[_prepareModelByName] Preparing model: $modelName');
    try {
      final dir = await WhisperController.getModelDir();
      debugPrint('[_prepareModelByName] Model dir: $dir');
      final modelPath = '$dir/ggml-$modelName.bin';
      final file = File(modelPath);

      if (await file.exists()) {
        _customModelPath = modelPath;
      } else {
        try {
          final bytes = await rootBundle.load('assets/ggml-$modelName.bin');
          await file.create(recursive: true);
          await file.writeAsBytes(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          );
          _customModelPath = modelPath;
        } catch (assetError) {
          final matchingEnum = WhisperModel.values
              .cast<WhisperModel?>()
              .firstWhere(
                (m) => m?.modelName == modelName,
                orElse: () => WhisperModel.base,
              );

          setState(
            () => _statusLog =
                "Downloading $modelName (this may take a while)...",
          );

          final controller = WhisperController();
          await controller.initModel(matchingEnum!);
          _customModelPath = await controller.getPath(matchingEnum);
        }
      }

      final matchingEnum = WhisperModel.values.cast<WhisperModel?>().firstWhere(
        (m) => m?.modelName == modelName,
        orElse: () => null,
      );
      if (matchingEnum != null) {
        _model = matchingEnum;
      }
    } catch (e, stackTrace) {
      debugPrint('[_prepareModelByName] Model preparation error: $e');
      debugPrint('[_prepareModelByName] Stack trace: $stackTrace');
      if (mounted) {
        setState(() => _statusLog = 'Model preparation failed: $e');
      }
    }
  }

  // サーバー起動
  Future<void> _startServer() async {
    debugPrint('[_startServer] Starting server...');
    final server = WhisperServer(
      getModel: () => _model,
      getCustomModelPath: () => _customModelPath,
      getSelectedModelName: () => _selectedModelName,

      onStatusUpdate: (status) => setState(() => _statusLog = status),
      onJobStarted: () => setState(() => _pendingJobs++),
      onJobCompleted: (timeMs) {
        setState(() {
          _pendingJobs--;
          _jobsServed++;
          _lastRequestTime = DateTime.now();
          _latencyHistory.add(timeMs);
          if (_latencyHistory.length > 100) _latencyHistory.removeAt(0);
          _avgLatency =
              (_latencyHistory.reduce((a, b) => a + b) / _latencyHistory.length)
                  .round();
        });
      },
      onError: (error) => setState(() {
        _pendingJobs--;
        _statusLog = error;
      }),
      onModelPreparationNeeded: (modelName) async {
        await _prepareModelByName(modelName);
      },
    );

    final ip = await server.getLocalIpAddress();
    setState(() => _ipAddress = ip);
    await server.start();
  }

  // モデルダウンロード処理
  Future<void> _downloadModel(String modelName) async {
    debugPrint('[_downloadModel] Starting download: $modelName');
    setState(() {
      _downloadProgress[modelName] = 0.0;
      _downloadCompleted.remove(modelName);
      _statusLog = "Downloading $modelName...";
    });

    try {
      final dir = await WhisperController.getModelDir();
      final modelPath = '$dir/ggml-$modelName.bin';
      final file = File(modelPath);

      WhisperModel? whisperModel;
      try {
        whisperModel = WhisperModel.values.firstWhere(
          (m) => m.modelName == modelName,
        );
      } catch (_) {}

      if (whisperModel != null) {
        final controller = WhisperController();

        Future.microtask(() async {
          for (int i = 1; i <= 10; i++) {
            await Future.delayed(const Duration(seconds: 1));
            if (mounted && !_downloadCompleted.contains(modelName)) {
              setState(() {
                _downloadProgress[modelName] = i / 10.0 * 0.9;
              });
            }
          }
        });

        await controller.downloadModel(whisperModel);
      } else {
        final url =
            'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$modelName.bin';
        setState(() => _statusLog = "Downloading from $url...");

        final httpClient = HttpClient();
        final request = await httpClient.getUrl(Uri.parse(url));
        final response = await request.close();

        if (response.statusCode != 200) {
          throw Exception('Failed to download: HTTP ${response.statusCode}');
        }

        final contentLength = response.contentLength;
        await file.create(recursive: true);
        final sink = file.openWrite();

        int received = 0;
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;

          if (contentLength > 0 &&
              mounted &&
              !_downloadCompleted.contains(modelName)) {
            setState(() {
              _downloadProgress[modelName] = received / contentLength;
            });
          }
        }

        await sink.close();
        httpClient.close();
      }

      setState(() {
        _downloadCompleted.add(modelName);
        _downloadProgress[modelName] = 1.0;
        _downloadedModels.add(modelName);
        _statusLog = "Downloaded $modelName successfully";
      });

      await Future.delayed(const Duration(seconds: 2));

      setState(() => _downloadProgress.remove(modelName));

      await _checkDownloadedModels();
      final updatedModels = await _discoverModelFiles();
      setState(() => _availableModelNames = updatedModels);

      debugPrint(
        '[_downloadModel] Download completed successfully: $modelName',
      );

      if (mounted && context.mounted) {
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('モデル "$modelName" をダウンロードしました')),
          );
        } catch (e) {
          debugPrint('[_downloadModel] Failed to show success SnackBar: $e');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('[_downloadModel] Download failed: $e');
      debugPrint('[_downloadModel] Stack trace: $stackTrace');

      setState(() {
        _downloadProgress.remove(modelName);
        _downloadCompleted.remove(modelName);
        _statusLog = "Download failed: $e";
      });

      if (mounted && context.mounted) {
        try {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
        } catch (e) {
          debugPrint('[_downloadModel] Failed to show error SnackBar: $e');
        }
      }
    }
  }

  // UI構築
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F5FA),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Whisper Orchard Node',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.dashboard), text: 'ダッシュボード'),
              Tab(icon: Icon(Icons.cloud_download), text: 'モデル管理'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            // ダッシュボード画面
            DashboardScreen(
              isModelLoaded: _isModelLoaded,
              ipAddress: _ipAddress,
              jobsServed: _jobsServed,
              pendingJobs: _pendingJobs,
              avgLatency: _avgLatency,
              lastRequestTime: _lastRequestTime,
              graphSpots: _graphSpots,
              statusLog: _statusLog,
              availableModelNames: _availableModelNames,
              selectedModelName: _selectedModelName,
              onModelChanged: (name) async {
                if (name == null) return;
                setState(() {
                  _selectedModelName = name;
                  _isModelLoaded = false;
                  _statusLog = 'Switching Model...';
                });
                await _prepareModelByName(name);
                setState(() {
                  _isModelLoaded = true;
                  _statusLog = 'Model Switched';
                });
              },
            ),
            // モデル管理画面
            ModelManagementScreen(
              downloadedModels: _downloadedModels,
              downloadProgress: _downloadProgress,
              downloadCompleted: _downloadCompleted,
              onDownload: _downloadModel,
            ),
          ],
        ),
      ),
    );
  }
}
