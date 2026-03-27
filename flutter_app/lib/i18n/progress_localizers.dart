import 'package:final_assignment_front/i18n/api_error_localizers.dart';
import 'package:final_assignment_front/i18n/i18n_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

const String progressStatusPending = 'Pending';
const String progressStatusProcessing = 'Processing';
const String progressStatusCompleted = 'Completed';
const String progressStatusArchived = 'Archived';

const List<String> kProgressStatusCategories = [
  progressStatusPending,
  progressStatusProcessing,
  progressStatusCompleted,
  progressStatusArchived,
];

String formatProgressDateTime(
  DateTime? value, {
  bool includeSeconds = false,
  String emptyKey = 'common.notFilled',
}) {
  final pattern = includeSeconds ? 'yyyy-MM-dd HH:mm:ss' : 'yyyy-MM-dd HH:mm';
  return formatOptionalLocalizedPatternDate(
    value,
    pattern,
    emptyKey: emptyKey,
  );
}

String formatProgressError(dynamic error) {
  return formatLocalizedApiError(
    error,
    requestKey: 'progress.error.request',
    forbiddenKey: 'progress.error.permission',
    notFoundKey: 'progress.error.notFound',
    serverKey: 'progress.error.server',
    fallbackKey: 'progress.error.operationFailed',
  );
}

String normalizeProgressStatusCode(String? status) {
  final normalized = status?.trim();
  if (normalized == null || normalized.isEmpty) {
    return '';
  }

  switch (normalized.toLowerCase()) {
    case 'pending':
    case '\u5f85\u5904\u7406':
      return progressStatusPending;
    case 'processing':
    case '\u5904\u7406\u4e2d':
      return progressStatusProcessing;
    case 'completed':
    case '\u5df2\u5b8c\u6210':
      return progressStatusCompleted;
    case 'archived':
    case '\u5df2\u5f52\u6863':
      return progressStatusArchived;
    default:
      return normalized;
  }
}

String localizeProgressStatus(String? status) {
  switch (normalizeProgressStatusCode(status)) {
    case progressStatusPending:
      return 'progress.status.pending'.tr;
    case progressStatusProcessing:
      return 'progress.status.processing'.tr;
    case progressStatusCompleted:
      return 'progress.status.completed'.tr;
    case progressStatusArchived:
      return 'progress.status.archived'.tr;
    default:
      return 'common.unknown'.tr;
  }
}

Color progressStatusColor(String? status, ThemeData themeData) {
  switch (normalizeProgressStatusCode(status)) {
    case progressStatusPending:
      return themeData.colorScheme.secondary;
    case progressStatusProcessing:
      return themeData.colorScheme.primary;
    case progressStatusCompleted:
      return themeData.colorScheme.tertiary;
    case progressStatusArchived:
      return themeData.colorScheme.outline;
    default:
      return themeData.colorScheme.outlineVariant;
  }
}
