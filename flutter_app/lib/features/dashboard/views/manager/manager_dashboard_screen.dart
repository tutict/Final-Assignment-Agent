import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/dashboard/controllers/manager_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/components/ai_chat.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/agent_dashboard_shell.dart';
import 'package:final_assignment_front/utils/navigation/page_resolver.dart';

class DashboardScreen extends GetView<DashboardController> {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    controller.pageResolver ??= resolveDashboardPage;

    return Obx(() {
      final theme = controller.currentBodyTheme.value;
      final profile = controller.currentProfile;

      return AgentDashboardShell(
        scaffoldKey: controller.scaffoldKey,
        theme: theme,
        title: 'admin.title'.tr,
        subtitle: 'admin.subtitle'.tr,
        profile: profile,
        navigationItems: _navigationItems(),
        chatPanel: const AiChat(),
        onToggleTheme: controller.toggleBodyTheme,
        body: controller.selectedPage.value != null
            ? _SelectedPageFrame(
                title: 'admin.pageTitle'.tr,
                onBack: controller.exitSidebarContent,
                child: controller.selectedPage.value!,
              )
            : _ManagerHome(
                controller: controller,
                onOpenAgent: () => Get.toNamed(Routes.aiChat),
              ),
      );
    });
  }

  List<AgentDashboardNavItem> _navigationItems() {
    final homeActive = controller.selectedPage.value == null;

    return [
      AgentDashboardNavItem(
        label: 'common.home'.tr,
        icon: Icons.space_dashboard_rounded,
        active: homeActive,
        onTap: controller.exitSidebarContent,
      ),
      AgentDashboardNavItem(
        label: 'admin.nav.users'.tr,
        icon: Icons.group_outlined,
        onTap: () => controller.navigateToPage(Routes.userManagementPage),
      ),
      AgentDashboardNavItem(
        label: 'admin.nav.progress'.tr,
        icon: Icons.track_changes_outlined,
        onTap: () => controller.navigateToPage(Routes.progressManagement),
      ),
      AgentDashboardNavItem(
        label: 'admin.nav.logs'.tr,
        icon: Icons.receipt_long_outlined,
        onTap: () => controller.navigateToPage(Routes.logManagement),
      ),
      AgentDashboardNavItem(
        label: 'admin.nav.business'.tr,
        icon: Icons.schema_outlined,
        onTap: () =>
            controller.navigateToPage(Routes.managerBusinessProcessing),
      ),
      AgentDashboardNavItem(
        label: 'common.profile'.tr,
        icon: Icons.account_circle_outlined,
        onTap: () => controller.navigateToPage(Routes.managerPersonalPage),
      ),
      AgentDashboardNavItem(
        label: 'common.settings'.tr,
        icon: Icons.tune_rounded,
        onTap: () => controller.navigateToPage(Routes.managerSetting),
      ),
    ];
  }
}

class _ManagerHome extends StatelessWidget {
  const _ManagerHome({
    required this.controller,
    required this.onOpenAgent,
  });

