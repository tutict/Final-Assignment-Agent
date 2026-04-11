// user_offense_list_page.dart
import 'dart:developer' as developer;

import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/api/driver_information_controller_api.dart';
import 'package:final_assignment_front/features/api/offense_information_controller_api.dart';
import 'package:final_assignment_front/features/api/user_management_controller_api.dart';
import 'package:final_assignment_front/features/dashboard/controllers/user_dashboard_screen_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/features/model/offense_information.dart';
import 'package:final_assignment_front/i18n/offense_localizers.dart';
import 'package:final_assignment_front/utils/helpers/api_exception.dart';
import 'package:final_assignment_front/utils/helpers/role_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserOffenseListPage extends StatefulWidget {
  const UserOffenseListPage({super.key});

  @override
  State<UserOffenseListPage> createState() => _UserOffenseListPageState();
}

class _UserOffenseListPageState extends State<UserOffenseListPage> {
  final OffenseInformationControllerApi offenseApi =
      OffenseInformationControllerApi();
  final DriverInformationControllerApi driverApi =
      DriverInformationControllerApi();
  final UserManagementControllerApi userApi = UserManagementControllerApi();
  final List<OffenseInformation> _offenses = [];
  List<OffenseInformation> _filteredOffenses = [];
  final TextEditingController _searchController = TextEditingController();
  String _driverName = '';
  int _currentPage = 1;
  final int _pageSize = 20;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isUser = false;
  String _errorMessage = '';
  DateTime? _startTime;
  DateTime? _endTime;
  late ScrollController _scrollController;

