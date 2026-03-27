import 'dart:convert';

import 'package:final_assignment_front/features/api/appeal_management_controller_api.dart';
import 'package:final_assignment_front/features/model/appeal_record.dart';
import 'package:final_assignment_front/features/model/progress_item.dart';
import 'package:final_assignment_front/i18n/api_error_localizers.dart';
import 'package:final_assignment_front/i18n/progress_localizers.dart';
import 'package:final_assignment_front/utils/helpers/api_exception.dart';
import 'package:final_assignment_front/utils/services/api_client.dart';
import 'package:final_assignment_front/utils/ui/ui_utils.dart';
import 'package:get/get.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProgressController extends GetxController {
  final ApiClient apiClient = ApiClient();
  final AppealManagementControllerApi appealApi =
      AppealManagementControllerApi();
  final RxList<ProgressItem> progressItems = <ProgressItem>[].obs;
  final RxList<ProgressItem> filteredItems = <ProgressItem>[].obs;
  final RxList<AppealRecordModel> appeals = <AppealRecordModel>[].obs;
  final RxList<String> statusCategories =
      List<String>.from(kProgressStatusCategories).obs;
  final RxBool isLoading = false.obs;
  final RxString errorMessage = ''.obs;
  final RxBool _isAdmin = false.obs;

  String _errorMessageOrHttpStatus(String body, int statusCode) {
    return body.isNotEmpty ? body : localizeHttpStatusError(statusCode);
  }

  void _showSnackbar(String title, String message, {bool isError = false}) {
    final ctx = Get.context;
    if (ctx != null) {
      if (isError) {
        AppSnackbar.showError(ctx, message: message);
      } else {
        AppSnackbar.showSuccess(ctx, message: message);
      }
    } else {
      Get.snackbar(
        title,
        message,
        snackPosition: SnackPosition.TOP,
        backgroundColor: isError ? Get.theme.colorScheme.error : null,
        colorText: isError ? Get.theme.colorScheme.onError : null,
      );
    }
  }

  @override
  void onInit() {
    super.onInit();
    _loadUserRole();
    fetchProgress();
    fetchAppeals();
  }

  bool get isAdmin => _isAdmin.value;

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwtToken');
    if (token == null || token.isEmpty) {
      _isAdmin.value = false;
      return;
    }
    try {
      final decoded = JwtDecoder.decode(token);
      final roles = decoded['roles'];
      if (roles is List) {
        _isAdmin.value = roles
            .map((e) => e.toString())
            .any((role) => role.contains('ADMIN'));
      } else if (roles is String) {
        _isAdmin.value = roles.contains('ADMIN');
      } else {
        _isAdmin.value = false;
      }
    } catch (_) {
      _isAdmin.value = false;
    }
  }

  Future<void> fetchAppeals() async {
    try {
      await appealApi.initializeWithJwt();
      final response = await appealApi.apiClient.invokeAPI(
        '/api/appeals',
        'GET',
        const [],
        null,
        {},
        const {},
        null,
        ['bearerAuth'],
      );
      if (response.statusCode == 404 || response.body.isEmpty) {
        appeals.clear();
        return;
      }
      if (response.statusCode >= 400) {
        throw ApiException(
          response.statusCode,
          _errorMessageOrHttpStatus(response.body, response.statusCode),
        );
      }
      final List<dynamic> data = jsonDecode(response.body);
      appeals.value = data
          .map((json) =>
              AppealRecordModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      errorMessage.value = formatProgressError(e);
      _showSnackbar(
        'common.error'.tr,
        'progress.error.loadAppeals'
            .trParams({'error': formatProgressError(e)}),
        isError: true,
      );
    }
  }

  Future<void> fetchProgress() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwtToken');
      if (jwtToken == null) {
        throw Exception('auth.error.loginRequiredForReset'.tr);
      }

      final response = await apiClient.invokeAPI(
        '/api/progress',
        'GET',
        [],
        null,
        {'Authorization': 'Bearer $jwtToken'},
        {},
        'application/json',
        ['bearerAuth'],
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        progressItems.value =
            data.map((json) => ProgressItem.fromJson(json)).toList();
        filteredItems.value = progressItems;
      } else {
        throw ApiException(
            response.statusCode, 'progress.error.fetchFailed'.tr);
      }
    } catch (e) {
      errorMessage.value = formatProgressError(e);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> submitProgress(String title, String? details,
      {int? appealId}) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwtToken');
      final username = prefs.getString('userName');
      if (jwtToken == null || username == null) {
        throw Exception('auth.error.loginRequiredForReset'.tr);
      }

      final progressItem = ProgressItem(
        title: title,
        details: details,
        status: progressStatusPending,
        submitTime: DateTime.now(),
        username: username,
        appealId: appealId,
      );

      final response = await apiClient.invokeAPI(
        '/api/progress',
        'POST',
        [],
        progressItem.toJson(),
        {
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'application/json',
        },
        {},
        'application/json',
        ['bearerAuth'],
      );

      if (response.statusCode == 201) {
        await fetchProgress();
        _showSnackbar('common.success'.tr, 'progress.success.submitted'.tr);
      } else {
        throw ApiException(
          response.statusCode,
          'progress.error.submitFailed'.tr,
        );
      }
    } catch (e) {
      errorMessage.value = formatProgressError(e);
      _showSnackbar('common.error'.tr, errorMessage.value, isError: true);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> updateProgress(
    int id,
    String title,
    String? details,
    String status, {
    int? appealId,
  }) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwtToken');
      final username = prefs.getString('username');
      if (jwtToken == null || username == null) {
        throw Exception('auth.error.loginRequiredForReset'.tr);
      }

      final progressItem = progressItems.firstWhere((item) => item.id == id);
      final updatedItem = progressItem.copyWith(
        title: title,
        details: details,
        status: status,
        submitTime: DateTime.now(),
        username: username,
        appealId: appealId ?? progressItem.appealId,
      );

      final response = await apiClient.invokeAPI(
        '/api/progress/$id',
        'PUT',
        [],
        updatedItem.toJson(),
        {
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'application/json',
        },
        {},
        'application/json',
        ['bearerAuth'],
      );

      if (response.statusCode == 200) {
        await fetchProgress();
        _showSnackbar('common.success'.tr, 'progress.success.updated'.tr);
      } else {
        throw ApiException(
          response.statusCode,
          'progress.error.updateFailed'.tr,
        );
      }
    } catch (e) {
      errorMessage.value = formatProgressError(e);
      _showSnackbar('common.error'.tr, errorMessage.value, isError: true);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> updateProgressStatus(int id, String newStatus) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwtToken');
      if (jwtToken == null) {
        throw Exception('auth.error.loginRequiredForReset'.tr);
      }

      final progressItem = progressItems.firstWhere((item) => item.id == id);
      final updatedItem = progressItem.copyWith(
        status: newStatus,
        submitTime: DateTime.now(),
      );

      final response = await apiClient.invokeAPI(
        '/api/progress/$id',
        'PUT',
        [],
        updatedItem.toJson(),
        {
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'application/json',
        },
        {},
        'application/json',
        ['bearerAuth'],
      );

      if (response.statusCode == 200) {
        await fetchProgress();
        _showSnackbar('common.success'.tr, 'progress.success.statusUpdated'.tr);
      } else {
        throw ApiException(
          response.statusCode,
          'progress.error.statusUpdateFailed'
              .trParams({'error': 'common.unknown'.tr}),
        );
      }
    } catch (e) {
      errorMessage.value = formatProgressError(e);
      _showSnackbar('common.error'.tr, errorMessage.value, isError: true);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> deleteProgress(int id) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwtToken');
      if (jwtToken == null) {
        throw Exception('auth.error.loginRequiredForReset'.tr);
      }

      final response = await apiClient.invokeAPI(
        '/api/progress/$id',
        'DELETE',
        [],
        null,
        {'Authorization': 'Bearer $jwtToken'},
        {},
        'application/json',
        ['bearerAuth'],
      );

      if (response.statusCode == 204) {
        await fetchProgress();
        _showSnackbar('common.success'.tr, 'progress.success.deleted'.tr);
      } else {
        throw ApiException(
          response.statusCode,
          'progress.error.deleteFailed'
              .trParams({'error': 'common.unknown'.tr}),
        );
      }
    } catch (e) {
      errorMessage.value = formatProgressError(e);
      _showSnackbar('common.error'.tr, errorMessage.value, isError: true);
    } finally {
      isLoading.value = false;
    }
  }

  void filterByStatus(String status) {
    final targetStatus = normalizeProgressStatusCode(status);
    filteredItems.value = progressItems
        .where(
            (item) => normalizeProgressStatusCode(item.status) == targetStatus)
        .toList();
  }

  Future<void> fetchProgressByTimeRange(DateTime start, DateTime end) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwtToken');
      if (jwtToken == null) {
        throw Exception('auth.error.loginRequiredForReset'.tr);
      }

      final response = await apiClient.invokeAPI(
        '/api/progress?start=${start.toIso8601String()}&end=${end.toIso8601String()}',
        'GET',
        [],
        null,
        {'Authorization': 'Bearer $jwtToken'},
        {},
        'application/json',
        ['bearerAuth'],
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        filteredItems.value =
            data.map((json) => ProgressItem.fromJson(json)).toList();
      } else {
        throw ApiException(
          response.statusCode,
          'progress.error.fetchByTimeRangeFailed'.tr,
        );
      }
    } catch (e) {
      errorMessage.value = formatProgressError(e);
    } finally {
      isLoading.value = false;
    }
  }

  void clearTimeRangeFilter() {
    filteredItems.value = progressItems;
  }

  String getBusinessContext(ProgressItem item) {
    final contexts = <String>[];
    if (item.appealId != null) {
      contexts.add(
        'progress.context.appealId'.trParams({'id': '${item.appealId}'}),
      );
    }
    if (item.deductionId != null) {
      contexts.add(
        'progress.context.deductionId'.trParams({'id': '${item.deductionId}'}),
      );
    }
    if (item.driverId != null) {
      contexts.add(
        'progress.context.driverId'.trParams({'id': '${item.driverId}'}),
      );
    }
    if (item.fineId != null) {
      contexts.add(
        'progress.context.fineId'.trParams({'id': '${item.fineId}'}),
      );
    }
    if (item.vehicleId != null) {
      contexts.add(
        'progress.context.vehicleId'.trParams({'id': '${item.vehicleId}'}),
      );
    }
    if (item.offenseId != null) {
      contexts.add(
        'progress.context.offenseId'.trParams({'id': '${item.offenseId}'}),
      );
    }
    return contexts.isNotEmpty
        ? contexts.join(', ')
        : 'progress.context.noRelatedBusiness'.tr;
  }
}
