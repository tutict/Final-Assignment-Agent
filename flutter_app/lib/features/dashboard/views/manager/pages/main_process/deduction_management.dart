import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/api/deduction_information_controller_api.dart';
import 'package:final_assignment_front/features/api/offense_information_controller_api.dart';
import 'package:final_assignment_front/features/dashboard/controllers/manager_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/features/model/deduction_record.dart';
import 'package:final_assignment_front/i18n/deduction_localizers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeductionManagement extends StatefulWidget {
  const DeductionManagement({super.key});

  @override
  State<DeductionManagement> createState() => _DeductionManagementState();
}

class _DeductionManagementState extends State<DeductionManagement> {
  final DeductionInformationControllerApi deductionApi =
      DeductionInformationControllerApi();
  final DashboardController controller = Get.find<DashboardController>();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<DeductionRecordModel> _deductions = [];
  List<DeductionRecordModel> _filteredDeductions = [];

  String _searchType = kDeductionSearchTypeHandler;
  bool _isLoading = false;
  bool _isAdmin = false;
  bool _showReloginAction = false;
  String _statusMessage = '';
  DateTime? _startTime;
  DateTime? _endTime;

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
    final prefs = await SharedPreferences.getInstance();
    final jwtToken = prefs.getString('jwtToken');
    if (jwtToken == null || jwtToken.isEmpty) {
      setState(() {
        _statusMessage = 'deductionAdmin.error.unauthorized'.tr;
        _showReloginAction = true;
      });
      return false;
    }
    try {
      if (JwtDecoder.isExpired(jwtToken)) {
        setState(() {
          _statusMessage = 'deductionAdmin.error.expired'.tr;
          _showReloginAction = true;
        });
        return false;
      }
      return true;
    } catch (e) {
      setState(() {
        _statusMessage = 'deductionAdmin.error.invalidLogin'.trParams({
          'error': formatDeductionAdminError(e),
        });
        _showReloginAction = true;
      });
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
      await deductionApi.initializeWithJwt();
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwtToken')!;
      final decodedToken = JwtDecoder.decode(jwtToken);
      _isAdmin = decodedToken['roles'] == 'ADMIN' ||
          (decodedToken['roles'] is List &&
              decodedToken['roles'].contains('ADMIN'));
      if (!_isAdmin) {
        setState(() {
          _statusMessage = 'deductionAdmin.error.adminOnly'.tr;
        });
        return;
      }
      await _loadDeductions();
    } catch (e) {
      setState(() {
        _statusMessage = 'deductionAdmin.error.initFailed'.trParams({
          'error': formatDeductionAdminError(e),
        });
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDeductions() async {
    if (!_isAdmin) return;
    setState(() {
      _isLoading = true;
      _statusMessage = '';
      _showReloginAction = false;
    });
    try {
      List<DeductionRecordModel> deductions;
      final query = _searchController.text.trim();
      if (_searchType == kDeductionSearchTypeHandler && query.isNotEmpty) {
        deductions = await deductionApi.apiDeductionsSearchHandlerGet(
          handler: query,
        );
      } else if (_searchType == kDeductionSearchTypeTimeRange &&
          _startTime != null &&
          _endTime != null) {
        deductions = await deductionApi.apiDeductionsSearchTimeRangeGet(
          startTime: _startTime!.toIso8601String(),
          endTime: _endTime!.add(const Duration(days: 1)).toIso8601String(),
        );
      } else {
        deductions = await deductionApi.apiDeductionsGet();
      }

      deductions.sort((a, b) {
        final aTime = a.deductionTime ?? DateTime(1970);
        final bTime = b.deductionTime ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });

      setState(() {
        _deductions
          ..clear()
          ..addAll(deductions);
        _applyFilters(_searchController.text);
      });

      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwtToken');
      await http.post(
        Uri.parse('http://localhost:8081/api/cache/clear'),
        headers: {'Authorization': 'Bearer $jwtToken'},
      );
    } catch (e) {
      setState(() {
        _statusMessage = 'deductionAdmin.error.loadFailed'.trParams({
          'error': formatDeductionAdminError(e),
        });
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters(String query) {
    final searchQuery = query.trim().toLowerCase();
    _filteredDeductions = _deductions.where((deduction) {
      final handler = (deduction.handler ?? '').toLowerCase();
      final deductionTime = deduction.deductionTime;
      final matchesQuery = _searchType == kDeductionSearchTypeHandler
          ? searchQuery.isEmpty || handler.contains(searchQuery)
          : true;
      final matchesDate = _searchType != kDeductionSearchTypeTimeRange ||
          _startTime == null ||
          _endTime == null ||
          (deductionTime != null &&
              !deductionTime.isBefore(_startTime!) &&
              !deductionTime.isAfter(_endTime!.add(const Duration(days: 1))));
      return matchesQuery && matchesDate;
    }).toList();

    if (_filteredDeductions.isEmpty) {
      _statusMessage = _deductions.isEmpty
          ? 'deductionAdmin.empty.default'.tr
          : 'deductionAdmin.error.filteredEmpty'.tr;
    } else {
      _statusMessage = '';
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: _startTime != null && _endTime != null
          ? DateTimeRange(start: _startTime!, end: _endTime!)
          : null,
      locale: Get.locale ?? const Locale('en', 'US'),
    );
    if (picked != null) {
      setState(() {
        _startTime = picked.start;
        _endTime = picked.end;
      });
      await _loadDeductions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData = controller.currentBodyTheme.value;
      return DashboardPageTemplate(
        theme: themeData,
        title: 'deductionAdmin.page.title'.tr,
        pageType: DashboardPageType.manager,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        actions: [
          if (_isAdmin)
            DashboardPageBarAction(
              icon: Icons.add,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddDeductionPage(),
                  ),
                ).then((value) {
                  if (value == true) _loadDeductions();
                });
              },
              tooltip: 'deductionAdmin.action.add'.tr,
            ),
          DashboardPageBarAction(
            icon: Icons.refresh,
            onPressed: _loadDeductions,
            tooltip: 'deductionAdmin.action.refresh'.tr,
          ),
        ],
        onThemeToggle: controller.toggleBodyTheme,
        body: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: themeData.colorScheme.primary,
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            enabled: _searchType == kDeductionSearchTypeHandler,
                            decoration: InputDecoration(
                              hintText: deductionSearchHintText(_searchType),
                              border: const OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _loadDeductions(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: _searchType,
                          items: [
                            DropdownMenuItem(
                              value: kDeductionSearchTypeHandler,
                              child: Text(deductionSearchTypeLabel(
                                  kDeductionSearchTypeHandler)),
                            ),
                            DropdownMenuItem(
                              value: kDeductionSearchTypeTimeRange,
                              child: Text(deductionSearchTypeLabel(
                                  kDeductionSearchTypeTimeRange)),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _searchType = value;
                            });
                          },
                        ),
                        if (_searchType == kDeductionSearchTypeTimeRange)
                          IconButton(
                            onPressed: _selectDateRange,
                            icon: const Icon(Icons.date_range),
                            tooltip: 'deductionAdmin.filter.tooltip'.tr,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_statusMessage.isNotEmpty &&
                        _filteredDeductions.isEmpty)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_statusMessage),
                              if (_showReloginAction)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: ElevatedButton(
                                    onPressed: () =>
                                        Get.offAllNamed(Routes.login),
                                    child: Text(
                                        'deductionAdmin.action.relogin'.tr),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: _filteredDeductions.length,
                          itemBuilder: (context, index) {
                            final deduction = _filteredDeductions[index];
                            return Card(
                              child: ListTile(
                                title: Text(
                                  'deductionAdmin.card.points'.trParams({
                                    'value': '${deduction.deductedPoints ?? 0}',
                                  }),
                                ),
                                subtitle: Text(
                                  'deductionAdmin.card.summary'.trParams({
                                    'handler': deduction.handler ??
                                        'common.unknown'.tr,
                                    'time': formatDeductionDateTime(
                                      deduction.deductionTime,
                                    ),
                                    'offenseId':
                                        '${deduction.offenseId ?? 'common.none'.tr}',
                                  }),
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => EditDeductionPage(
                                        deduction: deduction,
                                      ),
                                    ),
                                  ).then((value) {
                                    if (value == true) _loadDeductions();
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
      );
    });
  }
}

class AddDeductionPage extends StatefulWidget {
  const AddDeductionPage({super.key});

  @override
  State<AddDeductionPage> createState() => _AddDeductionPageState();
}

class _AddDeductionPageState extends State<AddDeductionPage> {
  final DeductionInformationControllerApi deductionApi =
      DeductionInformationControllerApi();
  final OffenseInformationControllerApi offenseApi =
      OffenseInformationControllerApi();
  final DashboardController controller = Get.find<DashboardController>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _deductedPointsController =
      TextEditingController();
  final TextEditingController _handlerController = TextEditingController();
  final TextEditingController _approverController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();

  bool _isLoading = false;
  int? _selectedOffenseId;
  DateTime? _selectedDeductionDate;
  List<Map<String, dynamic>> _offenseOptions = [];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _deductedPointsController.dispose();
    _handlerController.dispose();
    _approverController.dispose();
    _remarksController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  void _setDeductionDate(DateTime? value) {
    _selectedDeductionDate = value == null ? null : DateUtils.dateOnly(value);
    _dateController.text = formatDeductionDate(_selectedDeductionDate);
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      await deductionApi.initializeWithJwt();
      await offenseApi.initializeWithJwt();
      final offenses = await offenseApi.apiOffensesGet();
      _offenseOptions = offenses
          .map((offense) => {
                'offenseId': offense.offenseId,
                'label': buildDeductionOffenseOptionText(
                  offenseId: offense.offenseId,
                  points: offense.deductedPoints ?? 0,
                  timeText: formatDeductionDate(offense.offenseTime),
                ),
                'points': offense.deductedPoints ?? 0,
                'date': offense.offenseTime == null
                    ? null
                    : DateUtils.dateOnly(offense.offenseTime!),
              })
          .toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'deductionAdmin.error.initFailed'
                  .trParams({'error': formatDeductionAdminError(e)}),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDeductionDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: Get.locale ?? const Locale('en', 'US'),
    );
    if (picked != null) {
      setState(() {
        _setDeductionDate(picked);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedOffenseId == null) return;

    setState(() => _isLoading = true);
    try {
      await deductionApi.apiDeductionsPost(
        body: DeductionRecordModel(
          deductedPoints:
              int.tryParse(_deductedPointsController.text.trim()) ?? 0,
          deductionTime: _selectedDeductionDate,
          handler: _handlerController.text.trim().isEmpty
              ? null
              : _handlerController.text.trim(),
          approver: _approverController.text.trim().isEmpty
              ? null
              : _approverController.text.trim(),
          remarks: _remarksController.text.trim().isEmpty
              ? null
              : _remarksController.text.trim(),
          offenseId: _selectedOffenseId,
        ),
        idempotencyKey: Uuid().v4(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'deductionAdmin.error.createFailed'.trParams({
                'error': formatDeductionAdminError(e),
              }),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildField(
    String fieldKey,
    TextEditingController controllerRef, {
    bool required = false,
    TextInputType? keyboardType,
    int? maxLength,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controllerRef,
        keyboardType: keyboardType,
        maxLength: maxLength,
        readOnly: readOnly,
        onTap: onTap,
        decoration: InputDecoration(
          labelText: deductionFieldLabel(fieldKey, required: required),
          helperText: deductionFieldHelperText(fieldKey),
          border: const OutlineInputBorder(),
        ),
        validator: (value) => validateDeductionField(
          fieldKey,
          value,
          required: required,
          selectedDate: fieldKey == kDeductionFieldDeductionTime
              ? _selectedDeductionDate
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
        title: 'deductionAdmin.form.addTitle'.tr,
        pageType: DashboardPageType.manager,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        body: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: themeData.colorScheme.primary,
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: _selectedOffenseId,
                        items: _offenseOptions.map((option) {
                          return DropdownMenuItem<int>(
                            value: option['offenseId'] as int?,
                            child: Text(option['label'] as String? ?? ''),
                          );
                        }).toList(),
                        onChanged: (value) {
                          final option = _offenseOptions.firstWhere(
                            (item) => item['offenseId'] == value,
                            orElse: () => <String, Object>{},
                          );
                          setState(() {
                            _selectedOffenseId = value;
                            _deductedPointsController.text =
                                '${option['points'] ?? ''}';
                            _setDeductionDate(option['date'] as DateTime?);
                          });
                        },
                        decoration: InputDecoration(
                          labelText: deductionFieldLabel(
                              kDeductionFieldOffenseRecord,
                              required: true),
                          helperText: deductionFieldHelperText(
                              kDeductionFieldOffenseRecord),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) => value == null
                            ? 'deductionAdmin.error.selectOffenseFirst'.tr
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _buildField(
                        kDeductionFieldDeductedPoints,
                        _deductedPointsController,
                        required: true,
                        keyboardType: TextInputType.number,
                      ),
                      _buildField(kDeductionFieldHandler, _handlerController,
                          maxLength: 100),
                      _buildField(kDeductionFieldApprover, _approverController,
                          maxLength: 100),
                      _buildField(kDeductionFieldRemarks, _remarksController,
                          maxLength: 255),
                      _buildField(
                        kDeductionFieldDeductionTime,
                        _dateController,
                        required: true,
                        readOnly: true,
                        onTap: _pickDate,
                      ),
                      ElevatedButton(
                        onPressed: _submit,
                        child: Text('common.submit'.tr),
                      ),
                    ],
                  ),
                ),
              ),
      );
    });
  }
}

class EditDeductionPage extends StatefulWidget {
  final DeductionRecordModel deduction;

  const EditDeductionPage({super.key, required this.deduction});

  @override
  State<EditDeductionPage> createState() => _EditDeductionPageState();
}

class _EditDeductionPageState extends State<EditDeductionPage> {
  final DeductionInformationControllerApi deductionApi =
      DeductionInformationControllerApi();
  final OffenseInformationControllerApi offenseApi =
      OffenseInformationControllerApi();
  final DashboardController controller = Get.find<DashboardController>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _deductedPointsController =
      TextEditingController();
  final TextEditingController _handlerController = TextEditingController();
  final TextEditingController _approverController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();

  bool _isLoading = false;
  int? _selectedOffenseId;
  DateTime? _selectedDeductionDate;
  List<Map<String, dynamic>> _offenseOptions = [];

  @override
  void initState() {
    super.initState();
    _selectedOffenseId = widget.deduction.offenseId;
    _deductedPointsController.text =
        widget.deduction.deductedPoints?.toString() ?? '';
    _handlerController.text = widget.deduction.handler ?? '';
    _approverController.text = widget.deduction.approver ?? '';
    _remarksController.text = widget.deduction.remarks ?? '';
    _setDeductionDate(widget.deduction.deductionTime);
    _initialize();
  }

  @override
  void dispose() {
    _deductedPointsController.dispose();
    _handlerController.dispose();
    _approverController.dispose();
    _remarksController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  void _setDeductionDate(DateTime? value) {
    _selectedDeductionDate = value == null ? null : DateUtils.dateOnly(value);
    _dateController.text = formatDeductionDate(_selectedDeductionDate);
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      await deductionApi.initializeWithJwt();
      await offenseApi.initializeWithJwt();
      final offenses = await offenseApi.apiOffensesGet();
      _offenseOptions = offenses
          .map((offense) => {
                'offenseId': offense.offenseId,
                'label': buildDeductionOffenseOptionText(
                  offenseId: offense.offenseId,
                  points: offense.deductedPoints ?? 0,
                  timeText: formatDeductionDate(offense.offenseTime),
                ),
                'points': offense.deductedPoints ?? 0,
                'date': offense.offenseTime == null
                    ? null
                    : DateUtils.dateOnly(offense.offenseTime!),
              })
          .toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'deductionAdmin.error.initFailed'
                  .trParams({'error': formatDeductionAdminError(e)}),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDeductionDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: Get.locale ?? const Locale('en', 'US'),
    );
    if (picked != null) {
      setState(() {
        _setDeductionDate(picked);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedOffenseId == null) return;

    setState(() => _isLoading = true);
    try {
      await deductionApi.apiDeductionsDeductionIdPut(
        deductionId: widget.deduction.deductionId!,
        body: DeductionRecordModel(
          deductionId: widget.deduction.deductionId,
          deductedPoints:
              int.tryParse(_deductedPointsController.text.trim()) ?? 0,
          deductionTime: _selectedDeductionDate,
          handler: _handlerController.text.trim().isEmpty
              ? null
              : _handlerController.text.trim(),
          approver: _approverController.text.trim().isEmpty
              ? null
              : _approverController.text.trim(),
          remarks: _remarksController.text.trim().isEmpty
              ? null
              : _remarksController.text.trim(),
          offenseId: _selectedOffenseId,
        ),
        idempotencyKey: Uuid().v4(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'deductionAdmin.error.updateFailed'.trParams({
                'error': formatDeductionAdminError(e),
              }),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildField(
    String fieldKey,
    TextEditingController controllerRef, {
    bool required = false,
    TextInputType? keyboardType,
    int? maxLength,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controllerRef,
        keyboardType: keyboardType,
        maxLength: maxLength,
        readOnly: readOnly,
        onTap: onTap,
        decoration: InputDecoration(
          labelText: deductionFieldLabel(fieldKey, required: required),
          helperText: deductionFieldHelperText(fieldKey),
          border: const OutlineInputBorder(),
        ),
        validator: (value) => validateDeductionField(
          fieldKey,
          value,
          required: required,
          selectedDate: fieldKey == kDeductionFieldDeductionTime
              ? _selectedDeductionDate
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
        title: 'deductionAdmin.form.editTitle'.tr,
        pageType: DashboardPageType.manager,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        body: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: themeData.colorScheme.primary,
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: _selectedOffenseId,
                        items: _offenseOptions.map((option) {
                          return DropdownMenuItem<int>(
                            value: option['offenseId'] as int?,
                            child: Text(option['label'] as String? ?? ''),
                          );
                        }).toList(),
                        onChanged: (value) {
                          final option = _offenseOptions.firstWhere(
                            (item) => item['offenseId'] == value,
                            orElse: () => <String, Object>{},
                          );
                          setState(() {
                            _selectedOffenseId = value;
                            _deductedPointsController.text =
                                '${option['points'] ?? ''}';
                            _setDeductionDate(option['date'] as DateTime?);
                          });
                        },
                        decoration: InputDecoration(
                          labelText: deductionFieldLabel(
                              kDeductionFieldOffenseRecord,
                              required: true),
                          helperText: deductionFieldHelperText(
                              kDeductionFieldOffenseRecord),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) => value == null
                            ? 'deductionAdmin.error.selectOffenseFirst'.tr
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _buildField(
                        kDeductionFieldDeductedPoints,
                        _deductedPointsController,
                        required: true,
                        keyboardType: TextInputType.number,
                      ),
                      _buildField(kDeductionFieldHandler, _handlerController,
                          maxLength: 100),
                      _buildField(kDeductionFieldApprover, _approverController,
                          maxLength: 100),
                      _buildField(kDeductionFieldRemarks, _remarksController,
                          maxLength: 255),
                      _buildField(
                        kDeductionFieldDeductionTime,
                        _dateController,
                        required: true,
                        readOnly: true,
                        onTap: _pickDate,
                      ),
                      ElevatedButton(
                        onPressed: _submit,
                        child: Text('common.save'.tr),
                      ),
                    ],
                  ),
                ),
              ),
      );
    });
  }
}
