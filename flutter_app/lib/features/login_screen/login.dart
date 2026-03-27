// ignore_for_file: use_build_context_synchronously
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/config/themes/app_theme.dart';
import 'package:final_assignment_front/features/api/auth_controller_api.dart';
import 'package:final_assignment_front/features/api/driver_information_controller_api.dart';
import 'package:final_assignment_front/features/api/user_management_controller_api.dart';
import 'package:final_assignment_front/features/dashboard/controllers/chat_controller.dart';
import 'package:final_assignment_front/i18n/auth_localizers.dart';
import 'package:final_assignment_front/features/model/driver_information.dart';
import 'package:final_assignment_front/features/model/login_request.dart';
import 'package:final_assignment_front/features/model/register_request.dart';
import 'package:final_assignment_front/shared_components/local_captcha_main.dart';
import 'package:final_assignment_front/utils/helpers/api_exception.dart';
import 'package:final_assignment_front/utils/services/auth_token_store.dart';

String generateIdempotencyKey() =>
    DateTime.now().millisecondsSinceEpoch.toString();

mixin ValidatorMixin {
  String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'auth.validation.emailRequired'.tr;
    }
    final emailRegex =
        RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(value)) {
      return 'auth.validation.emailInvalid'.tr;
    }
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'auth.validation.passwordRequired'.tr;
    }
    if (value.length < 5) {
      return 'auth.validation.passwordShort'.tr;
    }
    return null;
  }
}

enum _AuthMode { login, register }

class LoginScreen extends StatefulWidget with ValidatorMixin {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with ValidatorMixin {
  late final AuthControllerApi authApi;
  late final DriverInformationControllerApi driverApi;

  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerConfirmController = TextEditingController();

  bool _isDarkMode = false;
  bool _isSubmitting = false;
  bool _hasSentRegisterRequest = false;
  bool _obscureLoginPassword = true;
  bool _obscureRegisterPassword = true;
  bool _obscureConfirmPassword = true;
  _AuthMode _mode = _AuthMode.login;
  String? _userRole;

  ThemeData get _pageTheme =>
      _isDarkMode ? AppTheme.basicDark : AppTheme.basicLight;

  void setMode(_AuthMode mode) {
    setState(() => _mode = mode);
  }

  void toggleLoginPasswordVisibility() {
    setState(() => _obscureLoginPassword = !_obscureLoginPassword);
  }

  void toggleRegisterPasswordVisibility() {
    setState(() => _obscureRegisterPassword = !_obscureRegisterPassword);
  }

  void toggleConfirmPasswordVisibility() {
    setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
  }

  @override
  void initState() {
    super.initState();
    authApi = AuthControllerApi();
    driverApi = DriverInformationControllerApi();
    if (!Get.isRegistered<ChatController>()) {
      Get.lazyPut(() => ChatController());
    }
    _loadTheme();
  }

