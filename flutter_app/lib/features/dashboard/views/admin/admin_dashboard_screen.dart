import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/dashboard/controllers/admin_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/components/ai_chat.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/agent_dashboard_shell.dart';
import 'package:final_assignment_front/shared_components/responsive_builder.dart';
import 'package:final_assignment_front/utils/helpers/role_utils.dart';
import 'package:final_assignment_front/utils/navigation/page_resolver.dart';

class AdminDashboardScreen extends GetView<DashboardController> {
  const AdminDashboardScreen({super.key});

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
            : _AdminHome(
                controller: controller,
                onOpenAgent: () => Get.toNamed(Routes.aiChat),
              ),
      );
    });
  }

  List<AgentDashboardNavItem> _navigationItems() {
    final homeActive = controller.selectedPage.value == null;
    final roles = controller.currentRoles;
    final canManageUsersAndLogs =
        hasAnyRole(roles, const ['SUPER_ADMIN', 'ADMIN']);

    return [
      AgentDashboardNavItem(
        label: 'common.home'.tr,
        icon: Icons.space_dashboard_rounded,
        active: homeActive,
        onTap: controller.exitSidebarContent,
      ),
      if (canManageUsersAndLogs)
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
      if (canManageUsersAndLogs)
        AgentDashboardNavItem(
          label: 'admin.nav.logs'.tr,
          icon: Icons.receipt_long_outlined,
          onTap: () => controller.navigateToPage(Routes.logManagement),
        ),
      AgentDashboardNavItem(
        label: 'admin.nav.business'.tr,
        icon: Icons.schema_outlined,
        onTap: () => controller.navigateToPage(Routes.adminBusinessProcessing),
      ),
      AgentDashboardNavItem(
        label: 'common.profile'.tr,
        icon: Icons.account_circle_outlined,
        onTap: () => controller.navigateToPage(Routes.adminPersonalPage),
      ),
      AgentDashboardNavItem(
        label: 'common.settings'.tr,
        icon: Icons.tune_rounded,
        onTap: () => controller.navigateToPage(Routes.adminSetting),
      ),
    ];
  }
}

class _AdminHome extends StatelessWidget {
  const _AdminHome({
    required this.controller,
    required this.onOpenAgent,
  });

  final DashboardController controller;
  final VoidCallback onOpenAgent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = ResponsiveMetrics.of(context);
    final displayName = controller.currentDriverName.value.isNotEmpty
        ? controller.currentDriverName.value
        : controller.currentProfile.name;
    final roles = controller.currentRoles;
    final canManageUsersAndLogs =
        hasAnyRole(roles, const ['SUPER_ADMIN', 'ADMIN']);

