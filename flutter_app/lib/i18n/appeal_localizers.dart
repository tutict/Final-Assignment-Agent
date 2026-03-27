import 'package:final_assignment_front/i18n/api_error_localizers.dart';
import 'package:final_assignment_front/i18n/i18n_utils.dart';
import 'package:get/get.dart';

const String kAppealSearchTypeAppealReason = 'appealReason';
const String kAppealSearchTypeAppellantName = 'appellantName';
const String kAppealSearchTypeProcessStatus = 'processStatus';
const String kAppealSearchTypeTimeRange = 'timeRange';

String formatAppealDateTime(
  DateTime? value, {
  String emptyKey = 'common.notFilled',
}) {
  return formatLocalizedDateTime(
    value,
    includeSeconds: false,
    emptyKey: emptyKey,
  );
}

String formatAppealAdminError(dynamic error) {
  return formatLocalizedApiError(
    error,
    requestKey: 'appealAdmin.error.request',
    forbiddenKey: 'appealAdmin.error.forbidden',
    notFoundKey: 'appealAdmin.error.notFound',
    duplicateKey: 'appealAdmin.error.duplicateRequest',
    serverKey: 'appealAdmin.error.server',
    fallbackKey: 'appealAdmin.error.operationFailed',
  );
}

String formatAppealErrorDetail(Object? error) {
  return localizeApiErrorDetail(error);
}

String formatUserAppealError(Object? error) {
  return formatAppealErrorDetail(error);
}

String appealAdminSearchHintText(String searchType) {
  switch (searchType) {
    case kAppealSearchTypeAppealReason:
      return 'appealAdmin.search.appealReason'.tr;
    case kAppealSearchTypeAppellantName:
      return 'appealAdmin.search.appellantName'.tr;
    case kAppealSearchTypeProcessStatus:
      return 'appealAdmin.search.processStatus'.tr;
    case kAppealSearchTypeTimeRange:
    default:
      return 'appealAdmin.search.timeRangeSelected'.tr;
  }
}

String appealAdminSearchTypeLabel(String searchType) {
  switch (searchType) {
    case kAppealSearchTypeAppealReason:
      return 'appealAdmin.filter.byAppealReason'.tr;
    case kAppealSearchTypeAppellantName:
      return 'appealAdmin.filter.byAppellantName'.tr;
    case kAppealSearchTypeProcessStatus:
      return 'appealAdmin.filter.byProcessStatus'.tr;
    case kAppealSearchTypeTimeRange:
    default:
      return 'appealAdmin.filter.byTimeRange'.tr;
  }
}

bool shouldShowAppealAdminReloginAction(String message) {
  return isAnyLocalizedMessage(message, const [
        'appealAdmin.error.unauthorizedMissing',
        'appealAdmin.error.expired',
        'appealAdmin.error.refreshedExpired',
      ]) ||
      hasLocalizedMessagePrefix(
        message,
        key: 'appealAdmin.error.invalidLogin',
        paramName: 'error',
        marker: '__error__',
      );
}
