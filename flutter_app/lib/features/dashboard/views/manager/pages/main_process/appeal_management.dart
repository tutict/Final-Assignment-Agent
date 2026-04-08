// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:developer' as developer;

import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/api/appeal_management_controller_api.dart';
import 'package:final_assignment_front/features/dashboard/controllers/manager_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/features/model/appeal_record.dart';
import 'package:final_assignment_front/features/model/appeal_review.dart';
import 'package:final_assignment_front/i18n/appeal_localizers.dart';
import 'package:final_assignment_front/i18n/status_localizers.dart';
import 'package:final_assignment_front/utils/helpers/api_exception.dart';
import 'package:final_assignment_front/utils/helpers/role_utils.dart';
import 'package:final_assignment_front/utils/services/auth_token_store.dart';
import 'package:final_assignment_front/utils/services/session_helper.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:uuid/uuid.dart';

String generateIdempotencyKey() {
  return const Uuid().v4();
}

class AppealManagementAdmin extends StatefulWidget {
  const AppealManagementAdmin({super.key});

  @override
  State<AppealManagementAdmin> createState() => _AppealManagementAdminState();
}

class _AppealManagementAdminState extends State<AppealManagementAdmin> {
  static const int _appealPageSize = 50;

  final AppealManagementControllerApi appealApi =
      AppealManagementControllerApi();
  final SessionHelper _sessionHelper = SessionHelper();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<AppealRecordModel> _appeals = [];
  List<AppealRecordModel> _filteredAppeals = [];
  String _searchType = kAppealSearchTypeAppealReason;
  String _activeQuery = '';
  DateTime? _startTime;
  DateTime? _endTime;
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isAdmin = false;
  String _errorMessage = '';
  Timer? _searchDebounce;
  final DashboardController controller = Get.find<DashboardController>();

  @override
  void initState() {
    super.initState();
    _initialize();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          _hasMore &&
          !_isLoading) {
        _loadAppeals();
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
    String? jwtToken = (await AuthTokenStore.instance.getJwtToken());
    if (jwtToken == null || jwtToken.isEmpty) {
      setState(
          () => _errorMessage = 'appealAdmin.error.unauthorizedMissing'.tr);
      return false;
    }
    try {
      final decodedToken = JwtDecoder.decode(jwtToken);
      if (JwtDecoder.isExpired(jwtToken)) {
        jwtToken = await _refreshJwtToken();
        if (jwtToken == null) {
          setState(() => _errorMessage = 'appealAdmin.error.expired'.tr);
          return false;
        }
        await AuthTokenStore.instance.setJwtToken(jwtToken);
        if (JwtDecoder.isExpired(jwtToken)) {
          setState(
              () => _errorMessage = 'appealAdmin.error.refreshedExpired'.tr);
          return false;
        }
        await appealApi.initializeWithJwt();
      }
      developer
          .log('JWT Token validated successfully: sub=${decodedToken['sub']}');
      return true;
    } catch (e) {
      setState(() => _errorMessage = 'appealAdmin.error.invalidLogin'.trParams({
            'error': formatAppealErrorDetail(e),
          }));
      developer.log('JWT validation failed: $e',
          stackTrace: StackTrace.current);
      return false;
    }
  }