    return SingleChildScrollView(
      padding: EdgeInsets.all(metrics.pagePadding),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: metrics.contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RevealIn(
                child: _WorkspaceOverview(
                  eyebrow: 'common.adminConsole'.tr,
                  title: displayName,
                  summary: 'admin.metric.modeDetail'.tr,
                  metrics: [
                    _OverviewMetric(
                      label: 'admin.metric.mode'.tr,
                      value: 'admin.metric.modeValue'.tr,
                      accent: const Color(0xFF18846F),
                    ),
                    _OverviewMetric(
                      label: 'common.theme'.tr,
                      value: controller.currentTheme.value == 'Dark'
                          ? 'common.dark'.tr
                          : 'common.light'.tr,
                      accent: theme.colorScheme.primary,
                    ),
                    _OverviewMetric(
                      label: 'common.agent'.tr,
                      value: 'common.online'.tr,
                      accent: const Color(0xFF2F6FD6),
                    ),
                  ],
                  queue: [
                    'admin.today.line1'.tr,
                    'admin.today.line2'.tr,
                    'admin.today.line3'.tr,
                  ],
                  primaryLabel: 'common.openAgent'.tr,
                  secondaryLabel: 'admin.hero.secondary'.tr,
                  onPrimaryPressed: onOpenAgent,
                  onSecondaryPressed: () => controller.navigateToPage(
                    canManageUsersAndLogs
                        ? Routes.userManagementPage
                        : Routes.adminBusinessProcessing,
                  ),
                ),
              ),
              SizedBox(height: metrics.sectionGap + 8),
              _RevealIn(
                child: _SectionTitleBlock(
                  eyebrow: 'common.adminConsole'.tr,
                  title: 'admin.coreEntries'.tr,
                  description: 'admin.metric.agentDetail'.tr,
                ),
              ),
              SizedBox(height: metrics.sectionGap),
              _RevealIn(
                child: _ActionDeck(
                  actions: [
                    if (canManageUsersAndLogs)
                      _DeckAction(
                        index: '01',
                        title: 'admin.card.users.title'.tr,
                        subtitle: 'admin.card.users.subtitle'.tr,
                        onTap: () => controller
                            .navigateToPage(Routes.userManagementPage),
                      ),
                    _DeckAction(
                      index: canManageUsersAndLogs ? '02' : '01',
                      title: 'admin.card.progress.title'.tr,
                      subtitle: 'admin.card.progress.subtitle'.tr,
                      onTap: () =>
                          controller.navigateToPage(Routes.progressManagement),
                    ),
                    if (canManageUsersAndLogs)
                      _DeckAction(
                        index: '03',
                        title: 'admin.card.logs.title'.tr,
                        subtitle: 'admin.card.logs.subtitle'.tr,
                        onTap: () =>
                            controller.navigateToPage(Routes.logManagement),
                      ),
                    _DeckAction(
                      index: canManageUsersAndLogs ? '04' : '02',
                      title: 'admin.card.business.title'.tr,
                      subtitle: 'admin.card.business.subtitle'.tr,
                      onTap: () => controller
                          .navigateToPage(Routes.adminBusinessProcessing),
                    ),
                    _DeckAction(
                      index: canManageUsersAndLogs ? '05' : '03',
                      title: 'admin.card.profile.title'.tr,
                      subtitle: 'admin.card.profile.subtitle'.tr,
                      onTap: () =>
                          controller.navigateToPage(Routes.adminPersonalPage),
                    ),
                    _DeckAction(
                      index: canManageUsersAndLogs ? '06' : '04',
                      title: 'admin.card.settings.title'.tr,
                      subtitle: 'admin.card.settings.subtitle'.tr,
                      onTap: () =>
                          controller.navigateToPage(Routes.adminSetting),
                    ),
                  ],
                ),
              ),
              SizedBox(height: metrics.sectionGap + 8),
              _RevealIn(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 920;
                    final left = _UtilityPanel(
                      title: 'common.today'.tr,
                      description: 'admin.metric.agentDetail'.tr,
                      rows: [
                        _UtilityRow(
                          label: 'admin.nav.progress'.tr,
                          value: 'admin.card.progress.subtitle'.tr,
                        ),
                        _UtilityRow(
                          label: 'admin.nav.business'.tr,
                          value: 'admin.card.business.subtitle'.tr,
                        ),
                        if (canManageUsersAndLogs)
                          _UtilityRow(
                            label: 'admin.nav.logs'.tr,
                            value: 'admin.card.logs.subtitle'.tr,
                          ),
                      ],
                    );
                    final right = _PlainChecklist(
                      title: 'common.focus'.tr,
                      items: const [
                        'admin.today.line1',
                        'admin.today.line2',
                        'admin.today.line3',
                      ],
                    );

                    if (stacked) {
                      return Column(
                        children: [
                          left,
                          SizedBox(height: metrics.sectionGap),
                          right,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: left),
                        SizedBox(width: metrics.sectionGap),
                        Expanded(flex: 4, child: right),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
            child: Row(
              children: [
                IconButton.filledTonal(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _WorkspaceOverview extends StatelessWidget {
  const _WorkspaceOverview({
    required this.eyebrow,
    required this.title,
    required this.summary,
    required this.metrics,
    required this.queue,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimaryPressed,
    required this.onSecondaryPressed,
  });

  final String eyebrow;
  final String title;
  final String summary;
  final List<_OverviewMetric> metrics;
  final List<String> queue;
  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0E1319),
            Color(0xFF13272F),
            Color(0xFF18555A),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 920;
          final narrow = constraints.maxWidth < 420;
          final lead = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.62),
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: (narrow
                        ? theme.textTheme.headlineMedium
                        : theme.textTheme.displayMedium)
                    ?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(
                  summary,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 18,
                runSpacing: 16,
                children: metrics
                    .map((metric) => _MetricRail(metric: metric))
                    .toList(),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton(
                    onPressed: onPrimaryPressed,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF102329),
                    ),
                    child: Text(primaryLabel),
                  ),
                  OutlinedButton(
                    onPressed: onSecondaryPressed,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Text(secondaryLabel),
                  ),
                ],
              ),
            ],
          );
          final side = Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'common.today'.tr.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.62),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 14),
                ...queue.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _QueueLine(
                          index: entry.key + 1,
                          text: entry.value,
                        ),
                      ),
                    ),
              ],
            ),
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                lead,
                const SizedBox(height: 22),
                side,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: lead),
              const SizedBox(width: 28),
              Expanded(flex: 4, child: side),
            ],
          );
        },
      ),
    );
  }
}

