import 'dart:developer' as developer;

import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/api/system_logs_controller_api.dart';
import 'package:final_assignment_front/features/dashboard/controllers/admin_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/features/model/login_log.dart';
import 'package:final_assignment_front/features/model/operation_log.dart';
import 'package:final_assignment_front/i18n/system_log_localizers.dart';
import 'package:final_assignment_front/utils/helpers/api_exception.dart';
import 'package:final_assignment_front/utils/helpers/role_utils.dart';
import 'package:final_assignment_front/utils/services/auth_token_store.dart';
import 'package:final_assignment_front/utils/services/session_helper.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

class SystemLogPage extends StatefulWidget {
  const SystemLogPage({super.key});

  @override
  State<SystemLogPage> createState() => _SystemLogPageState();
}

class _SystemLogPageState extends State<SystemLogPage> {
  final SystemLogsControllerApi logApi = SystemLogsControllerApi();
  final ScrollController _scrollController = ScrollController();
  final DashboardController controller = Get.find<DashboardController>();
  final SessionHelper _sessionHelper = SessionHelper();

  Map<String, dynamic> _overviewData = {};
  List<LoginLog> _recentLoginLogs = [];
  List<OperationLog> _recentOperationLogs = [];
  bool _isLoading = false;
  bool _isAdmin = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _setStateSafely(VoidCallback update) {
    if (!mounted) return;
    setState(update);
  }

  void _redirectToLogin() {
    if (!mounted) return;
    Get.offAllNamed(Routes.login);
  }

  Future<bool> _validateJwtToken() async {
    String? jwtToken = (await AuthTokenStore.instance.getJwtToken());
    if (jwtToken == null || jwtToken.isEmpty) {
      _setStateSafely(() => _errorMessage = 'systemLog.error.unauthorized'.tr);
      return false;
    }
    try {
      JwtDecoder.decode(jwtToken);
      if (JwtDecoder.isExpired(jwtToken)) {
        jwtToken = await _refreshJwtToken();
        if (!mounted) return false;
        if (jwtToken == null || JwtDecoder.isExpired(jwtToken)) {
          _setStateSafely(() => _errorMessage = 'systemLog.error.expired'.tr);
          return false;
        }
        await AuthTokenStore.instance.setJwtToken(jwtToken);
        await logApi.initializeWithJwt();
        if (!mounted) return false;
      }
      return true;
    } catch (_) {
      _setStateSafely(() => _errorMessage = 'systemLog.error.invalidLogin'.tr);
      return false;
    }
  }

  Future<String?> _refreshJwtToken() async {
    return await _sessionHelper.refreshJwtToken();
  }

  Future<void> _initialize() async {
    _setStateSafely(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final isValid = await _validateJwtToken();
      if (!mounted) return;
      if (!isValid) {
        _redirectToLogin();
        return;
      }
      await logApi.initializeWithJwt();
      if (!mounted) return;
      await _checkUserRole();
      if (!mounted) return;
      if (_isAdmin) {
        await _fetchSystemLogData(showLoader: false);
      } else {
        _setStateSafely(() => _errorMessage = 'systemLog.error.adminOnly'.tr);
      }
    } catch (e) {
      _setStateSafely(() => _errorMessage = 'systemLog.error.initFailed'
          .trParams({'error': formatSystemLogError(e)}));
    } finally {
      _setStateSafely(() => _isLoading = false);
    }
  }

  Future<void> _checkUserRole() async {
    try {
      final isValid = await _validateJwtToken();
      if (!mounted) return;
      if (!isValid) {
        _redirectToLogin();
        return;
      }
      final roles = await _sessionHelper.fetchCurrentRoles();
      if (!mounted) return;
      _setStateSafely(() => _isAdmin = hasAnyRole(roles, const [
            'SUPER_ADMIN',
            'ADMIN',
          ]));
      if (!_isAdmin) {
        _setStateSafely(() => _errorMessage = 'systemLog.error.adminOnly'.tr);
      }
    } catch (e) {
      _setStateSafely(() => _errorMessage = 'systemLog.error.roleCheckFailed'
          .trParams({'error': formatSystemLogError(e)}));
      developer.log('Error checking user role: $e',
          stackTrace: StackTrace.current);
    }
  }

