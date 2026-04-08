import 'package:final_assignment_front/features/api/fine_information_controller_api.dart';
import 'package:final_assignment_front/features/api/payment_record_controller_api.dart';
import 'package:final_assignment_front/features/api/driver_information_controller_api.dart';
import 'package:final_assignment_front/features/api/user_management_controller_api.dart';
import 'package:final_assignment_front/features/dashboard/controllers/user_dashboard_screen_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/features/model/fine_information.dart';
import 'package:final_assignment_front/features/model/payment_record.dart';
import 'package:final_assignment_front/i18n/api_error_localizers.dart';
import 'package:final_assignment_front/i18n/fine_localizers.dart';
import 'package:final_assignment_front/i18n/status_localizers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';

class FineInformationPage extends StatefulWidget {
  const FineInformationPage({super.key});

  @override
  State<FineInformationPage> createState() => _FineInformationPageState();
}

class _FineInformationPageState extends State<FineInformationPage> {
  static const int _pageSize = 100;

  late FineInformationControllerApi fineApi;
  late PaymentRecordControllerApi paymentApi;
  late Future<List<FineInformation>> _finesFuture;
  final UserDashboardController controller =
      Get.find<UserDashboardController>();
  final DriverInformationControllerApi driverApi =
      DriverInformationControllerApi();
  final UserManagementControllerApi userApi = UserManagementControllerApi();
  bool _isLoading = true;
  String _errorMessage = '';
  String? _currentDriverName;

  @override
  void initState() {
    super.initState();
    fineApi = FineInformationControllerApi();
    paymentApi = PaymentRecordControllerApi();
    _initializeFines();
  }

