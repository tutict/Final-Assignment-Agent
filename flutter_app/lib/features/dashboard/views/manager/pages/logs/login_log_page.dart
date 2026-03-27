// ignore_for_file: use_build_context_synchronously
import 'dart:developer' as developer;

import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/api/login_log_controller_api.dart';
import 'package:final_assignment_front/features/dashboard/controllers/manager_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/features/model/login_log.dart';
import 'package:final_assignment_front/i18n/log_localizers.dart';
import 'package:final_assignment_front/utils/helpers/api_exception.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

String generateIdempotencyKey() {
  return const Uuid().v4();
}

class LoginLogPage extends StatefulWidget {
  const LoginLogPage({super.key});

  @override
  State<LoginLogPage> createState() => _LoginLogPageState();
}

class _LoginLogPageState extends State<LoginLogPage> {
  final LoginLogControllerApi logApi = LoginLogControllerApi();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final DashboardController controller = Get.find<DashboardController>();
  final List<LoginLog> _logs = [];
  List<LoginLog> _filteredLogs = [];
  String _searchType = kLoginLogSearchTypeUsername;
  DateTime? _startTime;
  DateTime? _endTime;
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isAdmin = false;
  String _errorMessage = '';
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _initialize();
    _searchController.addListener(() {
      _applyFilters(_searchController.text);
    });
    _scrollController.addListener(() {
      if (_scrollController.position.pixels ==
              _scrollController.position.maxScrollExtent &&
          _hasMore &&
          !_isLoading) {
        _loadMoreLogs();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<bool> _validateJwtToken() async {
    final prefs = await SharedPreferences.getInstance();
    final jwtToken = prefs.getString('jwtToken');
    if (jwtToken == null || jwtToken.isEmpty) {
      setState(() => _errorMessage = 'loginLog.error.unauthorized'.tr);
      return false;
    }
    try {
      if (JwtDecoder.isExpired(jwtToken)) {
        setState(() => _errorMessage = 'loginLog.error.expired'.tr);
        return false;
      }
      await logApi.initializeWithJwt();
      final decodedToken = JwtDecoder.decode(jwtToken);
      _currentUsername = decodedToken['sub']?.toString() ?? '';
      return true;
    } catch (e) {
      setState(() => _errorMessage = 'loginLog.error.invalidLogin'.tr);
      return false;
    }
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      if (!await _validateJwtToken()) {
        Get.offAllNamed(Routes.login);
        return;
      }
      await logApi.initializeWithJwt();
      await _checkUserRole();
      if (_isAdmin) {
        await _fetchLogs(reset: true);
      } else {
        setState(() => _errorMessage = 'loginLog.error.adminOnly'.tr);
      }
    } catch (e) {
      setState(() => _errorMessage =
          'loginLog.error.initFailed'.trParams({'error': formatLoginLogError(e)}));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkUserRole() async {
    try {
      if (!await _validateJwtToken()) {
        Get.offAllNamed(Routes.login);
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwtToken')!;
      final decodedToken = JwtDecoder.decode(jwtToken);
      final roles = decodedToken['roles'] is List
          ? (decodedToken['roles'] as List).map((r) => r.toString()).toList()
          : decodedToken['roles'] is String
              ? [decodedToken['roles'].toString()]
              : [];
      setState(() => _isAdmin = roles.contains('ADMIN'));
      if (!_isAdmin) {
        setState(() => _errorMessage = 'loginLog.error.adminOnly'.tr);
      }
      developer.log('User roles from JWT: $roles');
    } catch (e) {
      setState(() => _errorMessage =
          'loginLog.error.roleCheckFailed'
              .trParams({'error': formatLoginLogError(e)}));
      developer.log('Error checking user role: $e',
          stackTrace: StackTrace.current);
    }
  }

  Future<void> _fetchLogs({bool reset = false, String? query}) async {
    if (!_isAdmin || !_hasMore) return;

    if (reset) {
      _currentPage = 1;
      _hasMore = true;
      _logs.clear();
      _filteredLogs.clear();
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      if (!await _validateJwtToken()) {
        Get.offAllNamed(Routes.login);
        return;
      }
      final logs = await logApi.apiLogsLoginGet();
      setState(() {
        _logs.addAll(logs);
        _hasMore = false;
        _applyFilters(query ?? _searchController.text);
        if (_filteredLogs.isEmpty) {
          _errorMessage = (_searchController.text.isNotEmpty ||
                  (_startTime != null && _endTime != null))
              ? 'loginLog.empty.filtered'.tr
              : 'loginLog.empty.default'.tr;
        }
        _currentPage = 1;
      });
      developer.log('Loaded logs: ${_logs.length}');
    } catch (e) {
      developer.log('Error fetching logs: $e', stackTrace: StackTrace.current);
      setState(() {
        if (e is ApiException && e.code == 404) {
          _logs.clear();
          _filteredLogs.clear();
          _errorMessage = 'loginLog.empty.filtered'.tr;
          _hasMore = false;
        } else if (e is ApiException && e.code == 403) {
          _errorMessage = 'loginLog.error.unauthorized'.tr;
          Get.offAllNamed(Routes.login);
        } else {
          _errorMessage = 'loginLog.error.loadFailed'
              .trParams({'error': formatLoginLogError(e)});
        }
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters(String query) {
    final searchQuery = query.trim().toLowerCase();
    setState(() {
      _filteredLogs = _logs.where((log) {
        final username = (log.username ?? '').toLowerCase();
        final loginResult =
            localizeLoginLogResult(log.loginResult).toLowerCase();
        final loginTime = log.loginTime;

        bool matchesQuery = true;
        if (searchQuery.isNotEmpty) {
          if (_searchType == kLoginLogSearchTypeUsername) {
            matchesQuery = username.contains(searchQuery);
          } else if (_searchType == kLoginLogSearchTypeLoginResult) {
            matchesQuery = loginResult.contains(searchQuery);
          }
        }

        bool matchesDateRange = true;
        if (_startTime != null && _endTime != null && loginTime != null) {
          matchesDateRange = loginTime.isAfter(_startTime!) &&
              loginTime.isBefore(_endTime!.add(const Duration(days: 1)));
        } else if (_startTime != null &&
            _endTime != null &&
            loginTime == null) {
          matchesDateRange = false;
        }

        return matchesQuery && matchesDateRange;
      }).toList();

      if (_filteredLogs.isEmpty && _logs.isNotEmpty) {
        _errorMessage = 'loginLog.empty.filtered'.tr;
      } else {
        _errorMessage = _filteredLogs.isEmpty && _logs.isEmpty
            ? 'loginLog.empty.default'.tr
            : '';
      }
    });
  }

  Future<List<String>> _fetchAutocompleteSuggestions(String prefix) async {
    final normalized = prefix.toLowerCase();
    final values = _searchType == kLoginLogSearchTypeUsername
        ? _logs.map((log) => log.username ?? '')
        : _logs.map((log) => localizeLoginLogResult(log.loginResult));
    return values
        .where((value) => value.isNotEmpty)
        .where((value) => value.toLowerCase().contains(normalized))
        .toSet()
        .take(5)
        .toList();
  }

  Future<void> _loadMoreLogs() async {
    if (!_isLoading && _hasMore) {
      await _fetchLogs();
    }
  }

  Future<void> _refreshLogs({String? query}) async {
    setState(() {
      _logs.clear();
      _filteredLogs.clear();
      _currentPage = 1;
      _hasMore = true;
      _isLoading = true;
      if (query == null) {
        _searchController.clear();
        _startTime = null;
        _endTime = null;
        _searchType = kLoginLogSearchTypeUsername;
      }
    });
    await _fetchLogs(reset: true, query: query);
  }

  // ignore: unused_element
  Future<void> _showCreateLogDialog() async {
    final usernameController = TextEditingController(text: _currentUsername);
    final loginIpController = TextEditingController();
    final loginResultController = TextEditingController();
    final browserTypeController = TextEditingController();
    final osVersionController = TextEditingController();
    final remarksController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final idempotencyKey = generateIdempotencyKey();

    await showDialog(
      context: context,
      builder: (context) {
        final themeData = controller.currentBodyTheme.value;
        return Theme(
          data: themeData,
          child: AlertDialog(
            title: Text(
              'loginLog.dialog.createTitle'.tr,
              style: themeData.textTheme.titleLarge,
            ),
            backgroundColor: themeData.colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0)),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: usernameController,
                      decoration: InputDecoration(
                        labelText: 'loginLog.field.username'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                      validator: (value) => value!.isEmpty
                          ? 'loginLog.validation.usernameRequired'.tr
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: loginIpController,
                      decoration: InputDecoration(
                        labelText: 'loginLog.field.loginIp'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                      validator: (value) => value!.isEmpty
                          ? 'loginLog.validation.loginIpRequired'.tr
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: loginResultController,
                      decoration: InputDecoration(
                        labelText: 'loginLog.field.loginResult'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                      validator: (value) => value!.isEmpty
                          ? 'loginLog.validation.loginResultRequired'.tr
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: browserTypeController,
                      decoration: InputDecoration(
                        labelText: 'loginLog.field.browserType'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: osVersionController,
                      decoration: InputDecoration(
                        labelText: 'loginLog.field.osVersion'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: remarksController,
                      decoration: InputDecoration(
                        labelText: 'loginLog.field.remarks'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('common.cancel'.tr,
                    style: TextStyle(color: themeData.colorScheme.error)),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    if (!await _validateJwtToken()) {
                      Get.offAllNamed(Routes.login);
                      return;
                    }
                    try {
                      final newLog = LoginLog(
                        username: usernameController.text,
                        loginIp: loginIpController.text,
                        loginResult: loginResultController.text,
                        browserType: browserTypeController.text.isEmpty
                            ? null
                            : browserTypeController.text,
                        osVersion: osVersionController.text.isEmpty
                            ? null
                            : osVersionController.text,
                        remarks: remarksController.text.isEmpty
                            ? null
                            : remarksController.text,
                        loginTime: DateTime.now(),
                      );
                      await logApi.apiLogsLoginPost(
                        loginLog: newLog,
                        idempotencyKey: idempotencyKey,
                      );
                      _showSnackBar('loginLog.success.created'.tr);
                      Navigator.pop(context);
                      await _refreshLogs();
                    } catch (e) {
                      _showSnackBar(formatLoginLogError(e), isError: true);
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeData.colorScheme.primary,
                  foregroundColor: themeData.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0)),
                ),
                child: Text('loginLog.action.create'.tr),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showEditLogDialog(LoginLog log) async {
    final logId = log.logId;
    if (logId == null) {
      _showSnackBar('loginLog.error.idMissingEdit'.tr, isError: true);
      return;
    }
    final usernameController = TextEditingController(text: log.username);
    final loginIpController = TextEditingController(text: log.loginIp ?? '');
    final loginResultController = TextEditingController(text: log.loginResult);
    final browserTypeController = TextEditingController(text: log.browserType);
    final osVersionController = TextEditingController(text: log.osVersion);
    final remarksController = TextEditingController(text: log.remarks);
    final formKey = GlobalKey<FormState>();
    final idempotencyKey = generateIdempotencyKey();

    await showDialog(
      context: context,
      builder: (context) {
        final themeData = controller.currentBodyTheme.value;
        return Theme(
          data: themeData,
          child: AlertDialog(
            title: Text(
              'loginLog.dialog.editTitle'.tr,
              style: themeData.textTheme.titleLarge,
            ),
            backgroundColor: themeData.colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0)),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: usernameController,
                      decoration: InputDecoration(
                        labelText: 'loginLog.field.username'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                      validator: (value) => value!.isEmpty
                          ? 'loginLog.validation.usernameRequired'.tr
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: loginIpController,
                      decoration: InputDecoration(
                        labelText: 'loginLog.field.loginIp'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                      validator: (value) => value!.isEmpty
                          ? 'loginLog.validation.loginIpRequired'.tr
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: loginResultController,
                      decoration: InputDecoration(
                        labelText: 'loginLog.field.loginResult'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                      validator: (value) => value!.isEmpty
                          ? 'loginLog.validation.loginResultRequired'.tr
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: browserTypeController,
                      decoration: InputDecoration(
                        labelText: 'loginLog.field.browserType'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: osVersionController,
                      decoration: InputDecoration(
                        labelText: 'loginLog.field.osVersion'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: remarksController,
                      decoration: InputDecoration(
                        labelText: 'loginLog.field.remarks'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('common.cancel'.tr,
                    style: TextStyle(color: themeData.colorScheme.error)),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    if (!await _validateJwtToken()) {
                      Get.offAllNamed(Routes.login);
                      return;
                    }
                    try {
                      final updatedLog = LoginLog(
                        logId: log.logId,
                        username: usernameController.text,
                        loginIp: loginIpController.text,
                        loginResult: loginResultController.text,
                        loginTime: log.loginTime,
                        browserType: browserTypeController.text.isEmpty
                            ? null
                            : browserTypeController.text,
                        osVersion: osVersionController.text.isEmpty
                            ? null
                            : osVersionController.text,
                        remarks: remarksController.text.isEmpty
                            ? null
                            : remarksController.text,
                      );
                      await logApi.apiLogsLoginLogIdPut(
                        logId: logId,
                        loginLog: updatedLog,
                        idempotencyKey: idempotencyKey,
                      );
                      _showSnackBar('loginLog.success.updated'.tr);
                      Navigator.pop(context);
                      await _refreshLogs();
                    } catch (e) {
                      _showSnackBar(formatLoginLogError(e), isError: true);
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeData.colorScheme.primary,
                  foregroundColor: themeData.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0)),
                ),
                child: Text('common.save'.tr),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteLog(int logId) async {
    final themeData = controller.currentBodyTheme.value;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: themeData,
        child: AlertDialog(
          title: Text('loginLog.delete.confirmTitle'.tr),
          content: Text('loginLog.delete.confirmBody'.tr),
          backgroundColor: themeData.colorScheme.surfaceContainerLowest,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('common.cancel'.tr,
                  style: TextStyle(color: themeData.colorScheme.error)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: themeData.colorScheme.error,
                foregroundColor: themeData.colorScheme.onError,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0)),
              ),
              child: Text('loginLog.action.delete'.tr),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      if (!await _validateJwtToken()) {
        Get.offAllNamed(Routes.login);
        return;
      }
      try {
        await logApi.apiLogsLoginLogIdDelete(logId: logId);
        _showSnackBar('loginLog.success.deleted'.tr);
        await _refreshLogs();
      } catch (e) {
        _showSnackBar(formatLoginLogError(e), isError: true);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    final themeData = controller.currentBodyTheme.value;
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        margin: const EdgeInsets.all(10.0),
      ),
    );
  }

  Widget _buildSearchBar(ThemeData themeData) {
    return Card(
      elevation: 4,
      color: themeData.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) async {
                      if (textEditingValue.text.isEmpty ||
                          _searchType == kLogSearchTypeTimeRange) {
                        return const Iterable<String>.empty();
                      }
                      return await _fetchAutocompleteSuggestions(
                          textEditingValue.text);
                    },
                    onSelected: (String selection) {
                      _searchController.text = selection;
                      _applyFilters(selection);
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: _searchController,
                        focusNode: focusNode,
                        style: themeData.textTheme.bodyMedium
                            ?.copyWith(color: themeData.colorScheme.onSurface),
                        decoration: InputDecoration(
                          hintText: loginLogSearchHintText(_searchType),
                          hintStyle: themeData.textTheme.bodyMedium?.copyWith(
                            color: themeData.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                          prefixIcon: Icon(Icons.search,
                              color: themeData.colorScheme.primary),
                          suffixIcon: _searchController.text.isNotEmpty ||
                                  (_startTime != null && _endTime != null)
                              ? IconButton(
                                  icon: Icon(Icons.clear,
                                      color: themeData
                                          .colorScheme.onSurfaceVariant),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _startTime = null;
                                      _endTime = null;
                                      _searchType = kLoginLogSearchTypeUsername;
                                    });
                                    _applyFilters('');
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: themeData.colorScheme.surfaceContainer,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 14.0, horizontal: 16.0),
                        ),
                        onChanged: (value) => _applyFilters(value),
                        onSubmitted: (value) => _applyFilters(value),
                        enabled: _searchType != kLogSearchTypeTimeRange,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _searchType,
                  onChanged: (String? newValue) {
                    setState(() {
                      _searchType = newValue!;
                      _searchController.clear();
                      _startTime = null;
                      _endTime = null;
                      _applyFilters('');
                    });
                  },
                  items: <String>[
                    kLoginLogSearchTypeUsername,
                    kLoginLogSearchTypeLoginResult,
                  ].map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        loginLogSearchTypeLabel(value),
                        style:
                            TextStyle(color: themeData.colorScheme.onSurface),
                      ),
                    );
                  }).toList(),
                  dropdownColor: themeData.colorScheme.surfaceContainer,
                  icon: Icon(Icons.arrow_drop_down,
                      color: themeData.colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _startTime != null && _endTime != null
                        ? 'loginLog.filter.dateRangeLabel'.trParams({
                            'start': formatLogDateTime(_startTime),
                            'end': formatLogDateTime(_endTime),
                          })
                        : 'loginLog.filter.selectDateRange'.tr,
                    style: themeData.textTheme.bodyMedium?.copyWith(
                      color: _startTime != null && _endTime != null
                          ? themeData.colorScheme.onSurface
                          : themeData.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.date_range,
                      color: themeData.colorScheme.primary),
                  tooltip: 'loginLog.filter.tooltip'.tr,
                  onPressed: () async {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      locale: Get.locale ?? const Locale('en', 'US'),
                      helpText: 'loginLog.filter.selectDateRange'.tr,
                      cancelText: 'common.cancel'.tr,
                      confirmText: 'common.confirm'.tr,
                      fieldStartHintText: 'loginLog.filter.startDate'.tr,
                      fieldEndHintText: 'loginLog.filter.endDate'.tr,
                      builder: (BuildContext context, Widget? child) {
                        return Theme(
                          data: themeData.copyWith(
                            colorScheme: themeData.colorScheme.copyWith(
                              primary: themeData.colorScheme.primary,
                              onPrimary: themeData.colorScheme.onPrimary,
                            ),
                            textButtonTheme: TextButtonThemeData(
                              style: TextButton.styleFrom(
                                foregroundColor: themeData.colorScheme.primary,
                              ),
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (range != null) {
                      setState(() {
                        _startTime = range.start;
                        _endTime = range.end;
                        _searchType = kLogSearchTypeTimeRange;
                        _searchController.clear();
                      });
                      _applyFilters('');
                    }
                  },
                ),
                if (_startTime != null && _endTime != null)
                  IconButton(
                    icon: Icon(Icons.clear,
                        color: themeData.colorScheme.onSurfaceVariant),
                    tooltip: 'loginLog.filter.clearDateRange'.tr,
                    onPressed: () {
                      setState(() {
                        _startTime = null;
                        _endTime = null;
                        _searchType = kLoginLogSearchTypeUsername;
                        _searchController.clear();
                      });
                      _applyFilters('');
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogCard(LoginLog log, ThemeData themeData) {
    return Card(
      elevation: 4,
      color: themeData.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        title: Text(
          'loginLog.detail.id'.trParams({
            'value': '${log.logId ?? 'common.unknown'.tr}',
          }),
          style: themeData.textTheme.titleMedium?.copyWith(
            color: themeData.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'loginLog.detail.username'.trParams({
                  'value': log.username ?? 'common.unknown'.tr,
                }),
                style: themeData.textTheme.bodyMedium?.copyWith(
                  color: themeData.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'loginLog.detail.loginIp'.trParams({
                  'value': log.loginIp ?? 'common.none'.tr,
                }),
                style: themeData.textTheme.bodyMedium?.copyWith(
                  color: themeData.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'loginLog.detail.loginResult'.trParams({
                  'value': localizeLoginLogResult(log.loginResult),
                }),
                style: themeData.textTheme.bodyMedium?.copyWith(
                  color: themeData.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'loginLog.detail.loginTime'.trParams({
                  'value': formatLogDateTime(log.loginTime),
                }),
                style: themeData.textTheme.bodyMedium?.copyWith(
                  color: themeData.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'loginLog.detail.browserType'.trParams({
                  'value': log.browserType ?? 'common.none'.tr,
                }),
                style: themeData.textTheme.bodyMedium?.copyWith(
                  color: themeData.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'loginLog.detail.osVersion'.trParams({
                  'value': log.osVersion ?? 'common.none'.tr,
                }),
                style: themeData.textTheme.bodyMedium?.copyWith(
                  color: themeData.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'loginLog.detail.remarks'.trParams({
                  'value': log.remarks ?? 'common.none'.tr,
                }),
                style: themeData.textTheme.bodyMedium?.copyWith(
                  color: themeData.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        trailing: _isAdmin
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon:
                        Icon(Icons.edit, color: themeData.colorScheme.primary),
                    onPressed: () => _showEditLogDialog(log),
                    tooltip: 'loginLog.action.edit'.tr,
                  ),
                  IconButton(
                    icon:
                        Icon(Icons.delete, color: themeData.colorScheme.error),
                    onPressed: () {
                      final logId = log.logId;
                      if (logId == null) {
                        _showSnackBar('loginLog.error.idMissingDelete'.tr,
                            isError: true);
                        return;
                      }
                      _deleteLog(logId);
                    },
                    tooltip: 'loginLog.action.delete'.tr,
                  ),
                ],
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData = controller.currentBodyTheme.value;
      return DashboardPageTemplate(
        theme: themeData,
        title: 'loginLog.page.title'.tr,
        pageType: DashboardPageType.manager,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        onRefresh: _refreshLogs,
        onThemeToggle: controller.toggleBodyTheme,
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isAdmin) _buildSearchBar(themeData),
              const SizedBox(height: 20),
              Expanded(
                child: _isLoading && _currentPage == 1
                    ? Center(
                        child: CupertinoActivityIndicator(
                          color: themeData.colorScheme.primary,
                          radius: 16.0,
                        ),
                      )
                    : _errorMessage.isNotEmpty && !_isLoading
                        ? Center(
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
                                  style:
                                      themeData.textTheme.titleMedium?.copyWith(
                                    color: themeData.colorScheme.error,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                if (shouldShowLoginLogReloginAction(
                                    _errorMessage))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 20.0),
                                    child: ElevatedButton(
                                      onPressed: () =>
                                          Get.offAllNamed(Routes.login),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            themeData.colorScheme.primary,
                                        foregroundColor:
                                            themeData.colorScheme.onPrimary,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12.0)),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 24.0, vertical: 12.0),
                                      ),
                                      child: Text(
                                        'loginLog.action.relogin'.tr,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : _filteredLogs.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      CupertinoIcons.doc,
                                      color: themeData
                                          .colorScheme.onSurfaceVariant,
                                      size: 48,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _errorMessage.isNotEmpty
                                          ? _errorMessage
                                          : 'loginLog.empty.default'.tr,
                                      style: themeData.textTheme.titleMedium
                                          ?.copyWith(
                                        color: themeData
                                            .colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                            : CupertinoScrollbar(
                                controller: _scrollController,
                                thumbVisibility: true,
                                thickness: 6.0,
                                thicknessWhileDragging: 10.0,
                                child: RefreshIndicator(
                                  onRefresh: () => _refreshLogs(),
                                  color: themeData.colorScheme.primary,
                                  backgroundColor:
                                      themeData.colorScheme.surfaceContainer,
                                  child: ListView.builder(
                                    controller: _scrollController,
                                    itemCount: _filteredLogs.length +
                                        (_hasMore ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (index == _filteredLogs.length &&
                                          _hasMore) {
                                        return const Padding(
                                          padding: EdgeInsets.all(8.0),
                                          child: Center(
                                              child:
                                                  CupertinoActivityIndicator()),
                                        );
                                      }
                                      final log = _filteredLogs[index];
                                      return _buildLogCard(log, themeData);
                                    },
                                  ),
                                ),
                              ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
