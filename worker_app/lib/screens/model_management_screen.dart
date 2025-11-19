import 'package:flutter/material.dart';

class ModelManagementScreen extends StatefulWidget {
  final Set<String> downloadedModels;
  final Map<String, double> downloadProgress;
  final Set<String> downloadCompleted;
  final Function(String) onDownload;

  const ModelManagementScreen({
    super.key,
    required this.downloadedModels,
    required this.downloadProgress,
    required this.downloadCompleted,
    required this.onDownload,
  });

  @override
  State<ModelManagementScreen> createState() => _ModelManagementScreenState();
}

class _ModelManagementScreenState extends State<ModelManagementScreen> {
  // 利用可能なモデル情報 (Hugging Face whisper.cpp公式リスト)
  final List<Map<String, dynamic>> availableModels = [
    // Tiny models
    {
      'name': 'tiny',
      'size': '75 MB',
      'description': '最小・最速 (多言語)',
    },
    {
      'name': 'tiny-q5_1',
      'size': '31 MB',
      'description': '最小・最速 (量子化Q5_1)',
    },
    {
      'name': 'tiny-q8_0',
      'size': '42 MB',
      'description': '最小・最速 (量子化Q8_0)',
    },
    {
      'name': 'tiny.en',
      'size': '75 MB',
      'description': '最小・最速 (英語専用)',
    },
    {
      'name': 'tiny.en-q5_1',
      'size': '31 MB',
      'description': '最小・最速 (英語専用, Q5_1)',
    },
    {
      'name': 'tiny.en-q8_0',
      'size': '42 MB',
      'description': '最小・最速 (英語専用, Q8_0)',
    },

    // Base models
    {
      'name': 'base',
      'size': '142 MB',
      'description': '小型・高速 (多言語)',
    },
    {
      'name': 'base-q5_1',
      'size': '57 MB',
      'description': '小型・高速 (量子化Q5_1)',
    },
    {
      'name': 'base-q8_0',
      'size': '78 MB',
      'description': '小型・高速 (量子化Q8_0)',
    },
    {
      'name': 'base.en',
      'size': '142 MB',
      'description': '小型・高速 (英語専用)',
    },
    {
      'name': 'base.en-q5_1',
      'size': '57 MB',
      'description': '小型・高速 (英語専用, Q5_1)',
    },
    {
      'name': 'base.en-q8_0',
      'size': '78 MB',
      'description': '小型・高速 (英語専用, Q8_0)',
    },

    // Small models
    {
      'name': 'small',
      'size': '466 MB',
      'description': '中型・バランス型 (多言語)',
    },
    {
      'name': 'small-q5_1',
      'size': '181 MB',
      'description': '中型・バランス型 (量子化Q5_1)',
    },
    {
      'name': 'small-q8_0',
      'size': '252 MB',
      'description': '中型・バランス型 (量子化Q8_0)',
    },
    {
      'name': 'small.en',
      'size': '466 MB',
      'description': '中型・バランス型 (英語専用)',
    },
    {
      'name': 'small.en-q5_1',
      'size': '181 MB',
      'description': '中型・バランス型 (英語専用, Q5_1)',
    },
    {
      'name': 'small.en-q8_0',
      'size': '252 MB',
      'description': '中型・バランス型 (英語専用, Q8_0)',
    },
    {
      'name': 'small.en-tdrz',
      'size': '465 MB',
      'description': '中型 (英語専用, 話者分離対応)',
    },

    // Medium models
    {
      'name': 'medium',
      'size': '1.5 GB',
      'description': '大型・高精度 (多言語)',
    },
    {
      'name': 'medium-q5_0',
      'size': '514 MB',
      'description': '大型・高精度 (量子化Q5_0)',
    },
    {
      'name': 'medium-q8_0',
      'size': '785 MB',
      'description': '大型・高精度 (量子化Q8_0)',
    },
    {
      'name': 'medium.en',
      'size': '1.5 GB',
      'description': '大型・高精度 (英語専用)',
    },
    {
      'name': 'medium.en-q5_0',
      'size': '514 MB',
      'description': '大型・高精度 (英語専用, Q5_0)',
    },
    {
      'name': 'medium.en-q8_0',
      'size': '785 MB',
      'description': '大型・高精度 (英語専用, Q8_0)',
    },

    // Large models
    {
      'name': 'large-v1',
      'size': '2.9 GB',
      'description': '最大精度 v1 (多言語)',
    },
    {
      'name': 'large-v2',
      'size': '2.9 GB',
      'description': '最大精度 v2 (多言語)',
    },
    {
      'name': 'large-v2-q5_0',
      'size': '1.1 GB',
      'description': '最大精度 v2 (量子化Q5_0)',
    },
    {
      'name': 'large-v2-q8_0',
      'size': '1.5 GB',
      'description': '最大精度 v2 (量子化Q8_0)',
    },
    {
      'name': 'large-v3',
      'size': '2.9 GB',
      'description': '最大精度 v3 (多言語)',
    },
    {
      'name': 'large-v3-q5_0',
      'size': '1.1 GB',
      'description': '最大精度 v3 (量子化Q5_0)',
    },

    // Large-v3-turbo models
    {
      'name': 'large-v3-turbo',
      'size': '1.5 GB',
      'description': '最新高速版 (多言語)',
    },
    {
      'name': 'large-v3-turbo-q5_0',
      'size': '547 MB',
      'description': '最新高速版 (量子化Q5_0)',
    },
    {
      'name': 'large-v3-turbo-q8_0',
      'size': '834 MB',
      'description': '最新高速版 (量子化Q8_0)',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: availableModels.length,
        itemBuilder: (context, index) {
          final model = availableModels[index];
          final modelName = model['name'] as String;
          final isDownloaded = widget.downloadedModels.contains(modelName);
          final isDownloading = widget.downloadProgress.containsKey(modelName);
          final isCompleted = widget.downloadCompleted.contains(
            modelName,
          );

          final progress = isCompleted
              ? 1.0
              : (widget.downloadProgress[modelName] ?? 0.0);

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ggml-${model['name']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              model['description'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'サイズ: ${model['size']}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isDownloaded || isCompleted)
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 32,
                        )
                      else if (isDownloading)
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 3,
                          ),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.download),
                          color: Colors.indigo,
                          onPressed: () {
                            widget.onDownload(modelName);
                          },
                        ),
                    ],
                  ),
                  if (isDownloading && !isCompleted)
                    Column(
                      children: [
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: progress),
                        const SizedBox(height: 4),
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
