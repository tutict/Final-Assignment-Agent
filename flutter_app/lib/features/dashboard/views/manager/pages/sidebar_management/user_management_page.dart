import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/api/user_management_controller_api.dart';
import 'package:final_assignment_front/features/dashboard/controllers/manager_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/features/model/user_management.dart';
import 'package:final_assignment_front/i18n/status_localizers.dart';
import 'package:final_assignment_front/i18n/user_admin_localizers.dart';
import 'package:final_assignment_front/utils/helpers/api_exception.dart';
import 'package:final_assignment_front/utils/services/auth_token_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:uuid/uuid.dart';

String generateIdempotencyKey() => const Uuid().v4();

List<String> _decodeRoles(dynamic rawRoles) {
  if (rawRoles is List) {
    return rawRoles.map((role) => role.toString()).toList();
  }
  if (rawRoles is String && rawRoles.isNotEmpty) {
    return [rawRoles];
  }
  return [];
}

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  final DashboardController controller = Get.find<DashboardController>();
  final UserManagementControllerApi userApi = UserManagementControllerApi();
  final TextEditingController _searchController = TextEditingController();

  final List<UserManagement> _allUsers = [];
  List<UserManagement> _filteredUsers = [];

  bool _isLoading = false;
  bool _isAdmin = false;
  bool _showReloginAction = false;
  String _statusMessage = '';
  String _searchType = kUserAdminSearchTypeUsername;
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _initialize();
    _searchController.addListener(() {
      _applyFilters(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<bool> _validateJwtToken() async {
    final jwtToken = await AuthTokenStore.instance.getJwtToken();
    if (jwtToken == null || jwtToken.isEmpty) {
      if (mounted) {
        setState(() {
          _statusMessage = 'userAdmin.error.unauthorized'.tr;
          _showReloginAction = true;
        });
      }
      return false;
    }

    try {
      if (JwtDecoder.isExpired(jwtToken)) {
        if (mounted) {
          setState(() {
            _statusMessage = 'userAdmin.error.expired'.tr;
            _showReloginAction = true;
          });
        }
        return false;
      }

      final decodedToken = JwtDecoder.decode(jwtToken);
      _currentUsername = decodedToken['sub']?.toString();
      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'userAdmin.error.invalidLogin'.trParams({
            'error': formatUserAdminError(e),
          });
          _showReloginAction = true;
        });
      }
      return false;
    }
  }

  Future<void> _initialize() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _statusMessage = '';
        _showReloginAction = false;
      });
    }

    try {
      if (!await _validateJwtToken()) {
        return;
      }

      await userApi.initializeWithJwt();
      final jwtToken = await AuthTokenStore.instance.getJwtToken();
      final decodedToken = JwtDecoder.decode(jwtToken!);
      final roles = _decodeRoles(decodedToken['roles']);

      if (!roles.contains('ADMIN') && !roles.contains('ROLE_ADMIN')) {
        if (mounted) {
          setState(() {
            _isAdmin = false;
            _statusMessage = 'userAdmin.error.adminOnly'.tr;
          });
        }
        return;
      }

      _isAdmin = true;
      await _loadUsers();
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'userAdmin.error.initFailed'.trParams({
            'error': formatUserAdminError(e),
          });
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadUsers() async {
    if (!_isAdmin) return;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _statusMessage = '';
        _showReloginAction = false;
      });
    }

    try {
      if (!await _validateJwtToken()) {
        return;
      }

      await userApi.initializeWithJwt();
      final users = await userApi.apiUsersGet();
      final visibleUsers = users
          .where((user) =>
              user.username != null && user.username != _currentUsername)
          .toList()
        ..sort((left, right) {
          final leftName = left.username?.toLowerCase() ?? '';
          final rightName = right.username?.toLowerCase() ?? '';
          return leftName.compareTo(rightName);
        });

      if (!mounted) return;
      setState(() {
        _allUsers
          ..clear()
          ..addAll(visibleUsers);
      });
      _applyFilters(_searchController.text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _allUsers.clear();
        _filteredUsers = [];
        _statusMessage = 'userAdmin.error.loadFailed'.trParams({
          'error': formatUserAdminError(e),
        });
        _showReloginAction = e is ApiException && e.code == 403;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshUsers() async {
    await _loadUsers();
  }

  void _applyFilters(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? List<UserManagement>.from(_allUsers)
        : _allUsers.where((user) {
            switch (_searchType) {
              case kUserAdminSearchTypeStatus:
                final status = user.status?.toLowerCase() ?? '';
                final localizedStatus =
                    userAdminStatusKey(user.status).tr.toLowerCase();
                return status.contains(query) ||
                    localizedStatus.contains(query);
              case kUserAdminSearchTypeDepartment:
                return (user.department?.toLowerCase() ?? '').contains(query);
              case kUserAdminSearchTypeContactNumber:
                return (user.contactNumber?.toLowerCase() ?? '')
                    .contains(query);
              case kUserAdminSearchTypeEmail:
                return (user.email?.toLowerCase() ?? '').contains(query);
              case kUserAdminSearchTypeUsername:
              default:
                return (user.username?.toLowerCase() ?? '').contains(query);
            }
          }).toList();

    if (!mounted) return;
    setState(() {
      _filteredUsers = filtered;
    });
  }

  Future<bool> _checkUsernameAvailability(String username) async {
    try {
      await userApi.apiUsersUsernameUsernameGet(username: username);
      return false;
    } catch (e) {
      if (e is ApiException && e.code == 404) {
        return true;
      }
      rethrow;
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    final themeData = controller.currentBodyTheme.value;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: isError
                ? themeData.colorScheme.onError
                : themeData.colorScheme.onPrimary,
          ),
        ),
        backgroundColor: isError
            ? themeData.colorScheme.error
            : themeData.colorScheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showCreateUserDialog() async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final contactNumberController = TextEditingController();
    final emailController = TextEditingController();
    final departmentController = TextEditingController();
    final remarksController = TextEditingController();
    String selectedStatus = kUserAdminStatusActive;
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final themeData = controller.currentBodyTheme.value;
        return Theme(
          data: themeData,
          child: AlertDialog(
            title: Text('userAdmin.dialog.createTitle'.tr),
            backgroundColor: themeData.colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.0),
            ),
            content: SizedBox(
              width: 480,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTextField(
                        controller: usernameController,
                        themeData: themeData,
                        fieldKey: kUserAdminFieldUsername,
                        isRequired: true,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: passwordController,
                        themeData: themeData,
                        fieldKey: kUserAdminFieldPassword,
                        isRequired: true,
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: contactNumberController,
                        themeData: themeData,
                        fieldKey: kUserAdminFieldContactNumber,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: emailController,
                        themeData: themeData,
                        fieldKey: kUserAdminFieldEmail,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: departmentController,
                        themeData: themeData,
                        fieldKey: kUserAdminFieldDepartment,
                      ),
                      const SizedBox(height: 12),
                      _buildStatusField(
                        themeData: themeData,
                        initialValue: selectedStatus,
                        onChanged: (value) {
                          if (value != null) {
                            selectedStatus = value;
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: remarksController,
                        themeData: themeData,
                        fieldKey: kUserAdminFieldRemarks,
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('common.cancel'.tr),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  if (!await _validateJwtToken()) return;

                  final username = usernameController.text.trim();

                  try {
                    await userApi.initializeWithJwt();
                    final isAvailable =
                        await _checkUsernameAvailability(username);
                    if (!isAvailable) {
                      _showSnackBar(
                        'userAdmin.validation.usernameExists'.tr,
                        isError: true,
                      );
                      return;
                    }

                    final newUser = UserManagement(
                      username: username,
                      password: passwordController.text.trim(),
                      contactNumber: _emptyToNull(contactNumberController.text),
                      email: _emptyToNull(emailController.text),
                      department: _emptyToNull(departmentController.text),
                      status: selectedStatus,
                      remarks: _emptyToNull(remarksController.text),
                    );

                    await userApi.apiUsersPost(
                      userManagement: newUser,
                      idempotencyKey: generateIdempotencyKey(),
                    );

                    if (!mounted || !dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop();
                    _showSnackBar('userAdmin.success.created'.tr);
                    await _refreshUsers();
                  } catch (e) {
                    _showSnackBar(
                      'userAdmin.error.createFailed'.trParams({
                        'error': formatUserAdminError(e),
                      }),
                      isError: true,
                    );
                  }
                },
                child: Text('userAdmin.action.create'.tr),
              ),
            ],
          ),
        );
      },
    );

    usernameController.dispose();
    passwordController.dispose();
    contactNumberController.dispose();
    emailController.dispose();
    departmentController.dispose();
    remarksController.dispose();
  }

  Future<void> _showEditUserDialog(UserManagement user) async {
    final usernameController = TextEditingController(text: user.username ?? '');
    final passwordController = TextEditingController();
    final contactNumberController =
        TextEditingController(text: user.contactNumber ?? '');
    final emailController = TextEditingController(text: user.email ?? '');
    final departmentController =
        TextEditingController(text: user.department ?? '');
    final remarksController = TextEditingController(text: user.remarks ?? '');
    String selectedStatus = normalizeAccountStatusCode(user.status);
    if (selectedStatus.isEmpty) {
      selectedStatus = kUserAdminStatusActive;
    }
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final themeData = controller.currentBodyTheme.value;
        return Theme(
          data: themeData,
          child: AlertDialog(
            title: Text('userAdmin.dialog.editTitle'.tr),
            backgroundColor: themeData.colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.0),
            ),
            content: SizedBox(
              width: 480,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTextField(
                        controller: usernameController,
                        themeData: themeData,
                        fieldKey: kUserAdminFieldUsername,
                        isRequired: true,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: passwordController,
                        themeData: themeData,
                        fieldKey: kUserAdminFieldNewPassword,
                        obscureText: true,
                        helperText: 'userAdmin.helper.passwordOptional'.tr,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: contactNumberController,
                        themeData: themeData,
                        fieldKey: kUserAdminFieldContactNumber,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: emailController,
                        themeData: themeData,
                        fieldKey: kUserAdminFieldEmail,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: departmentController,
                        themeData: themeData,
                        fieldKey: kUserAdminFieldDepartment,
                      ),
                      const SizedBox(height: 12),
                      _buildStatusField(
                        themeData: themeData,
                        initialValue: selectedStatus,
                        onChanged: (value) {
                          if (value != null) {
                            selectedStatus = value;
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: remarksController,
                        themeData: themeData,
                        fieldKey: kUserAdminFieldRemarks,
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('common.cancel'.tr),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  if (!await _validateJwtToken()) return;

                  final nextUsername = usernameController.text.trim();

                  try {
                    await userApi.initializeWithJwt();
                    if (nextUsername != (user.username ?? '')) {
                      final isAvailable =
                          await _checkUsernameAvailability(nextUsername);
                      if (!isAvailable) {
                        _showSnackBar(
                          'userAdmin.validation.usernameExists'.tr,
                          isError: true,
                        );
                        return;
                      }
                    }

                    final updatedUser = user.copyWith(
                      username: nextUsername,
                      password: passwordController.text.trim().isEmpty
                          ? user.password
                          : passwordController.text.trim(),
                      contactNumber: _emptyToNull(contactNumberController.text),
                      email: _emptyToNull(emailController.text),
                      department: _emptyToNull(departmentController.text),
                      status: selectedStatus,
                      remarks: _emptyToNull(remarksController.text),
                    );

                    await userApi.apiUsersUserIdPut(
                      userId: '${user.userId}',
                      userManagement: updatedUser,
                      idempotencyKey: generateIdempotencyKey(),
                    );

                    if (!mounted || !dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop();
                    _showSnackBar('userAdmin.success.updated'.tr);
                    await _refreshUsers();
                  } catch (e) {
                    _showSnackBar(
                      'userAdmin.error.updateFailed'.trParams({
                        'error': formatUserAdminError(e),
                      }),
                      isError: true,
                    );
                  }
                },
                child: Text('common.save'.tr),
              ),
            ],
          ),
        );
      },
    );

    usernameController.dispose();
    passwordController.dispose();
    contactNumberController.dispose();
    emailController.dispose();
    departmentController.dispose();
    remarksController.dispose();
  }

  Future<void> _deleteUser(UserManagement user) async {
    final themeData = controller.currentBodyTheme.value;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Theme(
          data: themeData,
          child: AlertDialog(
            title: Text('userAdmin.delete.confirmTitle'.tr),
            content: Text('userAdmin.delete.confirmBody'.tr),
            backgroundColor: themeData.colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.0),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text('common.cancel'.tr),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeData.colorScheme.error,
                  foregroundColor: themeData.colorScheme.onError,
                ),
                child: Text('userAdmin.action.delete'.tr),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) return;
    if (!await _validateJwtToken()) return;

    try {
      await userApi.initializeWithJwt();
      await userApi.apiUsersUserIdDelete(userId: '${user.userId}');
      _showSnackBar('userAdmin.success.deleted'.tr);
      await _refreshUsers();
    } catch (e) {
      _showSnackBar(
        'userAdmin.error.deleteFailed'.trParams({
          'error': formatUserAdminError(e),
        }),
        isError: true,
      );
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required ThemeData themeData,
    required String fieldKey,
    bool isRequired = false,
    bool obscureText = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? helperText,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: userAdminFieldLabel(fieldKey, required: isRequired),
        helperText: helperText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        filled: true,
        fillColor: themeData.colorScheme.surfaceContainer,
      ),
      obscureText: obscureText,
      maxLines: obscureText ? 1 : maxLines,
      keyboardType: keyboardType,
      validator: (value) => validateUserAdminField(
        fieldKey,
        value,
        required: isRequired,
      ),
    );
  }

  Widget _buildStatusField({
    required ThemeData themeData,
    required String initialValue,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: initialValue,
      decoration: InputDecoration(
        labelText: userAdminFieldLabel(kUserAdminFieldStatus, required: true),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        filled: true,
        fillColor: themeData.colorScheme.surfaceContainer,
      ),
      items: const [kUserAdminStatusActive, kUserAdminStatusInactive]
          .map(
            (status) => DropdownMenuItem<String>(
              value: status,
              child: Text(userAdminStatusKey(status).tr),
            ),
          )
          .toList(),
      onChanged: onChanged,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'userAdmin.validation.statusRequired'.tr;
        }
        return null;
      },
    );
  }

  Widget _buildSearchCard(ThemeData themeData) {
    return Card(
      elevation: 2,
      color: themeData.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: userAdminSearchHintKey(_searchType).tr,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.trim().isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            _applyFilters('');
                          },
                          icon: const Icon(Icons.clear),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: themeData.colorScheme.surfaceContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 160, maxWidth: 220),
              child: DropdownButtonFormField<String>(
                initialValue: _searchType,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: themeData.colorScheme.surfaceContainer,
                ),
                items: const [
                  kUserAdminSearchTypeUsername,
                  kUserAdminSearchTypeStatus,
                  kUserAdminSearchTypeDepartment,
                  kUserAdminSearchTypeContactNumber,
                  kUserAdminSearchTypeEmail,
                ]
                    .map(
                      (type) => DropdownMenuItem<String>(
                        value: type,
                        child: Text(userAdminSearchTypeLabelKey(type).tr),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _searchType = value;
                  });
                  _applyFilters(_searchController.text);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStateView(
    ThemeData themeData, {
    required IconData icon,
    required Color color,
    required String message,
    bool showReloginAction = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 16),
            Text(
              message,
              style: themeData.textTheme.titleMedium?.copyWith(color: color),
              textAlign: TextAlign.center,
            ),
            if (showReloginAction) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Get.offAllNamed(Routes.login),
                child: Text('userAdmin.action.relogin'.tr),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUserList(ThemeData themeData) {
    return RefreshIndicator(
      onRefresh: _refreshUsers,
      color: themeData.colorScheme.primary,
      backgroundColor: themeData.colorScheme.surfaceContainer,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _filteredUsers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final user = _filteredUsers[index];
          return Card(
            elevation: 2,
            color: themeData.colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.username?.trim().isNotEmpty == true
                              ? user.username!
                              : 'userAdmin.value.unknownUser'.tr,
                          style: themeData.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: normalizeAccountStatusCode(user.status) ==
                                  kUserAdminStatusActive
                              ? themeData.colorScheme.primaryContainer
                              : themeData.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          userAdminStatusKey(user.status).tr,
                          style: themeData.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInfoLine(
                    themeData,
                    userAdminFieldTranslationKey(kUserAdminFieldDepartment).tr,
                    userAdminDisplayValue(user.department),
                  ),
                  _buildInfoLine(
                    themeData,
                    userAdminFieldTranslationKey(kUserAdminFieldContactNumber)
                        .tr,
                    userAdminDisplayValue(user.contactNumber),
                  ),
                  _buildInfoLine(
                    themeData,
                    userAdminFieldTranslationKey(kUserAdminFieldEmail).tr,
                    userAdminDisplayValue(user.email),
                  ),
                  _buildInfoLine(
                    themeData,
                    userAdminFieldTranslationKey(kUserAdminFieldCreatedTime).tr,
                    formatUserAdminDateTime(user.createdTime),
                  ),
                  _buildInfoLine(
                    themeData,
                    userAdminFieldTranslationKey(kUserAdminFieldModifiedTime)
                        .tr,
                    formatUserAdminDateTime(user.modifiedTime),
                  ),
                  _buildInfoLine(
                    themeData,
                    userAdminFieldTranslationKey(kUserAdminFieldRemarks).tr,
                    userAdminDisplayValue(user.remarks),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'userAdmin.action.edit'.tr,
                        onPressed: () => _showEditUserDialog(user),
                        icon: Icon(
                          Icons.edit_outlined,
                          color: themeData.colorScheme.primary,
                        ),
                      ),
                      IconButton(
                        tooltip: 'userAdmin.action.delete'.tr,
                        onPressed: () => _deleteUser(user),
                        icon: Icon(
                          Icons.delete_outline,
                          color: themeData.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoLine(ThemeData themeData, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: RichText(
        text: TextSpan(
          style: themeData.textTheme.bodyMedium?.copyWith(
            color: themeData.colorScheme.onSurfaceVariant,
          ),
          children: [
            TextSpan(
              text: 'common.labelWithColon'.trParams({'label': label}),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData = controller.currentBodyTheme.value;

      return DashboardPageTemplate(
        theme: themeData,
        title: 'userAdmin.page.title'.tr,
        pageType: DashboardPageType.manager,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        onThemeToggle: controller.toggleBodyTheme,
        actions: [
          if (_isAdmin)
            DashboardPageBarAction(
              icon: Icons.person_add_alt_1_outlined,
              onPressed: () => _showCreateUserDialog(),
              tooltip: 'userAdmin.action.create'.tr,
            ),
          DashboardPageBarAction(
            icon: Icons.refresh,
            onPressed: () => _refreshUsers(),
            tooltip: 'userAdmin.action.refresh'.tr,
          ),
        ],
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isAdmin) _buildSearchCard(themeData),
              if (_isAdmin) const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CupertinoActivityIndicator(
                          color: themeData.colorScheme.primary,
                          radius: 16,
                        ),
                      )
                    : _statusMessage.isNotEmpty && _filteredUsers.isEmpty
                        ? _buildStateView(
                            themeData,
                            icon: CupertinoIcons.exclamationmark_triangle,
                            color: themeData.colorScheme.error,
                            message: _statusMessage,
                            showReloginAction: _showReloginAction,
                          )
                        : _filteredUsers.isEmpty
                            ? _buildStateView(
                                themeData,
                                icon: CupertinoIcons.person_2,
                                color: themeData.colorScheme.onSurfaceVariant,
                                message: _searchController.text.trim().isEmpty
                                    ? 'userAdmin.empty.default'.tr
                                    : 'userAdmin.empty.filtered'.tr,
                              )
                            : _buildUserList(themeData),
              ),
            ],
          ),
        ),
      );
    });
  }
}