  Future<void> _initializeFines() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwtToken');
      if (jwtToken == null) {
        throw Exception('fine.error.missingLoginOrDriver'.tr);
      }
      await fineApi.initializeWithJwt();
      await paymentApi.initializeWithJwt();
      await driverApi.initializeWithJwt();
      await userApi.initializeWithJwt();
      _currentDriverName = await _fetchDriverName();
      if (_currentDriverName != null && _currentDriverName!.isNotEmpty) {
        await prefs.setString('driverName', _currentDriverName!);
        await prefs.setString('displayName', _currentDriverName!);
      } else {
        _currentDriverName = prefs.getString('driverName') ??
            prefs.getString('displayName') ??
            prefs.getString('userName') ??
            'common.unknown'.tr;
      }
      developer.log('Current Driver Name: $_currentDriverName');
      _finesFuture = _loadUserFines();
      final fines = await _finesFuture;
      developer.log('Loaded Fines: $fines');
    } catch (e) {
      developer.log('Initialization error: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'fine.error.initializeFailed'
            .trParams({'error': localizeApiErrorDetail(e)});
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<String?> _fetchDriverName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = await userApi.apiUsersMeGet();
      final driverInfo = await driverApi.apiDriversMeGet();
      final driverName = driverInfo?.name ??
          prefs.getString('displayName') ??
          prefs.getString('driverName') ??
          user?.realName ??
          user?.username;
      developer.log('Driver name from API: $driverName');
      return driverName;
    } catch (e) {
      developer.log('Error fetching driver name: $e');
      return null;
    }
  }

  Future<List<FineInformation>> _loadUserFines() async {
    try {
      final fines = <FineInformation>[];
      var page = 1;
      while (true) {
        final pageItems = await fineApi.apiFinesMeGet(
          page: page,
          size: _pageSize,
        );
        fines.addAll(pageItems);
        if (pageItems.length < _pageSize) {
          break;
        }
        page++;
      }
      developer.log('Loaded fines for current user: $fines');
      return fines;
    } catch (e) {
      developer.log('Error loading fines: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'fine.error.loadFailed'
            .trParams({'error': localizeApiErrorDetail(e)});
      });
      return [];
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _generateIdempotencyKey() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  double _resolveOutstandingAmount(FineInformation fine) {
    final totalAmount =
        fine.totalAmount ?? ((fine.fineAmount ?? 0) + (fine.lateFee ?? 0));
    final paidAmount = fine.paidAmount ?? 0;
    final outstandingAmount = fine.unpaidAmount ?? (totalAmount - paidAmount);
    return outstandingAmount > 0 ? outstandingAmount : 0;
  }

  bool _canSubmitPayment(FineInformation fine) {
    final rawStatus =
        (fine.paymentStatus ?? fine.status ?? '').trim().toLowerCase();
    if (rawStatus == 'waived') {
      return false;
    }
    return _resolveOutstandingAmount(fine) > 0;
  }

  Future<void> _submitPayment(FineInformation fine) async {
    final outstandingAmount = _resolveOutstandingAmount(fine);
    if (fine.fineId == null || outstandingAmount <= 0) {
      Get.snackbar(
        'common.error'.tr,
        'fine.payment.unavailable'.tr,
        snackPosition: SnackPosition.TOP,
      );
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      await paymentApi.apiPaymentsMePost(
        paymentRecord: PaymentRecordModel(
          fineId: fine.fineId,
          paymentAmount: outstandingAmount,
          paymentMethod: 'WeChat',
          paymentChannel: 'APP',
          remarks: 'Current user self-service payment',
        ),
        idempotencyKey: _generateIdempotencyKey(),
      );
      Get.snackbar(
        'common.confirm'.tr,
        'fine.payment.success'.trParams({
          'amount': outstandingAmount.toStringAsFixed(2),
        }),
        snackPosition: SnackPosition.TOP,
      );
      await _refreshFines();
    } catch (e) {
      developer.log('Error submitting fine payment: $e');
      Get.snackbar(
        'common.error'.tr,
        'fine.payment.failed'.trParams({
          'error': localizeApiErrorDetail(e),
        }),
        snackPosition: SnackPosition.TOP,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshFines() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      _finesFuture = _loadUserFines();
      final fines = await _finesFuture;
      developer.log('Refreshed Fines: $fines');
    } catch (e) {
      developer.log('Error refreshing fines: $e');
      setState(() {
        _errorMessage = 'fine.error.refreshFailed'
            .trParams({'error': localizeApiErrorDetail(e)});
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showFineDetailsDialog(FineInformation fine) {
    final themeData = controller.currentBodyTheme.value;
    final outstandingAmount = _resolveOutstandingAmount(fine);
    final canSubmitPayment = _canSubmitPayment(fine);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: themeData.colorScheme.surfaceContainer,
        title: Text(
          'fine.detail.title'.tr,
          style: themeData.textTheme.titleLarge?.copyWith(
            color: themeData.colorScheme.onSurface,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(
                  'fine.detail.amount'.tr,
                  '\$${fine.fineAmount?.toStringAsFixed(2) ?? "0.00"}',
                  themeData),
              _buildDetailRow(
                  'fine.detail.payee'.tr,
                  fine.payee ?? _currentDriverName ?? 'common.unknown'.tr,
                  themeData),
              _buildDetailRow('fine.detail.account'.tr,
                  fine.accountNumber ?? 'common.unknown'.tr, themeData),
              _buildDetailRow('fine.detail.bank'.tr,
                  fine.bank ?? 'common.unknown'.tr, themeData),
              _buildDetailRow('fine.detail.receipt'.tr,
                  fine.receiptNumber ?? 'common.unknown'.tr, themeData),
              _buildDetailRow(
                  'fine.detail.time'.tr,
                  formatFineUserDateTime(fine.fineDate, fine.fineTime),
                  themeData),
              _buildDetailRow('fine.detail.status'.tr,
                  localizeFineDisplayStatus(fine.status), themeData),
              _buildDetailRow('fine.detail.outstanding'.tr,
                  '\$${outstandingAmount.toStringAsFixed(2)}', themeData),
              _buildDetailRow('fine.detail.remarks'.tr,
                  fine.remarks ?? 'common.none'.tr, themeData),
              if (canSubmitPayment) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _submitPayment(fine);
                    },
                    icon: const Icon(Icons.payment),
                    label: Text(
                      'fine.action.payNow'.trParams({
                        'amount': outstandingAmount.toStringAsFixed(2),
                      }),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'fine.action.close'.tr,
              style: themeData.textTheme.labelMedium?.copyWith(
                color: themeData.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, ThemeData themeData) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
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
    final themeData = controller.currentBodyTheme.value;

    return DashboardPageTemplate(
      theme: themeData,
      title: 'fine.page.title'.tr,
      pageType: DashboardPageType.user,
      onThemeToggle: controller.toggleBodyTheme,
      bodyIsScrollable: true,
      actions: [
        DashboardPageBarAction(
          icon: Icons.refresh,
          onPressed: _refreshFines,
          tooltip: 'fine.action.refresh'.tr,
        ),
      ],
      isLoading: _isLoading,
      errorMessage: _errorMessage.isNotEmpty ? _errorMessage : null,
      floatingActionButton: FloatingActionButton(
        onPressed: _refreshFines,
        backgroundColor: themeData.colorScheme.primary,
        foregroundColor: themeData.colorScheme.onPrimary,
        tooltip: 'fine.action.refresh'.tr,
        child: const Icon(Icons.refresh),
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<FineInformation>>(
              future: _finesFuture,
              builder: (context, snapshot) {
                developer.log(
                    'FutureBuilder state: ${snapshot.connectionState}, data: ${snapshot.data}, error: ${snapshot.error}');
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                          themeData.colorScheme.primary),
                    ),
                  );
                } else if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'fine.error.loadFailed'.trParams(
                          {'error': localizeApiErrorDetail(snapshot.error)}),
                      style: themeData.textTheme.bodyLarge?.copyWith(
                        color: themeData.colorScheme.onSurface,
                      ),
                    ),
                  );
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Text(
                      _currentDriverName != null
                          ? 'fine.empty.byDriver'.trParams(
                              {'driver': _currentDriverName!},
                            )
                          : 'fine.error.driverNotFoundRelogin'.tr,
                      style: themeData.textTheme.bodyLarge?.copyWith(
                        color: themeData.colorScheme.onSurface,
                      ),
                    ),
                  );
                } else {
                  final fines = snapshot.data!;
                  return RefreshIndicator(
                    onRefresh: _refreshFines,
                    child: ListView.builder(
                      itemCount: fines.length,
                      itemBuilder: (context, index) {
                        final record = fines[index];
                        final amount = record.fineAmount ?? 0.0;
                        final payee = record.payee ??
                            _currentDriverName ??
                            'common.unknown'.tr;
                        final date = formatFineUserDateTime(
                          record.fineDate,
                          record.fineTime,
                        );
                        final status = localizeFineDisplayStatus(record.status);
                        final isPaid = isPaidFineStatus(record.status);
                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(vertical: 8.0),
                          color: themeData.colorScheme.surfaceContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          child: ListTile(
                            title: Text(
                              'fine.card.amount'.trParams(
                                  {'amount': amount.toStringAsFixed(2)}),
                              style: themeData.textTheme.bodyLarge?.copyWith(
                                color: themeData.colorScheme.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              'fine.card.summary'.trParams({
                                'payee': payee,
                                'time': date,
                                'status': status,
                              }),
                              style: themeData.textTheme.bodyMedium?.copyWith(
                                color: themeData.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            trailing: Icon(
                              isPaid ? Icons.check_circle : Icons.payment,
                              color: isPaid
                                  ? Colors.green
                                  : themeData.colorScheme.onSurfaceVariant,
                            ),
                            onTap: () {
                              _showFineDetailsDialog(record);
                            },
                          ),
                        );
                      },
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
