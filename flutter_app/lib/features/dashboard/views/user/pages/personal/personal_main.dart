// ignore_for_file: use_build_context_synchronously
import 'dart:math';

import 'package:final_assignment_front/features/api/driver_information_controller_api.dart';
import 'package:final_assignment_front/features/api/user_management_controller_api.dart';
import 'package:final_assignment_front/features/dashboard/controllers/user_dashboard_screen_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/user/widgets/user_page_app_bar.dart';
import 'package:final_assignment_front/features/model/driver_information.dart';
import 'package:final_assignment_front/features/model/user_management.dart';
import 'package:final_assignment_front/i18n/personal_field_localizers.dart';
import 'package:final_assignment_front/utils/services/api_client.dart';
import 'package:final_assignment_front/utils/ui/ui_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

String generateIdempotencyKey() =>
    DateTime.now().millisecondsSinceEpoch.toString();

String generateDriverLicenseNumber() {
  final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
  final timestampPart = timestamp.substring(timestamp.length - 8);
  final randomPart = (1000 + Random().nextInt(9000)).toString();
  return timestampPart + randomPart;
}

class PersonalMainPage extends StatefulWidget {
  const PersonalMainPage({super.key});

  @override
  State<PersonalMainPage> createState() => _PersonalMainPageState();
}

class _PersonalMainPageState extends State<PersonalMainPage> {
  final UserDashboardController dashboardController =
      Get.find<UserDashboardController>();
  final DriverInformationControllerApi driverApi =
      DriverInformationControllerApi();
  final UserManagementControllerApi userApi = UserManagementControllerApi();
  final ApiClient apiClient = ApiClient();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _contactNumberController =
      TextEditingController();
  final TextEditingController _idCardController = TextEditingController();
  final TextEditingController _licenseController = TextEditingController();

  final ScrollController _scrollController = ScrollController();

  Future<UserManagement?>? _userFuture;
  DriverInformation? _driverInfo;
  bool _isLoading = true;
  bool _driverLicenseFinalized = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    ever(dashboardController.refreshPersonalPage, (_) {
      if (dashboardController.refreshPersonalPage.value && mounted) {
        _loadCurrentUser();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _contactNumberController.dispose();
    _idCardController.dispose();
    _licenseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwtToken');
      final storedUsername = prefs.getString('userName');
      if (jwtToken == null || storedUsername == null) {
        throw Exception('personal.error.notLoggedIn'.tr);
      }

      await driverApi.initializeWithJwt();
      await userApi.initializeWithJwt();

      final user =
          await userApi.apiUsersSearchUsernameGet(username: storedUsername);
      if (user == null || user.userId == null) {
        throw Exception('personal.error.loadUserFailed'.tr);
      }

      final userId = user.userId!;
      DriverInformation? driverInfo =
          await driverApi.apiDriversDriverIdGet(driverId: userId);

      if (driverInfo == null) {
        final newDriver = DriverInformation(
          driverId: userId,
          name: user.username ?? 'personal.value.unknownUser'.tr,
          contactNumber: user.contactNumber ?? '',
          idCardNumber: '',
          driverLicenseNumber: generateDriverLicenseNumber(),
        );
        await driverApi.apiDriversPost(
          driverInformation: newDriver,
          idempotencyKey: generateIdempotencyKey(),
        );
        driverInfo = await driverApi.apiDriversDriverIdGet(driverId: userId);
        _driverLicenseFinalized = true;
      } else {
        _driverLicenseFinalized =
            driverInfo.driverLicenseNumber?.isNotEmpty ?? false;
      }

      setState(() {
        _driverInfo = driverInfo;
        _userFuture = Future.value(user);
        _nameController.text = driverInfo?.name ?? user.username ?? '';
        _contactNumberController.text =
            driverInfo?.contactNumber ?? user.contactNumber ?? '';
        _idCardController.text = driverInfo?.idCardNumber ?? '';
        _licenseController.text = driverInfo?.driverLicenseNumber ?? '';
        _isLoading = false;
      });

      dashboardController.updateCurrentUser(
        driverInfo?.name ?? user.username ?? '',
        user.email ?? '',
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = formatPersonalError(e);
      });
    }
  }

  Future<void> _updateField(String field, String value) async {
    setState(() => _isLoading = true);
    try {
      final user = await _userFuture;
      if (user == null || user.userId == null) {
        throw Exception('personal.error.currentUserNotFound'.tr);
      }

      final userId = user.userId!;
      final idempotencyKey = generateIdempotencyKey();
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwtToken');
      if (jwtToken == null) {
        throw Exception('personal.error.loginTokenMissing'.tr);
      }

      switch (field) {
        case 'name':
        case 'contactNumber':
        case 'idCardNumber':
        case 'driverLicenseNumber':
          final updatedDriver = DriverInformation(
            driverId: userId,
            name: field == 'name'
                ? value
                : _driverInfo?.name ??
                    user.username ??
                    'personal.value.unknownUser'.tr,
            contactNumber: field == 'contactNumber'
                ? value
                : _driverInfo?.contactNumber ?? user.contactNumber ?? '',
            idCardNumber: field == 'idCardNumber'
                ? value
                : _driverInfo?.idCardNumber ?? '',
            driverLicenseNumber: field == 'driverLicenseNumber'
                ? value
                : _driverInfo?.driverLicenseNumber ?? '',
          );
          await driverApi.apiDriversPost(
            driverInformation: updatedDriver,
            idempotencyKey: idempotencyKey,
          );
          break;
        case 'password':
          await apiClient.invokeAPI(
            '/api/users/me/password?idempotencyKey=$idempotencyKey',
            'PUT',
            const [],
            value,
            {
              'Authorization': 'Bearer $jwtToken',
              'Content-Type': 'text/plain; charset=utf-8',
            },
            const {},
            'text/plain',
            const ['bearerAuth'],
          );
          break;
        default:
          throw Exception(
            'personal.error.unknownField'.trParams({'field': field}),
          );
      }

      await _loadCurrentUser();
      AppSnackbar.showSuccess(
        context,
        message: 'personal.success.fieldUpdated'.trParams(
          {'field': personalFieldLabel(field)},
        ),
      );
    } catch (e) {
      AppSnackbar.showError(context, message: formatPersonalError(e));
      setState(() => _isLoading = false);
    }
  }

