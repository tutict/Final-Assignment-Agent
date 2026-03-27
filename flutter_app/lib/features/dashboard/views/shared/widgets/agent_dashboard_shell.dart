import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:final_assignment_front/features/dashboard/models/profile.dart';
import 'package:final_assignment_front/i18n/app_translations.dart';
import 'package:final_assignment_front/i18n/locale_controller.dart';

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
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1120;
    final showRail = width >= 860;

    return Theme(
      data: theme,
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: theme.scaffoldBackgroundColor,
        drawer:
            showRail ? null : Drawer(child: _Sidebar(items: navigationItems)),
        endDrawer: isDesktop
            ? null
            : Drawer(
                width: math.min(440, width * 0.94),
                child: chatPanel,
              ),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.scaffoldBackgroundColor,
                theme.colorScheme.surfaceContainerLowest,
                theme.colorScheme.primaryContainer.withValues(alpha: 0.18),
              ],
            ),
          ),
          child: Stack(
            children: [
              const _BackdropOrbs(),
              SafeArea(
                child: Column(
                  children: [
                    _TopBar(
                      scaffoldKey: scaffoldKey,
                      title: title,
                      subtitle: subtitle,
                      profile: profile,
                      showRail: showRail,
                      onToggleTheme: onToggleTheme,
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          if (showRail)
                            SizedBox(
                              width: 268,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 12, 20),
                                child: _Sidebar(items: navigationItems),
                              ),
                            ),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                showRail ? 8 : 16,
                                0,
                                isDesktop && showDesktopChatPanel ? 12 : 16,
                                20,
                              ),
                              child: body,
                            ),
                          ),
                          if (isDesktop && showDesktopChatPanel)
                            SizedBox(
                              width: 420,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(4, 0, 20, 20),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(28),
                                  child: chatPanel,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.scaffoldKey,
    required this.title,
    required this.subtitle,
    required this.profile,
    required this.showRail,
    required this.onToggleTheme,
  });

  final GlobalKey<ScaffoldState> scaffoldKey;
  final String title;
  final String subtitle;
  final Profile profile;
  final bool showRail;
  final VoidCallback? onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localeController = Get.find<LocaleController>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            if (!showRail)
              IconButton(
                onPressed: () => scaffoldKey.currentState?.openDrawer(),
                icon: const Icon(Icons.menu_rounded),
              ),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.tertiary,
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.motion_photos_auto_rounded,
                color: theme.colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (!showRail)
              IconButton(
                onPressed: () => scaffoldKey.currentState?.openEndDrawer(),
                icon: const Icon(Icons.forum_outlined),
                tooltip: 'shell.openChat'.tr,
              ),
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
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Text(
                  localeController.isChinese ? 'ZH' : 'EN',
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ),
            IconButton(
              onPressed: onToggleTheme,
              icon: const Icon(Icons.contrast_rounded),
              tooltip: 'common.toggleTheme'.tr,
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: profile.photo,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: theme.textTheme.labelLarge,
                      ),
                      Text(
                        profile.email,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.items});

  final List<AgentDashboardNavItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
            child: Text(
              'shell.workspaceLabel'.tr,
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 0.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemBuilder: (context, index) {
                final item = items[index];
                return FilledButton.tonalIcon(
                  onPressed: item.onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: item.active
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surface,
                    foregroundColor: item.active
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurface,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: item.active
                            ? theme.colorScheme.primary.withValues(alpha: 0.22)
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  icon: Icon(item.icon, size: 18),
                  label: Text(item.label),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemCount: items.length,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Text(
              'shell.footer'.tr,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackdropOrbs extends StatelessWidget {
  const _BackdropOrbs();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -140,
            right: -80,
            child: _Orb(
              size: 320,
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -60,
            child: _Orb(
              size: 260,
              color: theme.colorScheme.tertiary.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.color});

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
          colors: [
            color,
            color.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}
