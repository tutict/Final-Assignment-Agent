// ignore_for_file: use_build_context_synchronously
import 'dart:developer' as developer;

import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/api/operation_log_controller_api.dart';
import 'package:final_assignment_front/features/dashboard/controllers/manager_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/features/model/operation_log.dart';
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

class OperationLogPage extends StatefulWidget {
  const OperationLogPage({super.key});

  @override
  State<OperationLogPage> createState() => _OperationLogPageState();
}

class _OperationLogPageState extends State<OperationLogPage> {
  final OperationLogControllerApi logApi = OperationLogControllerApi();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final DashboardController controller = Get.find<DashboardController>();
  final List<OperationLog> _logs = [];
  List<OperationLog> _filteredLogs = [];
  String _searchType = kOperationLogSearchTypeUserId;
  DateTime? _startTime;
  DateTime? _endTime;
  int _currentPage = 1;
  final int _pageSize = 20;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isAdmin = false;
  String _errorMessage = '';

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
      setState(() => _errorMessage = 'operationLog.error.unauthorized'.tr);
      return false;
    }
    try {
      if (JwtDecoder.isExpired(jwtToken)) {
        setState(() => _errorMessage = 'operationLog.error.expired'.tr);
        return false;
      }
      await logApi.initializeWithJwt();
      return true;
    } catch (e) {
      setState(() => _errorMessage = 'operationLog.error.invalidLogin'.tr);
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
      await _checkUserRole();
      if (_isAdmin) {
        await _fetchLogs(reset: true);
      } else {
        setState(() => _errorMessage = 'operationLog.error.adminOnly'.tr);
      }
    } catch (e) {
      setState(() => _errorMessage =
          'operationLog.error.initFailed'
              .trParams({'error': formatOperationLogError(e)}));
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
        setState(() => _errorMessage = 'operationLog.error.adminOnly'.tr);
      }
      developer.log('User roles from JWT: $roles');
    } catch (e) {
      setState(() => _errorMessage =
          'operationLog.error.roleCheckFailed'
              .trParams({'error': formatOperationLogError(e)}));
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
      List<OperationLog> logs = [];
      final searchQuery = query?.trim() ?? '';
      if (_searchType == kOperationLogSearchTypeUserId &&
          searchQuery.isNotEmpty) {
        logs = await logApi.apiLogsOperationGet();
        logs = logs
            .where((log) =>
                log.userId
                    ?.toString()
                    .toLowerCase()
                    .contains(searchQuery.toLowerCase()) ??
                false)
            .toList();
      } else if (_searchType == kOperationLogSearchTypeOperationResult &&
          searchQuery.isNotEmpty) {
        logs = await logApi.apiLogsOperationGet();
        logs = logs
            .where((log) =>
                log.operationResult
                    ?.toLowerCase()
                    .contains(searchQuery.toLowerCase()) ??
                false)
            .toList();
      } else if (_startTime != null && _endTime != null) {
        logs = await logApi.apiLogsOperationSearchTimeRangeGet(
          startTime: _startTime!.toIso8601String(),
          endTime: _endTime!.add(const Duration(days: 1)).toIso8601String(),
        );
      } else {
        logs = await logApi.apiLogsOperationGet();
      }

      setState(() {
        _logs.addAll(logs);
        _hasMore = logs.length == _pageSize;
        _applyFilters(query ?? _searchController.text);
        if (_filteredLogs.isEmpty) {
          _errorMessage =
              searchQuery.isNotEmpty || (_startTime != null && _endTime != null)
                  ? 'operationLog.empty.filtered'.tr
                  : 'operationLog.empty.default'.tr;
        }
        _currentPage++;
      });
      developer.log('Loaded logs: ${_logs.length}');
    } catch (e) {
      developer.log('Error fetching logs: $e', stackTrace: StackTrace.current);
      setState(() {
        if (e is ApiException && e.code == 404) {
          _logs.clear();
          _filteredLogs.clear();
          _errorMessage = 'operationLog.empty.filtered'.tr;
          _hasMore = false;
        } else if (e is ApiException && e.code == 403) {
          _errorMessage = 'operationLog.error.unauthorized'.tr;
          Get.offAllNamed(Routes.login);
        } else {
          _errorMessage = 'operationLog.error.loadFailed'
              .trParams({'error': formatOperationLogError(e)});
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
        final userId = (log.userId?.toString() ?? '').toLowerCase();
        final operationResult =
            localizeOperationLogResult(log.operationResult).toLowerCase();
        final operationTime = log.operationTime;

        bool matchesQuery = true;
        if (searchQuery.isNotEmpty) {
          if (_searchType == kOperationLogSearchTypeUserId) {
            matchesQuery = userId.contains(searchQuery);
          } else if (_searchType == kOperationLogSearchTypeOperationResult) {
            matchesQuery = operationResult.contains(searchQuery);
          }
        }

        bool matchesDateRange = true;
        if (_startTime != null && _endTime != null && operationTime != null) {
          matchesDateRange = operationTime.isAfter(_startTime!) &&
              operationTime.isBefore(_endTime!.add(const Duration(days: 1)));
        } else if (_startTime != null &&
            _endTime != null &&
            operationTime == null) {
          matchesDateRange = false;
        }

        return matchesQuery && matchesDateRange;
      }).toList();

      if (_filteredLogs.isEmpty && _logs.isNotEmpty) {
        _errorMessage = 'operationLog.empty.filtered'.tr;
      } else {
        _errorMessage = _filteredLogs.isEmpty && _logs.isEmpty
            ? 'operationLog.empty.default'.tr
            : '';
      }
    });
  }

  Future<List<String>> _fetchAutocompleteSuggestions(String prefix) async {
    if (prefix.isEmpty || _searchType == kLogSearchTypeTimeRange) {
      return [];
    }
    final normalized = prefix.toLowerCase();
    final values = _searchType == kOperationLogSearchTypeUserId
        ? _logs.map((log) => log.userId?.toString() ?? '')
        : _logs.map((log) => localizeOperationLogResult(log.operationResult));
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
        _searchType = kOperationLogSearchTypeUserId;
      }
    });
    await _fetchLogs(reset: true, query: query);
  }

  // ignore: unused_element
  Future<void> _showCreateLogDialog() async {
    final userIdController = TextEditingController();
    final operationContentController = TextEditingController();
    final operationResultController = TextEditingController();
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
            title: Text('operationLog.dialog.createTitle'.tr,
                style: themeData.textTheme.titleLarge),
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
                      controller: userIdController,
                      decoration: InputDecoration(
                        labelText: 'operationLog.field.userId'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value!.isEmpty) {
                          return 'operationLog.validation.userIdRequired'.tr;
                        }
                        if (int.tryParse(value) == null) {
                          return 'operationLog.validation.userIdNumeric'.tr;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: operationContentController,
                      decoration: InputDecoration(
                        labelText: 'operationLog.field.operationContent'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                      maxLines: 3,
                      validator: (value) => value!.isEmpty
                          ? 'operationLog.validation.operationContentRequired'
                              .tr
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: operationResultController,
                      decoration: InputDecoration(
                        labelText: 'operationLog.field.operationResult'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                      validator: (value) => value!.isEmpty
                          ? 'operationLog.validation.operationResultRequired'.tr
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: remarksController,
                      decoration: InputDecoration(
                        labelText: 'operationLog.field.remarks'.tr,
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
                      final newLog = OperationLog(
                        userId: int.parse(userIdController.text),
                        operationContent: operationContentController.text,
                        operationResult: operationResultController.text,
                        remarks: remarksController.text.isEmpty
                            ? null
                            : remarksController.text,
                        operationTime: DateTime.now(),
                      );
                      await logApi.apiLogsOperationPost(
                        operationLog: newLog,
                        idempotencyKey: idempotencyKey,
                      );
                      _showSnackBar('operationLog.success.created'.tr);
                      Navigator.pop(context);
                      await _refreshLogs();
                    } catch (e) {
                      _showSnackBar(formatOperationLogError(e), isError: true);
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeData.colorScheme.primary,
                  foregroundColor: themeData.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0)),
                ),
                child: Text('operationLog.action.create'.tr),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showEditLogDialog(OperationLog log) async {
    final logId = log.logId;
    if (logId == null) {
      _showSnackBar('operationLog.error.idMissingEdit'.tr, isError: true);
      return;
    }
    final userIdController =
        TextEditingController(text: log.userId?.toString());
    final operationContentController =
        TextEditingController(text: log.operationContent);
    final operationResultController =
        TextEditingController(text: log.operationResult);
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
            title: Text('operationLog.dialog.editTitle'.tr,
                style: themeData.textTheme.titleLarge),
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
                      controller: userIdController,
                      decoration: InputDecoration(
                        labelText: 'operationLog.field.userId'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value!.isEmpty) {
                          return 'operationLog.validation.userIdRequired'.tr;
                        }
                        if (int.tryParse(value) == null) {
                          return 'operationLog.validation.userIdNumeric'.tr;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: operationContentController,
                      decoration: InputDecoration(
                        labelText: 'operationLog.field.operationContent'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                      maxLines: 3,
                      validator: (value) => value!.isEmpty
                          ? 'operationLog.validation.operationContentRequired'
                              .tr
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: operationResultController,
                      decoration: InputDecoration(
                        labelText: 'operationLog.field.operationResult'.tr,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainer,
                      ),
                      validator: (value) => value!.isEmpty
                          ? 'operationLog.validation.operationResultRequired'.tr
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: remarksController,
                      decoration: InputDecoration(
                        labelText: 'operationLog.field.remarks'.tr,
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
                      final updatedLog = OperationLog(
                        logId: log.logId,
                        userId: int.parse(userIdController.text),
                        operationContent: operationContentController.text,
                        operationResult: operationResultController.text,
                        operationTime: log.operationTime,
                        remarks: remarksController.text.isEmpty
                            ? null
                            : remarksController.text,
                      );
                      await logApi.apiLogsOperationLogIdPut(
                        logId: logId,
                        operationLog: updatedLog,
                        idempotencyKey: idempotencyKey,
                      );
                      _showSnackBar('operationLog.success.updated'.tr);
                      Navigator.pop(context);
                      await _refreshLogs();
                    } catch (e) {
                      _showSnackBar(
                        formatOperationLogError(e),
                        isError: true,
                      );
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
          title: Text('operationLog.delete.confirmTitle'.tr),
          content: Text('operationLog.delete.confirmBody'.tr),
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
              child: Text('operationLog.action.delete'.tr),
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
        await logApi.apiLogsOperationLogIdDelete(logId: logId);
        _showSnackBar('operationLog.success.deleted'.tr);
        await _refreshLogs();
      } catch (e) {
        _showSnackBar(formatOperationLogError(e), isError: true);
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
                          hintText: operationLogSearchHintText(_searchType),
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
                                      _searchType =
                                          kOperationLogSearchTypeUserId;
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
                    kOperationLogSearchTypeUserId,
                    kOperationLogSearchTypeOperationResult,
                    kLogSearchTypeTimeRange,
                  ].map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        operationLogSearchTypeLabel(value),
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
                        ? 'operationLog.filter.dateRangeLabel'.trParams({
                            'start': formatLogDateTime(_startTime),
                            'end': formatLogDateTime(_endTime),
                          })
                        : 'operationLog.filter.selectDateRange'.tr,
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
                  tooltip: 'operationLog.filter.tooltip'.tr,
                  onPressed: () async {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      locale: Get.locale ?? const Locale('en', 'US'),
                      helpText: 'operationLog.filter.selectDateRange'.tr,
                      cancelText: 'common.cancel'.tr,
                      confirmText: 'common.confirm'.tr,
                      fieldStartHintText: 'operationLog.filter.startDate'.tr,
                      fieldEndHintText: 'operationLog.filter.endDate'.tr,
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
                    tooltip: 'operationLog.filter.clearDateRange'.tr,
                    onPressed: () {
                      setState(() {
                        _startTime = null;
                        _endTime = null;
                        _searchType = kOperationLogSearchTypeUserId;
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

  Widget _buildLogCard(OperationLog log, ThemeData themeData) {
    return Card(
      elevation: 4,
      color: themeData.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        title: Text(
          'operationLog.detail.id'
              .trParams({'value': '${log.logId ?? 'common.unknown'.tr}'}),
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
                'operationLog.detail.userId'.trParams(
                    {'value': '${log.userId ?? 'common.unknown'.tr}'}),
                style: themeData.textTheme.bodyMedium?.copyWith(
                  color: themeData.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'operationLog.detail.operationContent'.trParams(
                    {'value': log.operationContent ?? 'common.none'.tr}),
                style: themeData.textTheme.bodyMedium?.copyWith(
                  color: themeData.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'operationLog.detail.operationResult'.trParams(
                    {'value': localizeOperationLogResult(log.operationResult)}),
                style: themeData.textTheme.bodyMedium?.copyWith(
                  color: themeData.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'operationLog.detail.operationTime'.trParams({
                  'value': formatLogDateTime(log.operationTime),
                }),
                style: themeData.textTheme.bodyMedium?.copyWith(
                  color: themeData.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'operationLog.detail.requestIp'
                    .trParams({'value': log.requestIp ?? 'common.none'.tr}),
                style: themeData.textTheme.bodyMedium?.copyWith(
                  color: themeData.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'operationLog.detail.remarks'
                    .trParams({'value': log.remarks ?? 'common.none'.tr}),
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
                    tooltip: 'operationLog.action.edit'.tr,
                  ),
                  IconButton(
                    icon:
                        Icon(Icons.delete, color: themeData.colorScheme.error),
                    onPressed: () {
                      final logId = log.logId;
                      if (logId == null) {
                        _showSnackBar('operationLog.error.idMissingDelete'.tr,
                            isError: true);
                        return;
                      }
                      _deleteLog(logId);
                    },
                    tooltip: 'operationLog.action.delete'.tr,
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
        title: 'operationLog.page.title'.tr,
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
                                if (shouldShowOperationLogReloginAction(
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
                                          'operationLog.action.relogin'.tr),
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
                                          : 'operationLog.empty.default'.tr,
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