  void _showEditDialog(
    String field,
    TextEditingController controller,
    VoidCallback onSave,
  ) {
    final label = personalFieldLabel(field);
    AppDialog.showCustomDialog(
      context: context,
      title: 'personal.editDialog.title'.trParams({'field': label}),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: 'personal.editDialog.hint'.trParams({'field': label}),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            onSave();
          },
          child: Text('common.save'.tr),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData = dashboardController.currentBodyTheme.value;
      return Scaffold(
        backgroundColor: themeData.colorScheme.surface,
        appBar: UserPageAppBar(
          theme: themeData,
          title: 'personal.title'.tr,
          onThemeToggle: dashboardController.toggleBodyTheme,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage.isNotEmpty
                ? Center(
                    child: Text(
                      _errorMessage,
                      style: themeData.textTheme.bodyLarge?.copyWith(
                        color: themeData.colorScheme.error,
                      ),
                    ),
                  )
                : FutureBuilder<UserManagement?>(
                    future: _userFuture,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final user = snapshot.data!;
                      return CupertinoScrollbar(
                        controller: _scrollController,
                        child: ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          children: [
                            _buildEditableTile(
                              themeData,
                              title: personalFieldLabel('name'),
                              value: personalDisplayValue(_driverInfo?.name),
                              onTap: () {
                                _nameController.text = _driverInfo?.name ?? '';
                                _showEditDialog('name', _nameController, () {
                                  _updateField('name', _nameController.text);
                                });
                              },
                            ),
                            _buildEditableTile(
                              themeData,
                              title: personalFieldLabel('contactNumber'),
                              value: personalDisplayValue(
                                _driverInfo?.contactNumber ??
                                    user.contactNumber,
                              ),
                              onTap: () {
                                _contactNumberController.text =
                                    _driverInfo?.contactNumber ??
                                        user.contactNumber ??
                                        '';
                                _showEditDialog(
                                  'contactNumber',
                                  _contactNumberController,
                                  () => _updateField(
                                    'contactNumber',
                                    _contactNumberController.text,
                                  ),
                                );
                              },
                            ),
                            _buildEditableTile(
                              themeData,
                              title: personalFieldLabel('idCardNumber'),
                              value: personalDisplayValue(
                                _driverInfo?.idCardNumber,
                              ),
                              onTap: () {
                                _idCardController.text =
                                    _driverInfo?.idCardNumber ?? '';
                                _showEditDialog(
                                  'idCardNumber',
                                  _idCardController,
                                  () => _updateField(
                                    'idCardNumber',
                                    _idCardController.text,
                                  ),
                                );
                              },
                            ),
                            _buildEditableTile(
                              themeData,
                              title: personalFieldLabel('driverLicenseNumber'),
                              value: personalDisplayValue(
                                _driverInfo?.driverLicenseNumber,
                              ),
                              onTap: _driverLicenseFinalized
                                  ? null
                                  : () {
                                      _licenseController.text =
                                          _driverInfo?.driverLicenseNumber ??
                                              '';
                                      _showEditDialog(
                                        'driverLicenseNumber',
                                        _licenseController,
                                        () => _updateField(
                                          'driverLicenseNumber',
                                          _licenseController.text,
                                        ),
                                      );
                                    },
                            ),
                            _buildEditableTile(
                              themeData,
                              title: personalFieldLabel('password'),
                              value: 'personal.value.changePassword'.tr,
                              onTap: () {
                                _passwordController.clear();
                                _showEditDialog(
                                  'password',
                                  _passwordController,
                                  () => _updateField(
                                    'password',
                                    _passwordController.text,
                                  ),
                                );
                              },
                            ),
                            _buildDisplayTile(
                              themeData,
                              title: personalFieldLabel('email'),
                              value: personalDisplayValue(user.email),
                            ),
                            _buildDisplayTile(
                              themeData,
                              title: personalFieldLabel('status'),
                              value: localizePersonalAccountStatus(user.status),
                            ),
                            _buildDisplayTile(
                              themeData,
                              title: personalFieldLabel('createdTime'),
                              value: formatPersonalDateTime(user.createdTime),
                            ),
                            _buildDisplayTile(
                              themeData,
                              title: personalFieldLabel('modifiedTime'),
                              value: formatPersonalDateTime(user.modifiedTime),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      );
    });
  }

  Widget _buildEditableTile(
    ThemeData theme, {
    required String title,
    required String value,
    VoidCallback? onTap,
  }) {
    return Card(
      elevation: 2,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: onTap != null
            ? Icon(Icons.edit, color: theme.colorScheme.primary)
            : null,
        onTap: onTap,
      ),
    );
  }

  Widget _buildDisplayTile(
    ThemeData theme, {
    required String title,
    required String value,
  }) {
    return Card(
      elevation: 2,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
