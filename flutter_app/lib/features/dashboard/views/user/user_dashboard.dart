import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/dashboard/controllers/user_dashboard_screen_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/components/ai_chat.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/agent_dashboard_shell.dart';
import 'package:final_assignment_front/utils/navigation/page_resolver.dart';

class UserDashboard extends GetView<UserDashboardController> {
  const UserDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    controller.pageResolver ??= resolveDashboardPage;

    return Obx(() {
      final theme = controller.currentBodyTheme.value;
      final profile = controller.currentProfile;

      return AgentDashboardShell(
        scaffoldKey: controller.scaffoldKey,
        theme: theme,
        title: 'user.title'.tr,
        subtitle: 'user.subtitle'.tr,
        profile: profile,
        navigationItems: _navigationItems(),
        chatPanel: const AiChat(),
        onToggleTheme: controller.toggleBodyTheme,
        body: controller.selectedPage.value != null
            ? _SelectedPageFrame(
                title: 'user.pageTitle'.tr,
                onBack: controller.exitSidebarContent,
                child: controller.selectedPage.value!,
              )
            : _UserHome(
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
        icon: Icons.home_rounded,
        active: homeActive,
        onTap: controller.exitSidebarContent,
      ),
      AgentDashboardNavItem(
        label: 'user.nav.progress'.tr,
        icon: Icons.timeline_rounded,
        onTap: () => controller.navigateToPage(Routes.businessProgress),
      ),
      AgentDashboardNavItem(
        label: 'user.nav.records'.tr,
        icon: Icons.fact_check_outlined,
        onTap: () => controller.navigateToPage(Routes.userOffenseListPage),
      ),
      AgentDashboardNavItem(
        label: 'common.profile'.tr,
        icon: Icons.perm_identity_rounded,
        onTap: () => controller.navigateToPage(Routes.personalMain),
      ),
      AgentDashboardNavItem(
        label: 'user.nav.news'.tr,
        icon: Icons.newspaper_rounded,
        onTap: () =>
            controller.navigateToPage(Routes.latestTrafficViolationNewsPage),
      ),
      AgentDashboardNavItem(
        label: 'user.nav.support'.tr,
        icon: Icons.support_agent_rounded,
        onTap: () => controller.navigateToPage(Routes.consultation),
      ),
      AgentDashboardNavItem(
        label: 'common.settings'.tr,
        icon: Icons.tune_rounded,
        onTap: () => controller.navigateToPage(Routes.userSetting),
      ),
    ];
  }
}

class _UserHome extends StatelessWidget {
  const _UserHome({
    required this.controller,
    required this.onOpenAgent,
  });

