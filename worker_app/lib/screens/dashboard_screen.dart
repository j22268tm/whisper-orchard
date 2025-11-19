import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends StatelessWidget {
  final bool isModelLoaded;
  final String ipAddress;
  final int jobsServed;
  final int pendingJobs;
  final int avgLatency;
  final DateTime? lastRequestTime;
  final List<FlSpot> graphSpots;
  final String statusLog;
  final List<String> availableModelNames;
  final String selectedModelName;
  final Function(String?) onModelChanged;

  const DashboardScreen({
    super.key,
    required this.isModelLoaded,
    required this.ipAddress,
    required this.jobsServed,
    required this.pendingJobs,
    required this.avgLatency,
    required this.lastRequestTime,
    required this.graphSpots,
    required this.statusLog,
    required this.availableModelNames,
    required this.selectedModelName,
    required this.onModelChanged,
  });

  @override
  Widget build(BuildContext context) {
    String timeStr = lastRequestTime != null
        ? DateFormat('HH:mm:ss').format(lastRequestTime!)
        : "--:--:--";
    String dateStr = lastRequestTime != null
        ? DateFormat('MM/dd').format(lastRequestTime!)
        : "--/--";

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ステータスバッジ
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isModelLoaded
                        ? Colors.green.shade100
                        : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isModelLoaded ? Colors.green : Colors.red,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isModelLoaded ? Icons.check_circle : Icons.error,
                        size: 16,
                        color: isModelLoaded
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isModelLoaded ? "ONLINE" : "OFFLINE",
                        style: TextStyle(
                          color: isModelLoaded
                              ? Colors.green.shade900
                              : Colors.red.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  "IP: $ipAddress",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // モデル選択
            if (availableModelNames.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      const Icon(Icons.model_training, color: Colors.indigo),
                      const SizedBox(width: 12),
                      const Text(
                        '使用モデル:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<String>(
                          value: selectedModelName,
                          isExpanded: true,
                          underline: Container(),
                          items: availableModelNames
                              .map(
                                (name) => DropdownMenuItem(
                                  value: name,
                                  child: Text('ggml-$name'),
                                ),
                              )
                              .toList(),
                          onChanged: onModelChanged,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),

            // メトリクス
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _buildCard(
                  title: "Total Jobs",
                  value: jobsServed.toString(),
                  icon: Icons.analytics,
                  color: Colors.blue,
                ),
                _buildCard(
                  title: "Pending",
                  value: pendingJobs.toString(),
                  icon: Icons.hourglass_top,
                  color: Colors.orange,
                  isLive: pendingJobs > 0,
                ),
                _buildCard(
                  title: "Avg Latency",
                  value: "$avgLatency ms",
                  icon: Icons.timer,
                  color: Colors.purple,
                ),
                _buildCard(
                  title: "Last Request",
                  value: timeStr,
                  subValue: dateStr,
                  icon: Icons.access_time,
                  color: Colors.teal,
                ),
              ],
            ),

            const SizedBox(height: 24),
            const Text(
              "Workload (Realtime)",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),

            // グラフ
            Container(
              height: 180,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.shade200,
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: graphSpots,
                      isCurved: true,
                      color: Colors.indigoAccent,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.indigoAccent.withOpacity(0.2),
                      ),
                    ),
                  ],
                  minY: 0,
                  maxY: 20,
                ),
              ),
            ),

            const SizedBox(height: 24),
            const Text(
              "System Logs",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),

            // ログ
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusLog,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ヘルパー
  Widget _buildCard({
    required String title,
    required String value,
    String? subValue,
    required IconData icon,
    required Color color,
    bool isLive = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          if (isLive)
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 10,
              spreadRadius: 1,
            )
          else
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 6,
              spreadRadius: 1,
            ),
        ],
        border: isLive ? Border.all(color: color, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              if (subValue != null)
                Text(
                  subValue,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
