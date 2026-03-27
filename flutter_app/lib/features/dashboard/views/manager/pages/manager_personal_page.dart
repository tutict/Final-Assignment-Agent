import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/api/driver_information_controller_api.dart';
import 'package:final_assignment_front/features/api/user_management_controller_api.dart';
import 'package:final_assignment_front/features/dashboard/controllers/chat_controller.dart';
import 'package:final_assignment_front/features/dashboard/controllers/manager_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/features/model/driver_information.dart';
import 'package:final_assignment_front/features/model/user_management.dart';
import 'package:final_assignment_front/i18n/personal_field_localizers.dart';
import 'package:final_assignment_front/utils/services/auth_token_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

String generateIdempotencyKey() =>
    DateTime.now().millisecondsSinceEpoch.toString();

class ManagerPersonalPage extends StatefulWidget {
  const ManagerPersonalPage({super.key});

  @override
  State<ManagerPersonalPage> createState() => _ManagerPersonalPageState();
}

class _ManagerPersonalPageState extends State<ManagerPersonalPage> {
  late UserManagementControllerApi userApi;
  late DriverInformationControllerApi driverApi;
  late Future<UserManagement?> _managerFuture;
  UserManagement? _currentManager;
  DriverInformation? _driverInfo;
  final DashboardController? controller =
      Get.isRegistered<DashboardController>()
          ? Get.find<DashboardController>()
          : null;
  bool _isLoading = true;
  String _errorMessage = '';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _contactNumberController =
      TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    userApi = UserManagementControllerApi();
    driverApi = DriverInformationControllerApi();
    _scrollController = ScrollController();
    _managerFuture = Future.value(null);
    _loadCurrentManager();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _contactNumberController.dispose();
    _emailController.dispose();
    _remarksController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentManager() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final jwtToken = await AuthTokenStore.instance.getJwtToken();
      if (jwtToken == null || jwtToken.isEmpty) {
        throw Exception('manager.personal.error.jwtMissing'.tr);
      }

      await userApi.initializeWithJwt();
      await driverApi.initializeWithJwt();

      final decodedToken = JwtDecoder.decode(jwtToken);
      final username = decodedToken['sub']?.toString();
      if (username == null || username.isEmpty) {
        throw Exception('manager.personal.error.userFromToken'.tr);
      }

      final manager =
          await userApi.apiUsersUsernameUsernameGet(username: username);
      if (manager == null || manager.userId == null) {
        throw Exception('personal.error.currentUserNotFound'.tr);
      }

      DriverInformation? driverInfo =
          await driverApi.apiDriversDriverIdGet(driverId: manager.userId!);
      if (driverInfo == null) {
        final newDriver = DriverInformation(
          driverId: manager.userId,
          name: manager.username ?? 'personal.value.unknownUser'.tr,
          contactNumber: manager.contactNumber ?? '',
          idCardNumber: '',
        );
        await driverApi.apiDriversPost(
          driverInformation: newDriver,
          idempotencyKey: generateIdempotencyKey(),
        );
        driverInfo =
            await driverApi.apiDriversDriverIdGet(driverId: manager.userId!);
      }

      _driverInfo = driverInfo;
      _currentManager = manager;

