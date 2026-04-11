// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/api/driver_information_controller_api.dart';
import 'package:final_assignment_front/features/api/vehicle_information_controller_api.dart';
import 'package:final_assignment_front/features/dashboard/controllers/admin_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/features/model/driver_information.dart';
import 'package:final_assignment_front/features/model/user_management.dart';
import 'package:final_assignment_front/features/model/vehicle_information.dart';
import 'package:final_assignment_front/i18n/status_localizers.dart';
import 'package:final_assignment_front/i18n/vehicle_field_localizers.dart';
import 'package:final_assignment_front/utils/helpers/api_exception.dart';
import 'package:final_assignment_front/utils/helpers/role_utils.dart';
import 'package:final_assignment_front/utils/services/session_helper.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:final_assignment_front/utils/services/auth_token_store.dart';

String generateIdempotencyKey() {
  return DateTime.now().millisecondsSinceEpoch.toString();
}

const String _vehicleDefaultStatus = 'Active';

String buildVehicleLicensePlate(String plateSuffix) {
  return '$kVehiclePlatePrefix${plateSuffix.trim()}';
}

Future<bool> ensureVehicleLicensePlateAvailable({
  required VehicleInformationControllerApi vehicleApi,
  required String licensePlate,
  String? currentLicensePlate,
}) async {
  if (licensePlate == currentLicensePlate) {
    return true;
  }

  return !(await vehicleApi.apiVehiclesExistsLicensePlateGet(
    licensePlate: licensePlate,
  ));
}

class VehicleList extends StatefulWidget {
  const VehicleList({super.key});

  @override
  State<VehicleList> createState() => _VehicleListState();
}

class _VehicleListState extends State<VehicleList> {
  static const int _pageSize = 20;

  final DashboardController controller = Get.find<DashboardController>();
  final VehicleInformationControllerApi vehicleApi =
      VehicleInformationControllerApi();
  final DriverInformationControllerApi driverApi =
      DriverInformationControllerApi();
  final SessionHelper _sessionHelper = SessionHelper();
  final TextEditingController _searchController = TextEditingController();
  TextEditingController? _searchFieldController;
  final List<VehicleInformation> _vehicleList = [];
  List<VehicleInformation> _filteredVehicleList = [];
  String _searchType = kVehicleSearchTypeLicensePlate;
  String _activeQuery = '';
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  String _errorMessage = '';
  bool _isAdmin = false;
  DateTime? _startDate;
  DateTime? _endDate;
  Timer? _searchDebounce;

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

  void _setStateSafely(VoidCallback update) {
    if (!mounted) return;
    setState(update);
  }