  Future<void> _fetchSystemLogData({bool showLoader = true}) async {
    if (!_isAdmin) return;
    if (showLoader) {
      _setStateSafely(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }
    try {
      final isValid = await _validateJwtToken();
      if (!mounted) return;
      if (!isValid) {
        _redirectToLogin();
        return;
      }
      await logApi.initializeWithJwt();
      if (!mounted) return;
      final overview = await logApi.apiSystemLogsOverviewGet();
      if (!mounted) return;
      final loginLogs = await logApi.apiSystemLogsLoginRecentGet(limit: 20);
      if (!mounted) return;
      final operationLogs =
          await logApi.apiSystemLogsOperationRecentGet(limit: 20);
      if (!mounted) return;
      _setStateSafely(() {
        _overviewData = overview;
        _recentLoginLogs = loginLogs;
        _recentOperationLogs = operationLogs;
        _errorMessage = '';
      });
    } catch (e) {
      developer.log('Failed to fetch system logs: $e',
          stackTrace: StackTrace.current);
      if (e is ApiException && e.code == 403) {
        _setStateSafely(
            () => _errorMessage = 'systemLog.error.unauthorized'.tr);
        _redirectToLogin();
      } else {
        _setStateSafely(() {
          _errorMessage = 'systemLog.error.loadFailed'
              .trParams({'error': formatSystemLogError(e)});
        });
      }
    } finally {
      if (showLoader) {
        _setStateSafely(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleRefresh() async {
    await _fetchSystemLogData(showLoader: false);
  }

  Widget _buildWarningCard(ThemeData themeData) {
    return Card(
      color: themeData.colorScheme.errorContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(CupertinoIcons.exclamationmark_triangle_fill,
                color: themeData.colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _errorMessage,
                style: themeData.textTheme.bodyMedium?.copyWith(
                  color: themeData.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewSection(ThemeData themeData) {
    return Card(
      elevation: 4,
      color: themeData.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'systemLog.section.overview'.tr,
              style: themeData.textTheme.titleMedium?.copyWith(
                color: themeData.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (_overviewData.isEmpty)
              _buildEmptySection(themeData, 'systemLog.empty.overview'.tr)
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _overviewData.entries.map((entry) {
                  final value = entry.value;
                  return Container(
                    width: 150,
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: themeData.colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(
                        color: themeData.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatSystemLogOverviewLabel(entry.key),
                          style: themeData.textTheme.bodySmall?.copyWith(
                            color: themeData.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          value?.toString() ?? '0',
                          style: themeData.textTheme.titleMedium?.copyWith(
                            color: themeData.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySection(ThemeData themeData, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.info,
            color: themeData.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: themeData.textTheme.bodyMedium?.copyWith(
                color: themeData.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginLogsSection(ThemeData themeData) {
    return Card(
      elevation: 4,
      color: themeData.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'systemLog.section.recentLogin'.tr,
              style: themeData.textTheme.titleMedium?.copyWith(
                color: themeData.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (_recentLoginLogs.isEmpty)
              _buildEmptySection(themeData, 'systemLog.empty.login'.tr)
            else
              ..._recentLoginLogs.asMap().entries.map((entry) {
                return Column(
                  children: [
                    _buildLoginLogTile(entry.value, themeData),
                    if (entry.key != _recentLoginLogs.length - 1)
                      Divider(
                        height: 16,
                        color: themeData.colorScheme.outlineVariant,
                      ),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginLogTile(LoginLog log, ThemeData themeData) {
    final subtitleStyle = themeData.textTheme.bodyMedium?.copyWith(
      color: themeData.colorScheme.onSurfaceVariant,
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        log.username ?? 'systemLog.value.unknownUser'.tr,
        style: themeData.textTheme.titleMedium?.copyWith(
          color: themeData.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'systemLog.detail.loginResult'.trParams(
              {
                'value': localizeSystemLogResult(
                  log.loginResult,
                  emptyKey: 'common.unknown',
                ),
              },
            ),
            style: subtitleStyle,
          ),
          Text(
            'systemLog.detail.loginIp'.trParams(
              {'value': log.loginIp ?? 'common.unknown'.tr},
            ),
            style: subtitleStyle,
          ),
          if (log.loginLocation != null && log.loginLocation!.isNotEmpty)
            Text(
              'systemLog.detail.loginLocation'
                  .trParams({'value': log.loginLocation!}),
              style: subtitleStyle,
            ),
          Text(
            'systemLog.detail.loginDevice'
                .trParams({'value': buildSystemLogDeviceInfo(log)}),
            style: subtitleStyle,
          ),
          if (log.remarks != null && log.remarks!.isNotEmpty)
            Text(
              'systemLog.detail.remarks'.trParams({'value': log.remarks!}),
              style: subtitleStyle,
            ),
        ],
      ),
      trailing: Text(
        formatSystemLogDateTime(log.loginTime),
        style: themeData.textTheme.bodySmall?.copyWith(
          color: themeData.colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.right,
      ),
    );
  }

  Widget _buildOperationLogsSection(ThemeData themeData) {
    return Card(
      elevation: 4,
      color: themeData.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'systemLog.section.recentOperation'.tr,
              style: themeData.textTheme.titleMedium?.copyWith(
                color: themeData.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (_recentOperationLogs.isEmpty)
              _buildEmptySection(themeData, 'systemLog.empty.operation'.tr)
            else
              ..._recentOperationLogs.asMap().entries.map((entry) {
                return Column(
                  children: [
                    _buildOperationLogTile(entry.value, themeData),
                    if (entry.key != _recentOperationLogs.length - 1)
                      Divider(
                        height: 16,
                        color: themeData.colorScheme.outlineVariant,
                      ),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildOperationLogTile(OperationLog log, ThemeData themeData) {
    final subtitleStyle = themeData.textTheme.bodyMedium?.copyWith(
      color: themeData.colorScheme.onSurfaceVariant,
    );
    final userLabel = log.username ??
        log.realName ??
        log.userId?.toString() ??
        'systemLog.value.unknownUser'.tr;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        log.operationModule ??
            log.operationFunction ??
            'systemLog.value.unknownModule'.tr,
        style: themeData.textTheme.titleMedium?.copyWith(
          color: themeData.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'systemLog.detail.operationType'.trParams(
              {'value': log.operationType ?? 'common.unknown'.tr},
            ),
            style: subtitleStyle,
          ),
          Text(
            'systemLog.detail.user'.trParams({'value': userLabel}),
            style: subtitleStyle,
          ),
          Text(
            'systemLog.detail.operationResult'.trParams(
              {
                'value': localizeSystemLogResult(
                  log.operationResult,
                  emptyKey: 'common.unknown',
                ),
              },
            ),
            style: subtitleStyle,
          ),
          if (log.operationContent != null && log.operationContent!.isNotEmpty)
            Text(
              'systemLog.detail.operationContent'
                  .trParams({'value': log.operationContent!}),
              style: subtitleStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          Text(
            'systemLog.detail.requestIp'.trParams(
              {'value': log.requestIp ?? 'common.unknown'.tr},
            ),
            style: subtitleStyle,
          ),
          if (log.remarks != null && log.remarks!.isNotEmpty)
            Text(
              'systemLog.detail.remarks'.trParams({'value': log.remarks!}),
              style: subtitleStyle,
            ),
        ],
      ),
      trailing: Text(
        formatSystemLogDateTime(log.operationTime),
        style: themeData.textTheme.bodySmall?.copyWith(
          color: themeData.colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.right,
      ),
    );
  }

  Widget _buildErrorView(ThemeData themeData) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              color: themeData.colorScheme.error,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: themeData.textTheme.titleMedium?.copyWith(
                color: themeData.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Get.offAllNamed(Routes.login),
              style: ElevatedButton.styleFrom(
                backgroundColor: themeData.colorScheme.primary,
                foregroundColor: themeData.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
              child: Text('systemLog.action.relogin'.tr),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasData() {
    return _overviewData.isNotEmpty ||
        _recentLoginLogs.isNotEmpty ||
        _recentOperationLogs.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData = controller.currentBodyTheme.value;
      final showBlockingError = _errorMessage.isNotEmpty && !_hasData();
      return DashboardPageTemplate(
        theme: themeData,
        title: 'systemLog.page.title'.tr,
        pageType: DashboardPageType.admin,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        onRefresh: _fetchSystemLogData,
        onThemeToggle: controller.toggleBodyTheme,
        body: _isLoading
            ? Center(
                child: CupertinoActivityIndicator(
                  color: themeData.colorScheme.primary,
                  radius: 16.0,
                ),
              )
            : showBlockingError
                ? _buildErrorView(themeData)
                : RefreshIndicator(
                    onRefresh: _handleRefresh,
                    color: themeData.colorScheme.primary,
                    backgroundColor: themeData.colorScheme.surfaceContainer,
                    child: CupertinoScrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      thickness: 6.0,
                      thicknessWhileDragging: 10.0,
                      child: ListView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16.0),
                        children: [
                          if (_errorMessage.isNotEmpty && _hasData()) ...[
                            _buildWarningCard(themeData),
                            const SizedBox(height: 16),
                          ],
                          _buildOverviewSection(themeData),
                          const SizedBox(height: 16),
                          _buildLoginLogsSection(themeData),
                          const SizedBox(height: 16),
                          _buildOperationLogsSection(themeData),
                        ],
                      ),
                    ),
                  ),
      );
    });
  }
}