      if (mounted) {
        setState(() {
          _managerFuture = Future.value(manager);
          _nameController.text = driverInfo?.name ?? '';
          _usernameController.text = manager.username ?? '';
          _passwordController.text = '';
          _contactNumberController.text =
              driverInfo?.contactNumber ?? manager.contactNumber ?? '';
          _emailController.text = manager.email ?? '';
          _remarksController.text = manager.remarks ?? '';
          _isLoading = false;
        });
      }
      controller?.updateCurrentUser(
          driverInfo?.name ?? '', manager.username ?? '');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_errorMessage.isEmpty) {
            _errorMessage = formatPersonalError(e);
          }
        });
      }
    }
  }

  Future<void> _updateField(String field, String value) async {
    if (!mounted) return;

    setState(() => _isLoading = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final currentManager = _currentManager ?? await _managerFuture;
      if (currentManager == null || currentManager.userId == null) {
        throw Exception('personal.error.currentUserNotFound'.tr);
      }
      final userId = currentManager.userId!;
      final idempotencyKey = generateIdempotencyKey();

      switch (field) {
        case 'name':
          await driverApi.apiDriversDriverIdNamePut(
            driverId: userId,
            name: value,
            idempotencyKey: idempotencyKey,
          );
          break;
        case 'contactNumber':
          await driverApi.apiDriversDriverIdContactNumberPut(
            driverId: userId,
            contactNumber: value,
            idempotencyKey: idempotencyKey,
          );
          break;
        case 'password':
          await userApi.apiUsersUserIdPut(
            userId: userId.toString(),
            userManagement: currentManager.copyWith(password: value),
            idempotencyKey: idempotencyKey,
          );
          break;
        case 'email':
          await userApi.apiUsersUserIdPut(
            userId: userId.toString(),
            userManagement: currentManager.copyWith(email: value),
            idempotencyKey: idempotencyKey,
          );
          break;
        case 'remarks':
          await userApi.apiUsersUserIdPut(
            userId: userId.toString(),
            userManagement: currentManager.copyWith(remarks: value),
            idempotencyKey: idempotencyKey,
          );
          break;
        default:
          throw Exception(
            'personal.error.unknownField'.trParams({'field': field}),
          );
      }

      await _loadCurrentManager();

      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              'personal.success.fieldUpdated'.trParams({
                'field': managerPersonalFieldLabel(field),
              }),
              style: TextStyle(
                color: controller?.currentBodyTheme.value.colorScheme
                        .onPrimaryContainer ??
                    Colors.black,
              ),
            ),
            backgroundColor:
                controller?.currentBodyTheme.value.colorScheme.primary ??
                    Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              formatPersonalError(e),
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await _showConfirmationDialog(
      'manager.personal.logoutConfirmTitle'.tr,
      'manager.personal.logoutConfirmBody'.tr,
    );
    if (!confirmed) return;

    await AuthTokenStore.instance.clearJwtToken();
    if (Get.isRegistered<ChatController>()) {
      Get.find<ChatController>().clearMessages();
    }
    Get.offAllNamed(Routes.login);
  }

  Future<bool> _showConfirmationDialog(String title, String content) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => Theme(
            data: controller?.currentBodyTheme.value ?? ThemeData.light(),
            child: AlertDialog(
              backgroundColor: controller
                  ?.currentBodyTheme.value.colorScheme.surfaceContainer,
              title: Text(
                title,
                style: TextStyle(
                  color:
                      controller?.currentBodyTheme.value.colorScheme.onSurface,
                ),
              ),
              content: Text(
                content,
                style: TextStyle(
                  color: controller
                      ?.currentBodyTheme.value.colorScheme.onSurfaceVariant,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(
                    'common.cancel'.tr,
                    style: TextStyle(
                      color: controller
                          ?.currentBodyTheme.value.colorScheme.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(
                    'common.confirm'.tr,
                    style: TextStyle(
                      color: controller
                          ?.currentBodyTheme.value.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  void _showEditDialog(
    String field,
    TextEditingController textController,
    void Function(String) onSave,
  ) {
    final themeData = controller?.currentBodyTheme.value ?? ThemeData.light();
    final label = managerPersonalFieldLabel(field);
    showDialog<void>(
      context: context,
      builder: (_) => Theme(
        data: themeData,
        child: Dialog(
          backgroundColor: themeData.colorScheme.surfaceContainer,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300, minHeight: 150),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'personal.editDialog.title'.trParams({'field': label}),
                    style: themeData.textTheme.titleMedium?.copyWith(
                      color: themeData.colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    style: themeData.textTheme.bodyMedium?.copyWith(
                      color: themeData.colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'personal.editDialog.hint'.trParams({'field': label}),
                      hintStyle: themeData.textTheme.bodyMedium?.copyWith(
                        color: themeData.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                      ),
                      filled: true,
                      fillColor: themeData.colorScheme.surfaceContainerLowest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: themeData.colorScheme.outline
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: themeData.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'common.cancel'.tr,
                          style: themeData.textTheme.labelMedium?.copyWith(
                            color: themeData.colorScheme.onSurface,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onSave(textController.text.trim());
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeData.colorScheme.primary,
                          foregroundColor: themeData.colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'common.save'.tr,
                          style: themeData.textTheme.labelMedium?.copyWith(
                            color: themeData.colorScheme.onPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData = controller?.currentBodyTheme.value ?? ThemeData.light();
      return DashboardPageTemplate(
        theme: themeData,
        title: 'manager.personal.title'.tr,
        pageType: DashboardPageType.manager,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        onThemeToggle: controller?.toggleBodyTheme,
        actions: [
          DashboardPageBarAction(
            icon: Icons.logout,
            onPressed: _logout,
            tooltip: 'manager.personal.logoutTooltip'.tr,
          ),
        ],
        body: _buildBody(themeData),
      );
    });
  }

  Widget _buildBody(ThemeData themeData) {
    if (_isLoading) {
      return Center(
        child: CupertinoActivityIndicator(
          color: themeData.colorScheme.primary,
          radius: 16,
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Text(
          _errorMessage,
          style: themeData.textTheme.bodyLarge?.copyWith(
            color: themeData.colorScheme.error,
            fontSize: 18,
          ),
        ),
      );
    }

    return FutureBuilder<UserManagement?>(
      future: _managerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CupertinoActivityIndicator(
              color: themeData.colorScheme.primary,
              radius: 16,
            ),
          );
        } else if (snapshot.hasError ||
            !snapshot.hasData ||
            snapshot.data == null) {
          return Center(
            child: Text(
              _errorMessage.isNotEmpty
                  ? _errorMessage
                  : 'personal.error.currentUserNotFound'.tr,
              style: themeData.textTheme.bodyLarge?.copyWith(
                color: themeData.colorScheme.error,
                fontSize: 18,
              ),
            ),
          );
        }

        final manager = snapshot.data!;
        return CupertinoScrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          thickness: 6,
          thicknessWhileDragging: 10,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              _buildListTile(
                title: managerPersonalFieldLabel('name'),
                subtitle: _driverInfo?.name ?? 'manager.personal.noData'.tr,
                themeData: themeData,
                onTap: () {
                  _nameController.text = _driverInfo?.name ?? '';
                  _showEditDialog(
                    'name',
                    _nameController,
                    (value) => _updateField('name', value),
                  );
                },
              ),
              _buildListTile(
                title: managerPersonalFieldLabel('username'),
                subtitle: manager.username ?? 'manager.personal.noData'.tr,
                themeData: themeData,
              ),
              _buildListTile(
                title: managerPersonalFieldLabel('password'),
                subtitle: 'personal.value.changePassword'.tr,
                themeData: themeData,
                onTap: () {
                  _passwordController.clear();
                  _showEditDialog(
                    'password',
                    _passwordController,
                    (value) => _updateField('password', value),
                  );
                },
              ),
              _buildListTile(
                title: managerPersonalFieldLabel('contactNumber'),
                subtitle: _driverInfo?.contactNumber ??
                    manager.contactNumber ??
                    'manager.personal.noData'.tr,
                themeData: themeData,
                onTap: () {
                  _contactNumberController.text =
                      _driverInfo?.contactNumber ?? manager.contactNumber ?? '';
                  _showEditDialog(
                    'contactNumber',
                    _contactNumberController,
                    (value) => _updateField('contactNumber', value),
                  );
                },
              ),
              _buildListTile(
                title: managerPersonalFieldLabel('email'),
                subtitle: manager.email ?? 'manager.personal.noData'.tr,
                themeData: themeData,
                onTap: () {
                  _emailController.text = manager.email ?? '';
                  _showEditDialog(
                    'email',
                    _emailController,
                    (value) => _updateField('email', value),
                  );
                },
              ),
              _buildListTile(
                title: managerPersonalFieldLabel('status'),
                subtitle: localizeManagerPersonalAccountStatus(manager.status),
                themeData: themeData,
              ),
              _buildListTile(
                title: managerPersonalFieldLabel('createdTime'),
                subtitle: formatPersonalDateTime(
                  manager.createdTime,
                  emptyKey: 'manager.personal.noData',
                ),
                themeData: themeData,
              ),
              _buildListTile(
                title: managerPersonalFieldLabel('modifiedTime'),
                subtitle: formatPersonalDateTime(
                  manager.modifiedTime,
                  emptyKey: 'manager.personal.noData',
                ),
                themeData: themeData,
              ),
              _buildListTile(
                title: managerPersonalFieldLabel('remarks'),
                subtitle: manager.remarks ?? 'manager.personal.noData'.tr,
                themeData: themeData,
                onTap: () {
                  _remarksController.text = manager.remarks ?? '';
                  _showEditDialog(
                    'remarks',
                    _remarksController,
                    (value) => _updateField('remarks', value),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildListTile({
    required String title,
    required String subtitle,
    required ThemeData themeData,
    VoidCallback? onTap,
  }) {
    return Card(
      elevation: 2,
      shadowColor: themeData.colorScheme.shadow.withValues(alpha: 0.2),
      color: themeData.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(
          title,
          style: themeData.textTheme.bodyLarge?.copyWith(
            color: themeData.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: themeData.textTheme.bodyMedium?.copyWith(
            color: themeData.colorScheme.onSurfaceVariant,
          ),
        ),
        onTap: onTap,
        trailing: onTap != null
            ? Icon(Icons.edit, color: themeData.colorScheme.primary)
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }
}