  final UserDashboardController? dashboardController =
      Get.isRegistered<UserDashboardController>()
          ? Get.find<UserDashboardController>()
          : null;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _initialize();
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
      setState(() => _errorMessage = 'offense.error.unauthorized'.tr);
      return false;
    }
    try {
      final decodedToken = JwtDecoder.decode(jwtToken);
      _isUser = hasAnyRole(decodedToken['roles'], const ['USER']);
      if (!_isUser) {
        setState(() => _errorMessage = 'offense.error.userOnly'.tr);
        return false;
      }
      if (JwtDecoder.isExpired(jwtToken)) {
        setState(() => _errorMessage = 'offense.error.loginExpired'.tr);
        return false;
      }
      await userApi.initializeWithJwt();
      await driverApi.initializeWithJwt();
      _driverName = prefs.getString('driverName') ?? '';
      if (_driverName.isEmpty) {
        _driverName = await _fetchDriverName() ?? '';
      }
      if (_driverName.isNotEmpty) {
        await prefs.setString('driverName', _driverName);
        await prefs.setString('displayName', _driverName);
        developer.log('Stored driverName: $_driverName');
      }
      return true;
    } catch (e) {
      developer.log('JWT validation error: $e');
      setState(() => _errorMessage = 'offense.error.invalidLogin'.tr);
      return false;
    }
  }

  Future<String?> _fetchDriverName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = await userApi.apiUsersMeGet();
      final driverInfo = await driverApi.apiDriversMeGet();
      final driverName = driverInfo?.name ??
          prefs.getString('displayName') ??
          user?.realName ??
          user?.username ??
          prefs.getString('userName') ??
          '';
      developer.log('Driver name from API: $driverName');
      return driverName;
    } catch (e) {
      developer.log('Error fetching driver name: $e');
      return null;
    }
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      if (!await _validateJwtToken()) {
        Get.offAllNamed(Routes.login);
        return;
      }
      await offenseApi.initializeWithJwt();
      await _loadOffenses(reset: true);
    } catch (e) {
      developer.log('Initialization error: $e');
      setState(() => _errorMessage = 'offense.error.initializeFailed'.trParams({
            'error': formatUserOffenseErrorDetail(e),
          }));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadOffenses({bool reset = false}) async {
    if (!_hasMore) return;

    if (reset) {
      _currentPage = 1;
      _hasMore = true;
      _offenses.clear();
      _filteredOffenses.clear();
      _searchController.clear();
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
      final offenses = await offenseApi.apiOffensesMeGet(
        page: _currentPage,
        size: _pageSize,
      );

      setState(() {
        _offenses.addAll(offenses);
        _hasMore = offenses.length == _pageSize;
        _applyFilters();
        if (_filteredOffenses.isEmpty) {
          _errorMessage = _startTime != null && _endTime != null
              ? 'offense.error.noRecordsInRange'.tr
              : _searchController.text.isNotEmpty
                  ? 'offense.error.noRecordsBySearch'.tr
                  : 'offense.error.empty'.tr;
        }
        _currentPage++;
      });
      developer.log('Loaded offenses: ${_offenses.length}');
    } catch (e) {
      developer.log('Error fetching offenses: $e',
          stackTrace: StackTrace.current);
      setState(() {
        if (e is ApiException && e.code == 204) {
          _offenses.clear();
          _filteredOffenses.clear();
          _errorMessage = 'offense.error.notFound'.tr;
          _hasMore = false;
        } else if (e is ApiException && e.code == 403) {
          _errorMessage = 'offense.error.unauthorized'.tr;
          Get.offAllNamed(Routes.login);
        } else {
          _errorMessage = 'offense.error.loadFailed'
              .trParams({'error': formatUserOffenseError(e)});
        }
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredOffenses.clear();
      _filteredOffenses = _offenses.where((offense) {
        final offenseTime = offense.offenseTime;
        bool matchesDateRange = true;
        if (_startTime != null && _endTime != null && offenseTime != null) {
          matchesDateRange = offenseTime.isAfter(_startTime!) &&
              offenseTime.isBefore(_endTime!.add(const Duration(days: 1)));
        } else if (_startTime != null &&
            _endTime != null &&
            offenseTime == null) {
          matchesDateRange = false;
        }
        bool matchesSearch = true;
        if (_searchController.text.isNotEmpty) {
          final searchText = _searchController.text.toLowerCase();
          matchesSearch =
              (offense.offenseType?.toLowerCase().contains(searchText) ??
                      false) ||
                  (offense.offenseCode?.toLowerCase().contains(searchText) ??
                      false);
        }
        return matchesDateRange && matchesSearch;
      }).toList();

      if (_filteredOffenses.isEmpty && _offenses.isNotEmpty) {
        _errorMessage = _startTime != null && _endTime != null
            ? 'offense.error.noRecordsInRange'.tr
            : _searchController.text.isNotEmpty
                ? 'offense.error.noRecordsBySearch'.tr
                : 'offense.error.empty'.tr;
      } else {
        _errorMessage = _filteredOffenses.isEmpty && _offenses.isEmpty
            ? 'offense.error.empty'.tr
            : '';
      }
    });
  }

  Future<List<String>> _fetchAutocompleteSuggestions(String prefix) async {
    try {
      final offenses = _offenses.isNotEmpty
          ? _offenses
          : await offenseApi.apiOffensesMeGet(
              page: 1,
              size: 50,
            );
      final suggestions = <String>{};
      for (var offense in offenses) {
        if (offense.offenseType != null &&
            offense.offenseType!.toLowerCase().contains(prefix.toLowerCase())) {
          suggestions.add(offense.offenseType!);
        }
        if (offense.offenseCode != null &&
            offense.offenseCode!.toLowerCase().contains(prefix.toLowerCase())) {
          suggestions.add(offense.offenseCode!);
        }
      }
      return suggestions.toList();
    } catch (e) {
      developer.log('Failed to fetch autocomplete suggestions: $e');
      return [];
    }
  }

  Future<void> _loadMoreOffenses() async {
    if (!_isLoading && _hasMore) {
      await _loadOffenses();
    }
  }

  Future<void> _refreshOffenses() async {
    setState(() {
      _offenses.clear();
      _filteredOffenses.clear();
      _currentPage = 1;
      _hasMore = true;
      _isLoading = true;
      _startTime = null;
      _endTime = null;
      _searchController.clear();
    });
    await _loadOffenses(reset: true);
  }

  void _goToDetailPage(OffenseInformation offense) {
    Get.to(() => UserOffenseDetailPage(offense: offense));
  }

  Widget _buildSearchBar(ThemeData themeData) {
    return Card(
      elevation: 2,
      color: themeData.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
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
                      _searchController.text = selection;
                      _applyFilters();
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) {
                      _searchController.text = controller.text;
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        style:
                            TextStyle(color: themeData.colorScheme.onSurface),
                        decoration: InputDecoration(
                          hintText: 'offense.search.hint'.tr,
                          hintStyle: TextStyle(
                              color: themeData.colorScheme.onSurface
                                  .withValues(alpha: 0.6)),
                          prefixIcon: Icon(Icons.search,
                              color: themeData.colorScheme.primary),
                          suffixIcon: controller.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear,
                                      color: themeData
                                          .colorScheme.onSurfaceVariant),
                                  onPressed: () {
                                    controller.clear();
                                    _searchController.clear();
                                    _applyFilters();
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0)),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                                color: themeData.colorScheme.outline
                                    .withValues(alpha: 0.3)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                                color: themeData.colorScheme.primary,
                                width: 1.5),
                          ),
                          filled: true,
                          fillColor:
                              themeData.colorScheme.surfaceContainerLowest,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 12.0, horizontal: 16.0),
                        ),
                        onChanged: (value) {
                          if (value.isEmpty) {
                            _applyFilters();
                          }
                        },
                        onSubmitted: (value) => _applyFilters(),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildTimeRangeFilter(themeData),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRangeFilter(ThemeData themeData) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _startTime != null && _endTime != null
                ? 'offense.filter.rangeLabel'.trParams({
                    'start': formatOffenseDate(
                      _startTime,
                      emptyKey: 'common.notFilled',
                    ),
                    'end': formatOffenseDate(
                      _endTime,
                      emptyKey: 'common.notFilled',
                    ),
                  })
                : 'offense.filter.select'.tr,
            style: TextStyle(
              color: _startTime != null && _endTime != null
                  ? themeData.colorScheme.onSurface
                  : themeData.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.date_range, color: themeData.colorScheme.primary),
          tooltip: 'offense.filter.tooltip'.tr,
          onPressed: () async {
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2000),
              lastDate: DateTime.now(),
              locale: Get.locale ?? const Locale('en', 'US'),
              helpText: 'offense.filter.select'.tr,
              cancelText: 'common.cancel'.tr,
              confirmText: 'common.confirm'.tr,
              fieldStartHintText: 'offense.filter.startDate'.tr,
              fieldEndHintText: 'offense.filter.endDate'.tr,
              builder: (context, child) => Theme(
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
              ),
            );
            if (range != null) {
              setState(() {
                _startTime = range.start;
                _endTime = range.end;
              });
              _applyFilters();
            }
          },
        ),
        if (_startTime != null && _endTime != null)
          IconButton(
            icon: Icon(Icons.clear,
                color: themeData.colorScheme.onSurfaceVariant),
            tooltip: 'offense.filter.clear'.tr,
            onPressed: () {
              setState(() {
                _startTime = null;
                _endTime = null;
              });
              _applyFilters();
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData = dashboardController != null
          ? dashboardController!.currentBodyTheme.value
          : Theme.of(context);
      if (!_isUser) {
        return DashboardPageTemplate(
          theme: themeData,
          title: 'offense.page.title'.tr,
          pageType: DashboardPageType.custom,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _errorMessage,
                  style: themeData.textTheme.titleMedium?.copyWith(
                    color: themeData.colorScheme.error,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: ElevatedButton(
                    onPressed: () => Get.offAllNamed(Routes.login),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeData.colorScheme.primary,
                      foregroundColor: themeData.colorScheme.onPrimary,
                    ),
                    child: Text('offense.action.relogin'.tr),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return DashboardPageTemplate(
        theme: themeData,
        title: 'offense.page.title'.tr,
        pageType: DashboardPageType.user,
        onThemeToggle: dashboardController?.toggleBodyTheme,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        body: RefreshIndicator(
          onRefresh: _refreshOffenses,
          color: themeData.colorScheme.primary,
          backgroundColor: themeData.colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildSearchBar(themeData),
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
                        : _errorMessage.isNotEmpty && _filteredOffenses.isEmpty
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
                                    if (shouldShowUserOffenseReloginAction(
                                        _errorMessage))
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 16.0),
                                        child: ElevatedButton(
                                          onPressed: () =>
                                              Get.offAllNamed(Routes.login),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                themeData.colorScheme.primary,
                                            foregroundColor:
                                                themeData.colorScheme.onPrimary,
                                          ),
                                          child:
                                              Text('offense.action.relogin'.tr),
                                        ),
                                      ),
                                  ],
                                ),
                              )
                            : CupertinoScrollbar(
                                controller: _scrollController,
                                thumbVisibility: true,
                                child: ListView.builder(
                                  controller: _scrollController,
                                  itemCount: _filteredOffenses.length +
                                      (_hasMore ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index == _filteredOffenses.length &&
                                        _hasMore) {
                                      return const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Center(
                                            child: CircularProgressIndicator()),
                                      );
                                    }
                                    final offense = _filteredOffenses[index];
                                    return Card(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 8.0),
                                      elevation: 3,
                                      color: themeData
                                          .colorScheme.surfaceContainer,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16.0)),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 16.0,
                                                vertical: 12.0),
                                        title: Text(
                                          'offense.card.type'.trParams({
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
                                              'offense.card.licensePlate'
                                                  .trParams({
                                                'value': offense.licensePlate ??
                                                    'common.none'.tr,
                                              }),
                                              style: themeData
                                                  .textTheme.bodyMedium
                                                  ?.copyWith(
                                                color: themeData.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                            Text(
                                              'offense.card.points'.trParams({
                                                'value': formatOffensePoints(
                                                    offense.deductedPoints),
                                              }),
                                              style: themeData
                                                  .textTheme.bodyMedium
                                                  ?.copyWith(
                                                color: themeData.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                            Text(
                                              'offense.card.time'.trParams({
                                                'value': formatOffenseDate(
                                                  offense.offenseTime,
                                                  emptyKey: 'common.notFilled',
                                                ),
                                              }),
                                              style: themeData
                                                  .textTheme.bodyMedium
                                                  ?.copyWith(
                                                color: themeData.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: Icon(
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
                )
              ],
            ),
          ),
        ),
      );
    });
  }
}

