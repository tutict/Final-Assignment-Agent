// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:developer' as developer;

import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/api/offense_information_controller_api.dart';
import 'package:final_assignment_front/features/api/vehicle_information_controller_api.dart';
import 'package:final_assignment_front/features/dashboard/controllers/admin_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/features/model/offense_information.dart';
import 'package:final_assignment_front/i18n/offense_localizers.dart';
import 'package:final_assignment_front/i18n/status_localizers.dart';
import 'package:final_assignment_front/utils/helpers/api_exception.dart';
import 'package:final_assignment_front/utils/helpers/role_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:final_assignment_front/utils/services/auth_token_store.dart';
import 'package:final_assignment_front/utils/services/session_helper.dart';

String generateIdempotencyKey() {
  return DateTime.now().millisecondsSinceEpoch.toString();
}

final String _defaultOffenseProcessStatus = offensePendingProcessStatusCode();

class OffenseList extends StatefulWidget {
  const OffenseList({super.key});

  @override
  State<OffenseList> createState() => _OffenseListPageState();
}

class _OffenseListPageState extends State<OffenseList> {
  static const int _pageSize = 20;

  final OffenseInformationControllerApi offenseApi =
      OffenseInformationControllerApi();
  final SessionHelper _sessionHelper = SessionHelper();
  final TextEditingController _searchController = TextEditingController();
  TextEditingController? _searchFieldController;
  final List<OffenseInformation> _offenseList = [];
  List<OffenseInformation> _filteredOffenseList = [];
  String _searchType = kOffenseSearchTypeDriverName;
  String _activeQuery = '';
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  String _errorMessage = '';
  bool _canManageOffenses = false;
  DateTime? _startDate;
  DateTime? _endDate;
  Timer? _searchDebounce;
  final DashboardController controller = Get.find<DashboardController>();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<bool> _validateJwtToken() async {
    String? jwtToken = (await AuthTokenStore.instance.getJwtToken());
    if (jwtToken == null || jwtToken.isEmpty) {
      setState(() => _errorMessage = 'offenseAdmin.error.unauthorized'.tr);
      return false;
    }
    try {
      if (JwtDecoder.isExpired(jwtToken)) {
        jwtToken = await _refreshJwtToken();
        if (jwtToken == null) {
          setState(() => _errorMessage = 'offenseAdmin.error.expired'.tr);
          return false;
        }
        await AuthTokenStore.instance.setJwtToken(jwtToken);
        if (JwtDecoder.isExpired(jwtToken)) {
          setState(
              () => _errorMessage = 'offenseAdmin.error.refreshedExpired'.tr);
          return false;
        }
        await offenseApi.initializeWithJwt();
      }
      return true;
    } catch (e) {
      setState(() => _errorMessage = 'offenseAdmin.error.invalidLogin'.tr);
      return false;
    }
  }

