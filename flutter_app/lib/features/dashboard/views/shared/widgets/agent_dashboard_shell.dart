import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:final_assignment_front/features/dashboard/models/profile.dart';
import 'package:final_assignment_front/i18n/app_translations.dart';
import 'package:final_assignment_front/i18n/locale_controller.dart';
import 'package:final_assignment_front/shared_components/responsive_builder.dart';

class AgentDashboardNavItem {
  const AgentDashboardNavItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
}

class AgentDashboardShell extends StatelessWidget {
  const AgentDashboardShell({
    super.key,
    required this.scaffoldKey,
    required this.theme,
    required this.title,
    required this.subtitle,
    required this.profile,
    required this.body,
    required this.navigationItems,
    required this.chatPanel,
    this.onToggleTheme,
    this.showDesktopChatPanel = true,
  });

  final GlobalKey<ScaffoldState> scaffoldKey;
  final ThemeData theme;
  final String title;
  final String subtitle;
  final Profile profile;
  final Widget body;
  final List<AgentDashboardNavItem> navigationItems;
  final Widget chatPanel;
  final VoidCallback? onToggleTheme;
  final bool showDesktopChatPanel;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final metrics = ResponsiveMetrics.of(context);
    final showRail = metrics.isDesktop || metrics.isWide;
    final showPinnedChat = metrics.isWide && showDesktopChatPanel;
    final canOpenChat = !showPinnedChat && showDesktopChatPanel;
    final outerPadding = metrics.pagePadding;
    final sectionGap = metrics.sectionGap;