  void _redirectToLogin() {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, Routes.login);
  }

  List<VehicleInformation> _buildFilteredVehicleList(
    Iterable<VehicleInformation> vehicles,
  ) {
    final searchQuery = _activeQuery.toLowerCase();
    return vehicles.where((vehicle) {
      final licensePlate = (vehicle.licensePlate ?? '').toLowerCase();
      final vehicleType = (vehicle.vehicleType ?? '').toLowerCase();
      final registrationDate = vehicle.firstRegistrationDate;

      var matchesQuery = true;
      if (searchQuery.isNotEmpty) {
        if (_searchType == kVehicleSearchTypeLicensePlate) {
          matchesQuery = licensePlate.contains(searchQuery);
        } else if (_searchType == kVehicleSearchTypeVehicleType) {
          matchesQuery = vehicleType.contains(searchQuery);
        }
      }

      var matchesDateRange = true;
      if (_startDate != null && _endDate != null && registrationDate != null) {
        matchesDateRange = registrationDate.isAfter(_startDate!) &&
            registrationDate.isBefore(_endDate!.add(const Duration(days: 1)));
      } else if (_startDate != null &&
          _endDate != null &&
          registrationDate == null) {
        matchesDateRange = false;
      }

      return matchesQuery && matchesDateRange;
    }).toList();
  }

  String _resolveVehicleListErrorMessage(
    List<VehicleInformation> filteredVehicles,
  ) {
    if (filteredVehicles.isNotEmpty) {
      return '';
    }
    if (_hasMore && _hasClientSideFiltering) {
      return '';
    }
    return _hasActiveFilters ? 'vehicle.empty.filtered'.tr : 'vehicle.empty'.tr;
  }

  Future<bool> _validateJwtToken() async {
    String? jwtToken = (await AuthTokenStore.instance.getJwtToken());
    debugPrint('Retrieved JWT: $jwtToken');
    if (jwtToken == null || jwtToken.isEmpty) {
      debugPrint('JWT token not found or empty');
      _setStateSafely(() => _errorMessage = 'vehicle.error.unauthorized'.tr);
      return false;
    }
    try {
      final decodedToken = JwtDecoder.decode(jwtToken);
      debugPrint('Decoded JWT: $decodedToken');
      if (JwtDecoder.isExpired(jwtToken)) {
        debugPrint('JWT token is expired: ${decodedToken['exp']}');
        jwtToken = await _refreshJwtToken();
        if (!mounted) return false;
        if (jwtToken == null) {
          _setStateSafely(() => _errorMessage = 'vehicle.error.expired'.tr);
          return false;
        }
        await AuthTokenStore.instance.setJwtToken(jwtToken);
        final newDecodedToken = JwtDecoder.decode(jwtToken);
        debugPrint('New JWT decoded: $newDecodedToken');
        if (JwtDecoder.isExpired(jwtToken)) {
          _setStateSafely(
              () => _errorMessage = 'vehicle.error.refreshedExpired'.tr);
          return false;
        }
        await vehicleApi.initializeWithJwt();
        if (!mounted) return false;
      }
      debugPrint('JWT token is valid. Subject: ${decodedToken['sub']}');
      return true;
    } catch (e) {
      debugPrint('JWT decode error: $e');
      _setStateSafely(() => _errorMessage = 'vehicle.error.invalidLogin'.tr);
      return false;
    }
  }

  Future<String?> _refreshJwtToken() async {
    final newJwt = await _sessionHelper.refreshJwtToken();
    if (newJwt != null) {
      debugPrint('Refreshed JWT successfully');
    } else {
      debugPrint('Failed to refresh JWT');
    }
    return newJwt;
  }

  Future<void> _initialize() async {
    _setStateSafely(() => _isLoading = true);
    try {
      final isValid = await _validateJwtToken();
      if (!mounted) return;
      if (!isValid) {
        _redirectToLogin();
        return;
      }
      await vehicleApi.initializeWithJwt();
      if (!mounted) return;
      await _checkUserRole();
      if (!mounted) return;
      await _fetchVehicles(reset: true);
    } catch (e) {
      _setStateSafely(() => _errorMessage = 'vehicle.error.initializeFailed'
          .trParams({'error': formatVehicleError(e)}));
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
      debugPrint('Resolved user roles: $roles');
      _setStateSafely(() => _isAdmin = hasAnyRole(roles, const [
            'SUPER_ADMIN',
            'ADMIN',
            'TRAFFIC_POLICE',
          ]));
    } catch (e) {
      debugPrint('Error checking role: $e');
      _setStateSafely(() => _errorMessage = 'vehicle.error.roleCheckFailed'
          .trParams({'error': formatVehicleError(e)}));
    }
  }

  Future<void> _fetchVehicles({bool reset = false, String? query}) async {
    if (reset) {
      _currentPage = 1;
      _hasMore = true;
      _activeQuery = (query ?? _searchController.text).trim();
      _vehicleList.clear();
      _filteredVehicleList.clear();
      _errorMessage = '';
    }
    if (!_hasMore) return;

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
      var shouldAutoLoadMore = false;
      do {
        final vehicles = await _loadVehiclePage(
          page: _currentPage,
          query: _activeQuery,
        );
        if (!mounted) return;
        final updatedVehicles = <VehicleInformation>[
          ..._vehicleList,
          ...vehicles,
        ];
        final hasMore = vehicles.length == _pageSize;
        final filteredVehicles = _buildFilteredVehicleList(updatedVehicles);
        shouldAutoLoadMore =
            hasMore && filteredVehicles.isEmpty && _hasClientSideFiltering;

        _setStateSafely(() {
          _vehicleList
            ..clear()
            ..addAll(updatedVehicles);
          _filteredVehicleList = filteredVehicles;
          _hasMore = hasMore;
          _currentPage++;
          _errorMessage = _resolveVehicleListErrorMessage(filteredVehicles);
        });
      } while (shouldAutoLoadMore && mounted);
    } catch (e) {
      if (e is ApiException && e.code == 403) {
        _setStateSafely(() => _errorMessage = 'vehicle.error.unauthorized'.tr);
        _redirectToLogin();
      } else if (e is ApiException && e.code == 404) {
        _setStateSafely(() {
          _vehicleList.clear();
          _filteredVehicleList.clear();
          _errorMessage = 'vehicle.error.notFound'.tr;
          _hasMore = false;
        });
      } else {
        _setStateSafely(() {
          _errorMessage = 'vehicle.error.loadFailed'
              .trParams({'error': formatVehicleError(e)});
        });
      }
    } finally {
      _setStateSafely(() => _isLoading = false);
    }
  }

  Future<List<VehicleInformation>> _loadVehiclePage({
    required int page,
    required String query,
  }) {
    if (query.isEmpty) {
      return vehicleApi.apiVehiclesGet(page: page, size: _pageSize);
    }

    return vehicleApi.apiVehiclesSearchGeneralGet(
      keywords: query,
      page: page,
      size: _pageSize,
    );
  }

  Future<List<String>> _fetchAutocompleteSuggestions(String prefix) async {
    try {
      final isValid = await _validateJwtToken();
      if (!mounted) return const [];
      if (!isValid) {
        _redirectToLogin();
        return [];
      }
      if (_searchType == kVehicleSearchTypeLicensePlate) {
        final suggestions = await vehicleApi.apiVehiclesSearchLicenseGlobalGet(
          prefix: prefix,
        );
        if (!mounted) return const [];
        return suggestions
            .where((s) => s.toLowerCase().contains(prefix.toLowerCase()))
            .toList();
      } else {
        final suggestions =
            await vehicleApi.apiVehiclesAutocompleteTypesGlobalGet(
          prefix: prefix,
        );
        if (!mounted) return const [];
        return suggestions
            .where((s) => s.toLowerCase().contains(prefix.toLowerCase()))
            .toList();
      }
    } catch (e) {
      _setStateSafely(() => _errorMessage = 'vehicle.error.suggestionFailed'
          .trParams({'error': formatVehicleError(e)}));
      return [];
    }
  }

  bool get _hasDateFilter => _startDate != null && _endDate != null;

  bool get _hasActiveFilters => _activeQuery.isNotEmpty || _hasDateFilter;

  bool get _hasClientSideFiltering => _hasDateFilter || _activeQuery.isNotEmpty;

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
      _refreshVehicleList(query: value);
    });
  }

  // ignore: unused_element
  Future<void> _searchVehicles() async {
    await _refreshVehicleList(query: _searchController.text.trim());
  }

  Future<void> _refreshVehicleList({
    String? query,
    bool clearFilters = false,
  }) async {
    _searchDebounce?.cancel();
    final effectiveQuery =
        clearFilters ? '' : (query ?? _searchController.text).trim();
    _setStateSafely(() {
      _vehicleList.clear();
      _filteredVehicleList.clear();
      _currentPage = 1;
      _hasMore = true;
      _isLoading = true;
      _activeQuery = effectiveQuery;
      _errorMessage = '';
      if (clearFilters) {
        _setSearchText('');
        _startDate = null;
        _endDate = null;
        _searchType = kVehicleSearchTypeLicensePlate;
      } else {
        _setSearchText(effectiveQuery);
      }
    });
    await _fetchVehicles(reset: true, query: effectiveQuery);
  }

  Future<void> _loadMoreVehicles() async {
    if (!_isLoading && _hasMore) {
      await _fetchVehicles();
    }
  }

  void _goToDetailPage(VehicleInformation vehicle) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VehicleDetailPage(vehicle: vehicle),
      ),
    );
  }

  void _createVehicle() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddVehiclePage()),
    ).then((value) {
      if (value == true) {
        _refreshVehicleList();
      }
    });
  }

  void _editVehicle(VehicleInformation vehicle) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditVehiclePage(vehicle: vehicle),
      ),
    ).then((value) {
      if (value == true) {
        _refreshVehicleList();
      }
    });
  }

  Future<void> _deleteVehicle(int vehicleId) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('vehicle.dialog.deleteTitle'.tr),
        content: Text(
          'vehicle.dialog.deleteConfirm'
              .trParams({'action': 'vehicle.action.delete'.tr}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('vehicle.action.delete'.tr,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirm == true) {
      _setStateSafely(() => _isLoading = true);
      try {
        final isValid = await _validateJwtToken();
        if (!mounted) return;
        if (!isValid) {
          _redirectToLogin();
          return;
        }
        await vehicleApi.apiVehiclesVehicleIdDelete(vehicleId: vehicleId);
        if (!mounted) return;
        await _refreshVehicleList();
      } catch (e) {
        _setStateSafely(() {
          _errorMessage = 'vehicle.error.deleteFailed'
              .trParams({'error': formatVehicleError(e)});
        });
      } finally {
        _setStateSafely(() => _isLoading = false);
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
                    _refreshVehicleList(query: selection);
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) {
                    _searchFieldController = controller;
                    if (controller.text != _searchController.text) {
                      controller.value = _searchController.value;
                    }
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      style: TextStyle(color: themeData.colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: _searchType == kVehicleSearchTypeLicensePlate
                            ? 'vehicle.search.plateHint'.tr
                            : 'vehicle.search.typeHint'.tr,
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
                                  _refreshVehicleList(query: '');
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
                        _scheduleSearchRefresh(value);
                      },
                      onSubmitted: (value) {
                        _setSearchText(value);
                        _refreshVehicleList(query: value);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _searchType,
                onChanged: (String? newValue) {
                  _setStateSafely(() {
                    _searchType = newValue!;
                    _startDate = null;
                    _endDate = null;
                  });
                  _setSearchText('');
                  _refreshVehicleList(query: '');
                },
                items: <String>[
                  kVehicleSearchTypeLicensePlate,
                  kVehicleSearchTypeVehicleType,
                ].map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(
                      vehicleSearchTypeLabel(value),
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
                      ? 'vehicle.filter.dateRangeLabel'.trParams({
                          'start': formatVehicleDate(_startDate),
                          'end': formatVehicleDate(_endDate),
                        })
                      : 'vehicle.filter.selectDateRange'.tr,
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
                tooltip: 'vehicle.filter.tooltip'.tr,
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                    locale: Get.locale ?? const Locale('en', 'US'),
                    helpText: 'vehicle.filter.selectDateRange'.tr,
                    cancelText: 'common.cancel'.tr,
                    confirmText: 'common.confirm'.tr,
                    fieldStartHintText: 'vehicle.filter.startDate'.tr,
                    fieldEndHintText: 'vehicle.filter.endDate'.tr,
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
                  if (!mounted) return;
                  if (range != null) {
                    _setStateSafely(() {
                      _startDate = range.start;
                      _endDate = range.end;
                    });
                    _refreshVehicleList(query: _searchController.text);
                  }
                },
              ),
              if (_startDate != null && _endDate != null)
                IconButton(
                  icon: Icon(Icons.clear,
                      color: themeData.colorScheme.onSurfaceVariant),
                  tooltip: 'vehicle.filter.clearDateRange'.tr,
                  onPressed: () {
                    _setStateSafely(() {
                      _startDate = null;
                      _endDate = null;
                    });
                    _refreshVehicleList(query: _searchController.text);
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
        title: 'vehicle.page.title'.tr,
        pageType: DashboardPageType.admin,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        actions: [
          if (_isAdmin) ...[
            DashboardPageBarAction(
              icon: Icons.add,
              onPressed: _createVehicle,
              tooltip: 'vehicle.action.add'.tr,
            ),
            DashboardPageBarAction(
              icon: Icons.refresh,
              onPressed: () => _refreshVehicleList(),
              tooltip: 'vehicle.action.refresh'.tr,
            ),
          ],
        ],
        onThemeToggle: controller.toggleBodyTheme,
        body: RefreshIndicator(
          onRefresh: () => _refreshVehicleList(),
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
                        _loadMoreVehicles();
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
                                _filteredVehicleList.isEmpty
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
                                    if (shouldShowVehicleAdminReloginAction(
                                        _errorMessage))
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 16.0),
                                        child: ElevatedButton(
                                          onPressed: _redirectToLogin,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                themeData.colorScheme.primary,
                                            foregroundColor:
                                                themeData.colorScheme.onPrimary,
                                          ),
                                          child:
                                              Text('vehicle.action.relogin'.tr),
                                        ),
                                      ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: _filteredVehicleList.length +
                                    (_hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _filteredVehicleList.length &&
                                      _hasMore) {
                                    return const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  final vehicle = _filteredVehicleList[index];
                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                        vertical: 8.0),
                                    elevation: 3,
                                    color:
                                        themeData.colorScheme.surfaceContainer,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16.0),
                                    ),
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16.0, vertical: 12.0),
                                      title: Text(
                                        'vehicle.card.plate'.trParams({
                                          'value': vehicle.licensePlate ??
                                              'vehicle.value.noPlate'.tr
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
                                            'vehicle.card.type'.trParams({
                                              'value': vehicle.vehicleType ??
                                                  'vehicle.value.noType'.tr
                                            }),
                                            style: themeData
                                                .textTheme.bodyMedium
                                                ?.copyWith(
                                              color: themeData
                                                  .colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          Text(
                                            'vehicle.card.owner'.trParams({
                                              'value': vehicle.ownerName ??
                                                  'vehicle.value.noOwner'.tr
                                            }),
                                            style: themeData
                                                .textTheme.bodyMedium
                                                ?.copyWith(
                                              color: themeData
                                                  .colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          Text(
                                            'vehicle.card.status'.trParams({
                                              'value': localizeVehicleStatus(
                                                vehicle.currentStatus,
                                              )
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
                                      trailing: _isAdmin
                                          ? Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.edit,
                                                      size: 18),
                                                  color: themeData
                                                      .colorScheme.primary,
                                                  onPressed: () =>
                                                      _editVehicle(vehicle),
                                                  tooltip:
                                                      'vehicle.action.edit'.tr,
                                                ),
                                                IconButton(
                                                  icon: Icon(
                                                    Icons.delete,
                                                    size: 18,
                                                    color: themeData
                                                        .colorScheme.error,
                                                  ),
                                                  onPressed: () {
                                                    final vehicleId =
                                                        vehicle.vehicleId;
                                                    if (vehicleId == null) {
                                                      _showSnackBar(
                                                          'vehicle.error.idMissingDelete'
                                                              .tr,
                                                          isError: true);
                                                      return;
                                                    }
                                                    _deleteVehicle(vehicleId);
                                                  },
                                                  tooltip:
                                                      'vehicle.action.delete'
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
                                      onTap: () => _goToDetailPage(vehicle),
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
}

class AddVehiclePage extends StatefulWidget {
  final VoidCallback? onVehicleAdded;

  const AddVehiclePage({super.key, this.onVehicleAdded});

  @override
  State<AddVehiclePage> createState() => _AddVehiclePageState();
}

class _AddVehiclePageState extends State<AddVehiclePage> {
  final VehicleInformationControllerApi vehicleApi =
      VehicleInformationControllerApi();
  final DriverInformationControllerApi driverApi =
      DriverInformationControllerApi();
  final _formKey = GlobalKey<FormState>();
  final _licensePlateController = TextEditingController();
  final _vehicleTypeController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _idCardNumberController = TextEditingController();
  final _contactNumberController = TextEditingController();
  final _engineNumberController = TextEditingController();
  final _frameNumberController = TextEditingController();
  final _vehicleColorController = TextEditingController();
  final _firstRegistrationDateController = TextEditingController();
  final _currentStatusController = TextEditingController();
  DateTime? _selectedFirstRegistrationDate;
  bool _isLoading = false;
  final DashboardController controller = Get.find<DashboardController>();

  void _setStateSafely(VoidCallback update) {
    if (!mounted) return;
    setState(update);
  }

  void _redirectToLogin() {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, Routes.login);
  }

  Future<bool> _validateJwtToken() async {
    final jwtToken = (await AuthTokenStore.instance.getJwtToken());
    if (jwtToken == null || jwtToken.isEmpty) {
      _showSnackBar('vehicle.error.unauthorized'.tr, isError: true);
      return false;
    }
    try {
      if (JwtDecoder.isExpired(jwtToken)) {
        _showSnackBar('vehicle.error.expired'.tr, isError: true);
        return false;
      }
      return true;
    } catch (e) {
      _showSnackBar('vehicle.error.invalidLogin'.tr, isError: true);
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _setStateSafely(() => _isLoading = true);
    try {
      final isValid = await _validateJwtToken();
      if (!mounted) return;
      if (!isValid) {
        _redirectToLogin();
        return;
      }
      final jwtToken = (await AuthTokenStore.instance.getJwtToken());
      if (!mounted) return;
      if (jwtToken == null) throw Exception('vehicle.error.jwtMissing'.tr);
      final decodedToken = JwtDecoder.decode(jwtToken);
      final username = decodedToken['sub'] ?? '';
      if (username.isEmpty) {
        throw Exception('vehicle.error.usernameMissingInJwt'.tr);
      }
      await vehicleApi.initializeWithJwt();
      await driverApi.initializeWithJwt();
      if (!mounted) return;
      _setStateSafely(() {
        _contactNumberController.text = '';
      });
    } catch (e) {
      _showSnackBar(
        'vehicle.error.initializeFailed'
            .trParams({'error': formatVehicleError(e)}),
        isError: true,
      );
    } finally {
      _setStateSafely(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _licensePlateController.dispose();
    _vehicleTypeController.dispose();
    _ownerNameController.dispose();
    _idCardNumberController.dispose();
    _contactNumberController.dispose();
    _engineNumberController.dispose();
    _frameNumberController.dispose();
    _vehicleColorController.dispose();
    _firstRegistrationDateController.dispose();
    _currentStatusController.dispose();
    super.dispose();
  }

  void _setFirstRegistrationDate(DateTime? value) {
    _selectedFirstRegistrationDate =
        value == null ? null : DateUtils.dateOnly(value);
    _firstRegistrationDateController.text =
        _selectedFirstRegistrationDate == null
            ? ''
            : formatVehicleDate(_selectedFirstRegistrationDate);
  }

  Future<void> _submitVehicle() async {
    if (!_formKey.currentState!.validate()) return;
    final licensePlate = buildVehicleLicensePlate(_licensePlateController.text);
    final isValid = await _validateJwtToken();
    if (!mounted) return;
    if (!isValid) {
      _redirectToLogin();
      return;
    }
    if (!await ensureVehicleLicensePlateAvailable(
      vehicleApi: vehicleApi,
      licensePlate: licensePlate,
    )) {
      if (!mounted) return;
      _showSnackBar('vehicle.error.plateExists'.tr, isError: true);
      return;
    }
    final idCardNumber = _idCardNumberController.text.trim();
    _setStateSafely(() => _isLoading = true);
    try {
      final vehiclePayload = VehicleInformation(
        licensePlate: licensePlate,
        vehicleType: _vehicleTypeController.text.trim(),
        ownerName: _ownerNameController.text.trim(),
        ownerIdCard: idCardNumber,
        ownerContact: _contactNumberController.text.trim().isEmpty
            ? null
            : _contactNumberController.text.trim(),
        engineNumber: _engineNumberController.text.trim().isEmpty
            ? null
            : _engineNumberController.text.trim(),
        frameNumber: _frameNumberController.text.trim().isEmpty
            ? null
            : _frameNumberController.text.trim(),
        vehicleColor: _vehicleColorController.text.trim().isEmpty
            ? null
            : _vehicleColorController.text.trim(),
        firstRegistrationDate: _selectedFirstRegistrationDate,
        status: _currentStatusController.text.trim().isEmpty
            ? _vehicleDefaultStatus
            : _currentStatusController.text.trim(),
      );
      final idempotencyKey = generateIdempotencyKey();
      await vehicleApi.apiVehiclesPost(
        vehicle: vehiclePayload,
        idempotencyKey: idempotencyKey,
      );
      if (!mounted) return;
      _showSnackBar('vehicle.success.created'.tr);
      Navigator.pop(context, true);
      widget.onVehicleAdded?.call();
    } catch (e) {
      _showSnackBar(
        'vehicle.error.createFailed'.trParams({'error': formatVehicleError(e)}),
        isError: true,
      );
    } finally {
      _setStateSafely(() => _isLoading = false);
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
                  : themeData.colorScheme.onPrimary),
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
      initialDate: _selectedFirstRegistrationDate ?? DateTime.now(),
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
      _setStateSafely(() => _setFirstRegistrationDate(pickedDate));
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
    String? Function(String?)? validator,
  }) {
    final label = vehicleFieldLabel(fieldKey);
    final helperText = vehicleFieldHelperText(fieldKey);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: TextFormField(
        controller: controller,
        style: TextStyle(color: themeData.colorScheme.onSurface),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: themeData.colorScheme.onSurfaceVariant),
          helperText: helperText,
          helperStyle: TextStyle(
              color: themeData.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.6)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
          enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                  color: themeData.colorScheme.outline.withValues(alpha: 0.3))),
          focusedBorder: OutlineInputBorder(
              borderSide:
                  BorderSide(color: themeData.colorScheme.primary, width: 1.5)),
          filled: true,
          fillColor: readOnly
              ? themeData.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5)
              : themeData.colorScheme.surfaceContainerLowest,
          prefixText: isVehicleField(fieldKey, kVehicleFieldLicensePlate)
              ? kVehiclePlatePrefix
              : null,
          prefixStyle: TextStyle(
              color: themeData.colorScheme.onSurface,
              fontWeight: FontWeight.bold),
          suffixIcon: readOnly &&
                  isVehicleField(fieldKey, kVehicleFieldFirstRegistrationDate)
              ? Icon(Icons.calendar_today,
                  size: 18, color: themeData.colorScheme.primary)
              : null,
        ),
        keyboardType: keyboardType,
        readOnly: readOnly,
        onTap: onTap,
        maxLength: maxLength,
        validator: validator ??
            (value) => validateVehicleField(fieldKey, value,
                required: required,
                selectedDate:
                    isVehicleField(fieldKey, kVehicleFieldFirstRegistrationDate)
                        ? _selectedFirstRegistrationDate
                        : null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData = controller.currentBodyTheme.value;
      return DashboardPageTemplate(
        theme: themeData,
        title: 'vehicle.add.title'.tr,
        pageType: widget.onVehicleAdded != null
            ? DashboardPageType.custom
            : DashboardPageType.admin,
        appBar: widget.onVehicleAdded != null
            ? null
            : AppBar(
                title: Text('vehicle.add.title'.tr,
                    style: themeData.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: themeData.colorScheme.onPrimaryContainer)),
                backgroundColor: themeData.colorScheme.primaryContainer,
                foregroundColor: themeData.colorScheme.onPrimaryContainer,
                elevation: 2,
              ),
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
                                if (widget.onVehicleAdded != null)
                                  Text(
                                    'vehicle.add.emptyPrompt'.tr,
                                    style: themeData.textTheme.titleMedium
                                        ?.copyWith(
                                            color:
                                                themeData.colorScheme.onSurface,
                                            fontWeight: FontWeight.bold),
                                  ),
                                if (widget.onVehicleAdded != null)
                                  const SizedBox(height: 16),
                                _buildFormField('licensePlate',
                                    _licensePlateController, themeData,
                                    required: true, maxLength: 17),
                                _buildFormField('vehicleType',
                                    _vehicleTypeController, themeData,
                                    required: true, maxLength: 50),
                                _buildFormField('ownerName',
                                    _ownerNameController, themeData,
                                    required: true, maxLength: 100),
                                _buildFormField('idCardNumber',
                                    _idCardNumberController, themeData,
                                    required: true,
                                    keyboardType: TextInputType.number,
                                    maxLength: 18),
                                _buildFormField('contactNumber',
                                    _contactNumberController, themeData,
                                    keyboardType: TextInputType.phone,
                                    maxLength: 20),
                                _buildFormField('engineNumber',
                                    _engineNumberController, themeData,
                                    maxLength: 50),
                                _buildFormField('frameNumber',
                                    _frameNumberController, themeData,
                                    maxLength: 50),
                                _buildFormField('vehicleColor',
                                    _vehicleColorController, themeData,
                                    maxLength: 50),
                                _buildFormField('firstRegistrationDate',
                                    _firstRegistrationDateController, themeData,
                                    readOnly: true, onTap: _pickDate),
                                _buildFormField('currentStatus',
                                    _currentStatusController, themeData,
                                    maxLength: 50),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _submitVehicle,
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

class EditVehiclePage extends StatefulWidget {
  final VehicleInformation vehicle;

  const EditVehiclePage({super.key, required this.vehicle});

  @override
  State<EditVehiclePage> createState() => _EditVehiclePageState();
}

class _EditVehiclePageState extends State<EditVehiclePage> {
  final VehicleInformationControllerApi vehicleApi =
      VehicleInformationControllerApi();
  final DriverInformationControllerApi driverApi =
      DriverInformationControllerApi();
  final _formKey = GlobalKey<FormState>();
  final _licensePlateController = TextEditingController();
  final _vehicleTypeController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _idCardNumberController = TextEditingController();
  final _contactNumberController = TextEditingController();
  final _engineNumberController = TextEditingController();
  final _frameNumberController = TextEditingController();
  final _vehicleColorController = TextEditingController();
  final _firstRegistrationDateController = TextEditingController();
  final _currentStatusController = TextEditingController();
  DateTime? _selectedFirstRegistrationDate;
  bool _isLoading = false;
  final DashboardController controller = Get.find<DashboardController>();

  void _setStateSafely(VoidCallback update) {
    if (!mounted) return;
    setState(update);
  }

  void _redirectToLogin() {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, Routes.login);
  }

  Future<bool> _validateJwtToken() async {
    final jwtToken = (await AuthTokenStore.instance.getJwtToken());
    if (jwtToken == null || jwtToken.isEmpty) {
      _showSnackBar('vehicle.error.unauthorized'.tr, isError: true);
      return false;
    }
    try {
      if (JwtDecoder.isExpired(jwtToken)) {
        _showSnackBar('vehicle.error.expired'.tr, isError: true);
        return false;
      }
      return true;
    } catch (e) {
      _showSnackBar('vehicle.error.invalidLogin'.tr, isError: true);
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _setStateSafely(() => _isLoading = true);
    try {
      final isValid = await _validateJwtToken();
      if (!mounted) return;
      if (!isValid) {
        _redirectToLogin();
        return;
      }
      await vehicleApi.initializeWithJwt();
      await driverApi.initializeWithJwt();
      if (!mounted) return;
      _initializeFields();
    } catch (e) {
      _showSnackBar(
        'vehicle.error.initializeFailed'
            .trParams({'error': formatVehicleError(e)}),
        isError: true,
      );
    } finally {
      _setStateSafely(() => _isLoading = false);
    }
  }

  void _initializeFields() {
    _setStateSafely(() {
      _licensePlateController.text =
          widget.vehicle.licensePlate?.replaceFirst(kVehiclePlatePrefix, '') ??
              '';
      _vehicleTypeController.text = widget.vehicle.vehicleType ?? '';
      _ownerNameController.text = widget.vehicle.ownerName ?? '';
      _idCardNumberController.text = widget.vehicle.idCardNumber ?? '';
      _contactNumberController.text = widget.vehicle.contactNumber ?? '';
      _engineNumberController.text = widget.vehicle.engineNumber ?? '';
      _frameNumberController.text = widget.vehicle.frameNumber ?? '';
      _vehicleColorController.text = widget.vehicle.vehicleColor ?? '';
      _setFirstRegistrationDate(widget.vehicle.firstRegistrationDate);
      _currentStatusController.text = widget.vehicle.currentStatus ?? '';
    });
  }

  @override
  void dispose() {
    _licensePlateController.dispose();
    _vehicleTypeController.dispose();
    _ownerNameController.dispose();
    _idCardNumberController.dispose();
    _contactNumberController.dispose();
    _engineNumberController.dispose();
    _frameNumberController.dispose();
    _vehicleColorController.dispose();
    _firstRegistrationDateController.dispose();
    _currentStatusController.dispose();
    super.dispose();
  }

  void _setFirstRegistrationDate(DateTime? value) {
    _selectedFirstRegistrationDate =
        value == null ? null : DateUtils.dateOnly(value);
    _firstRegistrationDateController.text =
        _selectedFirstRegistrationDate == null
            ? ''
            : formatVehicleDate(_selectedFirstRegistrationDate);
  }

  Future<void> _submitVehicle() async {
    if (!_formKey.currentState!.validate()) return;
    final newLicensePlate =
        buildVehicleLicensePlate(_licensePlateController.text);
    final isValid = await _validateJwtToken();
    if (!mounted) return;
    if (!isValid) {
      _redirectToLogin();
      return;
    }
    if (!await ensureVehicleLicensePlateAvailable(
      vehicleApi: vehicleApi,
      licensePlate: newLicensePlate,
      currentLicensePlate: widget.vehicle.licensePlate,
    )) {
      if (!mounted) return;
      _showSnackBar('vehicle.error.plateExists'.tr, isError: true);
      return;
    }
    final idCardNumber = _idCardNumberController.text.trim();
    _setStateSafely(() => _isLoading = true);
    try {
      final vehiclePayload = VehicleInformation(
        vehicleId: widget.vehicle.vehicleId,
        licensePlate: newLicensePlate,
        vehicleType: _vehicleTypeController.text.trim(),
        ownerName: _ownerNameController.text.trim(),
        ownerIdCard: idCardNumber,
        ownerContact: _contactNumberController.text.trim().isEmpty
            ? null
            : _contactNumberController.text.trim(),
        engineNumber: _engineNumberController.text.trim().isEmpty
            ? null
            : _engineNumberController.text.trim(),
        frameNumber: _frameNumberController.text.trim().isEmpty
            ? null
            : _frameNumberController.text.trim(),
        vehicleColor: _vehicleColorController.text.trim().isEmpty
            ? null
            : _vehicleColorController.text.trim(),
        firstRegistrationDate: _selectedFirstRegistrationDate,
        status: _currentStatusController.text.trim().isEmpty
            ? _vehicleDefaultStatus
            : _currentStatusController.text.trim(),
      );
      final idempotencyKey = generateIdempotencyKey();
      await vehicleApi.apiVehiclesVehicleIdPut(
        vehicleId: widget.vehicle.vehicleId!,
        vehicle: vehiclePayload,
        idempotencyKey: idempotencyKey,
      );
      if (!mounted) return;
      _showSnackBar('vehicle.success.updated'.tr);
      Navigator.pop(context, true);
    } catch (e) {
      _showSnackBar(
        'vehicle.error.updateFailed'.trParams({'error': formatVehicleError(e)}),
        isError: true,
      );
    } finally {
      _setStateSafely(() => _isLoading = false);
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
                  : themeData.colorScheme.onPrimary),
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
      initialDate: _selectedFirstRegistrationDate ??
          widget.vehicle.firstRegistrationDate ??
          DateTime.now(),
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
      _setStateSafely(() => _setFirstRegistrationDate(pickedDate));
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
    String? Function(String?)? validator,
  }) {
    final label = vehicleFieldLabel(fieldKey);
    final helperText = vehicleFieldHelperText(fieldKey);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: TextFormField(
        controller: controller,
        style: TextStyle(color: themeData.colorScheme.onSurface),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: themeData.colorScheme.onSurfaceVariant),
          helperText: helperText,
          helperStyle: TextStyle(
              color: themeData.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.6)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
          enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                  color: themeData.colorScheme.outline.withValues(alpha: 0.3))),
          focusedBorder: OutlineInputBorder(
              borderSide:
                  BorderSide(color: themeData.colorScheme.primary, width: 1.5)),
          filled: true,
          fillColor: readOnly
              ? themeData.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5)
              : themeData.colorScheme.surfaceContainerLowest,
          prefixText: isVehicleField(fieldKey, kVehicleFieldLicensePlate)
              ? kVehiclePlatePrefix
              : null,
          prefixStyle: TextStyle(
              color: themeData.colorScheme.onSurface,
              fontWeight: FontWeight.bold),
          suffixIcon: readOnly &&
                  isVehicleField(fieldKey, kVehicleFieldFirstRegistrationDate)
              ? Icon(Icons.calendar_today,
                  size: 18, color: themeData.colorScheme.primary)
              : null,
          hintText: vehicleFieldHintText(fieldKey, readOnly: readOnly),
          hintStyle: TextStyle(
              color: themeData.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.6)),
        ),
        keyboardType: keyboardType,
        readOnly: readOnly,
        onTap: onTap,
        maxLength: maxLength,
        validator: validator ??
            (value) => validateVehicleField(fieldKey, value,
                required: required,
                selectedDate:
                    isVehicleField(fieldKey, kVehicleFieldFirstRegistrationDate)
                        ? _selectedFirstRegistrationDate
                        : null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData = controller.currentBodyTheme.value;
      return DashboardPageTemplate(
        theme: themeData,
        title: 'vehicle.edit.title'.tr,
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
                                _buildFormField('licensePlate',
                                    _licensePlateController, themeData,
                                    required: true, maxLength: 17),
                                _buildFormField('vehicleType',
                                    _vehicleTypeController, themeData,
                                    required: true, maxLength: 50),
                                _buildFormField('ownerName',
                                    _ownerNameController, themeData,
                                    required: true, maxLength: 100),
                                _buildFormField('idCardNumber',
                                    _idCardNumberController, themeData,
                                    required: true,
                                    readOnly: true,
                                    keyboardType: TextInputType.number,
                                    maxLength: 18),
                                _buildFormField('contactNumber',
                                    _contactNumberController, themeData,
                                    keyboardType: TextInputType.phone,
                                    maxLength: 20),
                                _buildFormField('engineNumber',
                                    _engineNumberController, themeData,
                                    maxLength: 50),
                                _buildFormField('frameNumber',
                                    _frameNumberController, themeData,
                                    maxLength: 50),
                                _buildFormField('vehicleColor',
                                    _vehicleColorController, themeData,
                                    maxLength: 50),
                                _buildFormField('firstRegistrationDate',
                                    _firstRegistrationDateController, themeData,
                                    readOnly: true, onTap: _pickDate),
                                _buildFormField('currentStatus',
                                    _currentStatusController, themeData,
                                    maxLength: 50),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _submitVehicle,
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
                          child: Text('common.save'.tr),
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

class VehicleDetailPage extends StatefulWidget {
  final VehicleInformation vehicle;

  const VehicleDetailPage({super.key, required this.vehicle});

  @override
  State<VehicleDetailPage> createState() => _VehicleDetailPageState();
}

class _VehicleDetailPageState extends State<VehicleDetailPage> {
  final VehicleInformationControllerApi vehicleApi =
      VehicleInformationControllerApi();
  final SessionHelper _sessionHelper = SessionHelper();
  bool _isLoading = false;
  bool _isEditable = false;
  String _errorMessage = '';
  String? _currentDriverName;
  final DashboardController controller = Get.find<DashboardController>();

  void _setStateSafely(VoidCallback update) {
    if (!mounted) return;
    setState(update);
  }

  void _redirectToLogin() {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, Routes.login);
  }

  Future<bool> _validateJwtToken() async {
    final jwtToken = (await AuthTokenStore.instance.getJwtToken());
    if (jwtToken == null || jwtToken.isEmpty) {
      _setStateSafely(() => _errorMessage = 'vehicle.error.unauthorized'.tr);
      return false;
    }
    try {
      if (JwtDecoder.isExpired(jwtToken)) {
        _setStateSafely(() => _errorMessage = 'vehicle.error.expired'.tr);
        return false;
      }
      return true;
    } catch (e) {
      _setStateSafely(() => _errorMessage = 'vehicle.error.invalidLogin'.tr);
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _setStateSafely(() => _isLoading = true);
    try {
      final isValid = await _validateJwtToken();
      if (!mounted) return;
      if (!isValid) {
        _redirectToLogin();
        return;
      }
      final jwtToken = (await AuthTokenStore.instance.getJwtToken());
      if (!mounted) return;
      if (jwtToken == null) {
        throw Exception('vehicle.error.jwtMissingRelogin'.tr);
      }
      final decodedToken = JwtDecoder.decode(jwtToken);
      final username = decodedToken['sub'] ?? '';
      if (username.isEmpty) {
        throw Exception('vehicle.error.usernameMissingInJwt'.tr);
      }
      await vehicleApi.initializeWithJwt();
      if (!mounted) return;
      final user = await _fetchUserManagement();
      if (!mounted) return;
      final driverInfo = user?.userId != null
          ? await _fetchDriverInformation(user!.userId!)
          : null;
      if (!mounted) return;
      _currentDriverName = driverInfo?.name ?? username;
      await _checkUserRole();
    } catch (e) {
      _setStateSafely(() => _errorMessage = 'vehicle.error.initializeFailed'
          .trParams({'error': formatVehicleError(e)}));
    } finally {
      _setStateSafely(() => _isLoading = false);
    }
  }

  Future<UserManagement?> _fetchUserManagement() async {
    try {
      final isValid = await _validateJwtToken();
      if (!mounted) return null;
      if (!isValid) {
        _redirectToLogin();
        return null;
      }
      return await _sessionHelper.fetchCurrentUser();
    } catch (e) {
      _setStateSafely(() => _errorMessage = 'vehicle.error.userInfoLoadFailed'
          .trParams({'error': formatVehicleError(e)}));
      return null;
    }
  }

  Future<DriverInformation?> _fetchDriverInformation(int userId) async {
    try {
      final isValid = await _validateJwtToken();
      if (!mounted) return null;
      if (!isValid) {
        _redirectToLogin();
        return null;
      }
      final driverApi = DriverInformationControllerApi();
      await driverApi.initializeWithJwt();
      if (!mounted) return null;
      return await driverApi.apiDriversDriverIdGet(driverId: userId);
    } catch (e) {
      _setStateSafely(() => _errorMessage = 'vehicle.error.driverInfoLoadFailed'
          .trParams({'error': formatVehicleError(e)}));
      return null;
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
      debugPrint('Resolved user roles: $roles');
      _setStateSafely(() => _isEditable = hasAnyRole(roles, const [
            'SUPER_ADMIN',
            'ADMIN',
            'TRAFFIC_POLICE',
          ]) ||
          (_currentDriverName == widget.vehicle.ownerName));
    } catch (e) {
      debugPrint('Error checking role: $e');
      _setStateSafely(() => _errorMessage = 'vehicle.error.permissionLoadFailed'
          .trParams({'error': formatVehicleError(e)}));
    }
  }

  Future<void> _deleteVehicle(int vehicleId) async {
    _setStateSafely(() => _isLoading = true);
    try {
      final isValid = await _validateJwtToken();
      if (!mounted) return;
      if (!isValid) {
        _redirectToLogin();
        return;
      }
      await vehicleApi.apiVehiclesVehicleIdDelete(vehicleId: vehicleId);
      if (!mounted) return;
      _showSnackBar('vehicle.success.deleted'.tr);
      Navigator.pop(context, true);
    } catch (e) {
      _showSnackBar(
        'vehicle.error.deleteFailed'.trParams({'error': formatVehicleError(e)}),
        isError: true,
      );
    } finally {
      _setStateSafely(() => _isLoading = false);
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
                  : themeData.colorScheme.onPrimary),
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
                  style: themeData.textTheme.bodyMedium?.copyWith(
                      color: themeData.colorScheme.onSurfaceVariant))),
        ],
      ),
    );
  }

  void _showDeleteConfirmationDialog(VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) {
        final themeData = controller.currentBodyTheme.value;
        return AlertDialog(
          backgroundColor: themeData.colorScheme.surfaceContainerHighest,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('vehicle.dialog.deleteTitle'.tr,
              style: themeData.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: themeData.colorScheme.onSurface)),
          content: Text(
              'vehicle.dialog.deleteConfirm'
                  .trParams({'action': 'vehicle.action.delete'.tr}),
              style: themeData.textTheme.bodyMedium
                  ?.copyWith(color: themeData.colorScheme.onSurfaceVariant)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('common.cancel'.tr,
                  style: themeData.textTheme.labelLarge?.copyWith(
                      color: themeData.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: () {
                onConfirm();
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: themeData.colorScheme.error,
                foregroundColor: themeData.colorScheme.onError,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: Text('vehicle.action.delete'.tr),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData = controller.currentBodyTheme.value;
      if (_errorMessage.isNotEmpty) {
        return DashboardPageTemplate(
          theme: themeData,
          title: 'vehicle.detail.title'.tr,
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
                if (shouldShowVehicleAdminReloginAction(_errorMessage))
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: ElevatedButton(
                      onPressed: _redirectToLogin,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: themeData.colorScheme.primary,
                          foregroundColor: themeData.colorScheme.onPrimary),
                      child: Text('vehicle.action.goLogin'.tr),
                    ),
                  ),
              ],
            ),
          ),
        );
      }

      return DashboardPageTemplate(
        theme: themeData,
        title: 'vehicle.detail.title'.tr,
        pageType: DashboardPageType.admin,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        actions: [
          if (_isEditable) ...[
            DashboardPageBarAction(
              icon: Icons.edit,
              onPressed: () {
                Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                EditVehiclePage(vehicle: widget.vehicle)))
                    .then((value) {
                  if (value == true && mounted) {
                    Navigator.pop(context, true);
                  }
                });
              },
              tooltip: 'vehicle.detail.editTooltip'.tr,
            ),
            DashboardPageBarAction(
              icon: Icons.delete,
              color: themeData.colorScheme.error,
              onPressed: () {
                final vehicleId = widget.vehicle.vehicleId;
                if (vehicleId == null) {
                  _showSnackBar('vehicle.error.idMissingDelete'.tr,
                      isError: true);
                  return;
                }
                _showDeleteConfirmationDialog(() => _deleteVehicle(vehicleId));
              },
              tooltip: 'vehicle.detail.deleteTooltip'.tr,
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
                              'vehicle.detail.type'.tr,
                              widget.vehicle.vehicleType ??
                                  'vehicle.value.noType'.tr,
                              themeData),
                          _buildDetailRow(
                              'vehicle.detail.plate'.tr,
                              widget.vehicle.licensePlate ??
                                  'vehicle.value.noPlate'.tr,
                              themeData),
                          _buildDetailRow(
                              'vehicle.detail.owner'.tr,
                              widget.vehicle.ownerName ??
                                  'vehicle.value.noOwner'.tr,
                              themeData),
                          _buildDetailRow(
                              'vehicle.detail.status'.tr,
                              localizeVehicleStatus(
                                widget.vehicle.currentStatus,
                              ),
                              themeData),
                          _buildDetailRow(
                              'vehicle.detail.idCard'.tr,
                              widget.vehicle.idCardNumber ?? 'common.none'.tr,
                              themeData),
                          _buildDetailRow(
                              'vehicle.detail.contact'.tr,
                              widget.vehicle.contactNumber ?? 'common.none'.tr,
                              themeData),
                          _buildDetailRow(
                              'vehicle.detail.engine'.tr,
                              widget.vehicle.engineNumber ?? 'common.none'.tr,
                              themeData),
                          _buildDetailRow(
                              'vehicle.detail.frame'.tr,
                              widget.vehicle.frameNumber ?? 'common.none'.tr,
                              themeData),
                          _buildDetailRow(
                              'vehicle.detail.color'.tr,
                              widget.vehicle.vehicleColor ?? 'common.none'.tr,
                              themeData),
                          _buildDetailRow(
                              'vehicle.detail.firstRegistrationDate'.tr,
                              formatVehicleDate(
                                widget.vehicle.firstRegistrationDate,
                              ),
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
