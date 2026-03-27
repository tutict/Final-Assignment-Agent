import 'package:final_assignment_front/i18n/i18n_utils.dart';
import 'package:final_assignment_front/i18n/status_localizers.dart';
import 'package:final_assignment_front/i18n/api_error_localizers.dart';
import 'package:final_assignment_front/utils/helpers/api_exception.dart';
import 'package:get/get.dart';

String personalFieldLabel(String field) {
  switch (field) {
    case 'name':
      return 'personal.field.name'.tr;
    case 'contactNumber':
      return 'personal.field.contactNumber'.tr;
    case 'idCardNumber':
      return 'personal.field.idCardNumber'.tr;
    case 'driverLicenseNumber':
      return 'personal.field.driverLicenseNumber'.tr;
    case 'password':
      return 'personal.field.password'.tr;
    case 'email':
      return 'personal.field.email'.tr;
    case 'status':
      return 'personal.field.status'.tr;
    case 'createdTime':
      return 'personal.field.createdTime'.tr;
    case 'modifiedTime':
      return 'personal.field.modifiedTime'.tr;
    default:
      return field;
  }
}

String managerPersonalFieldLabel(String field) {
  switch (field) {
    case 'email':
      return 'manager.personal.field.emailAddress'.tr;
    case 'remarks':
      return 'manager.personal.field.remarks'.tr;
    case 'username':
      return 'manager.personal.field.username'.tr;
    default:
      return personalFieldLabel(field);
  }
}

String localizePersonalAccountStatus(String? status) {
  return localizeAccountStatus(
    status,
    activeKey: 'personal.status.active',
    inactiveKey: 'personal.status.inactive',
  );
}

String localizeManagerPersonalAccountStatus(String? status) {
  return localizeAccountStatus(
    status,
    activeKey: 'manager.personal.status.active',
    inactiveKey: 'manager.personal.status.inactive',
  );
}

String personalDisplayValue(
  String? value, {
  String emptyKey = 'common.notFilled',
}) {
  return displayLocalizedValue(value, emptyKey: emptyKey);
}

String formatPersonalDateTime(
  DateTime? dateTime, {
  String emptyKey = 'common.notFilled',
}) {
  return formatLocalizedDateTime(
    dateTime,
    includeSeconds: false,
    emptyKey: emptyKey,
  );
}

String formatPersonalError(dynamic error) {
  if (error is ApiException) {
    return 'personal.error.requestFailed'.trParams({
      'code': '${error.code}',
      'message': localizeApiErrorDetail(error),
    });
  }

  return localizeApiErrorDetail(error);
}