    return Theme(
      data: theme,
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: theme.scaffoldBackgroundColor,
        drawer: showRail
            ? null
            : Drawer(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: _SidebarPanel(items: navigationItems, compact: true),
                  ),
                ),
              ),
        endDrawer: canOpenChat
            ? null
            : Drawer(
                width: math.min(
                  metrics.isPhone ? size.width * 0.94 : 440.0,
                  440.0,
                ),
                child: _ChatPanelFrame(child: chatPanel),
              ),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.scaffoldBackgroundColor,
                theme.colorScheme.surfaceContainerLowest,
                theme.colorScheme.primary.withValues(alpha: 0.06),
              ],
            ),
          ),
          child: Stack(
            children: [
              const _BackdropGrid(),
              Positioned(
                top: -120,
                right: -40,
                child: _AmbientGlow(
                  size: 320,
                  color: theme.colorScheme.primary.withValues(alpha: 0.16),
                ),
              ),
              Positioned(
                bottom: -100,
                left: -40,
                child: _AmbientGlow(
                  size: 280,
                  color: theme.colorScheme.tertiary.withValues(alpha: 0.12),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      outerPadding, outerPadding, outerPadding, 20),
                  child: Column(
                    children: [
                      _EntranceShift(
                        child: _TopCommandBar(
                          scaffoldKey: scaffoldKey,
                          title: title,
                          subtitle: subtitle,
                          profile: profile,
                          showRail: showRail,
                          canOpenChat: canOpenChat,
                          onToggleTheme: onToggleTheme,
                        ),
                      ),
                      SizedBox(height: sectionGap),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (showRail)
                              SizedBox(
                                width: 290,
                                child: _EntranceShift(
                                  child: _SidebarPanel(items: navigationItems),
                                ),
                              ),
                            if (showRail) SizedBox(width: sectionGap),
                            Expanded(
                              child: _EntranceShift(
                                child: _BodyFrame(child: body),
                              ),
                            ),
                            if (showPinnedChat) ...[
                              SizedBox(width: sectionGap),
                              SizedBox(
                                width: 400,
                                child: _EntranceShift(
                                  child: _ChatPanelFrame(child: chatPanel),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopCommandBar extends StatelessWidget {
  const _TopCommandBar({
    required this.scaffoldKey,
    required this.title,
    required this.subtitle,
    required this.profile,
    required this.showRail,
    required this.canOpenChat,
    required this.onToggleTheme,
  });

  final GlobalKey<ScaffoldState> scaffoldKey;
  final String title;
  final String subtitle;
  final Profile profile;
  final bool showRail;
  final bool canOpenChat;
  final VoidCallback? onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localeController = Get.find<LocaleController>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final narrow = constraints.maxWidth < 560;

        return _PanelShell(
          padding: EdgeInsets.symmetric(
            horizontal: narrow ? 14 : 18,
            vertical: narrow ? 14 : 16,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  if (!showRail)
                    IconButton(
                      onPressed: () => scaffoldKey.currentState?.openDrawer(),
                      icon: const Icon(Icons.menu_rounded),
                    ),
                  Container(
                    width: narrow ? 40 : 46,
                    height: narrow ? 40 : 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primary,
                          Color.lerp(
                                theme.colorScheme.primary,
                                Colors.white,
                                0.18,
                              ) ??
                              theme.colorScheme.primary,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(narrow ? 14 : 16),
                    ),
                    child: Icon(
                      Icons.traffic_rounded,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: narrow
                              ? theme.textTheme.titleLarge
                              : theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: compact ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  if (canOpenChat)
                    IconButton(
                      onPressed: () =>
                          scaffoldKey.currentState?.openEndDrawer(),
                      icon: const Icon(Icons.forum_outlined),
                      tooltip: 'shell.openChat'.tr,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const _StatusChip(
                      icon: Icons.wifi_tethering_rounded,
                      label: 'LIVE',
                    ),
                    const SizedBox(width: 10),
                    PopupMenuButton<Locale>(
                      tooltip: 'common.switchLanguage'.tr,
                      onSelected: localeController.updateLocale,
                      itemBuilder: (context) => AppTranslations.supportedLocales
                          .map(
                            (locale) => PopupMenuItem<Locale>(
                              value: locale,
                              child: Text(
                                locale.languageCode == 'zh'
                                    ? 'common.language.zh'.tr
                                    : 'common.language.en'.tr,
                              ),
                            ),
                          )
                          .toList(),
                      child: _ActionCapsule(
                        child: Text(
                          localeController.isChinese ? 'ZH' : 'EN',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      onPressed: onToggleTheme,
                      icon: const Icon(Icons.contrast_rounded),
                      tooltip: 'common.toggleTheme'.tr,
                    ),
                    const SizedBox(width: 6),
                    _ProfilePill(profile: profile),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SidebarPanel extends StatelessWidget {
  const _SidebarPanel({
    required this.items,
    this.compact = false,
  });

  final List<AgentDashboardNavItem> items;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _PanelShell(
      padding: EdgeInsets.fromLTRB(18, compact ? 18 : 20, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'shell.workspaceLabel'.tr.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text('app.name'.tr, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            'shell.footer'.tr,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _SidebarEntry(item: item);
              },
              separatorBuilder: (_, __) => const SizedBox(height: 8),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarEntry extends StatelessWidget {
  const _SidebarEntry({required this.item});

  final AgentDashboardNavItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: item.active
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 3,
              height: 34,
              decoration: BoxDecoration(
                color: item.active
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              item.icon,
              size: 18,
              color: item.active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: item.active
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: item.active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

class _BodyFrame extends StatelessWidget {
  const _BodyFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: child,
      ),
    );
  }
}

class _ChatPanelFrame extends StatelessWidget {
  const _ChatPanelFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 18,
            right: 18,
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.24),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _ProfilePill extends StatelessWidget {
  const _ProfilePill({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundImage: profile.photo,
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  profile.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
        ),
      ),
      child: child,
    );
  }
}

class _ActionCapsule extends StatelessWidget {
  const _ActionCapsule({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: child,
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _ActionCapsule(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntranceShift extends StatelessWidget {
  const _EntranceShift({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, widget) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 22),
            child: widget,
          ),
        );
      },
      child: child,
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, Colors.transparent],
        ),
      ),
    );
  }
}

class _BackdropGrid extends StatelessWidget {
  const _BackdropGrid();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _BackdropGridPainter(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.14),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _BackdropGridPainter extends CustomPainter {
  const _BackdropGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    const gap = 48.0;

    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropGridPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
