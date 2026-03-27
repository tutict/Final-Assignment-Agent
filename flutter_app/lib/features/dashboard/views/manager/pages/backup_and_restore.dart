import 'package:final_assignment_front/features/api/backup_restore_controller_api.dart';
import 'package:final_assignment_front/features/dashboard/controllers/manager_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/features/model/backup_restore.dart';
import 'package:final_assignment_front/i18n/backup_restore_localizers.dart';
import 'package:final_assignment_front/i18n/status_localizers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

String generateIdempotencyKey() => const Uuid().v4();

class BackupAndRestore extends StatefulWidget {
  const BackupAndRestore({super.key});

  @override
  State<BackupAndRestore> createState() => _BackupAndRestoreState();
}

class _BackupAndRestoreState extends State<BackupAndRestore> {
  final BackupRestoreControllerApi backupApi = BackupRestoreControllerApi();
  final DashboardController controller = Get.find<DashboardController>();
  final List<BackupRestore> _backups = [];
  List<BackupRestore> _filteredBackups = [];
  bool _apiInitialized = false;
  bool _isLoading = true;
  bool _isAdmin = false;
  String _errorMessage = '';
  final TextEditingController _fileNameController = TextEditingController();
  final TextEditingController _backupTimeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    _backupTimeController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      if (!await _ensureApiInitialized()) {
        setState(() {
          _errorMessage = 'backupRestore.error.notLoggedIn'.tr;
          _isLoading = false;
        });
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwtToken');
      if (jwtToken == null || jwtToken.isEmpty) {
        throw Exception('backupRestore.error.notLoggedIn'.tr);
      }
      final roles = _extractRoles(jwtToken);
      final isAdmin = roles.any((role) => role.toUpperCase().contains('ADMIN'));
      if (!isAdmin) {
        setState(() {
          _isAdmin = false;
          _errorMessage = 'backupRestore.error.adminOnly'.tr;
          _isLoading = false;
        });
        return;
      }
      setState(() => _isAdmin = true);
      await _loadBackups();
    } catch (e) {
      setState(() {
        _errorMessage = 'backupRestore.error.initFailed'
            .trParams({'error': formatBackupRestoreError(e)});
        _isLoading = false;
      });
    }
  }

  Future<bool> _ensureApiInitialized() async {
    if (_apiInitialized) return true;
    try {
      await backupApi.initializeWithJwt();
      _apiInitialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  List<String> _extractRoles(String jwtToken) {
    final decoded = JwtDecoder.decode(jwtToken);
    final rolesField = decoded['roles'];
    if (rolesField is List) {
      return rolesField.map((role) => role.toString()).toList();
    }
    if (rolesField is String) {
      return [rolesField];
    }
    return [];
  }

  Future<void> _loadBackups() async {
    if (!_isAdmin) {
      setState(() => _isLoading = false);
      return;
    }
    if (!await _ensureApiInitialized()) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'backupRestore.error.notLoggedIn'.tr;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final backups = await backupApi.apiSystemBackupGet();
      setState(() {
        _backups
          ..clear()
          ..addAll(backups);
        _filteredBackups = List<BackupRestore>.from(_backups);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'backupRestore.error.loadFailed'
            .trParams({'error': formatBackupRestoreError(e)});
        _filteredBackups = [];
      });
    }
  }

  void _searchBackups(String type, String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() => _filteredBackups = List.from(_backups));
      return;
    }
    final lowerQuery = trimmed.toLowerCase();
    List<BackupRestore> filtered;
    if (type == 'filename') {
      filtered = _backups
          .where((backup) =>
              (backup.backupFileName ?? '').toLowerCase().contains(lowerQuery))
          .toList();
    } else if (type == 'time') {
      filtered = _backups
          .where(
              (backup) => formatBackupDate(backup.backupTime).contains(trimmed))
          .toList();
    } else {
      filtered = List.from(_backups);
    }
    setState(() => _filteredBackups = filtered);
  }

  Future<void> _createBackup() async {
    if (!mounted || !_isAdmin) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (!await _ensureApiInitialized()) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('backupRestore.error.notLoggedIn'.tr)),
      );
      return;
    }

    try {
      final backupName =
          'backup_${DateTime.now().millisecondsSinceEpoch.toString()}';
      final idempotencyKey = generateIdempotencyKey();

      final newBackup = BackupRestore(
        backupFileName: backupName,
        backupTime: DateTime.now(),
        remarks: 'backupRestore.value.manualCreatedRemarks'.tr,
        status: 'PENDING',
        idempotencyKey: idempotencyKey,
      );

      await backupApi.apiSystemBackupPost(
        backupRestore: newBackup,
        idempotencyKey: idempotencyKey,
      );

      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('backupRestore.success.created'.tr)),
      );
      await _loadBackups();
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'backupRestore.error.createFailed'
                .trParams({'error': formatBackupRestoreError(e)}),
          ),
        ),
      );
    }
  }

  Future<void> _updateBackup(int backupId, BackupRestore updatedBackup) async {
    if (!mounted || !_isAdmin) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (!await _ensureApiInitialized()) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('backupRestore.error.notLoggedIn'.tr)),
      );
      return;
    }

    try {
      final idempotencyKey = generateIdempotencyKey();
      final payload = updatedBackup.copyWith(idempotencyKey: idempotencyKey);
      await backupApi.apiSystemBackupBackupIdPut(
        backupId: backupId,
        backupRestore: payload,
        idempotencyKey: idempotencyKey,
      );
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('backupRestore.success.updated'.tr)),
      );
      await _loadBackups();
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'backupRestore.error.updateFailed'
                .trParams({'error': formatBackupRestoreError(e)}),
          ),
        ),
      );
    }
  }

  Future<void> _restoreBackup(BackupRestore backup) async {
    if (!mounted || !_isAdmin || backup.backupId == null) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (!await _ensureApiInitialized()) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('backupRestore.error.notLoggedIn'.tr)),
      );
      return;
    }

    try {
      final idempotencyKey = generateIdempotencyKey();
      final payload = backup.copyWith(
        restoreTime: DateTime.now(),
        restoreStatus: 'RESTORED',
        status: 'RESTORED',
        idempotencyKey: idempotencyKey,
      );
      await backupApi.apiSystemBackupBackupIdPut(
        backupId: backup.backupId!,
        backupRestore: payload,
        idempotencyKey: idempotencyKey,
      );
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('backupRestore.success.restored'.tr)),
      );
      await _loadBackups();
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'backupRestore.error.restoreFailed'
                .trParams({'error': formatBackupRestoreError(e)}),
          ),
        ),
      );
    }
  }

  Future<void> _deleteBackup(int backupId) async {
    if (!mounted || !_isAdmin) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (!await _ensureApiInitialized()) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('backupRestore.error.notLoggedIn'.tr)),
      );
      return;
    }

    try {
      await backupApi.apiSystemBackupBackupIdDelete(backupId: backupId);
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('backupRestore.success.deleted'.tr)),
      );
      await _loadBackups();
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'backupRestore.error.deleteFailed'
                .trParams({'error': formatBackupRestoreError(e)}),
          ),
        ),
      );
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _goToDetailPage(BackupRestore backup) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BackupDetailPage(backup: backup),
      ),
    ).then((value) {
      if (value == true && mounted) {
        _loadBackups();
      }
    });
  }

  void _showUpdateBackupDialog(BackupRestore backup) {
    final TextEditingController fileNameController =
        TextEditingController(text: backup.backupFileName ?? '');
    final TextEditingController remarksController =
        TextEditingController(text: backup.remarks ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('backupRestore.dialog.editTitle'.tr),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: fileNameController,
                decoration: InputDecoration(
                  labelText: 'backupRestore.field.fileName'.tr,
                ),
              ),
              TextField(
                controller: remarksController,
                decoration: InputDecoration(
                  labelText: 'backupRestore.field.remarks'.tr,
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('common.cancel'.tr),
          ),
          ElevatedButton(
            onPressed: () {
              final String fileName = fileNameController.text.trim();
              final String remarks = remarksController.text.trim();

              if (fileName.isEmpty) {
                _showSnackBar('backupRestore.error.fileNameRequired'.tr);
                return;
              }

              final updatedBackup = backup.copyWith(
                backupFileName: fileName,
                remarks: remarks,
              );

              _updateBackup(backup.backupId!, updatedBackup);
              Navigator.pop(ctx);
            },
            child: Text('common.save'.tr),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return DashboardPageTemplate(
        theme: controller.currentBodyTheme.value,
        title: 'backupRestore.page.title'.tr,
        pageType: DashboardPageType.manager,
        isLoading: _isLoading,
        errorMessage: _errorMessage.isNotEmpty
            ? _errorMessage
            : 'backupRestore.error.adminOnly'.tr,
        body: const SizedBox.shrink(),
      );
    }

    return Obx(() {
      final themeData = controller.currentBodyTheme.value;
      final bool isLight = themeData.brightness == Brightness.light;
      return DashboardPageTemplate(
        theme: themeData,
        title: 'backupRestore.page.title'.tr,
        pageType: DashboardPageType.manager,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        actions: [
          DashboardPageBarAction(
            icon: Icons.add,
            onPressed: _createBackup,
            tooltip: 'backupRestore.action.create'.tr,
          ),
        ],
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _fileNameController,
                      decoration: InputDecoration(
                        labelText: 'backupRestore.search.byFileName'.tr,
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        labelStyle: TextStyle(
                          color: isLight ? Colors.black87 : Colors.white,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: isLight ? Colors.grey : Colors.grey[500]!,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: isLight ? Colors.blue : Colors.blueGrey,
                          ),
                        ),
                      ),
                      onChanged: (value) =>
                          _searchBackups('filename', value.trim()),
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _searchBackups(
                        'filename', _fileNameController.text.trim()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLight ? Colors.blue : Colors.blueGrey,
                      foregroundColor: Colors.white,
                    ),
                    child: Text('common.search'.tr),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _backupTimeController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'backupRestore.search.byBackupTime'.tr,
                        prefixIcon: const Icon(Icons.calendar_today),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        labelStyle: TextStyle(
                          color: isLight ? Colors.black87 : Colors.white,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: isLight ? Colors.grey : Colors.grey[500]!,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: isLight ? Colors.blue : Colors.blueGrey,
                          ),
                        ),
                      ),
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                      ),
                      onTap: () async {
                        FocusScope.of(context).requestFocus(FocusNode());
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2101),
                          builder: (context, child) => Theme(
                            data: ThemeData(
                              primaryColor:
                                  isLight ? Colors.blue : Colors.blueGrey,
                              colorScheme: ColorScheme.light(
                                primary:
                                    isLight ? Colors.blue : Colors.blueGrey,
                              ).copyWith(
                                  secondary:
                                      isLight ? Colors.blue : Colors.blueGrey),
                            ),
                            child: child!,
                          ),
                        );
                        if (pickedDate != null) {
                          final formatted = formatBackupDate(pickedDate);
                          _backupTimeController.text = formatted;
                          _searchBackups('time', formatted);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _searchBackups(
                        'time', _backupTimeController.text.trim()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLight ? Colors.blue : Colors.blueGrey,
                      foregroundColor: Colors.white,
                    ),
                    child: Text('common.search'.tr),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage.isNotEmpty
                        ? Center(
                            child: Text(
                              _errorMessage,
                              style: TextStyle(
                                color: isLight ? Colors.black : Colors.white,
                              ),
                            ),
                          )
                        : _filteredBackups.isEmpty
                            ? Center(
                                child: Text(
                                  'backupRestore.empty.noRecords'.tr,
                                  style: TextStyle(
                                    color:
                                        isLight ? Colors.black : Colors.white,
                                  ),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _loadBackups,
                                child: ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  itemCount: _filteredBackups.length,
                                  itemBuilder: (context, index) {
                                    final backup = _filteredBackups[index];
                                    return Card(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 8.0, horizontal: 16.0),
                                      elevation: 4,
                                      color: isLight
                                          ? Colors.white
                                          : Colors.grey[800],
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10.0),
                                      ),
                                      child: ListTile(
                                        title: Text(
                                          'backupRestore.detail.fileName'
                                              .trParams({
                                            'value': backupDisplayValue(
                                              backup.backupFileName,
                                            ),
                                          }),
                                          style: TextStyle(
                                            color: isLight
                                                ? Colors.black87
                                                : Colors.white,
                                          ),
                                        ),
                                        subtitle: Text(
                                          [
                                            'backupRestore.detail.backupTime'
                                                .trParams({
                                              'value': formatBackupDateTime(
                                                backup.backupTime,
                                              ),
                                            }),
                                            'backupRestore.detail.restoreTime'
                                                .trParams({
                                              'value': formatBackupDateTime(
                                                backup.restoreTime,
                                              ),
                                            }),
                                            'backupRestore.detail.restoreStatus'
                                                .trParams({
                                              'value':
                                                  localizeBackupRestoreStatus(
                                                backup.restoreStatus,
                                              ),
                                            }),
                                          ].join('\n'),
                                          style: TextStyle(
                                            color: isLight
                                                ? Colors.black54
                                                : Colors.white70,
                                          ),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(
                                                Icons.restore,
                                                color: isLight
                                                    ? Colors.green
                                                    : Colors.green[300],
                                              ),
                                              onPressed: () =>
                                                  _restoreBackup(backup),
                                              tooltip:
                                                  'backupRestore.action.restore'
                                                      .tr,
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                Icons.edit,
                                                color: isLight
                                                    ? Colors.blue
                                                    : Colors.blue[300],
                                              ),
                                              onPressed: () =>
                                                  _showUpdateBackupDialog(
                                                      backup),
                                              tooltip:
                                                  'backupRestore.action.edit'
                                                      .tr,
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                Icons.delete,
                                                color: isLight
                                                    ? Colors.red
                                                    : Colors.red[300],
                                              ),
                                              onPressed: () => _deleteBackup(
                                                  backup.backupId!),
                                              tooltip:
                                                  'backupRestore.action.delete'
                                                      .tr,
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                Icons.info,
                                                color: isLight
                                                    ? Colors.blue
                                                    : Colors.blue[300],
                                              ),
                                              onPressed: () =>
                                                  _goToDetailPage(backup),
                                              tooltip:
                                                  'backupRestore.action.viewDetails'
                                                      .tr,
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
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

class BackupDetailPage extends StatefulWidget {
  final BackupRestore backup;

  const BackupDetailPage({super.key, required this.backup});

  @override
  State<BackupDetailPage> createState() => _BackupDetailPageState();
}

class _BackupDetailPageState extends State<BackupDetailPage> {
  final BackupRestoreControllerApi _backupApi = BackupRestoreControllerApi();
  final TextEditingController _remarksController = TextEditingController();
  bool _apiInitialized = false;
  bool _isLoading = false;
  bool _isAdmin = false;
  late BackupRestore _backup;

  @override
  void initState() {
    super.initState();
    _backup = widget.backup;
    _remarksController.text = _backup.remarks ?? '';
    _initialize();
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      if (!await _ensureApiInitialized()) {
        setState(() => _isLoading = false);
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwtToken');
      if (token == null || token.isEmpty) {
        setState(() {
          _isAdmin = false;
          _isLoading = false;
        });
        return;
      }
      final roles = _extractRoles(token);
      setState(() {
        _isAdmin = roles.any((role) => role.toUpperCase().contains('ADMIN'));
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _isAdmin = false;
        _isLoading = false;
      });
    }
  }

  Future<bool> _ensureApiInitialized() async {
    if (_apiInitialized) return true;
    try {
      await _backupApi.initializeWithJwt();
      _apiInitialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  List<String> _extractRoles(String token) {
    final decoded = JwtDecoder.decode(token);
    final rolesField = decoded['roles'];
    if (rolesField is List) {
      return rolesField.map((role) => role.toString()).toList();
    }
    if (rolesField is String) {
      return [rolesField];
    }
    return [];
  }

  Future<void> _updateBackup(int backupId, BackupRestore updatedBackup) async {
    if (!mounted || !_isAdmin) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);

    if (!await _ensureApiInitialized()) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('backupRestore.error.notLoggedIn'.tr)),
      );
      setState(() => _isLoading = false);
      return;
    }

    try {
      final idempotencyKey = generateIdempotencyKey();
      final payload = updatedBackup.copyWith(idempotencyKey: idempotencyKey);
      final result = await _backupApi.apiSystemBackupBackupIdPut(
        backupId: backupId,
        backupRestore: payload,
        idempotencyKey: idempotencyKey,
      );

      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('backupRestore.success.updated'.tr)),
      );
      setState(() {
        _backup = result;
        _isLoading = false;
      });
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'backupRestore.error.updateFailed'
                .trParams({'error': formatBackupRestoreError(e)}),
          ),
        ),
      );
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return DashboardPageTemplate(
        theme: Theme.of(context),
        title: 'backupRestore.detailPage.title'.tr,
        pageType: DashboardPageType.manager,
        isLoading: _isLoading,
        errorMessage: _isLoading ? null : 'backupRestore.error.adminOnly'.tr,
        body: const SizedBox.shrink(),
      );
    }

    return DashboardPageTemplate(
      theme: Theme.of(context),
      title: 'backupRestore.detailPage.title'.tr,
      pageType: DashboardPageType.manager,
      bodyIsScrollable: true,
      padding: EdgeInsets.zero,
      actions: [
        DashboardPageBarAction(
          icon: Icons.edit,
          onPressed: () => _showUpdateBackupDialog(_backup),
          tooltip: 'backupRestore.action.edit'.tr,
        ),
      ],
      isLoading: _isLoading,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  _buildDetailRow(
                    context,
                    'backupRestore.field.backupId'.tr,
                    _backup.backupId?.toString() ?? 'common.none'.tr,
                  ),
                  _buildDetailRow(
                    context,
                    'backupRestore.field.fileName'.tr,
                    backupDisplayValue(_backup.backupFileName),
                  ),
                  _buildDetailRow(
                    context,
                    'backupRestore.field.backupTime'.tr,
                    formatBackupDateTime(_backup.backupTime),
                  ),
                  _buildDetailRow(
                    context,
                    'backupRestore.field.restoreTime'.tr,
                    formatBackupDateTime(_backup.restoreTime),
                  ),
                  _buildDetailRow(
                    context,
                    'backupRestore.field.restoreStatus'.tr,
                    localizeBackupRestoreStatus(_backup.restoreStatus),
                  ),
                  _buildDetailRow(
                    context,
                    'backupRestore.field.remarks'.tr,
                    backupDisplayValue(_backup.remarks),
                  ),
                  _buildDetailRow(
                    context,
                    'backupRestore.field.idempotencyKey'.tr,
                    backupDisplayValue(_backup.idempotencyKey),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    final currentTheme = Theme.of(context);
    final bool isLight = currentTheme.brightness == Brightness.light;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'common.labelWithColon'.trParams({'label': label}),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isLight ? Colors.black87 : Colors.white,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isLight ? Colors.black54 : Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showUpdateBackupDialog(BackupRestore backup) {
    final TextEditingController fileNameController =
        TextEditingController(text: backup.backupFileName ?? '');
    final TextEditingController remarksController =
        TextEditingController(text: backup.remarks ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('backupRestore.dialog.editTitle'.tr),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: fileNameController,
                decoration: InputDecoration(
                  labelText: 'backupRestore.field.fileName'.tr,
                ),
              ),
              TextField(
                controller: remarksController,
                decoration: InputDecoration(
                  labelText: 'backupRestore.field.remarks'.tr,
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('common.cancel'.tr),
          ),
          ElevatedButton(
            onPressed: () {
              final String fileName = fileNameController.text.trim();
              final String remarks = remarksController.text.trim();

              if (fileName.isEmpty) {
                _showSnackBar('backupRestore.error.fileNameRequired'.tr);
                return;
              }

              final updatedBackup = backup.copyWith(
                backupFileName: fileName,
                remarks: remarks,
              );

              _updateBackup(backup.backupId!, updatedBackup);
              Navigator.pop(ctx);
            },
            child: Text('common.save'.tr),
          ),
        ],
      ),
    );
  }
}