  Future<String?> _refreshJwtToken() async {
    return await _sessionHelper.refreshJwtToken();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return;
      }
      await offenseApi.initializeWithJwt();
      final jwtToken = (await AuthTokenStore.instance.getJwtToken())!;
      final decodedToken = JwtDecoder.decode(jwtToken);
      _canManageOffenses = hasAnyRole(decodedToken['roles'], const [
        'SUPER_ADMIN',
        'ADMIN',
        'TRAFFIC_POLICE',
      ]);
      await _checkUserRole();
      await _fetchOffenses(reset: true);
    } catch (e) {
      setState(() => _errorMessage = 'offenseAdmin.error.initFailed'
          .trParams({'error': formatOffenseAdminError(e)}));
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
      final hasReadAccess = hasAnyRole(roles, const [
        'SUPER_ADMIN',
        'ADMIN',
        'TRAFFIC_POLICE',
        'APPEAL_REVIEWER',
      ]);
      setState(() {
        _canManageOffenses = hasAnyRole(roles, const [
          'SUPER_ADMIN',
          'ADMIN',
          'TRAFFIC_POLICE',
        ]);
        if (!hasReadAccess) {
          _errorMessage = 'offenseAdmin.error.adminOnly'.tr;
        }
      });
    } catch (e) {
      setState(() => _errorMessage = 'offenseAdmin.error.roleCheckFailed'
          .trParams({'error': formatOffenseAdminError(e)}));
      developer.log('Role check failed: $e', stackTrace: StackTrace.current);
    }
  }

  Future<void> _fetchOffenses({bool reset = false, String? query}) async {
    if (reset) {
      _currentPage = 1;
      _hasMore = true;
      _activeQuery = (query ?? _searchController.text).trim();
      _offenseList.clear();
      _filteredOffenseList.clear();
    }
    if (!_hasMore) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return;
      }
      final offenses = await _loadOffensePage(
        page: _currentPage,
        query: _activeQuery,
      );

      setState(() {
        _offenseList.addAll(offenses);
        _hasMore = offenses.length == _pageSize;
        _rebuildFilteredOffenseList();
        if (_filteredOffenseList.isEmpty) {
          _errorMessage = _hasActiveFilters
              ? 'offenseAdmin.error.filteredEmpty'.tr
              : 'offenseAdmin.empty.default'.tr;
        }
        _currentPage++;
      });
    } catch (e) {
      setState(() {
        if (e is ApiException && e.code == 403) {
          _errorMessage = 'offenseAdmin.error.unauthorized'.tr;
          Navigator.pushReplacementNamed(context, Routes.login);
        } else if (e is ApiException && e.code == 404) {
          _offenseList.clear();
          _filteredOffenseList.clear();
          _errorMessage = 'offenseAdmin.error.notFound'.tr;
          _hasMore = false;
        } else {
          _errorMessage = 'offenseAdmin.error.loadFailed'
              .trParams({'error': formatOffenseAdminError(e)});
        }
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<List<OffenseInformation>> _loadOffensePage({
    required int page,
    required String query,
  }) {
    if (_startDate != null && _endDate != null) {
      return offenseApi.apiOffensesTimeRangeGet(
        startTime: _startDate!.toIso8601String(),
        endTime: _endDate!.add(const Duration(days: 1)).toIso8601String(),
        page: page,
        size: _pageSize,
      );
    }

    if (query.isEmpty) {
      return offenseApi.apiOffensesGet(page: page, size: _pageSize);
    }

    switch (_searchType) {
      case kOffenseSearchTypeDriverName:
        return offenseApi.apiOffensesByDriverNameGet(
          query: query,
          page: page,
          size: _pageSize,
        );
      case kOffenseSearchTypeLicensePlate:
        return offenseApi.apiOffensesByLicensePlateGet(
          query: query,
          page: page,
          size: _pageSize,
        );
      case kOffenseSearchTypeOffenseType:
        return offenseApi.apiOffensesByOffenseTypeGet(
          query: query,
          page: page,
          size: _pageSize,
        );
      default:
        return offenseApi.apiOffensesGet(page: page, size: _pageSize);
    }
  }

  Future<List<String>> _fetchAutocompleteSuggestions(String prefix) async {
    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return [];
      }
      switch (_searchType) {
        case kOffenseSearchTypeDriverName:
          final offenses = await offenseApi.apiOffensesByDriverNameGet(
              query: prefix.trim(), page: 1, size: 10);
          return offenses
              .map((o) => o.driverName ?? '')
              .where(
                  (name) => name.toLowerCase().contains(prefix.toLowerCase()))
              .toList();
        case kOffenseSearchTypeLicensePlate:
          final offenses = await offenseApi.apiOffensesByLicensePlateGet(
              query: prefix.trim(), page: 1, size: 10);
          return offenses
              .map((o) => o.licensePlate ?? '')
              .where(
                  (plate) => plate.toLowerCase().contains(prefix.toLowerCase()))
              .toList();
        case kOffenseSearchTypeOffenseType:
          final offenses = await offenseApi.apiOffensesByOffenseTypeGet(
              query: prefix.trim(), page: 1, size: 10);
          return offenses
              .map((o) => o.offenseType ?? '')
              .where(
                  (type) => type.toLowerCase().contains(prefix.toLowerCase()))
              .toList();
        default:
          return [];
      }
    } catch (e) {
      setState(() => _errorMessage = 'offenseAdmin.error.suggestionFailed'
          .trParams({'error': formatOffenseAdminError(e)}));
      return [];
    }
  }

  void _rebuildFilteredOffenseList() {
    final searchQuery = _activeQuery.trim().toLowerCase();
    _filteredOffenseList.clear();
    _filteredOffenseList = _offenseList.where((offense) {
      final driverName = (offense.driverName ?? '').toLowerCase();
      final licensePlate = (offense.licensePlate ?? '').toLowerCase();
      final offenseType = (offense.offenseType ?? '').toLowerCase();
      final offenseTime = offense.offenseTime;

      bool matchesQuery = true;
      if (searchQuery.isNotEmpty) {
        if (_searchType == kOffenseSearchTypeDriverName) {
          matchesQuery = driverName.contains(searchQuery);
        } else if (_searchType == kOffenseSearchTypeLicensePlate) {
          matchesQuery = licensePlate.contains(searchQuery);
        } else if (_searchType == kOffenseSearchTypeOffenseType) {
          matchesQuery = offenseType.contains(searchQuery);
        }
      }

      bool matchesDateRange = true;
      if (_startDate != null && _endDate != null && offenseTime != null) {
        matchesDateRange = offenseTime.isAfter(_startDate!) &&
            offenseTime.isBefore(_endDate!.add(const Duration(days: 1)));
      } else if (_startDate != null &&
          _endDate != null &&
          offenseTime == null) {
        matchesDateRange = false;
      }

      return matchesQuery && matchesDateRange;
    }).toList();

    if (_filteredOffenseList.isEmpty && _offenseList.isNotEmpty) {
      _errorMessage = 'offenseAdmin.error.filteredEmpty'.tr;
    } else {
      _errorMessage = _filteredOffenseList.isEmpty && _offenseList.isEmpty
          ? 'offenseAdmin.empty.default'.tr
          : '';
    }
  }

  // ignore: unused_element
  Future<void> _searchOffenses() async {
    await _refreshOffenses(query: _searchController.text.trim());
  }

  Future<void> _refreshOffenses({String? query}) async {
    _searchDebounce?.cancel();
    final effectiveQuery = (query ?? _searchController.text).trim();
    setState(() {
      _offenseList.clear();
      _filteredOffenseList.clear();
      _currentPage = 1;
      _hasMore = true;
      _isLoading = true;
      _activeQuery = effectiveQuery;
      _setSearchText(effectiveQuery);
    });
    await _fetchOffenses(reset: true, query: effectiveQuery);
  }

  Future<void> _loadMoreOffenses() async {
    if (!_isLoading && _hasMore) {
      await _fetchOffenses();
    }
  }

  bool get _hasActiveFilters =>
      _activeQuery.isNotEmpty || (_startDate != null && _endDate != null);

  void _setSearchText(String value) {
    final textValue = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _searchController.value = textValue;
    _searchFieldController?.value = textValue;
  }

  void _scheduleSearchRefresh(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _refreshOffenses(query: value);
    });
  }

  void _createOffense() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddOffensePage()),
    ).then((value) {
      if (value == true) {
        _refreshOffenses();
      }
    });
  }

  void _goToDetailPage(OffenseInformation offense) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OffenseDetailPage(offense: offense),
      ),
    );
  }

  Future<void> _deleteOffense(int offenseId) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('offenseAdmin.delete.confirmTitle'.tr),
        content: Text('offenseAdmin.delete.confirmBody'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('offenseAdmin.action.delete'.tr,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        if (!await _validateJwtToken()) {
          Navigator.pushReplacementNamed(context, Routes.login);
          return;
        }
        await offenseApi.apiOffensesOffenseIdDelete(offenseId: offenseId);
        await _refreshOffenses();
      } catch (e) {
        setState(() => _errorMessage = 'offenseAdmin.error.deleteFailed'
            .trParams({'error': formatOffenseAdminError(e)}));
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildSearchField(ThemeData themeData) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Autocomplete<String>(
                  optionsBuilder: (TextEditingValue textEditingValue) async {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<String>.empty();
                    }
                    return await _fetchAutocompleteSuggestions(
                        textEditingValue.text);
                  },
                  onSelected: (String selection) {
                    _setSearchText(selection);
                    _refreshOffenses(query: selection);
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) {
                    _searchFieldController = controller;
                    if (controller.text != _searchController.text) {
                      controller.value = TextEditingValue(
                        text: _searchController.text,
                        selection: TextSelection.collapsed(
                          offset: _searchController.text.length,
                        ),
                      );
                    }
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      style: TextStyle(color: themeData.colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: offenseSearchHintText(_searchType),
                        hintStyle: TextStyle(
                            color: themeData.colorScheme.onSurface
                                .withValues(alpha: 0.6)),
                        prefixIcon: Icon(Icons.search,
                            color: themeData.colorScheme.primary),
                        suffixIcon: controller.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear,
                                    color:
                                        themeData.colorScheme.onSurfaceVariant),
                                onPressed: () {
                                  _setSearchText('');
                                  _refreshOffenses(query: '');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0)),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                              color: themeData.colorScheme.outline
                                  .withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                              color: themeData.colorScheme.primary, width: 1.5),
                        ),
                        filled: true,
                        fillColor: themeData.colorScheme.surfaceContainerLowest,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12.0, horizontal: 16.0),
                      ),
                      onChanged: (value) {
                        _setSearchText(value);
                        setState(() {});
                        _scheduleSearchRefresh(value);
                      },
                      onSubmitted: (value) {
                        _setSearchText(value);
                        _refreshOffenses(query: value);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _searchType,
                onChanged: (String? newValue) {
                  if (newValue == null || newValue == _searchType) {
                    return;
                  }
                  setState(() {
                    _searchType = newValue;
                    _startDate = null;
                    _endDate = null;
                  });
                  _setSearchText('');
                  _refreshOffenses(query: '');
                },
                items: <String>[
                  kOffenseSearchTypeDriverName,
                  kOffenseSearchTypeLicensePlate,
                  kOffenseSearchTypeOffenseType,
                ].map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(
                      offenseSearchTypeLabel(value),
                      style: TextStyle(color: themeData.colorScheme.onSurface),
                    ),
                  );
                }).toList(),
                dropdownColor: themeData.colorScheme.surfaceContainer,
                icon: Icon(Icons.arrow_drop_down,
                    color: themeData.colorScheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _startDate != null && _endDate != null
                      ? 'offenseAdmin.filter.dateRangeLabel'.trParams({
                          'start': formatOffenseDate(_startDate),
                          'end': formatOffenseDate(_endDate),
                        })
                      : 'offenseAdmin.filter.selectDateRange'.tr,
                  style: themeData.textTheme.bodyMedium?.copyWith(
                    color: _startDate != null && _endDate != null
                        ? themeData.colorScheme.onSurface
                        : themeData.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.date_range,
                    color: themeData.colorScheme.primary),
                tooltip: 'offenseAdmin.filter.tooltip'.tr,
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                    locale: Get.locale ?? const Locale('en', 'US'),
                    helpText: 'offenseAdmin.filter.selectDateRange'.tr,
                    cancelText: 'common.cancel'.tr,
                    confirmText: 'common.confirm'.tr,
                    fieldStartHintText: 'offenseAdmin.filter.startDate'.tr,
                    fieldEndHintText: 'offenseAdmin.filter.endDate'.tr,
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
                      _startDate = range.start;
                      _endDate = range.end;
                    });
                    _refreshOffenses(query: _searchController.text.trim());
                  }
                },
              ),
              if (_startDate != null && _endDate != null)
                IconButton(
                  icon: Icon(Icons.clear,
                      color: themeData.colorScheme.onSurfaceVariant),
                  tooltip: 'offenseAdmin.filter.clearDateRange'.tr,
                  onPressed: () {
                    setState(() {
                      _startDate = null;
                      _endDate = null;
                    });
                    _refreshOffenses(query: _searchController.text.trim());
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData = controller.currentBodyTheme.value;
      return DashboardPageTemplate(
        theme: themeData,
        title: 'offenseAdmin.page.title'.tr,
        pageType: DashboardPageType.admin,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        actions: [
          if (_canManageOffenses) ...[
            DashboardPageBarAction(
              icon: Icons.add,
              onPressed: _createOffense,
              tooltip: 'offenseAdmin.action.add'.tr,
            ),
            DashboardPageBarAction(
              icon: Icons.refresh,
              onPressed: () => _refreshOffenses(),
              tooltip: 'offenseAdmin.action.refresh'.tr,
            ),
          ],
        ],
        onThemeToggle: controller.toggleBodyTheme,
        body: RefreshIndicator(
          onRefresh: () => _refreshOffenses(),
          color: themeData.colorScheme.primary,
          backgroundColor: themeData.colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const SizedBox(height: 12),
                _buildSearchField(themeData),
                const SizedBox(height: 12),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (scrollInfo) {
                      if (scrollInfo.metrics.pixels ==
                              scrollInfo.metrics.maxScrollExtent &&
                          _hasMore) {
                        _loadMoreOffenses();
                      }
                      return false;
                    },
                    child: _isLoading && _currentPage == 1
                        ? Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation(
                                  themeData.colorScheme.primary),
                            ),
                          )
                        : _errorMessage.isNotEmpty &&
                                _filteredOffenseList.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _errorMessage,
                                      style: themeData.textTheme.titleMedium
                                          ?.copyWith(
                                        color: themeData.colorScheme.error,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    if (shouldShowOffenseAdminReloginAction(
                                        _errorMessage))
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 16.0),
                                        child: ElevatedButton(
                                          onPressed: () =>
                                              Navigator.pushReplacementNamed(
                                                  context, Routes.login),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                themeData.colorScheme.primary,
                                            foregroundColor:
                                                themeData.colorScheme.onPrimary,
                                          ),
                                          child: Text(
                                              'offenseAdmin.action.relogin'.tr),
                                        ),
                                      ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: _filteredOffenseList.length +
                                    (_hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _filteredOffenseList.length &&
                                      _hasMore) {
                                    return const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Center(
                                          child: CircularProgressIndicator()),
                                    );
                                  }
                                  final offense = _filteredOffenseList[index];
                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                        vertical: 8.0),
                                    elevation: 3,
                                    color:
                                        themeData.colorScheme.surfaceContainer,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16.0)),
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16.0, vertical: 12.0),
                                      title: Text(
                                        'offenseAdmin.card.type'.trParams({
                                          'value': offense.offenseType ??
                                              'common.unknown'.tr,
                                        }),
                                        style: themeData.textTheme.titleMedium
                                            ?.copyWith(
                                          color:
                                              themeData.colorScheme.onSurface,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Text(
                                            'offenseAdmin.card.licensePlate'
                                                .trParams({
                                              'value': offense.licensePlate ??
                                                  'common.unknown'.tr,
                                            }),
                                            style: themeData
                                                .textTheme.bodyMedium
                                                ?.copyWith(
                                              color: themeData
                                                  .colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          Text(
                                            'offenseAdmin.card.driverName'
                                                .trParams({
                                              'value': offense.driverName ??
                                                  'common.unknown'.tr,
                                            }),
                                            style: themeData
                                                .textTheme.bodyMedium
                                                ?.copyWith(
                                              color: themeData
                                                  .colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          Text(
                                            'offenseAdmin.card.status'
                                                .trParams({
                                              'value':
                                                  localizeOffenseProcessStatus(
                                                offense.processStatus,
                                              ),
                                            }),
                                            style: themeData
                                                .textTheme.bodyMedium
                                                ?.copyWith(
                                              color: themeData
                                                  .colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                      trailing: _canManageOffenses
                                          ? Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: Icon(Icons.delete,
                                                      size: 18,
                                                      color: themeData
                                                          .colorScheme.error),
                                                  onPressed: () =>
                                                      _deleteOffense(
                                                          offense.offenseId ??
                                                              0),
                                                  tooltip:
                                                      'offenseAdmin.action.delete'
                                                          .tr,
                                                ),
                                                Icon(
                                                  Icons.arrow_forward_ios,
                                                  color: themeData.colorScheme
                                                      .onSurfaceVariant,
                                                  size: 18,
                                                ),
                                              ],
                                            )
                                          : Icon(
                                              Icons.arrow_forward_ios,
                                              color: themeData
                                                  .colorScheme.onSurfaceVariant,
                                              size: 18,
                                            ),
                                      onTap: () => _goToDetailPage(offense),
                                    ),
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class AddOffensePage extends StatefulWidget {
  const AddOffensePage({super.key});

  @override
  State<AddOffensePage> createState() => _AddOffensePageState();
}

class _AddOffensePageState extends State<AddOffensePage> {
  final OffenseInformationControllerApi offenseApi =
      OffenseInformationControllerApi();
  final VehicleInformationControllerApi vehicleApi =
      VehicleInformationControllerApi(); // Add vehicle API
  final _formKey = GlobalKey<FormState>();
  final _driverNameController = TextEditingController();
  final _licensePlateController = TextEditingController();
  final _offenseTypeController = TextEditingController();
  final _offenseCodeController = TextEditingController();
  final _offenseLocationController = TextEditingController();
  final _offenseTimeController = TextEditingController();
  final _deductedPointsController = TextEditingController();
  final _fineAmountController = TextEditingController();
  final _processStatusController = TextEditingController();
  final _processResultController = TextEditingController();
  DateTime? _selectedOffenseTime;
  bool _isLoading = false;
  final DashboardController controller = Get.find<DashboardController>();

  Future<bool> _validateJwtToken() async {
    final jwtToken = (await AuthTokenStore.instance.getJwtToken());
    if (jwtToken == null || jwtToken.isEmpty) {
      _showSnackBar('offenseAdmin.error.unauthorized'.tr, isError: true);
      return false;
    }
    try {
      if (JwtDecoder.isExpired(jwtToken)) {
        _showSnackBar('offenseAdmin.error.expired'.tr, isError: true);
        return false;
      }
      return true;
    } catch (e) {
      _showSnackBar('offenseAdmin.error.invalidLogin'.tr, isError: true);
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return;
      }
      await offenseApi.initializeWithJwt();
      await vehicleApi.initializeWithJwt(); // Initialize vehicle API
      _processStatusController.text =
          localizeOffenseProcessStatus(_defaultOffenseProcessStatus);
    } catch (e) {
      _showSnackBar(
        'offenseAdmin.error.initFailed'
            .trParams({'error': formatOffenseAdminError(e)}),
        isError: true,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _driverNameController.dispose();
    _licensePlateController.dispose();
    _offenseTypeController.dispose();
    _offenseCodeController.dispose();
    _offenseLocationController.dispose();
    _offenseTimeController.dispose();
    _deductedPointsController.dispose();
    _fineAmountController.dispose();
    _processStatusController.dispose();
    _processResultController.dispose();
    super.dispose();
  }

  void _setOffenseTime(DateTime? value) {
    _selectedOffenseTime = value == null ? null : DateUtils.dateOnly(value);
    _offenseTimeController.text = _selectedOffenseTime == null
        ? ''
        : formatOffenseDate(_selectedOffenseTime);
  }

  Future<List<String>> _fetchDriverNameSuggestions(String prefix) async {
    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return [];
      }
      final vehicles = await vehicleApi.apiVehiclesSearchGeneralGet(
          keywords: prefix, page: 1, size: 10);
      return vehicles
          .map((v) => v.ownerName ?? '')
          .where((name) => name.toLowerCase().contains(prefix.toLowerCase()))
          .toSet()
          .toList();
    } catch (e) {
      _showSnackBar(
        'offenseAdmin.error.suggestionFailed'
            .trParams({'error': formatOffenseAdminError(e)}),
        isError: true,
      );
      return [];
    }
  }

  Future<List<String>> _fetchLicensePlateSuggestions(String prefix) async {
    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return [];
      }
      return await vehicleApi.apiVehiclesSearchLicenseGlobalGet(prefix: prefix);
    } catch (e) {
      _showSnackBar(
        'offenseAdmin.error.suggestionFailed'
            .trParams({'error': formatOffenseAdminError(e)}),
        isError: true,
      );
      return [];
    }
  }

  Future<void> _submitOffense() async {
    if (!_formKey.currentState!.validate()) return;
    if (!await _validateJwtToken()) {
      Navigator.pushReplacementNamed(context, Routes.login);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final idempotencyKey = generateIdempotencyKey();
      final offensePayload = OffenseInformation(
        offenseTime: _selectedOffenseTime,
        driverName: _driverNameController.text.trim(),
        licensePlate: _licensePlateController.text.trim(),
        offenseType: _offenseTypeController.text.trim(),
        offenseCode: _offenseCodeController.text.trim(),
        offenseLocation: _offenseLocationController.text.trim(),
        deductedPoints: _deductedPointsController.text.trim().isEmpty
            ? null
            : int.parse(_deductedPointsController.text.trim()),
        fineAmount: _fineAmountController.text.trim().isEmpty
            ? null
            : double.parse(_fineAmountController.text.trim()),
        processResult: _processResultController.text.trim().isEmpty
            ? null
            : _processResultController.text.trim(),
        idempotencyKey: idempotencyKey,
      );
      await offenseApi.apiOffensesPost(
        offenseInformation: offensePayload,
        idempotencyKey: idempotencyKey,
      );
      _showSnackBar('offenseAdmin.success.created'.tr);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showSnackBar(
        'offenseAdmin.error.createFailed'
            .trParams({'error': formatOffenseAdminError(e)}),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedOffenseTime ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: controller.currentBodyTheme.value.copyWith(
          colorScheme: controller.currentBodyTheme.value.colorScheme.copyWith(
            primary: controller.currentBodyTheme.value.colorScheme.primary,
            onPrimary: controller.currentBodyTheme.value.colorScheme.onPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (pickedDate != null && mounted) {
      setState(() => _setOffenseTime(pickedDate));
    }
  }

  Widget _buildFormField(
    String fieldKey,
    TextEditingController controller,
    ThemeData themeData, {
    TextInputType? keyboardType,
    bool readOnly = false,
    VoidCallback? onTap,
    bool required = false,
    int? maxLength,
  }) {
    final label = offenseFieldLabel(fieldKey);
    final helperText = offenseFieldHelperText(fieldKey);
    final isAutocompleteField = fieldKey == kOffenseFieldDriverName ||
        fieldKey == kOffenseFieldLicensePlate;

    InputDecoration buildDecoration({Widget? suffixIcon}) {
      return InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: themeData.colorScheme.onSurfaceVariant),
        helperText: helperText,
        helperStyle: TextStyle(
          color: themeData.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: themeData.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide:
              BorderSide(color: themeData.colorScheme.primary, width: 1.5),
        ),
        filled: true,
        fillColor: readOnly
            ? themeData.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5)
            : themeData.colorScheme.surfaceContainerLowest,
        suffixIcon: suffixIcon ??
            (readOnly && fieldKey == kOffenseFieldOffenseTime
                ? Icon(
                    Icons.calendar_today,
                    size: 18,
                    color: themeData.colorScheme.primary,
                  )
                : null),
      );
    }

    if (isAutocompleteField) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Autocomplete<String>(
          optionsBuilder: (textEditingValue) async {
            if (textEditingValue.text.trim().isEmpty) {
              return const Iterable<String>.empty();
            }
            return fieldKey == kOffenseFieldDriverName
                ? await _fetchDriverNameSuggestions(textEditingValue.text)
                : await _fetchLicensePlateSuggestions(textEditingValue.text);
          },
          onSelected: (selection) {
            controller.text = selection;
          },
          fieldViewBuilder:
              (context, textEditingController, focusNode, onFieldSubmitted) {
            if (textEditingController.text != controller.text) {
              textEditingController.value = TextEditingValue(
                text: controller.text,
                selection:
                    TextSelection.collapsed(offset: controller.text.length),
              );
            }
            return TextFormField(
              controller: textEditingController,
              focusNode: focusNode,
              style: TextStyle(color: themeData.colorScheme.onSurface),
              decoration: buildDecoration(
                suffixIcon: textEditingController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: themeData.colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () {
                          textEditingController.clear();
                          controller.clear();
                        },
                      )
                    : null,
              ),
              keyboardType: keyboardType,
              maxLength: maxLength,
              validator: (value) => validateOffenseFormField(
                fieldKey,
                value,
                required: required,
                selectedDate: fieldKey == kOffenseFieldOffenseTime
                    ? _selectedOffenseTime
                    : null,
              ),
              onChanged: (value) {
                controller.text = value;
              },
            );
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: TextFormField(
        controller: controller,
        style: TextStyle(color: themeData.colorScheme.onSurface),
        decoration: buildDecoration(),
        keyboardType: keyboardType,
        readOnly: readOnly,
        onTap: onTap,
        maxLength: maxLength,
        validator: (value) => validateOffenseFormField(
          fieldKey,
          value,
          required: required,
          selectedDate: fieldKey == kOffenseFieldOffenseTime
              ? _selectedOffenseTime
              : null,
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
        title: 'offenseAdmin.form.addTitle'.tr,
        pageType: DashboardPageType.admin,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Card(
                          elevation: 3,
                          color: themeData.colorScheme.surfaceContainer,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16.0)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                _buildFormField(kOffenseFieldDriverName,
                                    _driverNameController, themeData,
                                    required: true, maxLength: 100),
                                _buildFormField(kOffenseFieldLicensePlate,
                                    _licensePlateController, themeData,
                                    required: true, maxLength: 20),
                                _buildFormField(kOffenseFieldOffenseType,
                                    _offenseTypeController, themeData,
                                    required: true, maxLength: 100),
                                _buildFormField(kOffenseFieldOffenseCode,
                                    _offenseCodeController, themeData,
                                    required: true, maxLength: 50),
                                _buildFormField(kOffenseFieldOffenseLocation,
                                    _offenseLocationController, themeData,
                                    required: true, maxLength: 100),
                                _buildFormField(kOffenseFieldOffenseTime,
                                    _offenseTimeController, themeData,
                                    required: true,
                                    readOnly: true,
                                    onTap: _pickDate),
                                _buildFormField(kOffenseFieldDeductedPoints,
                                    _deductedPointsController, themeData,
                                    keyboardType: TextInputType.number),
                                _buildFormField(kOffenseFieldFineAmount,
                                    _fineAmountController, themeData,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true)),
                                _buildFormField(kOffenseFieldProcessStatus,
                                    _processStatusController, themeData,
                                    readOnly: true, maxLength: 50),
                                _buildFormField(kOffenseFieldProcessResult,
                                    _processResultController, themeData,
                                    maxLength: 255),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _submitOffense,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: themeData.colorScheme.primary,
                            foregroundColor: themeData.colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.0)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14.0, horizontal: 20.0),
                            textStyle: themeData.textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          child: Text('common.submit'.tr),
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

class OffenseDetailPage extends StatefulWidget {
  final OffenseInformation offense;

  const OffenseDetailPage({super.key, required this.offense});

  @override
  State<OffenseDetailPage> createState() => _OffenseDetailPageState();
}

class _OffenseDetailPageState extends State<OffenseDetailPage> {
  final OffenseInformationControllerApi offenseApi =
      OffenseInformationControllerApi();
  final SessionHelper _sessionHelper = SessionHelper();
  bool _isLoading = false;
  bool _isEditable = false;
  String _errorMessage = '';
  final DashboardController controller = Get.find<DashboardController>();

  Future<bool> _validateJwtToken() async {
    final jwtToken = (await AuthTokenStore.instance.getJwtToken());
    if (jwtToken == null || jwtToken.isEmpty) {
      setState(() => _errorMessage = 'offenseAdmin.error.unauthorized'.tr);
      return false;
    }
    try {
      if (JwtDecoder.isExpired(jwtToken)) {
        setState(() => _errorMessage = 'offenseAdmin.error.expired'.tr);
        return false;
      }
      return true;
    } catch (e) {
      setState(() => _errorMessage = 'offenseAdmin.error.invalidLogin'.tr);
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return;
      }
      await offenseApi.initializeWithJwt();
      await _checkUserRole();
    } catch (e) {
      setState(() => _errorMessage = 'offenseAdmin.error.initFailed'
          .trParams({'error': formatOffenseAdminError(e)}));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkUserRole() async {
    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return;
      }
      final roles = await _sessionHelper.fetchCurrentRoles();
      setState(() => _isEditable = hasAnyRole(roles, const [
            'SUPER_ADMIN',
            'ADMIN',
            'TRAFFIC_POLICE',
          ]));
    } catch (e) {
      setState(() => _errorMessage = 'offenseAdmin.error.permissionLoadFailed'
          .trParams({'error': formatOffenseAdminError(e)}));
    }
  }

  Future<void> _deleteOffense(int offenseId) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('offenseAdmin.delete.confirmTitle'.tr),
        content: Text('offenseAdmin.delete.confirmBody'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('offenseAdmin.action.delete'.tr,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        if (!await _validateJwtToken()) {
          Navigator.pushReplacementNamed(context, Routes.login);
          return;
        }
        await offenseApi.apiOffensesOffenseIdDelete(offenseId: offenseId);
        _showSnackBar('offenseAdmin.success.deleted'.tr);
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        _showSnackBar(
          'offenseAdmin.error.deleteFailed'
              .trParams({'error': formatOffenseAdminError(e)}),
          isError: true,
        );
      } finally {
        if (mounted) setState(() => _isLoading = false);
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

  Widget _buildDetailRow(String label, String value, ThemeData themeData) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('common.labelWithColon'.trParams({'label': label}),
              style: themeData.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: themeData.colorScheme.onSurface)),
          Expanded(
            child: Text(value,
                style: themeData.textTheme.bodyMedium
                    ?.copyWith(color: themeData.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData = controller.currentBodyTheme.value;
      if (_errorMessage.isNotEmpty) {
        return DashboardPageTemplate(
          theme: themeData,
          title: 'offense.detail.title'.tr,
          pageType: DashboardPageType.admin,
          bodyIsScrollable: true,
          padding: EdgeInsets.zero,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_errorMessage,
                    style: themeData.textTheme.titleMedium?.copyWith(
                        color: themeData.colorScheme.error,
                        fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center),
                if (shouldShowOffenseAdminReloginAction(_errorMessage))
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.pushReplacementNamed(context, Routes.login),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: themeData.colorScheme.primary,
                          foregroundColor: themeData.colorScheme.onPrimary),
                      child: Text('offenseAdmin.action.relogin'.tr),
                    ),
                  ),
              ],
            ),
          ),
        );
      }

      return DashboardPageTemplate(
        theme: themeData,
        title: 'offense.detail.title'.tr,
        pageType: DashboardPageType.admin,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        actions: [
          if (_isEditable) ...[
            DashboardPageBarAction(
              icon: Icons.delete,
              color: themeData.colorScheme.error,
              onPressed: () => _deleteOffense(widget.offense.offenseId!),
              tooltip: 'offenseAdmin.action.delete'.tr,
            ),
          ],
        ],
        body: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation(themeData.colorScheme.primary)))
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  elevation: 3,
                  color: themeData.colorScheme.surfaceContainer,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow(
                              'offense.detail.driverName'.tr,
                              widget.offense.driverName ?? 'common.unknown'.tr,
                              themeData),
                          _buildDetailRow(
                              'offense.detail.licensePlate'.tr,
                              widget.offense.licensePlate ??
                                  'common.unknown'.tr,
                              themeData),
                          _buildDetailRow(
                              'offense.detail.type'.tr,
                              widget.offense.offenseType ?? 'common.unknown'.tr,
                              themeData),
                          _buildDetailRow(
                              'offense.detail.code'.tr,
                              widget.offense.offenseCode ?? 'common.none'.tr,
                              themeData),
                          _buildDetailRow(
                              'offense.detail.location'.tr,
                              widget.offense.offenseLocation ??
                                  'common.none'.tr,
                              themeData),
                          _buildDetailRow(
                              'offense.detail.time'.tr,
                              formatOffenseDate(widget.offense.offenseTime),
                              themeData),
                          _buildDetailRow(
                              'offense.detail.points'.tr,
                              widget.offense.deductedPoints?.toString() ??
                                  'common.none'.tr,
                              themeData),
                          _buildDetailRow(
                              'offense.detail.amount'.tr,
                              widget.offense.fineAmount?.toString() ??
                                  'common.none'.tr,
                              themeData),
                          _buildDetailRow(
                              'offense.detail.processStatus'.tr,
                              localizeOffenseProcessStatus(
                                  widget.offense.processStatus),
                              themeData),
                          _buildDetailRow(
                              'offense.detail.processResult'.tr,
                              widget.offense.processResult ?? 'common.none'.tr,
                              themeData),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      );
    });
  }
}
