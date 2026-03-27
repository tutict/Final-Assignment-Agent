import 'package:final_assignment_front/features/dashboard/views/user/widgets/news_page_layout.dart';
import 'package:final_assignment_front/i18n/news_localizers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LatestTrafficViolationNewsPage extends StatelessWidget {
  const LatestTrafficViolationNewsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return NewsPageLayout(
      title: 'news.latest.title'.tr,
      accentColor: Colors.blueAccent,
      contentBuilder: (context, theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(context, 'news.latest.section.headlines'.tr),
          _buildNewsCard(
            context,
            'news.latest.item1.title'.tr,
            'news.latest.item1.body'.tr,
            DateTime(2025, 2, 27),
          ),
          _buildSectionTitle(context, 'news.latest.section.recent'.tr),
          _buildNewsCard(
            context,
            'news.latest.item2.title'.tr,
            'news.latest.item2.body'.tr,
            DateTime(2025, 2, 25),
          ),
          _buildNewsCard(
            context,
            'news.latest.item3.title'.tr,
            'news.latest.item3.body'.tr,
            DateTime(2025, 2, 20),
          ),
          _buildSectionTitle(context, 'news.latest.section.expert'.tr),
          _buildContentCard(
            context,
            'news.latest.expert.title'.tr,
            'news.latest.expert.body'.tr,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildNewsCard(
    BuildContext context,
    String title,
    String description,
    DateTime date,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 16, color: colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  formatNewsDate(date),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentCard(
    BuildContext context,
    String title,
    String description,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      color: colorScheme.surfaceContainerHighest,
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
