// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'package:final_assignment_front/features/api/offense_information_controller_api.dart';
import 'package:final_assignment_front/features/api/vehicle_information_controller_api.dart';
import 'package:final_assignment_front/utils/helpers/api_exception.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:final_assignment_front/features/dashboard/controllers/manager_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/api/fine_information_controller_api.dart';
import 'package:final_assignment_front/features/model/fine_information.dart';
import 'package:final_assignment_front/i18n/fine_localizers.dart';
import 'package:final_assignment_front/i18n/status_localizers.dart';
import 'package:get/get.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:final_assignment_front/utils/services/auth_token_store.dart';

/// Generates a unique idempotency key.
String generateIdempotencyKey() {
  return DateTime.now().millisecondsSinceEpoch.toString();
}

/// Fine list page for managers.
class FineList extends StatefulWidget {
  const FineList({super.key});

  @override
  State<FineList> createState() => _FineListState();
}

class _FineListState extends State<FineList> {
  final FineInformationControllerApi fineApi = FineInformationControllerApi();
  final TextEditingController _searchController = TextEditingController();
  final List<FineInformation> _fineList = [];
  List<FineInformation> _cachedFineList = [];
  List<FineInformation> _filteredFineList = [];
  String _searchType = kFineSearchTypePayee;
  int _currentPage = 1;
  final int _pageSize = 20;
  bool _hasMore = true;
  bool _isLoading = false;
  String _errorMessage = '';
  bool _isAdmin = false;
  bool _needsRelogin = false;
  bool _hasRecoverableLoadError = false;
  DateTime? _startDate;
  DateTime? _endDate;
  final DashboardController controller = Get.find<DashboardController>();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initialize();
    _searchController.addListener(() {
      _applyFilters(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<bool> _validateJwtToken() async {
    String? jwtToken = (await AuthTokenStore.instance.getJwtToken());
    if (jwtToken == null || jwtToken.isEmpty) {
      setState(() {
        _errorMessage = 'fineAdmin.error.unauthorized'.tr;
        _needsRelogin = true;
      });
      return false;
    }
    try {
      if (JwtDecoder.isExpired(jwtToken)) {
        jwtToken = await _refreshJwtToken();
        if (jwtToken == null) {
          setState(() {
            _errorMessage = 'fineAdmin.error.expired'.tr;
            _needsRelogin = true;
          });
          return false;
        }
        await AuthTokenStore.instance.setJwtToken(jwtToken);
        if (JwtDecoder.isExpired(jwtToken)) {
          setState(() {
            _errorMessage = 'fineAdmin.error.refreshedExpired'.tr;
            _needsRelogin = true;
          });
          return false;
        }
        await fineApi.initializeWithJwt();
      }
      if (_needsRelogin || _errorMessage == 'fineAdmin.error.invalidLogin'.tr) {
        setState(() => _needsRelogin = false);
      }
      return true;
    } catch (e) {
      setState(() {
        _errorMessage = 'fineAdmin.error.invalidLogin'.tr;
        _needsRelogin = true;
      });
      return false;
    }
  }

  Future<String?> _refreshJwtToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refreshToken');
    if (refreshToken == null) return null;
    try {
      final response = await http.post(
        Uri.parse('http://localhost:8081/api/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );
      if (response.statusCode == 200) {
        final newJwt = jsonDecode(response.body)['jwtToken'];
        await AuthTokenStore.instance.setJwtToken(newJwt);
        return newJwt;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return;
      }
      await fineApi.initializeWithJwt();
      final jwtToken = (await AuthTokenStore.instance.getJwtToken())!;
      final decodedToken = JwtDecoder.decode(jwtToken);
      _isAdmin = decodedToken['roles'] == 'ADMIN' ||
          (decodedToken['roles'] is List &&
              decodedToken['roles'].contains('ADMIN'));
      if (!_isAdmin) {
        setState(() {
          _errorMessage = 'fineAdmin.error.adminOnly'.tr;
          _needsRelogin = true;
        });
        return;
      }
      await _fetchFines(reset: true);
    } catch (e) {
      setState(() => _errorMessage = 'fineAdmin.error.initFailed'
          .trParams({'error': formatFineAdminError(e)}));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ignore: unused_element
  Future<void> _checkUserRole() async {
    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return;
      }
      final jwtToken = (await AuthTokenStore.instance.getJwtToken())!;
      final response = await http.get(
        Uri.parse('http://localhost:8081/api/users/me'),
        headers: {
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'application/json'
        },
      );
      if (response.statusCode == 200) {
        final userData = jsonDecode(utf8.decode(response.bodyBytes));
        final roles = (userData['roles'] as List<dynamic>?)
                ?.map((r) => r.toString())
                .toList() ??
            [];
        setState(() => _isAdmin = roles.contains('ADMIN'));
        if (!_isAdmin) {
          setState(() {
            _errorMessage = 'fineAdmin.error.adminOnly'.tr;
            _needsRelogin = true;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'fineAdmin.error.roleCheckFailed'.trParams({
            'error': 'fineAdmin.error.httpStatus'
                .trParams({'statusCode': '${response.statusCode}'})
          });
          _needsRelogin = true;
        });
        return;
      }
    } catch (e) {
      setState(() => _errorMessage = 'fineAdmin.error.roleCheckFailed'
          .trParams({'error': formatFineAdminError(e)}));
    }
  }

  Future<void> _fetchFines(
      {bool reset = false, String? query, int retries = 5}) async {
    if (!_isAdmin || !_hasMore) return;

    if (reset) {
      _currentPage = 1;
      _hasMore = true;
      _fineList.clear();
      _filteredFineList.clear();
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _needsRelogin = false;
      _hasRecoverableLoadError = false;
    });

    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return;
      }
      List<FineInformation> fines = [];
      final searchQuery = query?.trim() ?? '';
      for (int attempt = 1; attempt <= retries; attempt++) {
        try {
          if (searchQuery.isEmpty && _startDate == null && _endDate == null) {
            fines = await fineApi.apiFinesGet();
            fines.sort((a, b) => comparableFineDisplayDate(
                  b.fineDate,
                  b.fineTime,
                ).compareTo(comparableFineDisplayDate(
                  a.fineDate,
                  a.fineTime,
                )));
          } else if (_searchType == kFineSearchTypePayee &&
              searchQuery.isNotEmpty) {
            fines = await fineApi.apiFinesPayeePayeeGet(payee: searchQuery);
          } else if (_searchType == kFineSearchTypeTimeRange &&
              _startDate != null &&
              _endDate != null) {
            fines = await fineApi.apiFinesTimeRangeGet(
              startDate: _startDate!.toIso8601String().split('T').first,
              endDate: _endDate!
                  .add(const Duration(days: 1))
                  .toIso8601String()
                  .split('T')
                  .first,
            );
          }
          break;
        } catch (e) {
          if (attempt == retries) {
            rethrow;
          }
          await Future.delayed(Duration(milliseconds: 1000 * attempt));
        }
      }

      setState(() {
        _fineList.addAll(fines);
        _cachedFineList = List.from(fines);
        _hasMore = fines.length == _pageSize;
        _applyFilters(query ?? _searchController.text);
        if (_filteredFineList.isEmpty) {
          _errorMessage =
              searchQuery.isNotEmpty || (_startDate != null && _endDate != null)
                  ? 'fineAdmin.error.filteredEmpty'.tr
                  : 'fineAdmin.empty.default'.tr;
        }
        _currentPage++;
        if (reset && _scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      });
    } catch (e) {
      setState(() {
        if (e is ApiException && e.code == 403) {
          _errorMessage = 'fineAdmin.error.unauthorized'.tr;
          _needsRelogin = true;
          Navigator.pushReplacementNamed(context, Routes.login);
        } else if (e is ApiException && e.code == 404) {
          _errorMessage = 'fineAdmin.error.notFound'.tr;
          _hasMore = false;
        } else {
          _errorMessage = 'fineAdmin.error.loadFailed'.trParams({
            'error': '$e',
          });
          _hasRecoverableLoadError = true;
        }
        if (_cachedFineList.isNotEmpty) {
          _fineList.addAll(_cachedFineList);
          _applyFilters(query ?? _searchController.text);
          _errorMessage = 'fineAdmin.error.loadLatestFallback'.tr;
          _hasRecoverableLoadError = true;
        }
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<List<String>> _fetchAutocompleteSuggestions(String prefix) async {
    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return [];
      }
      if (_searchType == kFineSearchTypePayee) {
        final fines = await fineApi.apiFinesPayeePayeeGet(payee: prefix.trim());
        return fines
            .map((fine) => fine.payee ?? '')
            .where(
                (payee) => payee.toLowerCase().contains(prefix.toLowerCase()))
            .take(5)
            .toList();
      }
      return [];
    } catch (e) {
      setState(() => _errorMessage = 'fineAdmin.error.suggestionFailed'
          .trParams({'error': formatFineAdminError(e)}));
      return [];
    }
  }

  void _applyFilters(String query) {
    final searchQuery = query.trim().toLowerCase();
    setState(() {
      _filteredFineList.clear();
      _filteredFineList = _fineList.where((fine) {
        final payee = (fine.payee ?? '').toLowerCase();
        final fineDate = resolveFineDisplayDate(fine.fineDate, fine.fineTime);

        bool matchesQuery = true;
        if (searchQuery.isNotEmpty && _searchType == kFineSearchTypePayee) {
          matchesQuery = payee.contains(searchQuery);
        }

        bool matchesDateRange = true;
        if (_startDate != null && _endDate != null) {
          if (fineDate == null) {
            matchesDateRange = false;
          } else {
            final inclusiveEnd = _endDate!.add(const Duration(days: 1));
            matchesDateRange = !fineDate.isBefore(_startDate!) &&
                fineDate.isBefore(inclusiveEnd);
          }
        }

        return matchesQuery && matchesDateRange;
      }).toList();

      if (_filteredFineList.isEmpty && _fineList.isNotEmpty) {
        _errorMessage = 'fineAdmin.error.filteredEmpty'.tr;
      } else {
        _errorMessage = _filteredFineList.isEmpty && _fineList.isEmpty
            ? 'fineAdmin.empty.default'.tr
            : '';
      }
    });
  }

  // ignore: unused_element
  Future<void> _searchFines() async {
    final query = _searchController.text.trim();
    _applyFilters(query);
  }

  Future<void> _refreshFines({String? query}) async {
    setState(() {
      _fineList.clear();
      _filteredFineList.clear();
      _currentPage = 1;
      _hasMore = true;
      _isLoading = true;
      if (query == null) {
        _searchController.clear();
        _startDate = null;
        _endDate = null;
        _searchType = kFineSearchTypePayee;
      }
    });
    await _fetchFines(reset: true, query: query);
    if (_errorMessage.isEmpty && _fineList.isNotEmpty) {
      _showSnackBar('fineAdmin.success.refreshed'.tr);
    }
  }

  Future<void> _loadMoreFines() async {
    if (!_isLoading && _hasMore) {
      await _fetchFines();
    }
  }

  void _createFine() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddFinePage()),
    ).then((value) {
      if (value == true) {
        _refreshFines();
      }
    });
  }

  void _editFine(FineInformation fine) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => AddFinePage(fine: fine, isEditMode: true)),
    ).then((value) {
      if (value == true) {
        _refreshFines();
      }
    });
  }

  void _goToDetailPage(FineInformation fine) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => FineDetailPage(fine: fine)),
    ).then((value) {
      if (value == true) {
        _refreshFines();
      }
    });
  }

  Future<void> _deleteFine(int fineId) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('fineAdmin.delete.confirmTitle'.tr),
        content: Text('fineAdmin.delete.confirmBody'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'fineAdmin.action.delete'.tr,
              style: const TextStyle(color: Colors.red),
            ),
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
        await fineApi.apiFinesFineIdDelete(fineId: fineId);
        _showSnackBar('fineAdmin.success.deleted'.tr);
        await _refreshFines();
      } catch (e) {
        _showSnackBar(
          'fineAdmin.error.deleteFailed'
              .trParams({'error': formatFineAdminError(e)}),
          isError: true,
        );
      } finally {
        setState(() => _isLoading = false);
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
                    if (textEditingValue.text.isEmpty ||
                        _searchType != kFineSearchTypePayee) {
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
                    _searchController.text = controller.text;
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      style: TextStyle(color: themeData.colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: fineSearchHintText(_searchType),
                        hintStyle: TextStyle(
                            color: themeData.colorScheme.onSurface
                                .withValues(alpha: 0.6)),
                        prefixIcon: Icon(Icons.search,
                            color: themeData.colorScheme.primary),
                        suffixIcon: controller.text.isNotEmpty ||
                                (_startDate != null && _endDate != null)
                            ? IconButton(
                                icon: Icon(Icons.clear,
                                    color:
                                        themeData.colorScheme.onSurfaceVariant),
                                onPressed: () {
                                  controller.clear();
                                  _searchController.clear();
                                  setState(() {
                                    _startDate = null;
                                    _endDate = null;
                                    _searchType = kFineSearchTypePayee;
                                  });
                                  _applyFilters('');
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
                      onChanged: (value) => _applyFilters(value),
                      onSubmitted: (value) => _applyFilters(value),
                      enabled: _searchType == kFineSearchTypePayee,
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
                    _startDate = null;
                    _endDate = null;
                    _applyFilters('');
                  });
                },
                items: <String>[
                  kFineSearchTypePayee,
                  kFineSearchTypeTimeRange,
                ].map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(
                      fineSearchTypeLabel(value),
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
                      ? 'fineAdmin.filter.dateRangeLabel'.trParams({
                          'start': formatFineVisibleDate(_startDate),
                          'end': formatFineVisibleDate(_endDate),
                        })
                      : 'fineAdmin.filter.selectDateRange'.tr,
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
                tooltip: 'fineAdmin.filter.tooltip'.tr,
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                    locale: Get.locale ?? const Locale('en', 'US'),
                    helpText: 'fineAdmin.filter.selectDateRange'.tr,
                    cancelText: 'common.cancel'.tr,
                    confirmText: 'common.confirm'.tr,
                    fieldStartHintText: 'fineAdmin.filter.startDate'.tr,
                    fieldEndHintText: 'fineAdmin.filter.endDate'.tr,
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
                      _searchType = kFineSearchTypeTimeRange;
                    });
                    _applyFilters(_searchController.text);
                  }
                },
              ),
              if (_startDate != null && _endDate != null)
                IconButton(
                  icon: Icon(Icons.clear,
                      color: themeData.colorScheme.onSurfaceVariant),
                  tooltip: 'fineAdmin.filter.clearDateRange'.tr,
                  onPressed: () {
                    setState(() {
                      _startDate = null;
                      _endDate = null;
                      _searchType = kFineSearchTypePayee;
                    });
                    _applyFilters(_searchController.text);
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
        title: 'fineAdmin.page.title'.tr,
        pageType: DashboardPageType.manager,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        actions: [
          if (_isAdmin) ...[
            DashboardPageBarAction(
              icon: Icons.add,
              onPressed: _createFine,
              tooltip: 'fineAdmin.action.add'.tr,
            ),
            DashboardPageBarAction(
              icon: Icons.refresh,
              onPressed: () => _refreshFines(),
              tooltip: 'fineAdmin.action.refresh'.tr,
            ),
          ],
        ],
        onThemeToggle: controller.toggleBodyTheme,
        body: RefreshIndicator(
          onRefresh: () => _refreshFines(),
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
                        _loadMoreFines();
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
                        : _errorMessage.isNotEmpty && _filteredFineList.isEmpty
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
                                    if (_hasRecoverableLoadError)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 16.0),
                                        child: ElevatedButton(
                                          onPressed: () => _refreshFines(),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                themeData.colorScheme.primary,
                                            foregroundColor:
                                                themeData.colorScheme.onPrimary,
                                          ),
                                          child:
                                              Text('fineAdmin.action.retry'.tr),
                                        ),
                                      ),
                                    if (_hasRecoverableLoadError &&
                                        _cachedFineList.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 16.0),
                                        child: ElevatedButton(
                                          onPressed: () {
                                            setState(() {
                                              _fineList.clear();
                                              _fineList.addAll(_cachedFineList);
                                              _applyFilters(
                                                  _searchController.text);
                                              _errorMessage = '';
                                            });
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                themeData.colorScheme.secondary,
                                            foregroundColor: themeData
                                                .colorScheme.onSecondary,
                                          ),
                                          child: Text(
                                              'fineAdmin.action.restoreCache'
                                                  .tr),
                                        ),
                                      ),
                                    if (_needsRelogin ||
                                        shouldShowFineAdminReloginAction(
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
                                              'fineAdmin.action.relogin'.tr),
                                        ),
                                      ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                itemCount: _filteredFineList.length +
                                    (_hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _filteredFineList.length &&
                                      _hasMore) {
                                    return const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Center(
                                          child: CircularProgressIndicator()),
                                    );
                                  }
                                  final fijne = _filteredFineList[index];
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
                                        'fineAdmin.card.amount'.trParams({
                                          'amount': '${fijne.fineAmount ?? 0}',
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
                                            'fineAdmin.card.payee'.trParams({
                                              'value': fijne.payee ??
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
                                            'fineAdmin.card.time'.trParams({
                                              'value': formatFineVisibleDate(
                                                resolveFineDisplayDate(
                                                  fijne.fineDate,
                                                  fijne.fineTime,
                                                ),
                                              ),
                                            }),
                                            style: themeData
                                                .textTheme.bodyMedium
                                                ?.copyWith(
                                              color: themeData
                                                  .colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          Text(
                                            'fineAdmin.card.status'.trParams({
                                              'value':
                                                  localizeManagerFineStatus(
                                                fijne.status,
                                                emptyKey:
                                                    'common.status.processing',
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
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: Icon(Icons.edit,
                                                size: 18,
                                                color: themeData
                                                    .colorScheme.primary),
                                            onPressed: () => _editFine(fijne),
                                            tooltip: 'fineAdmin.action.edit'.tr,
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.delete,
                                                size: 18,
                                                color: themeData
                                                    .colorScheme.error),
                                            onPressed: () =>
                                                _deleteFine(fijne.fineId ?? 0),
                                            tooltip:
                                                'fineAdmin.action.delete'.tr,
                                          ),
                                          Icon(
                                            Icons.arrow_forward_ios,
                                            color: themeData
                                                .colorScheme.onSurfaceVariant,
                                            size: 18,
                                          ),
                                        ],
                                      ),
                                      onTap: () => _goToDetailPage(fijne),
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

class AddFinePage extends StatefulWidget {
  final FineInformation? fine;
  final bool isEditMode;

  const AddFinePage({super.key, this.fine, this.isEditMode = false});

  @override
  State<AddFinePage> createState() => _AddFinePageState();
}

class _AddFinePageState extends State<AddFinePage> {
  final FineInformationControllerApi fineApi = FineInformationControllerApi();
  final OffenseInformationControllerApi offenseApi =
      OffenseInformationControllerApi();
  final VehicleInformationControllerApi vehicleApi =
      VehicleInformationControllerApi();
  final _formKey = GlobalKey<FormState>();
  final _plateNumberController = TextEditingController();
  final _fineAmountController = TextEditingController();
  final _payeeController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _bankController = TextEditingController();
  final _receiptNumberController = TextEditingController();
  final _remarksController = TextEditingController();
  final _dateController = TextEditingController();
  bool _isLoading = false;
  final DashboardController controller = Get.find<DashboardController>();
  int? _selectedOffenseId;
  DateTime? _selectedFineDate;

  @override
  void initState() {
    super.initState();
    if (widget.isEditMode && widget.fine != null) {
      _prepopulateFields(widget.fine!);
    }
    _initialize();
  }

  void _prepopulateFields(FineInformation fine) {
    _plateNumberController.text =
        ''; // Plate number not stored in FineInformation
    _fineAmountController.text = fine.fineAmount?.toString() ?? '';
    _payeeController.text = fine.payee ?? '';
    _accountNumberController.text = fine.accountNumber ?? '';
    _bankController.text = fine.bank ?? '';
    _receiptNumberController.text = fine.receiptNumber ?? '';
    _remarksController.text = fine.remarks ?? '';
    _setFineDate(resolveFineDisplayDate(fine.fineDate, fine.fineTime));
    _selectedOffenseId = fine.offenseId;
  }

  void _setFineDate(DateTime? value) {
    _selectedFineDate = value == null ? null : DateUtils.dateOnly(value);
    _dateController.text =
        _selectedFineDate == null ? '' : formatFineAdminDate(_selectedFineDate);
  }

  Future<bool> _validateJwtToken() async {
    final jwtToken = (await AuthTokenStore.instance.getJwtToken());
    if (jwtToken == null || jwtToken.isEmpty) {
      _showSnackBar('fineAdmin.error.unauthorized'.tr, isError: true);
      return false;
    }
    try {
      if (JwtDecoder.isExpired(jwtToken)) {
        _showSnackBar('fineAdmin.error.expired'.tr, isError: true);
        return false;
      }
      return true;
    } catch (e) {
      _showSnackBar('fineAdmin.error.invalidLogin'.tr, isError: true);
      return false;
    }
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return;
      }
      await fineApi.initializeWithJwt();
      await offenseApi.initializeWithJwt();
      await vehicleApi.initializeWithJwt();
    } catch (e) {
      _showSnackBar(
        'fineAdmin.error.initFailed'
            .trParams({'error': formatFineAdminError(e)}),
        isError: true,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _plateNumberController.dispose();
    _fineAmountController.dispose();
    _payeeController.dispose();
    _accountNumberController.dispose();
    _bankController.dispose();
    _receiptNumberController.dispose();
    _remarksController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  Future<List<String>> _fetchLicensePlateSuggestions(String prefix) async {
    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return [];
      }
      return await vehicleApi.apiVehiclesSearchLicenseGlobalGet(
        prefix: prefix,
        size: 10,
      );
    } catch (e) {
      _showSnackBar(
        'fineAdmin.error.fetchPlateSuggestionsFailed'
            .trParams({'error': formatFineAdminError(e)}),
        isError: true,
      );
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPayeeSuggestions(
      String prefix) async {
    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return [];
      }
      if (prefix.trim().isEmpty) return [];
      final offenses = await offenseApi.apiOffensesByDriverNameGet(
        query: prefix.trim(),
        page: 1,
        size: 10,
      );
      return offenses
          .where((o) => o.driverName != null && o.driverName!.isNotEmpty)
          .map((o) => {
                'payee': o.driverName!,
                'offenseId': o.offenseId ?? 0,
                'fineAmount': o.fineAmount ?? 0.0,
                'licensePlate': o.licensePlate ?? '',
              })
          .where(
              (item) => item['payee'].toString().contains(prefix.toLowerCase()))
          .toList();
    } catch (e) {
      if (e is ApiException && e.code == 400 && prefix.trim().isEmpty) {
        return [];
      }
      _showSnackBar(
        'fineAdmin.error.fetchPayeeSuggestionsFailed'
            .trParams({'error': formatFineAdminError(e)}),
        isError: true,
      );
      return [];
    }
  }

  Future<void> _onLicensePlateSelected(String licensePlate) async {
    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return;
      }
      final offenses = await offenseApi.apiOffensesByLicensePlateGet(
        query: licensePlate,
        page: 1,
        size: 10,
      );
      if (offenses.isNotEmpty) {
        final latestOffense = offenses.first;
        setState(() {
          _selectedOffenseId = latestOffense.offenseId;
          _payeeController.text = latestOffense.driverName ?? '';
          _fineAmountController.text =
              latestOffense.fineAmount?.toString() ?? '';
        });
      } else {
        _showSnackBar('fineAdmin.error.offenseNotFoundByPlate'.tr,
            isError: true);
        setState(() {
          _selectedOffenseId = null;
          _payeeController.clear();
          _fineAmountController.clear();
        });
      }
    } catch (e) {
      _showSnackBar(
        'fineAdmin.error.fetchOffenseFailed'
            .trParams({'error': formatFineAdminError(e)}),
        isError: true,
      );
    }
  }

  Future<void> _onPayeeSelected(Map<String, dynamic> payeeData) async {
    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return;
      }
      if (payeeData['offenseId'] == 0) {
        _showSnackBar('fineAdmin.error.invalidOffense'.tr, isError: true);
        return;
      }
      setState(() {
        _payeeController.text = payeeData['payee'];
        _selectedOffenseId = payeeData['offenseId'];
        _fineAmountController.text = payeeData['fineAmount']?.toString() ?? '';
        _plateNumberController.text = payeeData['licensePlate'].isNotEmpty
            ? payeeData['licensePlate']
            : _plateNumberController.text;
      });
    } catch (e) {
      _showSnackBar(
        'fineAdmin.error.loadPayeeFailed'
            .trParams({'error': formatFineAdminError(e)}),
        isError: true,
      );
    }
  }

  Future<void> _submitFine() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedOffenseId == null) {
      _showSnackBar('fineAdmin.error.selectValidOffense'.tr, isError: true);
      return;
    }
    if (!await _validateJwtToken()) {
      Navigator.pushReplacementNamed(context, Routes.login);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final idempotencyKey = generateIdempotencyKey();
      final finePayload = FineInformation(
        fineId: widget.isEditMode ? widget.fine?.fineId : null,
        offenseId: _selectedOffenseId!,
        fineAmount: double.tryParse(_fineAmountController.text.trim()) ?? 0.0,
        payee: _payeeController.text.trim(),
        accountNumber: _accountNumberController.text.trim().isEmpty
            ? null
            : _accountNumberController.text.trim(),
        bank: _bankController.text.trim().isEmpty
            ? null
            : _bankController.text.trim(),
        receiptNumber: _receiptNumberController.text.trim().isEmpty
            ? null
            : _receiptNumberController.text.trim(),
        remarks: _remarksController.text.trim().isEmpty
            ? null
            : _remarksController.text.trim(),
        fineTime: _selectedFineDate?.toIso8601String(),
        status: widget.isEditMode
            ? widget.fine?.status
            : fineProcessingStatusCode(),
        idempotencyKey: idempotencyKey,
      );
      if (widget.isEditMode) {
        await fineApi.apiFinesFineIdPut(
          fineId: finePayload.fineId ?? 0,
          fineInformation: finePayload,
          idempotencyKey: idempotencyKey,
        );
        _showSnackBar('fineAdmin.success.updated'.tr);
      } else {
        await fineApi.apiFinesPost(
          fineInformation: finePayload,
          idempotencyKey: idempotencyKey,
        );
        _showSnackBar('fineAdmin.success.created'.tr);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      _showSnackBar(
        (widget.isEditMode
                ? 'fineAdmin.error.updateFailed'
                : 'fineAdmin.error.createFailed')
            .trParams({'error': formatFineAdminError(e)}),
        isError: true,
      );
    } catch (e) {
      _showSnackBar(
        (widget.isEditMode
                ? 'fineAdmin.error.updateFailed'
                : 'fineAdmin.error.createFailed')
            .trParams({'error': formatFineAdminError(e)}),
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
      initialDate: _selectedFineDate ??
          (widget.fine != null
              ? resolveFineDisplayDate(
                  widget.fine!.fineDate,
                  widget.fine!.fineTime,
                )
              : null) ??
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
      setState(() => _setFineDate(pickedDate));
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
    final label = fineFieldLabel(fieldKey);
    final helperText = fineFieldHelperText(fieldKey);
    final isAutocompleteField =
        fieldKey == kFineFieldPlateNumber || fieldKey == kFineFieldPayee;

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
            (readOnly
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
        child: Autocomplete<Map<String, dynamic>>(
          optionsBuilder: (TextEditingValue textEditingValue) async {
            if (textEditingValue.text.trim().isEmpty) {
              return const Iterable<Map<String, dynamic>>.empty();
            }
            if (fieldKey == kFineFieldPlateNumber) {
              final suggestions =
                  await _fetchLicensePlateSuggestions(textEditingValue.text);
              return suggestions.map((item) => {'value': item}).toList();
            }
            return await _fetchPayeeSuggestions(textEditingValue.text);
          },
          displayStringForOption: (Map<String, dynamic> option) =>
              fieldKey == kFineFieldPlateNumber
                  ? option['value']
                  : option['payee'],
          onSelected: (Map<String, dynamic> selection) async {
            if (fieldKey == kFineFieldPlateNumber) {
              controller.text = selection['value'];
              await _onLicensePlateSelected(selection['value']);
              return;
            }
            await _onPayeeSelected(selection);
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
                          setState(() {
                            _selectedOffenseId = null;
                            if (fieldKey == kFineFieldPlateNumber) {
                              _payeeController.clear();
                              _fineAmountController.clear();
                            }
                          });
                        },
                      )
                    : null,
              ),
              keyboardType: keyboardType,
              maxLength: maxLength,
              validator: validator ??
                  (value) => validateFineFormField(
                        fieldKey,
                        value,
                        required: required,
                        selectedDate: fieldKey == kFineFieldFineDate
                            ? _selectedFineDate
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
        validator: validator ??
            (value) => validateFineFormField(
                  fieldKey,
                  value,
                  required: required,
                  selectedDate:
                      fieldKey == kFineFieldFineDate ? _selectedFineDate : null,
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
        title: widget.isEditMode
            ? 'fineAdmin.form.editTitle'.tr
            : 'fineAdmin.form.addTitle'.tr,
        pageType: DashboardPageType.manager,
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
                                _buildFormField(kFineFieldPlateNumber,
                                    _plateNumberController, themeData,
                                    required: true, maxLength: 20),
                                _buildFormField(kFineFieldAmount,
                                    _fineAmountController, themeData,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    required: true),
                                _buildFormField(kFineFieldPayee,
                                    _payeeController, themeData,
                                    required: true, maxLength: 100),
                                _buildFormField(kFineFieldAccountNumber,
                                    _accountNumberController, themeData,
                                    maxLength: 50),
                                _buildFormField(
                                    kFineFieldBank, _bankController, themeData,
                                    maxLength: 100),
                                _buildFormField(kFineFieldReceiptNumber,
                                    _receiptNumberController, themeData,
                                    maxLength: 50),
                                _buildFormField(kFineFieldRemarks,
                                    _remarksController, themeData,
                                    maxLength: 255),
                                _buildFormField(kFineFieldFineDate,
                                    _dateController, themeData,
                                    readOnly: true,
                                    onTap: _pickDate,
                                    required: true),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _submitFine,
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
                          child: Text(
                            widget.isEditMode
                                ? 'common.save'.tr
                                : 'common.submit'.tr,
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

class FineDetailPage extends StatefulWidget {
  final FineInformation fine;

  const FineDetailPage({super.key, required this.fine});

  @override
  State<FineDetailPage> createState() => _FineDetailPageState();
}

class _FineDetailPageState extends State<FineDetailPage> {
  final FineInformationControllerApi fineApi = FineInformationControllerApi();
  bool _isLoading = false;
  bool _isAdmin = false;
  String _errorMessage = '';
  final DashboardController controller = Get.find<DashboardController>();
  late FineInformation _currentFine;

  @override
  void initState() {
    super.initState();
    _currentFine = widget.fine;
    _initialize();
  }

  Future<bool> _validateJwtToken() async {
    final jwtToken = (await AuthTokenStore.instance.getJwtToken());
    if (jwtToken == null || jwtToken.isEmpty) {
      setState(() => _errorMessage = 'fineAdmin.error.unauthorized'.tr);
      return false;
    }
    try {
      if (JwtDecoder.isExpired(jwtToken)) {
        setState(() => _errorMessage = 'fineAdmin.error.expired'.tr);
        return false;
      }
      return true;
    } catch (e) {
      setState(() => _errorMessage = 'fineAdmin.error.invalidLogin'.tr);
      return false;
    }
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return;
      }
      await fineApi.initializeWithJwt();
      await _checkUserRole();
    } catch (e) {
      setState(() => _errorMessage = 'fineAdmin.error.initFailed'
          .trParams({'error': formatFineAdminError(e)}));
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
      final jwtToken = (await AuthTokenStore.instance.getJwtToken());
      if (jwtToken == null) {
        throw Exception('fineAdmin.error.jwtMissingRelogin'.tr);
      }
      final response = await http.get(
        Uri.parse('http://localhost:8081/api/users/me'),
        headers: {
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'application/json'
        },
      );
      if (response.statusCode == 200) {
        final userData = jsonDecode(utf8.decode(response.bodyBytes));
        final roles = (userData['roles'] as List<dynamic>?)
                ?.map((r) => r.toString())
                .toList() ??
            [];
        setState(() => _isAdmin = roles.contains('ADMIN'));
      } else {
        setState(() =>
            _errorMessage = 'fineAdmin.error.permissionLoadFailed'.trParams({
              'error': 'fineAdmin.error.httpStatus'
                  .trParams({'statusCode': '${response.statusCode}'})
            }));
        return;
      }
    } catch (e) {
      setState(() => _errorMessage = 'fineAdmin.error.permissionLoadFailed'
          .trParams({'error': formatFineAdminError(e)}));
    }
  }

  Future<void> _updateFineStatus(int fineId, String status) async {
    setState(() => _isLoading = true);
    try {
      if (!await _validateJwtToken()) {
        Navigator.pushReplacementNamed(context, Routes.login);
        return;
      }
      final idempotencyKey = const Uuid().v4();
      final updatedFine = FineInformation(
        fineId: _currentFine.fineId,
        offenseId: _currentFine.offenseId,
        fineAmount: _currentFine.fineAmount,
        payee: _currentFine.payee,
        fineTime: _currentFine.fineTime,
        accountNumber: _currentFine.accountNumber,
        bank: _currentFine.bank,
        receiptNumber: _currentFine.receiptNumber,
        status: status,
        remarks: _currentFine.remarks,
        idempotencyKey: idempotencyKey,
      );
      final result = await fineApi.apiFinesFineIdPut(
        fineId: fineId,
        fineInformation: updatedFine,
        idempotencyKey: idempotencyKey,
      );
      setState(() => _currentFine = result);
      final localizedStatus =
          normalizeFineStatusCode(status) == fineApprovedStatusCode()
              ? 'common.status.approved'.tr
              : 'common.status.rejected'.tr;
      _showSnackBar(
        'fineAdmin.success.statusUpdated'.trParams({'status': localizedStatus}),
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      _showSnackBar(
        'fineAdmin.error.statusUpdateFailed'
            .trParams({'error': formatFineAdminError(e)}),
        isError: true,
      );
    } catch (e) {
      _showSnackBar(
        'fineAdmin.error.statusUpdateFailed'
            .trParams({'error': formatFineAdminError(e)}),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteFine(int fineId) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('fineAdmin.delete.confirmTitle'.tr),
        content: Text('fineAdmin.delete.confirmBody'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'fineAdmin.action.delete'.tr,
              style: const TextStyle(color: Colors.red),
            ),
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
        await fineApi.apiFinesFineIdDelete(fineId: fineId);
        _showSnackBar('fineAdmin.success.deleted'.tr);
        if (mounted) Navigator.pop(context, true);
      } on ApiException catch (e) {
        _showSnackBar(
          'fineAdmin.error.deleteFailed'
              .trParams({'error': formatFineAdminError(e)}),
          isError: true,
        );
      } catch (e) {
        _showSnackBar(
          'fineAdmin.error.deleteFailed'
              .trParams({'error': formatFineAdminError(e)}),
          isError: true,
        );
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _editFine() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddFinePage(
          fine: _currentFine,
          isEditMode: true,
        ),
      ),
    ).then((value) {
      if (value == true) {
        Navigator.pop(context, true); // Trigger refresh in FineList
      }
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

  bool _isProcessingStatus(String? status) {
    return isProcessingFineStatus(status);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData = controller.currentBodyTheme.value;
      if (_errorMessage.isNotEmpty) {
        return DashboardPageTemplate(
          theme: themeData,
          title: 'fineAdmin.detail.title'.tr,
          pageType: DashboardPageType.manager,
          bodyIsScrollable: true,
          padding: EdgeInsets.zero,
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
                if (shouldShowFineDetailReloginAction(_errorMessage))
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.pushReplacementNamed(context, Routes.login),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeData.colorScheme.primary,
                        foregroundColor: themeData.colorScheme.onPrimary,
                      ),
                      child: Text('fineAdmin.action.relogin'.tr),
                    ),
                  ),
              ],
            ),
          ),
        );
      }

      return DashboardPageTemplate(
        theme: themeData,
        title: 'fineAdmin.detail.title'.tr,
        pageType: DashboardPageType.manager,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        actions: [
          if (_isAdmin) ...[
            DashboardPageBarAction(
              icon: Icons.edit,
              onPressed: _editFine,
              tooltip: 'fineAdmin.detail.editTooltip'.tr,
            ),
            if (_isProcessingStatus(_currentFine.status)) ...[
              DashboardPageBarAction(
                icon: Icons.check,
                onPressed: () => _updateFineStatus(
                  _currentFine.fineId ?? 0,
                  fineApprovedStatusCode(),
                ),
                tooltip: 'fineAdmin.detail.approveTooltip'.tr,
              ),
              DashboardPageBarAction(
                icon: Icons.close,
                onPressed: () => _updateFineStatus(
                  _currentFine.fineId ?? 0,
                  fineRejectedStatusCode(),
                ),
                tooltip: 'fineAdmin.detail.rejectTooltip'.tr,
              ),
            ],
            DashboardPageBarAction(
              icon: Icons.delete,
              color: themeData.colorScheme.error,
              onPressed: () => _deleteFine(_currentFine.fineId ?? 0),
              tooltip: 'fineAdmin.detail.deleteTooltip'.tr,
            ),
          ],
        ],
        body: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation(themeData.colorScheme.primary),
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  elevation: 3,
                  color: themeData.colorScheme.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow(
                            'fine.detail.amount'.tr,
                            '${_currentFine.fineAmount ?? 0}',
                            themeData,
                          ),
                          _buildDetailRow(
                            'fine.detail.payee'.tr,
                            _currentFine.payee ?? 'common.unknown'.tr,
                            themeData,
                          ),
                          _buildDetailRow(
                            'fine.detail.time'.tr,
                            formatFineAdminDateTime(
                              resolveFineDisplayDate(
                                _currentFine.fineDate,
                                _currentFine.fineTime,
                              ),
                            ),
                            themeData,
                          ),
                          _buildDetailRow(
                            'fine.detail.status'.tr,
                            localizeManagerFineStatus(_currentFine.status),
                            themeData,
                          ),
                          _buildDetailRow(
                            'fine.detail.account'.tr,
                            _currentFine.accountNumber ?? 'common.none'.tr,
                            themeData,
                          ),
                          _buildDetailRow(
                            'fine.detail.bank'.tr,
                            _currentFine.bank ?? 'common.none'.tr,
                            themeData,
                          ),
                          _buildDetailRow(
                            'fine.detail.receipt'.tr,
                            _currentFine.receiptNumber ?? 'common.none'.tr,
                            themeData,
                          ),
                          _buildDetailRow(
                            'fine.detail.remarks'.tr,
                            _currentFine.remarks ?? 'common.none'.tr,
                            themeData,
                          ),
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