class _OverviewMetric {
  const _OverviewMetric({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;
}

class _MetricRail extends StatelessWidget {
  const _MetricRail({required this.metric});

  final _OverviewMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 132,
        maxWidth: 180,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.56),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 42,
            height: 3,
            color: metric.accent,
          ),
          const SizedBox(height: 10),
          Text(
            metric.value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueLine extends StatelessWidget {
  const _QueueLine({
    required this.index,
    required this.text,
  });

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          index.toString().padLeft(2, '0'),
          style: theme.textTheme.labelLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.48),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.84),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitleBlock extends StatelessWidget {
  const _SectionTitleBlock({
    required this.eyebrow,
    required this.title,
    required this.description,
  });

  final String eyebrow;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(description, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _ActionDeck extends StatelessWidget {
  const _ActionDeck({required this.actions});

  final List<_DeckAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        children: actions
            .asMap()
            .entries
            .map(
              (entry) => Column(
                children: [
                  _ActionRow(action: entry.value),
                  if (entry.key != actions.length - 1)
                    Divider(
                      height: 1,
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.22,
                      ),
                    ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DeckAction {
  const _DeckAction({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String index;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _ActionRow extends StatefulWidget {
  const _ActionRow({required this.action});

  final _DeckAction action;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.action.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          color: _hovered
              ? theme.colorScheme.primary.withValues(alpha: 0.04)
              : Colors.transparent,
          child: Row(
            children: [
              SizedBox(
                width: 42,
                child: Text(
                  widget.action.index,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary.withValues(alpha: 0.78),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.action.title,
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 5),
                    Text(
                      widget.action.subtitle,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_outward_rounded,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UtilityPanel extends StatelessWidget {
  const _UtilityPanel({
    required this.title,
    required this.description,
    required this.rows,
  });

  final String title;
  final String description;
  final List<_UtilityRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 520;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(description, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 18),
              ...rows.map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.label,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(row.value, style: theme.textTheme.bodyLarge),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                row.label,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              flex: 3,
                              child: Text(row.value,
                                  style: theme.textTheme.bodyLarge),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UtilityRow {
  const _UtilityRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

class _PlainChecklist extends StatelessWidget {
  const _PlainChecklist({
    required this.title,
    required this.items,
  });

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 18),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item.tr, style: theme.textTheme.bodyLarge),
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

class _RevealIn extends StatelessWidget {
  const _RevealIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, widget) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 16),
            child: widget,
          ),
        );
      },
      child: child,
    );
  }
}
