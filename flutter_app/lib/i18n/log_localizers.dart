import 'package:final_assignment_front/i18n/api_error_localizers.dart';
import 'package:final_assignment_front/i18n/i18n_utils.dart';
import 'package:get/get.dart';

const String kLogSearchTypeTimeRange = 'timeRange';

const String kLoginLogSearchTypeUsername = 'username';
const String kLoginLogSearchTypeLoginResult = 'loginResult';

const String kOperationLogSearchTypeUserId = 'userId';
const String kOperationLogSearchTypeOperationResult = 'operationResult';

String formatLogDateTime(
  DateTime? value, {
  String emptyKey = 'common.notFilled',
}) {
  return formatLocalizedDateTime(value, emptyKey: emptyKey);
}

String localizeLoginLogResult(
  String? result, {
  String emptyKey = 'common.unknown',
}) {
  return localizeCommonResult(result, emptyKey: emptyKey);
}

String formatLoginLogError(dynamic error) {
  return formatLocalizedApiError(
    error,
    requestKey: 'loginLog.error.request',
    forbiddenKey: 'loginLog.error.forbidden',
    notFoundKey: 'loginLog.error.notFound',
    duplicateKey: 'loginLog.error.duplicateRequest',
    serverKey: 'loginLog.error.server',
    fallbackKey: 'loginLog.error.operationFailed',
  );
}

String loginLogSearchHintText(String searchType) {
  switch (searchType) {
    case kLoginLogSearchTypeUsername:
      return 'loginLog.search.username'.tr;
    case kLoginLogSearchTypeLoginResult:
      return 'loginLog.search.loginResult'.tr;
    case kLogSearchTypeTimeRange:
    default:
      return 'loginLog.search.timeRangeSelected'.tr;
  }
}

String loginLogSearchTypeLabel(String searchType) {
  switch (searchType) {
    case kLoginLogSearchTypeUsername:
      return 'loginLog.filter.byUsername'.tr;
    case kLoginLogSearchTypeLoginResult:
      return 'loginLog.filter.byLoginResult'.tr;
    case kLogSearchTypeTimeRange:
    default:
      return 'loginLog.search.timeRangeSelected'.tr;
  }
}

bool shouldShowLoginLogReloginAction(String message) {
  return isAnyLocalizedMessage(message, const [
    'loginLog.error.unauthorized',
    'loginLog.error.expired',
    'loginLog.error.invalidLogin',
    'loginLog.error.adminOnly',
  ]);
}

String localizeOperationLogResult(
  String? result, {
  String emptyKey = 'common.unknown',
}) {
  return localizeLoginLogResult(result, emptyKey: emptyKey);
}

String formatOperationLogError(dynamic error) {
  return formatLocalizedApiError(
    error,
    requestKey: 'operationLog.error.request',
    forbiddenKey: 'operationLog.error.forbidden',
    notFoundKey: 'operationLog.error.notFound',
    duplicateKey: 'operationLog.error.duplicateRequest',
    serverKey: 'operationLog.error.server',
    fallbackKey: 'operationLog.error.operationFailed',
  );
}

String operationLogSearchHintText(String searchType) {
  switch (searchType) {
    case kOperationLogSearchTypeUserId:
      return 'operationLog.search.userId'.tr;
    case kOperationLogSearchTypeOperationResult:
      return 'operationLog.search.operationResult'.tr;
    case kLogSearchTypeTimeRange:
    default:
      return 'operationLog.search.timeRangeSelected'.tr;
  }
}

String operationLogSearchTypeLabel(String searchType) {
  switch (searchType) {
    case kOperationLogSearchTypeUserId:
      return 'operationLog.filter.byUserId'.tr;
    case kOperationLogSearchTypeOperationResult:
      return 'operationLog.filter.byOperationResult'.tr;
    case kLogSearchTypeTimeRange:
    default:
      return 'operationLog.search.timeRangeSelected'.tr;
  }
}

bool shouldShowOperationLogReloginAction(String message) {
  return isAnyLocalizedMessage(message, const [
    'operationLog.error.unauthorized',
    'operationLog.error.expired',
    'operationLog.error.invalidLogin',
    'operationLog.error.adminOnly',
  ]);
}