  Future<String?> _refreshJwtToken() async {
    final newJwt = await _sessionHelper.refreshJwtToken();
    if (newJwt != null) {
      developer.log('JWT token refreshed successfully');
    } else {
      developer.log('Failed to refresh JWT token');
    }
    return newJwt;
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      if (!await _validateJwtToken()) {
        Get.offAllNamed(Routes.login);
        return;
      }
      await appealApi.initializeWithJwt();
      await _checkUserRole();
      if (_isAdmin) {
        await _loadAppeals(reset: true);
      } else {
        setState(() => _errorMessage = 'appealAdmin.error.adminOnly'.tr);
      }
    } catch (e) {
      setState(() => _errorMessage = 'appealAdmin.error.initFailed'.trParams({
            'error': formatAppealErrorDetail(e),
          }));
      developer.log('Initialization failed: $e',
          stackTrace: StackTrace.current);
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
      final roles = await _sessionHelper.fetchCurrentRoles();
      final hasAdminAccess = hasAnyRole(roles, const [
        'SUPER_ADMIN',
        'ADMIN',
        'APPEAL_REVIEWER',
      ]);
      setState(() {
        _isAdmin = hasAdminAccess;
        if (!hasAdminAccess) {
          _errorMessage = 'appealAdmin.error.adminOnly'.tr;
        }
      });
    } catch (e) {
      setState(
          () => _errorMessage = 'appealAdmin.error.roleCheckFailed'.trParams({
                'error': formatAppealErrorDetail(e),
              }));
      developer.log('Role check failed: $e', stackTrace: StackTrace.current);
    }
  }

  Future<List<String>> _fetchAutocompleteSuggestions(String prefix) async {
    if (prefix.isEmpty) return [];
    final normalized = prefix.toLowerCase();
    Iterable<String> values = const Iterable.empty();
    switch (_searchType) {
      case kAppealSearchTypeAppealReason:
        values = _appeals.map((appeal) => appeal.appealReason ?? '');
        break;
      case kAppealSearchTypeAppellantName:
        values = _appeals.map((appeal) => appeal.appellantName ?? '');
        break;
      case kAppealSearchTypeProcessStatus:
        values = _appeals
            .map((appeal) => localizeAppealStatus(appeal.processStatus));
        break;
      default:
        return [];
    }
    return values
        .where((value) => value.isNotEmpty)
        .where((value) => value.toLowerCase().contains(normalized))
        .toSet()
        .take(5)
        .toList();
  }

  Future<void> _loadAppeals({bool reset = false, String? query}) async {
    if (!_isAdmin) return;

    if (reset) {
      _currentPage = 1;
      _hasMore = true;
      _activeQuery = (query ?? _searchController.text).trim();
      _appeals.clear();
      _filteredAppeals.clear();
    }
    if (!reset && (_isLoading || !_hasMore)) {
      return;
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
      await appealApi.initializeWithJwt();
      final appeals =
          await _loadAppealPage(page: _currentPage, query: _activeQuery);
      setState(() {
        _appeals.addAll(appeals);
        _rebuildVisibleAppeals();
        _hasMore = appeals.length == _appealPageSize;
        _currentPage++;
      });
      developer.log('Loaded appeals: ${_appeals.length}');
    } catch (e) {
      developer.log('Error fetching appeals: $e',
          stackTrace: StackTrace.current);
      setState(() {
        _appeals.clear();
        _filteredAppeals.clear();
        if (e is ApiException && e.code == 403) {
          _errorMessage = 'appealAdmin.error.unauthorized'.tr;
          Get.offAllNamed(Routes.login);
        } else {
          _errorMessage = 'appealAdmin.error.loadFailed'
              .trParams({'error': formatAppealAdminError(e)});
        }
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<List<AppealRecordModel>> _loadAppealPage({
    required int page,
    required String query,
  }) {
    if (_searchType == kAppealSearchTypeTimeRange &&
        _startTime != null &&
        _endTime != null) {
      return appealApi.apiAppealsSearchTimeRangeGet(
        startTime: _startTime!.toIso8601String(),
        endTime: _endTime!.add(const Duration(days: 1)).toIso8601String(),
        page: page,
        size: _appealPageSize,
      );
    }
    if (query.isEmpty) {
      return appealApi.apiAppealsGet(page: page, size: _appealPageSize);
    }
    switch (_searchType) {
      case kAppealSearchTypeAppellantName:
        return appealApi.apiAppealsSearchAppellantNameFuzzyGet(
          appellantName: query,
          page: page,
          size: _appealPageSize,
        );
      case kAppealSearchTypeProcessStatus:
        return appealApi.apiAppealsSearchProcessStatusGet(
          processStatus: normalizeAppealStatusCode(query),
          page: page,
          size: _appealPageSize,
        );
      case kAppealSearchTypeAppealReason:
      default:
        return appealApi.apiAppealsSearchReasonFuzzyGet(
          appealReason: query,
          page: page,
          size: _appealPageSize,
        );
    }
  }

  void _rebuildVisibleAppeals() {
    _filteredAppeals = List<AppealRecordModel>.from(_appeals);
    if (_filteredAppeals.isEmpty) {
      _errorMessage =
          _activeQuery.isNotEmpty || (_startTime != null && _endTime != null)
              ? 'appeal.empty.filtered'.tr
              : 'appeal.empty'.tr;
    } else {
      _errorMessage = '';
    }
  }

  Future<void> _refreshAppeals({String? query}) async {
    _searchDebounce?.cancel();
    final effectiveQuery = (query ?? _searchController.text).trim();
    setState(() {
      _appeals.clear();
      _filteredAppeals.clear();
      _currentPage = 1;
      _hasMore = true;
      _isLoading = true;
      _searchController.value = TextEditingValue(
        text: effectiveQuery,
        selection: TextSelection.collapsed(offset: effectiveQuery.length),
      );
    });
    await _loadAppeals(reset: true, query: effectiveQuery);
  }

  void _scheduleSearchRefresh(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) {
        return;
      }
      _refreshAppeals(query: value);
    });
  }

  void _goToDetailPage(AppealRecordModel appeal) {
    Get.to(() => AppealDetailPage(
          appeal: appeal,
          onAppealUpdated: (updatedAppeal) {
            setState(() {
              final index = _appeals
                  .indexWhere((a) => a.appealId == updatedAppeal.appealId);
              if (index != -1) {
                _appeals[index] = updatedAppeal;
              }
              final visibleIndex = _filteredAppeals
                  .indexWhere((a) => a.appealId == updatedAppeal.appealId);
              if (visibleIndex != -1) {
                _filteredAppeals[visibleIndex] = updatedAppeal;
              }
              _rebuildVisibleAppeals();
            });
          },
        ))?.then((value) {
      if (value == true && mounted) _refreshAppeals();
    });
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
                          _searchType == kAppealSearchTypeTimeRange) {
                        return const Iterable<String>.empty();
                      }
                      return await _fetchAutocompleteSuggestions(
                          textEditingValue.text);
                    },
                    onSelected: (String selection) {
                      _searchController.text = selection;
                      _refreshAppeals(query: selection);
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: _searchController,
                        focusNode: focusNode,
                        style: themeData.textTheme.bodyMedium
                            ?.copyWith(color: themeData.colorScheme.onSurface),
                        decoration: InputDecoration(
                          hintText: appealAdminSearchHintText(_searchType),
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
                                          kAppealSearchTypeAppealReason;
                                    });
                                    _refreshAppeals(query: '');
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
                        onSubmitted: (value) => _refreshAppeals(query: value),
                        enabled: _searchType != kAppealSearchTypeTimeRange,
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
                    _refreshAppeals(query: '');
                  },
                  items: <String>[
                    kAppealSearchTypeAppealReason,
                    kAppealSearchTypeAppellantName,
                    kAppealSearchTypeProcessStatus,
                    kAppealSearchTypeTimeRange,
                  ].map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        appealAdminSearchTypeLabel(value),
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
                        ? 'appeal.filter.rangeLabel'.trParams({
                            'start': formatAppealDateTime(_startTime),
                            'end': formatAppealDateTime(_endTime),
                          })
                        : 'appeal.filter.select'.tr,
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
                  tooltip: 'appeal.filter.tooltip'.tr,
                  onPressed: () async {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      locale: Get.locale ?? const Locale('en', 'US'),
                      helpText: 'appeal.filter.select'.tr,
                      cancelText: 'common.cancel'.tr,
                      confirmText: 'common.confirm'.tr,
                      fieldStartHintText: 'appeal.filter.startDate'.tr,
                      fieldEndHintText: 'appeal.filter.endDate'.tr,
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
                        _searchType = kAppealSearchTypeTimeRange;
                        _searchController.clear();
                      });
                      _refreshAppeals(query: '');
                    }
                  },
                ),
                if (_startTime != null && _endTime != null)
                  IconButton(
                    icon: Icon(Icons.clear,
                        color: themeData.colorScheme.onSurfaceVariant),
                    tooltip: 'appeal.filter.clear'.tr,
                    onPressed: () {
                      setState(() {
                        _startTime = null;
                        _endTime = null;
                        _searchType = kAppealSearchTypeAppealReason;
                        _searchController.clear();
                      });
                      _refreshAppeals(query: '');
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppealCard(AppealRecordModel appeal, ThemeData themeData) {
    final acceptance = normalizeAppealStatusCode(appeal.acceptanceStatus);
    final displayStatus = acceptance == appealPendingStatusCode() ||
            acceptance == appealRejectedStatusCode() ||
            acceptance == 'Need_Supplement'
        ? localizeAppealStatus(appeal.acceptanceStatus)
        : localizeAppealStatus(appeal.processStatus);
    final isRejected = isRejectedAppealStatus(appeal.acceptanceStatus) ||
        isRejectedAppealStatus(appeal.processStatus);
    return Card(
      elevation: 4,
      color: themeData.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        title: Text(
          'appeal.card.title'.trParams({
            'name': appeal.appellantName ?? 'common.unknown'.tr,
            'id': '${appeal.appealId ?? 'common.none'.tr}',
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
                'appealAdmin.card.reason'.trParams({
                  'value': appeal.appealReason ?? 'common.none'.tr,
                }),
                style: themeData.textTheme.bodyMedium?.copyWith(
                  color: themeData.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'appealAdmin.card.status'.trParams({
                  'value': displayStatus,
                }),
                style: themeData.textTheme.bodyMedium?.copyWith(
                  color: isApprovedAppealStatus(appeal.processStatus)
                      ? Colors.green
                      : isRejected
                          ? Colors.red
                          : themeData.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'appealAdmin.card.time'.trParams({
                  'value': formatAppealDateTime(appeal.appealTime),
                }),
                style: themeData.textTheme.bodyMedium?.copyWith(
                  color: themeData.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        trailing: Icon(
          CupertinoIcons.forward,
          color: themeData.colorScheme.primary,
          size: 18,
        ),
        onTap: () => _goToDetailPage(appeal),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData = controller.currentBodyTheme.value;
      final showBlockingError = _errorMessage.isNotEmpty &&
          _errorMessage != 'appeal.empty'.tr &&
          _errorMessage != 'appeal.empty.filtered'.tr;

      return DashboardPageTemplate(
        theme: themeData,
        title: 'appealAdmin.page.title'.tr,
        pageType: DashboardPageType.manager,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        actions: [
          DashboardPageBarAction(
            icon: Icons.refresh,
            onPressed: () => _refreshAppeals(),
            tooltip: 'page.refreshList'.tr,
          ),
        ],
        onThemeToggle: controller.toggleBodyTheme,
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSearchBar(themeData),
              const SizedBox(height: 20),
              Expanded(
                child: _isLoading && _appeals.isEmpty
                    ? Center(
                        child: CupertinoActivityIndicator(
                          color: themeData.colorScheme.primary,
                          radius: 16.0,
                        ),
                      )
                    : showBlockingError
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
                                if (shouldShowAppealAdminReloginAction(
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
                                      child:
                                          Text('appealAdmin.action.relogin'.tr),
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : _filteredAppeals.isEmpty
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
                                          : 'appeal.empty'.tr,
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
                                  onRefresh: () => _refreshAppeals(),
                                  color: themeData.colorScheme.primary,
                                  backgroundColor:
                                      themeData.colorScheme.surfaceContainer,
                                  child: ListView.builder(
                                    controller: _scrollController,
                                    itemCount: _filteredAppeals.length +
                                        ((_isLoading && _appeals.isNotEmpty)
                                            ? 1
                                            : 0),
                                    itemBuilder: (context, index) {
                                      if (index >= _filteredAppeals.length) {
                                        return const Padding(
                                          padding: EdgeInsets.all(8.0),
                                          child: Center(
                                            child: CupertinoActivityIndicator(),
                                          ),
                                        );
                                      }
                                      final appeal = _filteredAppeals[index];
                                      return _buildAppealCard(
                                          appeal, themeData);
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

class AppealDetailPage extends StatefulWidget {
  final AppealRecordModel appeal;
  final Function(AppealRecordModel)? onAppealUpdated;

  const AppealDetailPage(
      {super.key, required this.appeal, this.onAppealUpdated});

  @override
  State<AppealDetailPage> createState() => _AppealDetailPageState();
}

class _AppealDetailPageState extends State<AppealDetailPage> {
  final AppealManagementControllerApi appealApi =
      AppealManagementControllerApi();
  final SessionHelper _sessionHelper = SessionHelper();
  final TextEditingController _rejectionReasonController =
      TextEditingController();
  bool _isLoading = false;
  bool _isAdmin = false;
  String _errorMessage = '';
  final DashboardController controller = Get.find<DashboardController>();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _rejectionReasonController.dispose();
    super.dispose();
  }

  Future<bool> _validateJwtToken() async {
    String? jwtToken = (await AuthTokenStore.instance.getJwtToken());
    if (jwtToken == null || jwtToken.isEmpty) {
      setState(
          () => _errorMessage = 'appealAdmin.error.unauthorizedMissing'.tr);
      return false;
    }
    try {
      final decodedToken = JwtDecoder.decode(jwtToken);
      if (JwtDecoder.isExpired(jwtToken)) {
        jwtToken = await _refreshJwtToken();
        if (jwtToken == null) {
          setState(() => _errorMessage = 'appealAdmin.error.expired'.tr);
          return false;
        }
        await AuthTokenStore.instance.setJwtToken(jwtToken);
        if (JwtDecoder.isExpired(jwtToken)) {
          setState(
              () => _errorMessage = 'appealAdmin.error.refreshedExpired'.tr);
          return false;
        }
        await appealApi.initializeWithJwt();
      }
      developer
          .log('JWT Token validated successfully: sub=${decodedToken['sub']}');
      return true;
    } catch (e) {
      setState(() => _errorMessage = 'appealAdmin.error.invalidLogin'.trParams({
            'error': formatAppealErrorDetail(e),
          }));
      developer.log('JWT validation failed: $e',
          stackTrace: StackTrace.current);
      return false;
    }
  }

  Future<String?> _refreshJwtToken() async {
    final newJwt = await _sessionHelper.refreshJwtToken();
    if (newJwt != null) {
      developer.log('JWT token refreshed successfully');
    } else {
      developer.log('Failed to refresh JWT token');
    }
    return newJwt;
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      if (!await _validateJwtToken()) {
        Get.offAllNamed(Routes.login);
        return;
      }
      await appealApi.initializeWithJwt();
      await _checkUserRole();
    } catch (e) {
      setState(() => _errorMessage = 'appealAdmin.error.initFailed'.trParams({
            'error': formatAppealErrorDetail(e),
          }));
      developer.log('Initialization failed: $e',
          stackTrace: StackTrace.current);
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
      final roles = await _sessionHelper.fetchCurrentRoles();
      final hasAdminAccess = hasAnyRole(roles, const [
        'SUPER_ADMIN',
        'ADMIN',
        'APPEAL_REVIEWER',
      ]);
      setState(() {
        _isAdmin = hasAdminAccess;
        if (!hasAdminAccess) {
          _errorMessage = 'appealAdmin.error.adminOnly'.tr;
        }
      });
    } catch (e) {
      setState(
          () => _errorMessage = 'appealAdmin.error.roleCheckFailed'.trParams({
                'error': formatAppealErrorDetail(e),
              }));
      developer.log('Role check failed: $e', stackTrace: StackTrace.current);
    }
  }

  Future<void> _approveAppeal(int appealId) async {
    await _submitFinalReview(
      appealId: appealId,
      reviewResult: 'Approved',
      successMessage: 'appealAdmin.success.approved'.tr,
    );
  }

  Future<void> _acceptAppeal(int appealId) async {
    await _triggerAcceptanceEvent(
      appealId: appealId,
      event: 'ACCEPT',
      successMessage: 'lookup.appealAcceptanceEventType.accept'.tr,
    );
  }

  Future<void> _requestSupplement(int appealId) async {
    await _showAcceptanceReasonDialog(
      appealId: appealId,
      titleKey: 'appealAdmin.dialog.requestSupplementTitle',
      fieldLabelKey: 'appealAdmin.field.supplementReason',
      validationMessageKey: 'appealAdmin.validation.supplementReasonRequired',
      confirmLabelKey: 'appealAdmin.action.confirmRequestSupplement',
      event: 'REQUEST_SUPPLEMENT',
      successMessage: 'appealAdmin.success.supplementRequested'.tr,
    );
  }

  Future<void> _startReview(int appealId) async {
    await _triggerProcessEvent(
      appealId: appealId,
      event: 'START_REVIEW',
      successMessage: 'lookup.appealProcessEventType.startReview'.tr,
    );
  }

  Future<void> _rejectAcceptedAppeal(int appealId) async {
    await _showAcceptanceReasonDialog(
      appealId: appealId,
      titleKey: 'appealAdmin.dialog.rejectTitle',
      fieldLabelKey: 'appealAdmin.field.rejectionReason',
      validationMessageKey: 'appealAdmin.validation.rejectionReasonRequired',
      confirmLabelKey: 'appealAdmin.action.confirmReject',
      event: 'REJECT',
      successMessage: 'appealAdmin.success.acceptanceRejected'.tr,
      useErrorStyle: true,
    );
  }

  Future<void> _showAcceptanceReasonDialog({
    required int appealId,
    required String titleKey,
    required String fieldLabelKey,
    required String validationMessageKey,
    required String confirmLabelKey,
    required String event,
    required String successMessage,
    bool useErrorStyle = false,
  }) async {
    final themeData = controller.currentBodyTheme.value;
    _rejectionReasonController.clear();
    showDialog(
      context: context,
      builder: (ctx) => Theme(
        data: themeData,
        child: Dialog(
          backgroundColor: themeData.colorScheme.surfaceContainerLowest,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  titleKey.tr,
                  style: themeData.textTheme.titleLarge?.copyWith(
                    color: themeData.colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16.0),
                TextField(
                  controller: _rejectionReasonController,
                  decoration: InputDecoration(
                    labelText: fieldLabelKey.tr,
                    labelStyle: themeData.textTheme.bodyMedium?.copyWith(
                      color: themeData.colorScheme.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor: themeData.colorScheme.surfaceContainer,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      borderSide: BorderSide(
                        color: themeData.colorScheme.primary,
                        width: 2.0,
                      ),
                    ),
                  ),
                  maxLines: 3,
                  style: themeData.textTheme.bodyMedium?.copyWith(
                    color: themeData.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 20.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        'common.cancel'.tr,
                        style: themeData.textTheme.labelLarge?.copyWith(
                          color: themeData.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final reason = _rejectionReasonController.text.trim();
                        if (reason.isEmpty) {
                          _showSnackBar(
                            validationMessageKey.tr,
                            isError: true,
                          );
                          return;
                        }
                        if (widget.appeal.appealId == null) {
                          _showSnackBar(
                            'appealAdmin.error.invalidAppealId'.tr,
                            isError: true,
                          );
                          Navigator.pop(ctx);
                          return;
                        }
                        final didUpdate = await _triggerAcceptanceEvent(
                          appealId: appealId,
                          event: event,
                          rejectionReason: reason,
                          successMessage: successMessage,
                          closePage: false,
                        );
                        if (didUpdate && mounted) {
                          Navigator.pop(ctx);
                          Navigator.pop(context, true);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: useErrorStyle
                            ? themeData.colorScheme.error
                            : themeData.colorScheme.primary,
                        foregroundColor: useErrorStyle
                            ? themeData.colorScheme.onError
                            : themeData.colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20.0, vertical: 12.0),
                      ),
                      child: Text(
                        confirmLabelKey.tr,
                        style: themeData.textTheme.labelLarge?.copyWith(
                          color: useErrorStyle
                              ? themeData.colorScheme.onError
                              : themeData.colorScheme.onPrimary,
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
    );
  }

  Future<void> _rejectReviewedAppeal(int appealId) async {
    final confirmed = await _showConfirmationDialog(
      title: 'lookup.appealProcessEventType.reject'.tr,
      content: 'lookup.appealProcessEventType.reject'.tr,
      confirmLabel: 'lookup.appealProcessEventType.reject'.tr,
      useErrorStyle: true,
    );
    if (confirmed == true) {
      await _submitFinalReview(
        appealId: appealId,
        reviewResult: 'Rejected',
        successMessage: 'appealAdmin.success.finalRejected'.tr,
      );
    }
  }

  Future<bool?> _showConfirmationDialog({
    required String title,
    required String content,
    required String confirmLabel,
    bool useErrorStyle = false,
  }) {
    final themeData = controller.currentBodyTheme.value;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: themeData,
        child: AlertDialog(
          backgroundColor: themeData.colorScheme.surfaceContainerLowest,
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: useErrorStyle
                    ? themeData.colorScheme.error
                    : themeData.colorScheme.primary,
                foregroundColor: useErrorStyle
                    ? themeData.colorScheme.onError
                    : themeData.colorScheme.onPrimary,
              ),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitFinalReview({
    required int appealId,
    required String reviewResult,
    required String successMessage,
    String? reviewOpinion,
  }) async {
    if (widget.appeal.appealId == null) {
      _showSnackBar('appealAdmin.error.invalidAppealId'.tr, isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final review = AppealReviewModel(
        appealId: appealId,
        reviewLevel: 'Final',
        reviewResult: reviewResult,
        reviewOpinion: reviewOpinion == null || reviewOpinion.trim().isEmpty
            ? null
            : reviewOpinion.trim(),
      );
      await appealApi
          .apiAppealsAppealIdReviewsPost(
            appealId: appealId,
            review: review,
            idempotencyKey: generateIdempotencyKey(),
          )
          .timeout(const Duration(seconds: 5));
      final refreshedAppeal =
          await appealApi.apiAppealsAppealIdGet(appealId: appealId);
      _showSnackBar(successMessage);
      if (refreshedAppeal != null) {
        widget.onAppealUpdated?.call(refreshedAppeal);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      developer.log('Error submitting final appeal review $reviewResult: $e',
          stackTrace: StackTrace.current);
      _showSnackBar(formatAppealAdminError(e), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _triggerAcceptanceEvent({
    required int appealId,
    required String event,
    required String successMessage,
    String? rejectionReason,
    bool closePage = true,
  }) async {
    if (widget.appeal.appealId == null) {
      _showSnackBar('appealAdmin.error.invalidAppealId'.tr, isError: true);
      return false;
    }
    setState(() => _isLoading = true);
    try {
      final updatedAppeal = await appealApi
          .apiWorkflowAppealsAppealIdAcceptanceEventsEventPost(
            appealId: appealId,
            event: event,
            rejectionReason: rejectionReason,
            idempotencyKey: generateIdempotencyKey(),
          )
          .timeout(const Duration(seconds: 5));
      _showSnackBar(successMessage);
      widget.onAppealUpdated?.call(updatedAppeal);
      if (closePage && mounted) {
        Navigator.pop(context, true);
      }
      return true;
    } catch (e) {
      developer.log('Error triggering appeal acceptance event $event: $e',
          stackTrace: StackTrace.current);
      _showSnackBar(formatAppealAdminError(e), isError: true);
      return false;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _triggerProcessEvent({
    required int appealId,
    required String event,
    required String successMessage,
  }) async {
    if (widget.appeal.appealId == null) {
      _showSnackBar('appealAdmin.error.invalidAppealId'.tr, isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final updatedAppeal = await appealApi
          .apiWorkflowAppealsAppealIdEventsEventPost(
            appealId: appealId,
            event: event,
            idempotencyKey: generateIdempotencyKey(),
          )
          .timeout(const Duration(seconds: 5));
      _showSnackBar(successMessage);
      widget.onAppealUpdated?.call(updatedAppeal);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      developer.log('Error triggering appeal process event $event: $e',
          stackTrace: StackTrace.current);
      _showSnackBar(formatAppealAdminError(e), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isAcceptancePending() {
    return normalizeAppealStatusCode(widget.appeal.acceptanceStatus) ==
        appealPendingStatusCode();
  }

  bool _isAcceptanceAccepted() {
    return normalizeAppealStatusCode(widget.appeal.acceptanceStatus) ==
        'Accepted';
  }

  bool _isAcceptanceRejected() {
    return normalizeAppealStatusCode(widget.appeal.acceptanceStatus) ==
        appealRejectedStatusCode();
  }

  bool _isAcceptanceNeedSupplement() {
    return normalizeAppealStatusCode(widget.appeal.acceptanceStatus) ==
        'Need_Supplement';
  }

  bool _isProcessUnprocessed() {
    return normalizeAppealStatusCode(widget.appeal.processStatus) ==
        'Unprocessed';
  }

  bool _isProcessUnderReview() {
    return normalizeAppealStatusCode(widget.appeal.processStatus) ==
        'Under_Review';
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

  Widget _buildDetailRow(String label, String value, ThemeData themeData,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'common.labelWithColon'.trParams({'label': label}),
            style: themeData.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: themeData.colorScheme.onSurface,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: themeData.textTheme.bodyLarge?.copyWith(
                color: valueColor ?? themeData.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData = controller.currentBodyTheme.value;
      final appealId =
          widget.appeal.appealId?.toString() ?? 'common.notFilled'.tr;
      final offenseId =
          widget.appeal.offenseId?.toString() ?? 'common.notFilled'.tr;
      final name = widget.appeal.appellantName ?? 'common.notFilled'.tr;
      final idCard = widget.appeal.appellantIdCard ?? 'common.notFilled'.tr;
      final contact = widget.appeal.appellantContact ?? 'common.notFilled'.tr;
      final reason = widget.appeal.appealReason ?? 'common.notFilled'.tr;
      final time = formatAppealDateTime(widget.appeal.appealTime);
      final acceptanceStatus =
          localizeAppealStatus(widget.appeal.acceptanceStatus);
      final processStatus = localizeAppealStatus(widget.appeal.processStatus);
      final result = widget.appeal.processResult ??
          widget.appeal.rejectionReason ??
          'common.notFilled'.tr;

      return DashboardPageTemplate(
        theme: themeData,
        title: 'appeal.detail.title'.tr,
        pageType: DashboardPageType.manager,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _isLoading
              ? Center(
                  child: CupertinoActivityIndicator(
                    color: themeData.colorScheme.primary,
                    radius: 16.0,
                  ),
                )
              : _errorMessage.isNotEmpty
                  ? Column(
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
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (shouldShowAppealAdminReloginAction(_errorMessage))
                          Padding(
                            padding: const EdgeInsets.only(top: 20.0),
                            child: ElevatedButton(
                              onPressed: () => Get.offAllNamed(Routes.login),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: themeData.colorScheme.primary,
                                foregroundColor:
                                    themeData.colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.0)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24.0, vertical: 12.0),
                              ),
                              child: Text('appealAdmin.action.relogin'.tr),
                            ),
                          ),
                      ],
                    )
                  : CupertinoScrollbar(
                      controller: ScrollController(),
                      thumbVisibility: true,
                      thickness: 6.0,
                      thicknessWhileDragging: 10.0,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Card(
                              elevation: 4,
                              color:
                                  themeData.colorScheme.surfaceContainerLowest,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16.0)),
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildDetailRow(
                                      'appeal.detail.appealId'.tr,
                                      appealId,
                                      themeData,
                                    ),
                                    _buildDetailRow(
                                      'appeal.detail.offenseId'.tr,
                                      offenseId,
                                      themeData,
                                    ),
                                    _buildDetailRow(
                                      'appeal.detail.appellant'.tr,
                                      name,
                                      themeData,
                                    ),
                                    _buildDetailRow(
                                      'appeal.detail.idCard'.tr,
                                      idCard,
                                      themeData,
                                    ),
                                    _buildDetailRow(
                                      'appeal.detail.contact'.tr,
                                      contact,
                                      themeData,
                                    ),
                                    _buildDetailRow(
                                      'appeal.detail.reason'.tr,
                                      reason,
                                      themeData,
                                    ),
                                    _buildDetailRow(
                                      'appeal.detail.time'.tr,
                                      time,
                                      themeData,
                                    ),
                                    _buildDetailRow(
                                      'appeal.detail.acceptanceStatus'.tr,
                                      acceptanceStatus,
                                      themeData,
                                      valueColor: isRejectedAppealStatus(
                                              widget.appeal.acceptanceStatus)
                                          ? Colors.red
                                          : themeData
                                              .colorScheme.onSurfaceVariant,
                                    ),
                                    _buildDetailRow('appeal.detail.status'.tr,
                                        processStatus, themeData,
                                        valueColor: isApprovedAppealStatus(
                                                widget.appeal.processStatus)
                                            ? Colors.green
                                            : isRejectedAppealStatus(
                                                    widget.appeal.processStatus)
                                                ? Colors.red
                                                : themeData.colorScheme
                                                    .onSurfaceVariant),
                                    _buildDetailRow(
                                      'appeal.detail.result'.tr,
                                      result,
                                      themeData,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (_isAdmin && _isAcceptancePending()) ...[
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 12.0,
                                runSpacing: 12.0,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () => _acceptAppeal(
                                        widget.appeal.appealId ?? 0),
                                    icon: const Icon(CupertinoIcons.checkmark,
                                        size: 20),
                                    label: Text(
                                        'lookup.appealAcceptanceEventType.accept'
                                            .tr),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12.0)),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20.0, vertical: 12.0),
                                      elevation: 2,
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _requestSupplement(
                                        widget.appeal.appealId ?? 0),
                                    icon: const Icon(CupertinoIcons.doc_text,
                                        size: 20),
                                    label: Text(
                                        'lookup.appealAcceptanceEventType.requestSupplement'
                                            .tr),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12.0)),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20.0, vertical: 12.0),
                                      elevation: 2,
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _rejectAcceptedAppeal(
                                        widget.appeal.appealId ?? 0),
                                    icon: const Icon(CupertinoIcons.xmark,
                                        size: 20),
                                    label: Text(
                                        'lookup.appealAcceptanceEventType.reject'
                                            .tr),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          themeData.colorScheme.error,
                                      foregroundColor:
                                          themeData.colorScheme.onError,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12.0)),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20.0, vertical: 12.0),
                                      elevation: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ] else if (_isAdmin &&
                                _isAcceptanceNeedSupplement()) ...[
                              Center(
                                child: Text(
                                  'appealAdmin.note.awaitingApplicantSupplement'
                                      .tr,
                                  style:
                                      themeData.textTheme.bodyMedium?.copyWith(
                                    color:
                                        themeData.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ] else if (_isAdmin && _isAcceptanceRejected()) ...[
                              Center(
                                child: Text(
                                  'appealAdmin.note.awaitingApplicantResubmission'
                                      .tr,
                                  style:
                                      themeData.textTheme.bodyMedium?.copyWith(
                                    color:
                                        themeData.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ] else if (_isAdmin &&
                                _isAcceptanceAccepted() &&
                                _isProcessUnprocessed()) ...[
                              Center(
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _startReview(widget.appeal.appealId ?? 0),
                                  icon: const Icon(CupertinoIcons.play_arrow,
                                      size: 20),
                                  label: Text(
                                      'lookup.appealProcessEventType.startReview'
                                          .tr),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        themeData.colorScheme.primary,
                                    foregroundColor:
                                        themeData.colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ] else if (_isAdmin && _isProcessUnderReview()) ...[
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 12.0,
                                runSpacing: 12.0,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () => _approveAppeal(
                                        widget.appeal.appealId ?? 0),
                                    icon: const Icon(CupertinoIcons.checkmark,
                                        size: 20),
                                    label: Text(
                                        'lookup.appealProcessEventType.approve'
                                            .tr),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _rejectReviewedAppeal(
                                        widget.appeal.appealId ?? 0),
                                    icon: const Icon(CupertinoIcons.xmark,
                                        size: 20),
                                    label: Text(
                                        'lookup.appealProcessEventType.reject'
                                            .tr),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          themeData.colorScheme.error,
                                      foregroundColor:
                                          themeData.colorScheme.onError,
                                    ),
                                  ),
                                ],
                              ),
                            ] else
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12.0, horizontal: 20.0),
                                  decoration: BoxDecoration(
                                    color:
                                        themeData.colorScheme.surfaceContainer,
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  child: Text(
                                    _isAdmin
                                        ? 'appealAdmin.note.alreadyProcessed'.tr
                                        : 'appealAdmin.note.adminApprovalOnly'
                                            .tr,
                                    style:
                                        themeData.textTheme.bodyLarge?.copyWith(
                                      color: themeData
                                          .colorScheme.onSurfaceVariant,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
        ),
      );
    });
  }
}
