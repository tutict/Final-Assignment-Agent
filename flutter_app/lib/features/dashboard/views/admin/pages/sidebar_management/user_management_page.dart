import 'dart:async';

import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/api/role_management_controller_api.dart';
import 'package:final_assignment_front/features/api/user_management_controller_api.dart';
import 'package:final_assignment_front/features/dashboard/controllers/admin_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/features/model/role_management.dart';
import 'package:final_assignment_front/features/model/user_management.dart';
import 'package:final_assignment_front/i18n/status_localizers.dart';
import 'package:final_assignment_front/i18n/user_admin_localizers.dart';
import 'package:final_assignment_front/utils/helpers/api_exception.dart';
import 'package:final_assignment_front/utils/helpers/role_utils.dart';
import 'package:final_assignment_front/utils/services/auth_token_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:uuid/uuid.dart';

String generateIdempotencyKey() => const Uuid().v4();

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  static const int _pageSize = 20;
  static const int _rolePageSize = 100;

  final DashboardController controller = Get.find<DashboardController>();
  final UserManagementControllerApi userApi = UserManagementControllerApi();
  final RoleManagementControllerApi roleApi = RoleManagementControllerApi();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<UserManagement> _allUsers = [];
  List<UserManagement> _filteredUsers = [];

  String _activeQuery = '';
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isAdmin = false;
  bool _showReloginAction = false;
  String _statusMessage = '';
  String _searchType = kUserAdminSearchTypeUsername;
  String? _currentUsername;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _initialize();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
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
      final roles = decodedToken['roles'];

      if (!hasAnyRole(roles, const ['SUPER_ADMIN', 'ADMIN'])) {
        if (mounted) {
          setState(() {
            _isAdmin = false;
            _statusMessage = 'userAdmin.error.adminOnly'.tr;
          });
        }
        return;
      }

      _isAdmin = true;
      await _loadUsers(reset: true);
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

  Future<void> _loadUsers({bool reset = false, String? query}) async {
    if (!_isAdmin) return;
    if (reset) {
      _currentPage = 1;
      _hasMore = true;
      _activeQuery = (query ?? _searchController.text).trim();
      _allUsers.clear();
      _filteredUsers.clear();
    }
    if (!reset && (_isLoading || !_hasMore)) {
      return;
    }

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
      final users =
          await _loadUserPage(page: _currentPage, query: _activeQuery);
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
        _allUsers.addAll(visibleUsers);
        _rebuildVisibleUsers();
        _hasMore = users.length == _pageSize;
        _currentPage++;
      });
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
    await _refreshUsersWithQuery();
  }

  Future<List<UserManagement>> _loadUserPage({
    required int page,
    required String query,
  }) {
    if (query.isEmpty) {
      return userApi.apiUsersGet(page: page, size: _pageSize);
    }

    switch (_searchType) {
      case kUserAdminSearchTypeStatus:
        return userApi.apiUsersSearchStatusGet(
          status: query,
          page: page,
          size: _pageSize,
        );
      case kUserAdminSearchTypeDepartment:
        return userApi.apiUsersSearchDepartmentPrefixGet(
          department: query,
          page: page,
          size: _pageSize,
        );
      case kUserAdminSearchTypeContactNumber:
        return userApi.apiUsersSearchContactGet(
          contactNumber: query,
          page: page,
          size: _pageSize,
        );
      case kUserAdminSearchTypeEmail:
        return userApi.apiUsersSearchEmailGet(
          email: query,
          page: page,
          size: _pageSize,
        );
      case kUserAdminSearchTypeUsername:
      default:
        return userApi.apiUsersSearchUsernameFuzzyGet(
          username: query,
          page: page,
          size: _pageSize,
        );
    }
  }

  void _rebuildVisibleUsers() {
    _filteredUsers = List<UserManagement>.from(_allUsers);
    if (_filteredUsers.isEmpty) {
      _statusMessage = _activeQuery.isEmpty
          ? 'userAdmin.empty.default'.tr
          : 'userAdmin.empty.filtered'.tr;
    } else {
      _statusMessage = '';
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _isLoading || !_hasMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadUsers();
    }
  }

  Future<void> _refreshUsersWithQuery({String? query}) async {
    _searchDebounce?.cancel();
    final effectiveQuery = (query ?? _searchController.text).trim();
    _searchController.value = TextEditingValue(
      text: effectiveQuery,
      selection: TextSelection.collapsed(offset: effectiveQuery.length),
    );
    await _loadUsers(reset: true, query: effectiveQuery);
  }

  void _scheduleSearchRefresh(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) {
        return;
      }
      _refreshUsersWithQuery(query: value);
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
                            setState(() {});
                            _refreshUsersWithQuery(query: '');
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
                onChanged: (value) {
                  setState(() {});
                  _scheduleSearchRefresh(value);
                },
                onSubmitted: (value) => _refreshUsersWithQuery(query: value),
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
                  _refreshUsersWithQuery(query: _searchController.text);
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
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _filteredUsers.length +
            ((_isLoading && _allUsers.isNotEmpty) ? 1 : 0),
        separatorBuilder: (_, index) => index >= _filteredUsers.length - 1
            ? const SizedBox.shrink()
            : const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index >= _filteredUsers.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CupertinoActivityIndicator(radius: 12),
              ),
            );
          }
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
                        tooltip: 'userAdmin.action.manageRoles'.tr,
                        onPressed: () => _showManageRolesDialog(user),
                        icon: Icon(
                          Icons.admin_panel_settings_outlined,
                          color: themeData.colorScheme.secondary,
                        ),
                      ),
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

  bool _isRoleActive(RoleManagement role) {
    final status = normalizeAccountStatusCode(role.status);
    return status.isEmpty || status == kUserAdminStatusActive;
  }

  int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Set<int> _boundRoleIds(List<Map<String, dynamic>> bindings) {
    return bindings
        .map((binding) => _readInt(binding['roleId']))
        .whereType<int>()
        .toSet();
  }

  String _roleLabel(RoleManagement? role, int? roleId) {
    if (role == null) {
      return roleId == null ? 'common.none'.tr : 'ROLE#$roleId';
    }
    if (role.roleName?.trim().isNotEmpty == true &&
        role.roleCode?.trim().isNotEmpty == true) {
      return '${role.roleName} (${role.roleCode})';
    }
    if (role.roleName?.trim().isNotEmpty == true) {
      return role.roleName!;
    }
    if (role.roleCode?.trim().isNotEmpty == true) {
      return role.roleCode!;
    }
    return 'ROLE#${role.roleId}';
  }

  Future<List<RoleManagement>> _fetchAllRoles() async {
    final roles = <RoleManagement>[];
    var page = 1;
    while (true) {
      final pageRoles = await roleApi.apiRolesGet(
        page: page,
        size: _rolePageSize,
      );
      roles.addAll(pageRoles);
      if (pageRoles.length < _rolePageSize) {
        break;
      }
      page++;
    }
    return roles;
  }

  Future<void> _showManageRolesDialog(UserManagement user) async {
    if (user.userId == null) {
      _showSnackBar(
        'userAdmin.error.notFound'.trParams({'message': 'userId'}),
        isError: true,
      );
      return;
    }
    if (!await _validateJwtToken()) return;

    try {
      await userApi.initializeWithJwt();
      await roleApi.initializeWithJwt();

      final allRoles = await _fetchAllRoles();
      final availableRoles = allRoles
          .where((role) => role.roleId != null && _isRoleActive(role))
          .toList();
      final roleById = <int, RoleManagement>{
        for (final role in availableRoles) role.roleId!: role,
      };

      var bindings = await userApi.apiUsersUserIdRolesGet(userId: user.userId!);
      var dialogBusy = false;

      int? firstAvailableRoleId() {
        final assigned = _boundRoleIds(bindings);
        for (final role in availableRoles) {
          final roleId = role.roleId;
          if (roleId != null && !assigned.contains(roleId)) {
            return roleId;
          }
        }
        return null;
      }

      int? selectedRoleId = firstAvailableRoleId();

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final themeData = controller.currentBodyTheme.value;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final assignedRoleIds = _boundRoleIds(bindings);
              final selectableRoles = availableRoles
                  .where((role) => !assignedRoleIds.contains(role.roleId))
                  .toList();

              if (selectedRoleId != null &&
                  selectableRoles
                      .every((role) => role.roleId != selectedRoleId)) {
                selectedRoleId = selectableRoles.isNotEmpty
                    ? selectableRoles.first.roleId
                    : null;
              }

              Future<void> reloadBindings() async {
                bindings =
                    await userApi.apiUsersUserIdRolesGet(userId: user.userId!);
                selectedRoleId = firstAvailableRoleId();
              }

              Future<void> addRole() async {
                if (selectedRoleId == null) {
                  _showSnackBar(
                    'userAdmin.validation.roleRequired'.tr,
                    isError: true,
                  );
                  return;
                }
                setDialogState(() => dialogBusy = true);
                try {
                  await userApi.apiUsersUserIdRolesPost(
                    userId: user.userId!,
                    body: {
                      'userId': user.userId,
                      'roleId': selectedRoleId,
                    },
                    idempotencyKey: generateIdempotencyKey(),
                  );
                  await reloadBindings();
                  if (mounted) {
                    _showSnackBar('userAdmin.success.roleAdded'.tr);
                  }
                  setDialogState(() {});
                } catch (e) {
                  if (mounted) {
                    _showSnackBar(
                      'userAdmin.error.roleLoadFailed'
                          .trParams({'error': formatUserAdminError(e)}),
                      isError: true,
                    );
                  }
                } finally {
                  if (dialogContext.mounted) {
                    setDialogState(() => dialogBusy = false);
                  }
                }
              }

              Future<void> removeRole(int relationId) async {
                setDialogState(() => dialogBusy = true);
                try {
                  await userApi.apiUsersRolesRelationIdDelete(
                    relationId: relationId,
                  );
                  await reloadBindings();
                  if (mounted) {
                    _showSnackBar('userAdmin.success.roleRemoved'.tr);
                  }
                  setDialogState(() {});
                } catch (e) {
                  if (mounted) {
                    _showSnackBar(
                      'userAdmin.error.roleLoadFailed'
                          .trParams({'error': formatUserAdminError(e)}),
                      isError: true,
                    );
                  }
                } finally {
                  if (dialogContext.mounted) {
                    setDialogState(() => dialogBusy = false);
                  }
                }
              }

              return Theme(
                data: themeData,
                child: AlertDialog(
                  title: Text(
                    'userAdmin.dialog.manageRolesTitle'.trParams(
                        {'username': user.username ?? '${user.userId}'}),
                  ),
                  backgroundColor: themeData.colorScheme.surfaceContainerLowest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  content: SizedBox(
                    width: 480,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'userAdmin.action.manageRoles'.tr,
                          style: themeData.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (bindings.isEmpty)
                          Text(
                            'userAdmin.empty.roles'.tr,
                            style: themeData.textTheme.bodyMedium,
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: bindings.map((binding) {
                              final relationId = _readInt(binding['id']);
                              final roleId = _readInt(binding['roleId']);
                              return InputChip(
                                label:
                                    Text(_roleLabel(roleById[roleId], roleId)),
                                onDeleted: dialogBusy || relationId == null
                                    ? null
                                    : () => removeRole(relationId),
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<int>(
                          initialValue: selectedRoleId,
                          decoration: InputDecoration(
                            labelText: 'userAdmin.hint.selectRole'.tr,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                            filled: true,
                            fillColor: themeData.colorScheme.surfaceContainer,
                          ),
                          items: selectableRoles
                              .map(
                                (role) => DropdownMenuItem<int>(
                                  value: role.roleId,
                                  child: Text(_roleLabel(role, role.roleId)),
                                ),
                              )
                              .toList(),
                          onChanged: dialogBusy
                              ? null
                              : (value) {
                                  setDialogState(() => selectedRoleId = value);
                                },
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: dialogBusy
                          ? null
                          : () => Navigator.of(dialogContext).pop(),
                      child: Text('common.cancel'.tr),
                    ),
                    ElevatedButton(
                      onPressed: dialogBusy || selectableRoles.isEmpty
                          ? null
                          : addRole,
                      child: Text('common.add'.tr),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      _showSnackBar(
        'userAdmin.error.roleLoadFailed'
            .trParams({'error': formatUserAdminError(e)}),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData = controller.currentBodyTheme.value;

      return DashboardPageTemplate(
        theme: themeData,
        title: 'userAdmin.page.title'.tr,
        pageType: DashboardPageType.admin,
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
                child: _isLoading && _allUsers.isEmpty
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
