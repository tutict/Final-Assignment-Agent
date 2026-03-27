import 'package:final_assignment_front/features/dashboard/views/shared/components/active_project_card.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/i18n/traffic_dashboard_localizers.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class TrafficViolationScreen extends StatefulWidget {
  const TrafficViolationScreen({super.key});

  @override
  State<TrafficViolationScreen> createState() => _TrafficViolationScreenState();
}

class _TrafficViolationScreenState extends State<TrafficViolationScreen> {
  Map<String, int>? _violationTypes;
  List<Map<String, dynamic>>? _timeSeries;
  Map<String, int>? _appealReasons;
  Map<String, int>? _paymentStatus;
  bool _isLoading = false;
  final DateTime _startTime = DateTime.now().subtract(const Duration(days: 30));

  @override
  void initState() {
    super.initState();
    _setHardcodedData();
  }

  void _setHardcodedData() {
    setState(() {
      _isLoading = true;
    });

    _violationTypes = {
      'trafficDashboard.violationType.speeding'.tr: 120,
      'trafficDashboard.violationType.redLight'.tr: 80,
      'trafficDashboard.violationType.illegalParking'.tr: 50,
      'trafficDashboard.violationType.drunkDriving'.tr: 20,
      'trafficDashboard.violationType.other'.tr: 30,
    };

    _timeSeries = List.generate(7, (index) {
      final date = _startTime.add(Duration(days: index));
      return {
        'time': date.toIso8601String(),
        'value1': 50 + index * 10, // Fines
        'value2': 30 + index * 5, // Points
      };
    });

    _appealReasons = {
      'trafficDashboard.appealReason.insufficientEvidence'.tr: 50,
      'trafficDashboard.appealReason.proceduralIssue'.tr: 30,
      'trafficDashboard.appealReason.misjudgment'.tr: 20,
      'trafficDashboard.appealReason.other'.tr: 10,
    };

    _paymentStatus = {
      'trafficDashboard.paymentStatus.paid'.tr: 100,
      'trafficDashboard.paymentStatus.unpaid'.tr: 50,
    };

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DashboardPageTemplate(
      theme: theme,
      title: 'trafficDashboard.page.title'.tr,
      pageType: DashboardPageType.manager,
      onRefresh: () async => _setHardcodedData(),
      isLoading: _isLoading,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChartSection(
            'trafficDashboard.section.violationType'.tr,
            _violationTypes == null || _violationTypes!.isEmpty
                ? Center(
                    child: Text('trafficDashboard.empty.violationType'.tr),
                  )
                : ActiveProjectCard(
                    title: 'trafficDashboard.section.violationType'.tr,
                    onPressedSeeAll: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'trafficDashboard.snackbar.violationType'.tr,
                          ),
                        ),
                      );
                    },
                    child: SizedBox(
                      height: 250,
                      child: TrafficViolationBarChart(
                        typeCountMap: _violationTypes!,
                        startTime: _startTime,
                      ),
                    ),
                  ),
          ),
          _buildChartSection(
            'trafficDashboard.section.fineTrend'.tr,
            _timeSeries == null || _timeSeries!.isEmpty
                ? Center(
                    child: Text('trafficDashboard.empty.timeSeries'.tr),
                  )
                : ActiveProjectCard(
                    title: 'trafficDashboard.section.fineTrend'.tr,
                    onPressedSeeAll: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'trafficDashboard.snackbar.timeSeries'.tr,
                          ),
                        ),
                      );
                    },
                    child: SizedBox(
                      height: 200,
                      child: _buildLineChart(),
                    ),
                  ),
          ),
          _buildChartSection(
            'trafficDashboard.section.appealReason'.tr,
            _appealReasons == null || _appealReasons!.isEmpty
                ? Center(
                    child: Text('trafficDashboard.empty.appealReason'.tr),
                  )
                : ActiveProjectCard(
                    title: 'trafficDashboard.section.appealReason'.tr,
                    onPressedSeeAll: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'trafficDashboard.snackbar.appealReason'.tr,
                          ),
                        ),
                      );
                    },
                    child: SizedBox(
                      height: 250,
                      child: TrafficViolationPieChart(
                        data: _appealReasons!,
                      ),
                    ),
                  ),
          ),
          _buildChartSection(
            'trafficDashboard.section.paymentStatus'.tr,
            _paymentStatus == null || _paymentStatus!.isEmpty
                ? Center(
                    child: Text('trafficDashboard.empty.paymentStatus'.tr),
                  )
                : ActiveProjectCard(
                    title: 'trafficDashboard.section.paymentStatus'.tr,
                    onPressedSeeAll: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'trafficDashboard.snackbar.paymentStatus'.tr,
                          ),
                        ),
                      );
                    },
                    child: SizedBox(
                      height: 250,
                      child: TrafficViolationPieChart(
                        data: _paymentStatus!,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection(String title, Widget chart) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: chart,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildLineChart() {
    if (_timeSeries == null || _timeSeries!.isEmpty) {
      return Center(
          child: Text('trafficDashboard.empty.timeSeriesAvailable'.tr));
    }

    final theme = Theme.of(context);
    final dataList = _timeSeries!
        .map((item) => {
              'time': DateTime.parse(item['time'] as String),
              'value1': (item['value1'] as num).toDouble(),
              'value2': (item['value2'] as num).toDouble(),
            })
        .toList();

    final maxX = dataList
        .map((item) => (item['time'] as DateTime).difference(_startTime).inDays)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    final maxY1 = dataList
        .map((item) => item['value1'] as double)
        .reduce((a, b) => a > b ? a : b);
    final maxY2 = dataList
        .map((item) => item['value2'] as double)
        .reduce((a, b) => a > b ? a : b);
    final maxY = (maxY1 > maxY2 ? maxY1 : maxY2) * 1.2;

    return Stack(
      children: [
        BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY > 0 ? maxY : 500,
            minY: 0,
            barGroups: dataList.asMap().entries.map((entry) {
              final item = entry.value;
              final days =
                  (item['time'] as DateTime).difference(_startTime).inDays;
              final value = item['value1'] as double;
              return BarChartGroupData(
                x: days,
                barRods: [
                  BarChartRodData(
                    toY: value,
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.primaryContainer,
                      ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                    width: 12,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(4)),
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                ],
              );
            }).toList(),
            titlesData: FlTitlesData(
              show: true,
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 48,
                  interval: maxY / 5,
                  getTitlesWidget: (value, meta) => Text(
                    value.toInt().toString(),
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  interval: maxX > 7 ? maxX / 7 : 1,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    final date = _startTime.add(Duration(days: index));
                    return Text(
                      formatTrafficDashboardAxisDate(date),
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    );
                  },
                ),
              ),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: true,
              horizontalInterval: maxY / 5,
              verticalInterval: maxX > 7 ? maxX / 7 : 1,
              getDrawingHorizontalLine: (value) {
                return FlLine(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                  strokeWidth: 1,
                );
              },
            ),
            borderData: FlBorderData(
              show: true,
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                tooltipRoundedRadius: 8,
                tooltipPadding: const EdgeInsets.all(8),
                tooltipMargin: 8,
                getTooltipColor: (_) =>
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.9),
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final date = _startTime.add(Duration(days: group.x));
                  return BarTooltipItem(
                    'trafficDashboard.tooltip.fine'.trParams({
                      'date': formatTrafficDashboardDate(date),
                      'value': '${rod.toY.toInt()}',
                    }),
                    TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        LineChart(
          LineChartData(
            lineBarsData: [
              LineChartBarData(
                spots: dataList.asMap().entries.map((entry) {
                  final item = entry.value;
                  final days = (item['time'] as DateTime)
                      .difference(_startTime)
                      .inDays
                      .toDouble();
                  return FlSpot(days, item['value1'] as double);
                }).toList(),
                isCurved: true,
                color: theme.colorScheme.primary,
                barWidth: 3,
                dotData: const FlDotData(show: false),
              ),
              LineChartBarData(
                spots: dataList.asMap().entries.map((entry) {
                  final item = entry.value;
                  final days = (item['time'] as DateTime)
                      .difference(_startTime)
                      .inDays
                      .toDouble();
                  return FlSpot(days, item['value2'] as double);
                }).toList(),
                isCurved: true,
                color: theme.colorScheme.secondary,
                barWidth: 3,
                dotData: const FlDotData(show: false),
              ),
            ],
            minX: 0,
            maxX: maxX > 0 ? maxX : 30,
            minY: 0,
            maxY: maxY > 0 ? maxY : 500,
            titlesData: const FlTitlesData(show: false),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: LineTouchData(
              enabled: true,
              touchTooltipData: LineTouchTooltipData(
                tooltipRoundedRadius: 8,
                tooltipPadding: const EdgeInsets.all(8),
                getTooltipColor: (_) =>
                    theme.colorScheme.secondaryContainer.withValues(alpha: 0.9),
                getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                  final date = _startTime.add(Duration(days: spot.x.toInt()));
                  final label = spot.barIndex == 0
                      ? 'trafficDashboard.metric.fine'.tr
                      : 'trafficDashboard.metric.points'.tr;
                  return LineTooltipItem(
                    '${formatTrafficDashboardDate(date)}\n${'common.labelWithValue'.trParams({
                          'label': label,
                          'value': '${spot.y.toInt()}',
                        })}',
                    TextStyle(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Pie chart wrapper
class TrafficViolationPieChartCard extends StatelessWidget {
  final Map<String, int> data;
  final String title;

  const TrafficViolationPieChartCard({
    super.key,
    required this.data,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return ActiveProjectCard(
      title: title,
      onPressedSeeAll: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'trafficDashboard.snackbar.viewDetails'
                  .trParams({'title': title}),
            ),
          ),
        );
      },
      child: SizedBox(
        height: 250,
        child: TrafficViolationPieChart(data: data),
      ),
    );
  }
}

// Pie chart with dynamic data
class TrafficViolationPieChart extends StatelessWidget {
  final Map<String, int> data;

  const TrafficViolationPieChart({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(child: Text('trafficDashboard.empty.dataAvailable'.tr));
    }

    final theme = Theme.of(context);
    final dataList = data.entries.toList();
    final totalCount = data.values.reduce((a, b) => a + b);

    final colors = List<Color>.generate(
      dataList.length,
      (index) => [
        theme.colorScheme.primary,
        theme.colorScheme.secondary,
        theme.colorScheme.tertiary,
        theme.colorScheme.error,
        theme.colorScheme.primaryContainer,
      ][index % 5],
    );

    return SizedBox(
      height: 250,
      child: Stack(
        children: [
          PieChart(
            PieChartData(
              sections:
                  _buildPieChartSections(dataList, colors, totalCount, theme),
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              borderData: FlBorderData(show: false),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'trafficDashboard.metric.total'.tr,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  totalCount.toString(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildPieChartSections(
    List<MapEntry<String, int>> dataList,
    List<Color> colors,
    int totalCount,
    ThemeData theme,
  ) {
    return List.generate(dataList.length, (index) {
      final entry = dataList[index];
      final value = entry.value.toDouble();
      final percentage = (value / totalCount * 100).toStringAsFixed(1);

      return PieChartSectionData(
        value: value,
        color: colors[index],
        radius: 100,
        title: '$percentage%',
        titleStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onPrimary,
        ),
        badgeWidget: _buildBadgeWidget(entry.key, colors[index], theme),
        badgePositionPercentageOffset: 1.2,
      );
    });
  }

  Widget _buildBadgeWidget(String type, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Text(
        type,
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// Bar chart with dynamic data
class TrafficViolationBarChart extends StatelessWidget {
  final Map<String, int> typeCountMap;
  final DateTime startTime;

  const TrafficViolationBarChart({
    super.key,
    required this.typeCountMap,
    required this.startTime,
  });

  @override
  Widget build(BuildContext context) {
    if (typeCountMap.isEmpty) {
      return Center(
          child: Text('trafficDashboard.empty.violationAvailable'.tr));
    }

    final theme = Theme.of(context);
    final dataList = typeCountMap.entries.toList();
    final maxY = dataList
            .map((entry) => entry.value.toDouble())
            .reduce((a, b) => a > b ? a : b) *
        1.2;

    return SizedBox(
      height: 250,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY > 0 ? maxY : 100,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 8,
              tooltipPadding: const EdgeInsets.all(8),
              tooltipMargin: 8,
              getTooltipColor: (_) =>
                  theme.colorScheme.primaryContainer.withValues(alpha: 0.9),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  'trafficDashboard.tooltip.count'.trParams({
                    'label': dataList[groupIndex].key,
                    'value': '${rod.toY.toInt()}',
                  }),
                  TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < dataList.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        dataList[index].key,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                interval: maxY / 5,
                getTitlesWidget: (value, meta) {
                  if (value == 0) return const SizedBox.shrink();
                  return Text(
                    value.toInt().toString(),
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  );
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 5,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                strokeWidth: 1,
              );
            },
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          barGroups: dataList.asMap().entries.map((entry) {
            final index = entry.key;
            final value = entry.value.value.toDouble();
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: value,
                  width: 16,
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                    ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.2),
                  ),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      ),
    );
  }
}
