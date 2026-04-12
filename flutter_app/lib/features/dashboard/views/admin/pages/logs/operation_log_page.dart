// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:developer' as developer;

import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/api/operation_log_controller_api.dart';
import 'package:final_assignment_front/features/dashboard/controllers/admin_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/features/model/operation_log.dart';
import 'package:final_assignment_front/i18n/log_localizers.dart';
import 'package:final_assignment_front/utils/helpers/api_exception.dart';
import 'package:final_assignment_front/utils/helpers/role_utils.dart';
import 'package:final_assignment_front/utils/services/auth_token_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

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
  String _activeQuery = '';
  DateTime? _startTime;
  DateTime? _endTime;
  int _currentPage = 1;
  final int _pageSize = 20;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isAdmin = false;
  String _errorMessage = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _initialize();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          _hasMore &&
          !_isLoading) {
        _loadMoreLogs();
      }
    });
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
      setState(() => _errorMessage = 'operationLog.error.initFailed'
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
      final jwtToken = (await AuthTokenStore.instance.getJwtToken())!;
      final decodedToken = JwtDecoder.decode(jwtToken);
      final roles = decodedToken['roles'];
      setState(() => _isAdmin = hasAnyRole(roles, const [
            'SUPER_ADMIN',
            'ADMIN',
          ]));
      if (!_isAdmin) {
        setState(() => _errorMessage = 'operationLog.error.adminOnly'.tr);
      }
      developer.log('User roles from JWT: $roles');
    } catch (e) {
      setState(() => _errorMessage = 'operationLog.error.roleCheckFailed'
          .trParams({'error': formatOperationLogError(e)}));
      developer.log('Error checking user role: $e',
          stackTrace: StackTrace.current);
    }
  }

  Future<void> _fetchLogs({bool reset = false, String? query}) async {
    if (reset) {
      _currentPage = 1;
      _hasMore = true;
      _activeQuery = (query ?? _searchController.text).trim();
      _logs.clear();
      _filteredLogs.clear();
    }
    if (!_isAdmin || (!reset && (_isLoading || !_hasMore))) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      if (!await _validateJwtToken()) {
        Get.offAllNamed(Routes.login);
        return;
      }
      final logs = await _loadLogPage(page: _currentPage, query: _activeQuery);

      setState(() {
        _logs.addAll(logs);
        _rebuildVisibleLogs();
        _hasMore = logs.length == _pageSize;
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

  Future<List<OperationLog>> _loadLogPage({
    required int page,
    required String query,
  }) {
    if (_searchType == kLogSearchTypeTimeRange &&
        _startTime != null &&
        _endTime != null) {
      return logApi.apiLogsOperationSearchTimeRangeGet(
        startTime: _startTime!.toIso8601String(),
        endTime: _endTime!.add(const Duration(days: 1)).toIso8601String(),
        page: page,
        size: _pageSize,
      );
    }
    if (query.isEmpty) {
      return logApi.apiLogsOperationGet(page: page, size: _pageSize);
    }
    if (_searchType == kOperationLogSearchTypeOperationResult) {
      return logApi.apiLogsOperationSearchResultGet(
        operationResult: _normalizeResultQuery(query),
        page: page,
        size: _pageSize,
      );
    }
    final userId = int.tryParse(query);
    if (userId == null) {
      return Future.value(const <OperationLog>[]);
    }
    return logApi.apiLogsOperationSearchUserUserIdGet(
      userId: userId,
      page: page,
      size: _pageSize,
    );
  }

  void _rebuildVisibleLogs() {
    _filteredLogs = List<OperationLog>.from(_logs);
    if (_filteredLogs.isEmpty) {
      _errorMessage =
          _activeQuery.isNotEmpty || (_startTime != null && _endTime != null)
              ? 'operationLog.empty.filtered'.tr
              : 'operationLog.empty.default'.tr;
    } else {
      _errorMessage = '';
    }
  }

  String _normalizeResultQuery(String query) {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return normalized;
    }
    final lowered = normalized.toLowerCase();
    final successAliases = <String>{
      'success',
      'succeeded',
      'successful',
      'ok',
      'passed',
      'common.success'.tr.toLowerCase(),
    };
    final failedAliases = <String>{
      'failed',
      'failure',
      'error',
      'errored',
      'fail',
      'common.failed'.tr.toLowerCase(),
    };
    if (successAliases.any((alias) =>
        alias.contains(lowered) || lowered.contains(alias.toLowerCase()))) {
      return 'SUCCESS';
    }
    if (failedAliases.any((alias) =>
        alias.contains(lowered) || lowered.contains(alias.toLowerCase()))) {
      return 'FAILED';
    }
    return normalized;
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
    _searchDebounce?.cancel();
    final effectiveQuery = (query ?? _searchController.text).trim();
    setState(() {
      _logs.clear();
      _filteredLogs.clear();
      _currentPage = 1;
      _hasMore = true;
      _isLoading = true;
      _searchController.value = TextEditingValue(
        text: effectiveQuery,
        selection: TextSelection.collapsed(offset: effectiveQuery.length),
      );
    });
    await _fetchLogs(reset: true, query: effectiveQuery);
  }

  void _scheduleSearchRefresh(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) {
        return;
      }
      _refreshLogs(query: value);
    });
  }

  void _resetFilters() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _startTime = null;
      _endTime = null;
      _searchType = kOperationLogSearchTypeUserId;
    });
    _refreshLogs(query: '');
  }

  // ignore: unused_element
  Future<void> _showCreateLogDialog() async {
    return;
  }

  // ignore: unused_element
  Future<void> _showEditLogDialog(OperationLog log) async {
    return;
  }

  // ignore: unused_element
  Future<void> _deleteLog(int logId) async {
    return;
  }

  // ignore: unused_element
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
                      _refreshLogs(query: selection);
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
                                    _resetFilters();
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
                        onChanged: (value) {
                          setState(() {});
                          _scheduleSearchRefresh(value);
                        },
                        onSubmitted: (value) => _refreshLogs(query: value),
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
                    });
                    _refreshLogs(query: '');
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
                      _refreshLogs(query: '');
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
                      _refreshLogs(query: '');
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
        pageType: DashboardPageType.admin,
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
                child: _isLoading && _logs.isEmpty
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
                                        ((_isLoading && _logs.isNotEmpty)
                                            ? 1
                                            : 0),
                                    itemBuilder: (context, index) {
                                      if (index == _filteredLogs.length) {
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
