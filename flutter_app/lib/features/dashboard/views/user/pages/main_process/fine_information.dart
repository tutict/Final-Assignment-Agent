import 'package:final_assignment_front/features/api/fine_information_controller_api.dart';
import 'package:final_assignment_front/features/api/driver_information_controller_api.dart';
import 'package:final_assignment_front/features/api/user_management_controller_api.dart';
import 'package:final_assignment_front/features/dashboard/controllers/user_dashboard_screen_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/features/model/fine_information.dart';
import 'package:final_assignment_front/i18n/api_error_localizers.dart';
import 'package:final_assignment_front/i18n/fine_localizers.dart';
import 'package:final_assignment_front/i18n/status_localizers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:developer' as developer;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FineInformationPage extends StatefulWidget {
  const FineInformationPage({super.key});

  @override
  State<FineInformationPage> createState() => _FineInformationPageState();
}

class _FineInformationPageState extends State<FineInformationPage> {
  late FineInformationControllerApi fineApi;
  late Future<List<FineInformation>> _finesFuture;
  final UserDashboardController controller =
      Get.find<UserDashboardController>();
  final DriverInformationControllerApi driverApi =
      DriverInformationControllerApi();
  final UserManagementControllerApi userApi = UserManagementControllerApi();
  bool _isLoading = true;
  String _errorMessage = '';
  String? _currentDriverName;
  final Map<String, Widget> _qrCodes = {};

  @override
  void initState() {
    super.initState();
    fineApi = FineInformationControllerApi();
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
      _currentDriverName = prefs.getString('driverName');
      if (_currentDriverName == null && jwtToken != null) {
        _currentDriverName = await _fetchDriverName(jwtToken);
        if (_currentDriverName != null) {
          await prefs.setString('driverName', _currentDriverName!);
        } else {
          _currentDriverName = 'common.unknown'.tr;
        }
        developer.log('Fetched and stored driver name: $_currentDriverName');
      }
      developer.log('Current Driver Name: $_currentDriverName');
      if (jwtToken == null || _currentDriverName == null) {
        throw Exception('fine.error.missingLoginOrDriver'.tr);
      }
      await fineApi.initializeWithJwt();
      await driverApi.initializeWithJwt();
      await userApi.initializeWithJwt();
      _finesFuture = _loadUserFines();
      final fines = await _finesFuture;
      developer.log('Loaded Fines: $fines');
      for (var fine in fines) {
        if (!isPaidFineStatus(fine.status)) await _generateQRCode(fine);
      }
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

  Future<String?> _fetchDriverName(String jwtToken) async {
    try {
      await userApi.initializeWithJwt();
      final prefs = await SharedPreferences.getInstance();
      final storedUsername = prefs.getString('userName');
      Map<String, dynamic>? decoded;
      try {
        decoded = JwtDecoder.decode(jwtToken);
      } catch (_) {}
      final username = storedUsername?.isNotEmpty == true
          ? storedUsername!
          : decoded?['sub']?.toString();
      if (username == null || username.isEmpty) {
        throw Exception('fine.error.usernameMissing'.tr);
      }

      final user = await userApi.apiUsersSearchUsernameGet(username: username);
      if (user?.userId == null) {
        throw Exception('personal.error.currentUserNotFound'.tr);
      }

      await driverApi.initializeWithJwt();
      final driverInfo =
          await driverApi.apiDriversDriverIdGet(driverId: user!.userId!);
      if (driverInfo != null && driverInfo.name != null) {
        final driverName = driverInfo.name!;
        developer.log('Driver name from API: $driverName');
        return driverName;
      } else {
        developer.log('No driver info found for userId: ${user.userId}');
        return null;
      }
    } catch (e) {
      developer.log('Error fetching driver name: $e');
      return null;
    }
  }

  Future<List<FineInformation>> _loadUserFines() async {
    try {
      final allFines = await fineApi.apiFinesGet();
      developer.log('All Fines: $allFines');
      final filteredFines =
          allFines.where((fine) => fine.payee == _currentDriverName).toList();
      developer.log('Filtered Fines for $_currentDriverName: $filteredFines');
      return filteredFines;
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

  Future<void> _generateQRCode(FineInformation fine) async {
    try {
      final paymentUrl =
          'weixin://pay?amount=${fine.fineAmount}&payee=${fine.payee}&receipt=${fine.receiptNumber}';

      final qrWidget = QrImageView(
        data: paymentUrl,
        version: QrVersions.auto,
        size: 200.0,
        backgroundColor: const Color(0xFFFFFFFF),
        eyeStyle: const QrEyeStyle(color: Color(0xFF7CB342)),
        dataModuleStyle: const QrDataModuleStyle(color: Color(0xFF7CB342)),
        embeddedImageStyle: const QrEmbeddedImageStyle(size: Size(60, 60)),
      );
      final qrKey = fine.receiptNumber ?? fine.fineTime ?? 'unknown';
      setState(() {
        _qrCodes[qrKey] = qrWidget;
      });
      developer.log('Generated QR code for fine ${fine.receiptNumber}');
    } catch (e) {
      debugPrint(
          'Failed to generate QR code for fine ${fine.receiptNumber}: $e');
      _showSnackBar(
        'fine.error.generateQrFailed'
            .trParams({'error': localizeApiErrorDetail(e)}),
        isError: true,
      );
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _refreshFines() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _qrCodes.clear();
    });
    try {
      _finesFuture = _loadUserFines();
      final fines = await _finesFuture;
      developer.log('Refreshed Fines: $fines');
      for (var fine in fines) {
        if (!isPaidFineStatus(fine.status)) await _generateQRCode(fine);
      }
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
    final qrKey = fine.receiptNumber ?? fine.fineTime ?? 'unknown';
    final hasQRCode =
        _qrCodes.containsKey(qrKey) && !isPaidFineStatus(fine.status);

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
              _buildDetailRow('fine.detail.payee'.tr,
                  fine.payee ?? 'common.unknown'.tr, themeData),
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
              _buildDetailRow('fine.detail.remarks'.tr,
                  fine.remarks ?? 'common.none'.tr, themeData),
              if (hasQRCode) ...[
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'fine.qr.alipayHint'.tr,
                    style: themeData.textTheme.bodyMedium?.copyWith(
                      color: themeData.colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: SizedBox(
                    width: 200,
                    height: 200,
                    child: _qrCodes[qrKey] ?? const CircularProgressIndicator(),
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
                        final payee = record.payee ?? 'common.unknown'.tr;
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