  final UserDashboardController controller;
  final VoidCallback onOpenAgent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = controller.currentDriverName.value.isNotEmpty
        ? controller.currentDriverName.value
        : controller.currentProfile.name;
    final profileReady = controller.driverLicenseNumber.value.isNotEmpty &&
        controller.idCardNumber.value.isNotEmpty;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroCard(
            title: 'user.hero.title'.trParams({'name': displayName}),
            subtitle: 'user.hero.subtitle'.tr,
            commandHint: 'user.hero.commandHint'.tr,
            primaryLabel: 'common.openAgent'.tr,
            onPrimaryPressed: onOpenAgent,
            secondaryLabel: 'user.hero.secondary'.tr,
            onSecondaryPressed: () =>
                controller.navigateToPage(Routes.businessProgress),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _MetricCard(
                label: 'user.metric.identity'.tr,
                value: profileReady
                    ? 'user.metric.identityReady'.tr
                    : 'user.metric.identityPending'.tr,
                detail: profileReady
                    ? 'user.metric.identityReadyDetail'.tr
                    : 'user.metric.identityPendingDetail'.tr,
                accent: profileReady
                    ? const Color(0xFF1B8A5A)
                    : const Color(0xFFB96E11),
              ),
              _MetricCard(
                label: 'common.theme'.tr,
                value: controller.currentTheme.value == 'Dark'
                    ? 'common.dark'.tr
                    : 'common.light'.tr,
                detail: 'user.metric.themeDetail'.tr,
                accent: theme.colorScheme.primary,
              ),
              _MetricCard(
                label: 'common.agent'.tr,
                value: controller.isLoadingUser.value
                    ? 'user.metric.agentSyncing'.tr
                    : 'common.online'.tr,
                detail: 'user.metric.agentDetail'.tr,
                accent: const Color(0xFF2563EB),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text('user.quickAccess'.tr, style: theme.textTheme.headlineSmall),
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
                    title: 'user.card.progress.title'.tr,
                    subtitle: 'user.card.progress.subtitle'.tr,
                    icon: Icons.timeline_rounded,
                    onTap: () =>
                        controller.navigateToPage(Routes.businessProgress),
                  ),
                  _ActionCard(
                    title: 'user.card.records.title'.tr,
                    subtitle: 'user.card.records.subtitle'.tr,
                    icon: Icons.fact_check_outlined,
                    onTap: () =>
                        controller.navigateToPage(Routes.userOffenseListPage),
                  ),
                  _ActionCard(
                    title: 'user.card.profile.title'.tr,
                    subtitle: 'user.card.profile.subtitle'.tr,
                    icon: Icons.badge_outlined,
                    onTap: () => controller.navigateToPage(Routes.personalMain),
                  ),
                  _ActionCard(
                    title: 'user.card.news.title'.tr,
                    subtitle: 'user.card.news.subtitle'.tr,
                    icon: Icons.newspaper_rounded,
                    onTap: () => controller
                        .navigateToPage(Routes.latestTrafficViolationNewsPage),
                  ),
                  _ActionCard(
                    title: 'user.card.support.title'.tr,
                    subtitle: 'user.card.support.subtitle'.tr,
                    icon: Icons.forum_outlined,
                    onTap: () => controller.navigateToPage(Routes.consultation),
                  ),
                  _ActionCard(
                    title: 'user.card.preferences.title'.tr,
                    subtitle: 'user.card.preferences.subtitle'.tr,
                    icon: Icons.tune_rounded,
                    onTap: () => controller.navigateToPage(Routes.userSetting),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 920;
              final left = _AdviceCard(theme: theme);
              final right = _FocusCard(
                items: [
                  _FocusItem(
                    label: 'user.focus.profileStatus',
                    value: profileReady
                        ? 'user.focus.profileReady'
                        : 'user.focus.profilePending',
                    accent: profileReady
                        ? const Color(0xFF1B8A5A)
                        : const Color(0xFFB96E11),
                  ),
                  const _FocusItem(
                    label: 'user.focus.agentPanel',
                    value: 'user.focus.agentPanelValue',
                    accent: Color(0xFF2563EB),
                  ),
                  _FocusItem(
                    label: 'user.focus.workspace',
                    value: 'user.focus.workspaceValue',
                    accent: theme.colorScheme.primary,
                  ),
                ],
              );

              if (stacked) {
                return Column(
                  children: [
                    left,
                    const SizedBox(height: 16),
                    right,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: left),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: right),
                ],
              );
            },
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
            Color(0xFF09203F),
            Color(0xFF27496D),
            Color(0xFF1B365D),
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
              'user.hero.badge'.tr,
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
              color: const Color(0xFF0E1520).withValues(alpha: 0.72),
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
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(color: accent),
          ),
          const SizedBox(height: 6),
          Text(detail, style: theme.textTheme.bodyMedium),
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

class _AdviceCard extends StatelessWidget {
  const _AdviceCard({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          _AdviceLine('user.today.line1'),
          _AdviceLine('user.today.line2'),
          _AdviceLine('user.today.line3'),
        ],
      ),
    );
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.items});

  final List<_FocusItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('common.focus'.tr, style: theme.textTheme.titleLarge),
          const SizedBox(height: 14),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: item.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.label.tr, style: theme.textTheme.labelLarge),
                        const SizedBox(height: 4),
                        Text(item.value.tr, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusItem {
  const _FocusItem({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;
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
