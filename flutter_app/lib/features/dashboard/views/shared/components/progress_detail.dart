// ignore_for_file: use_build_context_synchronously
import 'package:final_assignment_front/features/dashboard/controllers/progress_controller.dart';
import 'package:final_assignment_front/features/dashboard/controllers/user_dashboard_screen_controller.dart';
import 'package:final_assignment_front/features/model/progress_item.dart';
import 'package:final_assignment_front/i18n/progress_localizers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProgressDetailPage extends StatefulWidget {
  final ProgressItem item;

  const ProgressDetailPage({super.key, required this.item});

  @override
  State<ProgressDetailPage> createState() => _ProgressDetailPageState();
}

class _ProgressDetailPageState extends State<ProgressDetailPage> {
  final ProgressController progressController = Get.find<ProgressController>();
  final UserDashboardController? dashboardController =
      Get.isRegistered<UserDashboardController>()
          ? Get.find<UserDashboardController>()
          : null;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData =
          dashboardController?.currentBodyTheme.value ?? ThemeData.light();
      return Scaffold(
        backgroundColor: themeData.colorScheme.surface,
        appBar: AppBar(
          title: Text('progress.detail.title'.tr),
          backgroundColor: themeData.colorScheme.primary,
          foregroundColor: themeData.colorScheme.onPrimary,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              _buildDetailRow(
                'progress.detail.id'.tr,
                widget.item.id?.toString() ?? 'common.unknown'.tr,
                themeData,
              ),
              _buildDetailRow(
                  'progress.field.title'.tr, widget.item.title, themeData),
              _buildDetailRow(
                'progress.status'.tr,
                localizeProgressStatus(widget.item.status),
                themeData,
              ),
              _buildDetailRow(
                'progress.submitTime'.tr,
                formatProgressDateTime(
                  widget.item.submitTime,
                  includeSeconds: true,
                ),
                themeData,
              ),
              _buildDetailRow(
                'progress.detail.user'.tr,
                widget.item.username,
                themeData,
              ),
              _buildDetailRow(
                'progress.field.details'.tr,
                widget.item.details ?? 'common.noData'.tr,
                themeData,
              ),
              _buildDetailRow(
                'progress.detail.relatedBusiness'.tr,
                progressController.getBusinessContext(widget.item),
                themeData,
              ),
              if (progressController.isAdmin) ...[
                const SizedBox(height: 20),
                _buildActionButtons(themeData),
              ],
            ],
          ),
        ),
      );
    });
  }

  Widget _buildDetailRow(String label, String? value, ThemeData themeData) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('common.labelWithColon'.trParams({'label': label}),
              style: themeData.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: themeData.colorScheme.onSurface,
              )),
          Expanded(
            child: Text(
              value ?? 'common.unknown'.tr,
              style: themeData.textTheme.bodyMedium?.copyWith(
                color: themeData.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(ThemeData themeData) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton.icon(
          onPressed: () => _updateStatus(progressStatusProcessing, themeData),
          icon: const Icon(Icons.play_arrow),
          label: Text('progress.action.processing'.tr),
        ),
        ElevatedButton.icon(
          onPressed: () => _updateStatus(progressStatusCompleted, themeData),
          icon: const Icon(Icons.check),
          label: Text('progress.action.completed'.tr),
        ),
        ElevatedButton.icon(
          onPressed: () => _showDeleteConfirmationDialog(themeData),
          icon: const Icon(Icons.delete),
          label: Text('progress.action.delete'.tr),
          style: ElevatedButton.styleFrom(
            backgroundColor: themeData.colorScheme.error,
            foregroundColor: themeData.colorScheme.onError,
          ),
        ),
      ],
    );
  }

  Future<void> _updateStatus(String newStatus, ThemeData themeData) async {
    if (widget.item.id == null) {
      _showSnackBar('progress.error.idMissingUpdate'.tr,
          isError: true, themeData: themeData);
      return;
    }
    try {
      await progressController.updateProgressStatus(widget.item.id!, newStatus);
      if (mounted) {
        _showSnackBar('progress.success.statusUpdated'.tr,
            themeData: themeData);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          'progress.error.statusUpdateFailed'
              .trParams({'error': formatProgressError(e)}),
          isError: true,
          themeData: themeData,
        );
      }
    }
  }

  void _showDeleteConfirmationDialog(ThemeData themeData) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('progress.delete.confirmTitle'.tr),
        content: Text('progress.delete.confirmBody'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('common.cancel'.tr),
          ),
          ElevatedButton(
            onPressed: () async {
              if (widget.item.id == null) {
                _showSnackBar(
                  'progress.error.idMissingDelete'.tr,
                  isError: true,
                  themeData: themeData,
                );
                Navigator.pop(ctx);
                return;
              }
              try {
                await progressController.deleteProgress(widget.item.id!);
                if (mounted) {
                  _showSnackBar('progress.success.deleted'.tr,
                      themeData: themeData);
                  Navigator.pop(context, true);
                }
              } catch (e) {
                if (mounted) {
                  _showSnackBar(
                    'progress.error.deleteFailed'
                        .trParams({'error': formatProgressError(e)}),
                    isError: true,
                    themeData: themeData,
                  );
                }
              }
              Navigator.pop(ctx);
            },
            child: Text('progress.action.delete'.tr),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message,
      {bool isError = false, required ThemeData themeData}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? themeData.colorScheme.error
            : themeData.colorScheme.primary,
      ),
    );
  }
}