class UserOffenseDetailPage extends StatelessWidget {
  final OffenseInformation offense;
  final UserDashboardController? dashboardController;

  UserOffenseDetailPage({super.key, required this.offense})
      : dashboardController = Get.isRegistered<UserDashboardController>()
            ? Get.find<UserDashboardController>()
            : null;

  Widget _buildDetailRow(String label, String value, ThemeData themeData) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'common.labelWithColon'.trParams({'label': label}),
            style: themeData.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: themeData.colorScheme.onSurface,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: themeData.textTheme.bodyMedium?.copyWith(
                color: themeData.colorScheme.onSurfaceVariant,
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
      final themeData = dashboardController != null
          ? dashboardController!.currentBodyTheme.value
          : Theme.of(context);
      return DashboardPageTemplate(
        theme: themeData,
        title: 'offense.detail.title'.tr,
        pageType: DashboardPageType.user,
        onThemeToggle: dashboardController?.toggleBodyTheme,
        body: Card(
          elevation: 3,
          color: themeData.colorScheme.surfaceContainer,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow(
                    'offense.detail.id'.tr,
                    offense.offenseId?.toString() ?? 'common.notFilled'.tr,
                    themeData),
                _buildDetailRow('offense.detail.licensePlate'.tr,
                    offense.licensePlate ?? 'common.none'.tr, themeData),
                _buildDetailRow('offense.detail.driverName'.tr,
                    offense.driverName ?? 'common.none'.tr, themeData),
                _buildDetailRow('offense.detail.type'.tr,
                    offense.offenseType ?? 'common.unknown'.tr, themeData),
                _buildDetailRow('offense.detail.code'.tr,
                    offense.offenseCode ?? 'common.none'.tr, themeData),
                _buildDetailRow('offense.detail.points'.tr,
                    formatOffensePoints(offense.deductedPoints), themeData),
                _buildDetailRow('offense.detail.amount'.tr,
                    formatOffenseAmount(offense.fineAmount), themeData),
                _buildDetailRow(
                    'offense.detail.time'.tr,
                    formatOffenseDate(
                      offense.offenseTime,
                      emptyKey: 'common.notFilled',
                    ),
                    themeData),
                _buildDetailRow(
                    'offense.detail.location'.tr,
                    offense.offenseLocation ?? 'common.notFilled'.tr,
                    themeData),
                _buildDetailRow(
                    'offense.detail.processStatus'.tr,
                    formatUserOffenseProcessStatus(offense.processStatus),
                    themeData),
                _buildDetailRow('offense.detail.processResult'.tr,
                    offense.processResult ?? 'common.none'.tr, themeData),
              ],
            ),
          ),
        ),
      );
    });
  }
}
