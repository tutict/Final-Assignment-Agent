import 'package:final_assignment_front/i18n/api_error_localizers.dart';
import 'package:final_assignment_front/i18n/i18n_utils.dart';
import 'package:final_assignment_front/utils/helpers/api_exception.dart';
import 'package:get/get.dart';

String formatBackupDate(DateTime? dateTime) {
  return formatLocalizedDate(dateTime?.toLocal());
}

String formatBackupDateTime(DateTime? dateTime) {
  return formatLocalizedDateTime(
    dateTime?.toLocal(),
    emptyKey: 'common.none',
  );
}

String backupDisplayValue(String? value) {
  return displayLocalizedValue(value, emptyKey: 'common.none');
}

String formatBackupRestoreError(dynamic error) {
  if (error is ApiException) {
    final message = error.message.isNotEmpty
        ? localizeApiErrorDetail(error)
        : 'backupRestore.error.server'.tr;
    return '$message (HTTP ${error.code})';
  }
  return localizeApiErrorDetail(error);
}