  @override
  void dispose() {
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _registerConfirmController.dispose();
    super.dispose();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _isDarkMode = prefs.getBool('isDarkMode') ?? false);
  }

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _isDarkMode = !_isDarkMode);
    await prefs.setBool('isDarkMode', _isDarkMode);
  }

  Map<String, dynamic> _decodeJwt(String token) {
    final parts = token.split('.');
    if (parts.length != 3) throw const FormatException('invalid_jwt');
    final payload = base64Url.decode(base64Url.normalize(parts[1]));
    return jsonDecode(utf8.decode(payload));
  }

  Future<void> _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    final error = await _authenticateUser(
      _loginEmailController.text.trim(),
      _loginPasswordController.text.trim(),
    );
    if (mounted) setState(() => _isSubmitting = false);
    if (error == null) {
      Get.offAllNamed(
        _userRole == 'ADMIN' ? Routes.dashboard : Routes.userDashboard,
      );
      return;
    }
    _showMessage(error, isError: true);
  }

  Future<void> _handleRegister() async {
    if (!_registerFormKey.currentState!.validate()) return;
    if (_registerPasswordController.text != _registerConfirmController.text) {
      _showMessage('auth.error.passwordMismatch'.tr, isError: true);
      return;
    }
    if (_hasSentRegisterRequest) {
      _showMessage('auth.error.registering'.tr, isError: true);
      return;
    }
    final isCaptchaValid = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const LocalCaptchaMain(),
    );
    if (isCaptchaValid != true) {
      _showMessage('auth.error.registerCancelled'.tr, isError: true);
      return;
    }
    setState(() => _isSubmitting = true);
    final error = await _registerUser(
      _registerEmailController.text.trim(),
      _registerPasswordController.text.trim(),
    );
    if (mounted) setState(() => _isSubmitting = false);
    if (error == null) {
      Get.offAllNamed(
        _userRole == 'ADMIN' ? Routes.dashboard : Routes.userDashboard,
      );
      return;
    }
    _showMessage(error, isError: true);
  }

  Future<String?> _authenticateUser(String username, String password) async {
    try {
      final result = await authApi.apiAuthLoginPost(
        loginRequest: LoginRequest(username: username, password: password),
      );
      if (!result.containsKey('jwtToken')) {
        return result['message'] ?? 'auth.error.loginFailed'.tr;
      }

      final jwtToken = result['jwtToken'];
      final decodedJwt = _decodeJwt(jwtToken);
      _userRole = (decodedJwt['roles'] ?? 'USER') as String;

      final prefs = await SharedPreferences.getInstance();
      await AuthTokenStore.instance.setJwtToken(jwtToken);
      await prefs.setString('userRole', _userRole!);
      await prefs.setString('userName', username);

      final userData = result['user'] ?? {};
      final int? userIdFromLogin = userData['userId'];
      String resolvedName = userData['name'] ?? username.split('@').first;
      String resolvedEmail = userData['email'] ?? username;

      await driverApi.initializeWithJwt();
      final userManagementApi = UserManagementControllerApi();
      await userManagementApi.initializeWithJwt();

      int? userId = userIdFromLogin;
      try {
        final userInfo = await userManagementApi.apiUsersSearchUsernameGet(
            username: username);
        if (userInfo != null) {
          userId = userInfo.userId ?? userId;
          resolvedName = userInfo.realName ?? userInfo.username ?? resolvedName;
          resolvedEmail = userInfo.email ?? resolvedEmail;
        }
      } catch (_) {}

      String driverName = resolvedName;
      if (userId != null) {
        try {
          final driverInfo =
              await driverApi.apiDriversDriverIdGet(driverId: userId);
          if (driverInfo?.name != null && driverInfo!.name!.isNotEmpty) {
            driverName = driverInfo.name!;
          }
        } catch (error) {
          if (error is ApiException && error.code == 404) {
            await driverApi.apiDriversPost(
              driverInformation: DriverInformation(
                driverId: userId,
                name: resolvedName,
                contactNumber: '',
                idCardNumber: '',
              ),
              idempotencyKey: generateIdempotencyKey(),
            );
          }
        }
      }

      await prefs.setString('driverName', driverName);
      await prefs.setString('userEmail', resolvedEmail);
      if (userId != null) {
        await prefs.setString('userId', userId.toString());
      }

      Get.find<ChatController>().setUserRole(_userRole!);
      return null;
    } on FormatException {
      return 'auth.error.invalidJwt'.tr;
    } on ApiException catch (error) {
      return formatAuthApiError(error, 'auth.error.loginFailed'.tr);
    } catch (error) {
      return 'auth.error.loginError'.trParams({
        'error': formatAuthErrorDetail(error),
      });
    }
  }

  Future<String?> _registerUser(String username, String password) async {
    try {
      final registerResult = await authApi.apiAuthRegisterPost(
        registerRequest: RegisterRequest(
          username: username,
          password: password,
          idempotencyKey: generateIdempotencyKey(),
        ),
      );
      if (registerResult['status'] != 'CREATED') {
        return registerResult['error'] ?? 'auth.error.registerFailed'.tr;
      }
      _hasSentRegisterRequest = true;
      return _authenticateUser(username, password);
    } on ApiException catch (error) {
      return formatAuthApiError(error, 'auth.error.registerFailed'.tr);
    } catch (error) {
      return 'auth.error.registerError'.trParams({
        'error': formatAuthErrorDetail(error),
      });
    }
  }

  Future<void> _showResetPasswordDialog() async {
    final emailController = TextEditingController(
      text: _loginEmailController.text.trim(),
    );
    final passwordController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: _pageTheme,
        child: AlertDialog(
          title: Text('auth.resetPassword'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                decoration: InputDecoration(labelText: 'auth.email'.tr),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(labelText: 'auth.newPassword'.tr),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('common.cancel'.tr),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('common.continue'.tr),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    final emailError = validateEmail(emailController.text.trim());
    if (emailError != null) {
      _showMessage(emailError, isError: true);
      return;
    }
    final passwordError = validatePassword(passwordController.text.trim());
    if (passwordError != null) {
      _showMessage(passwordError, isError: true);
      return;
    }
    final isCaptchaValid = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const LocalCaptchaMain(),
    );
    if (isCaptchaValid != true) {
      _showMessage('auth.error.passwordResetCancelled'.tr, isError: true);
      return;
    }

    final jwtToken = await AuthTokenStore.instance.getJwtToken();
    if (jwtToken == null) {
      _showMessage('auth.error.loginRequiredForReset'.tr, isError: true);
      return;
    }

    try {
      final response = await authApi.apiClient.invokeAPI(
        '/api/users/me/password?idempotencyKey=${generateIdempotencyKey()}',
        'PUT',
        const [],
        passwordController.text.trim(),
        {
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'text/plain; charset=utf-8',
        },
        const {},
        'text/plain',
        const ['bearerAuth'],
      );
      if (response.statusCode == 200) {
        _showMessage('auth.success.passwordUpdated'.tr);
      } else {
        _showMessage(
          'auth.error.passwordResetFailed'
              .trParams({'code': '${response.statusCode}'}),
          isError: true,
        );
      }
    } on ApiException catch (error) {
      _showMessage(
        formatAuthApiError(
          error,
          'auth.error.passwordResetFailed'.trParams({'code': '${error.code}'}),
        ),
        isError: true,
      );
    } catch (error) {
      _showMessage(
        'auth.error.passwordResetError'.trParams({
          'error': formatAuthErrorDetail(error),
        }),
        isError: true,
      );
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Colors.red.shade700 : _pageTheme.colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _pageTheme;
    final isWide = MediaQuery.of(context).size.width >= 980;

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Stack(
          children: [
            const _LoginBackdrop(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                theme.colorScheme.primary,
                                theme.colorScheme.tertiary,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.motion_photos_auto_rounded,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('app.name'.tr,
                                  style: theme.textTheme.titleLarge),
                              Text(
                                'auth.brandTitle'.tr,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _toggleTheme,
                          icon: const Icon(Icons.contrast_rounded),
                          tooltip: 'common.toggleTheme'.tr,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1240),
                          child: isWide
                              ? Row(
                                  children: [
                                    Expanded(
                                      child: _BrandPanel(
                                        theme: theme,
                                        darkMode: _isDarkMode,
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    SizedBox(
                                      width: 460,
                                      child:
                                          _AuthPanel(state: this, theme: theme),
                                    ),
                                  ],
                                )
                              : SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      _BrandPanel(
                                        theme: theme,
                                        darkMode: _isDarkMode,
                                        compact: true,
                                      ),
                                      const SizedBox(height: 18),
                                      _AuthPanel(state: this, theme: theme),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthPanel extends StatelessWidget {
  const _AuthPanel({
    required this.state,
    required this.theme,
  });

  final _LoginScreenState state;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('auth.enterWorkspace'.tr, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'auth.enterWorkspaceBody'.tr,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          SegmentedButton<_AuthMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: _AuthMode.login,
                label: Text('common.login'.tr),
              ),
              ButtonSegment(
                value: _AuthMode.register,
                label: Text('common.register'.tr),
              ),
            ],
            selected: {state._mode},
            onSelectionChanged: (selection) {
              state.setMode(selection.first);
            },
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: state._mode == _AuthMode.login
                ? _LoginForm(state: state)
                : _RegisterForm(state: state),
          ),
        ],
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({required this.state});

  final _LoginScreenState state;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: state._loginFormKey,
      child: Column(
        key: const ValueKey('login-form'),
        children: [
          TextFormField(
            controller: state._loginEmailController,
            validator: state.validateEmail,
            decoration: InputDecoration(
              labelText: 'auth.email'.tr,
              prefixIcon: const Icon(Icons.mail_outline_rounded),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: state._loginPasswordController,
            validator: state.validatePassword,
            obscureText: state._obscureLoginPassword,
            decoration: InputDecoration(
              labelText: 'auth.password'.tr,
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                onPressed: () {
                  state.toggleLoginPasswordVisibility();
                },
                icon: Icon(
                  state._obscureLoginPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: state._isSubmitting ? null : state._handleLogin,
              child: Text(
                state._isSubmitting ? 'auth.signingIn'.tr : 'common.login'.tr,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed:
                    state._isSubmitting ? null : state._showResetPasswordDialog,
                child: Text('auth.resetPassword'.tr),
              ),
              const Spacer(),
              TextButton(
                onPressed: state._isSubmitting
                    ? null
                    : () => state.setMode(_AuthMode.register),
                child: Text('auth.createAccount'.tr),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RegisterForm extends StatelessWidget {
  const _RegisterForm({required this.state});

  final _LoginScreenState state;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: state._registerFormKey,
      child: Column(
        key: const ValueKey('register-form'),
        children: [
          TextFormField(
            controller: state._registerEmailController,
            validator: state.validateEmail,
            decoration: InputDecoration(
              labelText: 'auth.email'.tr,
              prefixIcon: const Icon(Icons.mail_outline_rounded),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: state._registerPasswordController,
            validator: state.validatePassword,
            obscureText: state._obscureRegisterPassword,
            decoration: InputDecoration(
              labelText: 'auth.password'.tr,
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                onPressed: () {
                  state.toggleRegisterPasswordVisibility();
                },
                icon: Icon(
                  state._obscureRegisterPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: state._registerConfirmController,
            validator: state.validatePassword,
            obscureText: state._obscureConfirmPassword,
            decoration: InputDecoration(
              labelText: 'auth.confirmPassword'.tr,
              prefixIcon: const Icon(Icons.verified_user_outlined),
              suffixIcon: IconButton(
                onPressed: () {
                  state.toggleConfirmPasswordVisibility();
                },
                icon: Icon(
                  state._obscureConfirmPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: state._isSubmitting ? null : state._handleRegister,
              child: Text(
                state._isSubmitting ? 'auth.creating'.tr : 'common.register'.tr,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: state._isSubmitting
                  ? null
                  : () => state.setMode(_AuthMode.login),
              child: Text('auth.backToLogin'.tr),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({
    required this.theme,
    required this.darkMode,
    this.compact = false,
  });

  final ThemeData theme;
  final bool darkMode;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 22 : 32),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'auth.brandBadge'.tr,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'auth.brandTitle'.tr,
            style: theme.textTheme.displaySmall,
          ),
          const SizedBox(height: 12),
          Text(
            'auth.brandBody'.tr,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _MetricTile(
                label: 'auth.metric.mode'.tr,
                value: darkMode ? 'common.dark'.tr : 'common.light'.tr,
                tone: theme.colorScheme.primary,
              ),
              _MetricTile(
                label: 'auth.metric.flow'.tr,
                value: 'auth.metric.flowValue'.tr,
                tone: theme.colorScheme.tertiary,
              ),
              _MetricTile(
                label: 'auth.metric.agent'.tr,
                value: 'auth.metric.agentValue'.tr,
                tone: const Color(0xFF0F766E),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _CommandCard(
            theme: theme,
            lines: [
              'auth.promptLine1'.tr,
              'auth.promptLine2'.tr,
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 170,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Text(value,
              style: theme.textTheme.titleMedium?.copyWith(color: tone)),
        ],
      ),
    );
  }
}

class _CommandCard extends StatelessWidget {
  const _CommandCard({
    required this.theme,
    required this.lines,
  });

  final ThemeData theme;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.14),
            theme.colorScheme.tertiary.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('auth.promptIdeas'.tr, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('> $line', style: theme.textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Positioned(
          top: -140,
          left: -90,
          child: _Blob(
            size: 300,
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
          ),
        ),
        Positioned(
          right: -80,
          top: 120,
          child: _Blob(
            size: 260,
            color: theme.colorScheme.tertiary.withValues(alpha: 0.12),
          ),
        ),
        Positioned(
          bottom: -120,
          right: 120,
          child: _Blob(
            size: 340,
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.20),
          ),
        ),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
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
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