  final DashboardController controller;
  final VoidCallback onOpenAgent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = controller.currentDriverName.value.isNotEmpty
        ? controller.currentDriverName.value
        : controller.currentProfile.name;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroCard(
            title: 'admin.hero.title'.trParams({'name': displayName}),
            subtitle: 'admin.hero.subtitle'.tr,
            commandHint: 'admin.hero.commandHint'.tr,
            primaryLabel: 'common.openAgent'.tr,
            onPrimaryPressed: onOpenAgent,
            secondaryLabel: 'admin.hero.secondary'.tr,
            onSecondaryPressed: () =>
                controller.navigateToPage(Routes.userManagementPage),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              const _MetricCard(
                label: 'admin.metric.mode',
                value: 'admin.metric.modeValue',
                detail: 'admin.metric.modeDetail',
                accent: Color(0xFF0F766E),
              ),
              _MetricCard(
                label: 'common.theme',
                value: controller.currentTheme.value == 'Dark'
                    ? 'common.dark'
                    : 'common.light',
                detail: 'admin.metric.themeDetail',
                accent: theme.colorScheme.primary,
              ),
              const _MetricCard(
                label: 'common.agent',
                value: 'common.online',
                detail: 'admin.metric.agentDetail',
                accent: Color(0xFF2563EB),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text('admin.coreEntries'.tr, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 960
                  ? 3
                  : constraints.maxWidth >= 620
                      ? 2
                      : 1;
              return GridView.count(
                crossAxisCount: columns,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.48,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _ActionCard(
                    title: 'admin.card.users.title'.tr,
                    subtitle: 'admin.card.users.subtitle'.tr,
                    icon: Icons.group_outlined,
                    onTap: () =>
                        controller.navigateToPage(Routes.userManagementPage),
                  ),
                  _ActionCard(
                    title: 'admin.card.progress.title'.tr,
                    subtitle: 'admin.card.progress.subtitle'.tr,
                    icon: Icons.track_changes_outlined,
                    onTap: () =>
                        controller.navigateToPage(Routes.progressManagement),
                  ),
                  _ActionCard(
                    title: 'admin.card.logs.title'.tr,
                    subtitle: 'admin.card.logs.subtitle'.tr,
                    icon: Icons.receipt_long_outlined,
                    onTap: () =>
                        controller.navigateToPage(Routes.logManagement),
                  ),
                  _ActionCard(
                    title: 'admin.card.business.title'.tr,
                    subtitle: 'admin.card.business.subtitle'.tr,
                    icon: Icons.schema_outlined,
                    onTap: () => controller
                        .navigateToPage(Routes.managerBusinessProcessing),
                  ),
                  _ActionCard(
                    title: 'admin.card.profile.title'.tr,
                    subtitle: 'admin.card.profile.subtitle'.tr,
                    icon: Icons.account_circle_outlined,
                    onTap: () =>
                        controller.navigateToPage(Routes.managerPersonalPage),
                  ),
                  _ActionCard(
                    title: 'admin.card.settings.title'.tr,
                    subtitle: 'admin.card.settings.subtitle'.tr,
                    icon: Icons.tune_rounded,
                    onTap: () =>
                        controller.navigateToPage(Routes.managerSetting),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _SectionTitle('common.today'),
                SizedBox(height: 12),
                _AdviceLine('admin.today.line1'),
                _AdviceLine('admin.today.line2'),
                _AdviceLine('admin.today.line3'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedPageFrame extends StatelessWidget {
  const _SelectedPageFrame({
    required this.title,
    required this.onBack,
    required this.child,
  });

  final String title;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                IconButton.filledTonal(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 12),
                Text(title, style: theme.textTheme.titleLarge),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(28),
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.commandHint,
    required this.primaryLabel,
    required this.onPrimaryPressed,
    required this.secondaryLabel,
    required this.onSecondaryPressed,
  });

  final String title;
  final String subtitle;
  final String commandHint;
  final String primaryLabel;
  final VoidCallback onPrimaryPressed;
  final String secondaryLabel;
  final VoidCallback onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF111827),
            Color(0xFF1F2937),
            Color(0xFF134E4A),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Text(
              'admin.hero.badge'.tr,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: theme.textTheme.displaySmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.84),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1220).withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    commandHint,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton(
                onPressed: onPrimaryPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF10223A),
                ),
                child: Text(primaryLabel),
              ),
              OutlinedButton(
                onPressed: onSecondaryPressed,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
                ),
                child: Text(secondaryLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.accent,
  });

  final String label;
  final String value;
  final String detail;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 240,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.tr, style: theme.textTheme.labelMedium),
          const SizedBox(height: 10),
          Text(
            value.tr,
            style: theme.textTheme.headlineSmall?.copyWith(color: accent),
          ),
          const SizedBox(height: 6),
          Text(detail.tr, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 18),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(subtitle, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title.tr, style: Theme.of(context).textTheme.titleLarge);
  }
}

class _AdviceLine extends StatelessWidget {
  const _AdviceLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.subdirectory_arrow_right_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text.tr, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}
