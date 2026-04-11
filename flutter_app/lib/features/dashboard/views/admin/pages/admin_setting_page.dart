import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/dashboard/controllers/admin_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/controllers/chat_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/utils/services/auth_token_store.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminSettingPage extends StatefulWidget {
  const AdminSettingPage({super.key});

  @override
  State<AdminSettingPage> createState() => _AdminSettingPageState();
}

class _AdminSettingPageState extends State<AdminSettingPage> {
  bool _notificationEnabled = false;
  final DashboardController controller = Get.find<DashboardController>();
  final TextEditingController _themeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _themeController.text = _selectedThemeLabel;
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await AuthTokenStore.instance.clearJwtToken();
    if (Get.isRegistered<ChatController>()) {
      final chatController = Get.find<ChatController>();
      chatController.clearMessages();
    }
    Get.offAllNamed(Routes.login);
  }

  void _saveSettings() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('settings.saved'.tr),
          content: Text(
            '${'settings.notifications'.tr}: '
            '${_notificationEnabled ? 'settings.themeMode.enabled'.tr : 'settings.themeMode.disabled'.tr}\n'
            '${'settings.summary.darkMode'.trParams({
                  'value': controller.currentTheme.value == 'Dark'
                      ? 'settings.themeMode.enabled'.tr
                      : 'settings.themeMode.disabled'.tr,
                })}\n'
            '${'settings.summary.currentTheme'.trParams({
                  'value': _selectedThemeLabel,
                })}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('common.ok'.tr),
            ),
          ],
        );
      },
    );
  }

  void _applyThemeSelection({
    required String style,
    required bool darkMode,
  }) {
    controller.setSelectedStyle(style);
    final shouldToggle = (controller.currentTheme.value == 'Dark') != darkMode;
    if (shouldToggle) {
      controller.toggleBodyTheme();
    }
    _themeController.text = _selectedThemeLabel;
    Navigator.pop(context);
  }

  String get _selectedThemeLabel {
    final style = controller.selectedStyle.value.toLowerCase();
    final mode = controller.currentTheme.value == 'Dark' ? 'Dark' : 'Light';
    return 'settings.theme.$style$mode'.tr;
  }

  void _showThemeDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('settings.themeDialogTitle'.tr),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text('settings.theme.materialLight'.tr),
                  onTap: () => _applyThemeSelection(
                    style: 'Material',
                    darkMode: false,
                  ),
                ),
                ListTile(
                  title: Text('settings.theme.materialDark'.tr),
                  onTap: () => _applyThemeSelection(
                    style: 'Material',
                    darkMode: true,
                  ),
                ),
                ListTile(
                  title: Text('settings.theme.ionicLight'.tr),
                  onTap: () => _applyThemeSelection(
                    style: 'Ionic',
                    darkMode: false,
                  ),
                ),
                ListTile(
                  title: Text('settings.theme.ionicDark'.tr),
                  onTap: () => _applyThemeSelection(
                    style: 'Ionic',
                    darkMode: true,
                  ),
                ),
                ListTile(
                  title: Text('settings.theme.basicLight'.tr),
                  onTap: () => _applyThemeSelection(
                    style: 'Basic',
                    darkMode: false,
                  ),
                ),
                ListTile(
                  title: Text('settings.theme.basicDark'.tr),
                  onTap: () => _applyThemeSelection(
                    style: 'Basic',
                    darkMode: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('common.cancel'.tr),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => DashboardPageTemplate(
        theme: controller.currentBodyTheme.value,
        title: 'settings.title'.tr,
        pageType: DashboardPageType.admin,
        bodyIsScrollable: true,
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.notifications, color: Colors.blue),
                title: Text(
                  'settings.notificationsEnabled'.tr,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  _notificationEnabled
                      ? 'settings.themeMode.enabled'.tr
                      : 'settings.themeMode.disabled'.tr,
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
                trailing: Switch(
                  value: _notificationEnabled,
                  onChanged: (value) {
                    setState(() {
                      _notificationEnabled = value;
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.palette, color: Colors.blue),
                title: Text(
                  'settings.theme'.tr,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  _themeController.text,
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
                trailing:
                    const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                onTap: _showThemeDialog,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.save, color: Colors.blue),
                title: Text(
                  'settings.saveSettings'.tr,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                trailing:
                    const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                onTap: _saveSettings,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.blue),
                title: Text(
                  'common.logout'.tr,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                trailing:
                    const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                onTap: () {
                  showDialog<void>(
                    context: context,
                    builder: (dialogContext) {
                      return AlertDialog(
                        title: Text('settings.confirmLogoutTitle'.tr),
                        content: Text('settings.confirmLogoutMessage'.tr),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: Text('common.cancel'.tr),
                          ),
                          TextButton(
                            onPressed: () {
                              _logout();
                              Navigator.pop(dialogContext);
                            },
                            child: Text('common.confirm'.tr),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
