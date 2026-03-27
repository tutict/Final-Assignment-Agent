import 'package:final_assignment_front/config/routes/app_routes.dart';
import 'package:final_assignment_front/features/dashboard/controllers/progress_controller.dart';
import 'package:final_assignment_front/features/dashboard/controllers/manager_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/features/model/appeal_record.dart';
import 'package:final_assignment_front/i18n/progress_localizers.dart';
import 'package:final_assignment_front/utils/ui/ui_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProgressManagementPage extends StatelessWidget {
  const ProgressManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final DashboardController dashboardController =
        Get.find<DashboardController>();
    final ProgressController progressController =
        Get.find<ProgressController>();

    return Obx(() {
      final themeData = dashboardController.currentBodyTheme.value;
      final actions = <DashboardPageBarAction>[];
      if (progressController.isAdmin) {
        actions.add(
          DashboardPageBarAction(
            icon: Icons.add,
            tooltip: 'progress.action.createTooltip'.tr,
            onPressed: () => _showCreateProgressDialog(
                context, progressController, themeData),
          ),
        );
      }
      return DashboardPageTemplate(
        theme: themeData,
        title: 'progress.pageTitle'.tr,
        pageType: DashboardPageType.manager,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        actions: actions,
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Filter controls
              _buildFilterControls(context, progressController, themeData),
              const SizedBox(height: 16),
              // Progress list
              Expanded(
                child: progressController.isLoading.value
                    ? Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(
                              themeData.colorScheme.primary),
                        ),
                      )
                    : progressController.errorMessage.isNotEmpty
                        ? Center(
                            child: Text(
                              progressController.errorMessage.value,
                              style: themeData.textTheme.bodyLarge?.copyWith(
                                color: themeData.colorScheme.error,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )
                        : !progressController.isAdmin
                            ? Center(
                                child: Text(
                                  'progress.error.adminOnly'.tr,
                                  style:
                                      themeData.textTheme.titleMedium?.copyWith(
                                    color:
                                        themeData.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              )
                            : progressController.filteredItems.isEmpty
                                ? Center(
                                    child: Text(
                                      'progress.empty'.tr,
                                      style: themeData.textTheme.titleMedium
                                          ?.copyWith(
                                        color: themeData
                                            .colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount:
                                        progressController.filteredItems.length,
                                    itemBuilder: (context, index) {
                                      final item = progressController
                                          .filteredItems[index];
                                      return Card(
                                        elevation: 3,
                                        color: themeData
                                            .colorScheme.surfaceContainer,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 16, vertical: 12),
                                          leading: CircleAvatar(
                                            backgroundColor: _getStatusColor(
                                                item.status, themeData),
                                            radius: 24,
                                            child: Text(
                                              item.title.isNotEmpty
                                                  ? item.title[0].toUpperCase()
                                                  : '?',
                                              style: themeData
                                                  .textTheme.titleMedium
                                                  ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          title: Text(
                                            item.title,
                                            style: themeData
                                                .textTheme.titleMedium
                                                ?.copyWith(
                                              color: themeData
                                                  .colorScheme.onSurface,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const SizedBox(height: 4),
                                              Text(
                                                'progress.detail.status'
                                                    .trParams({
                                                  'value':
                                                      localizeProgressStatus(
                                                          item.status),
                                                }),
                                                style: themeData
                                                    .textTheme.bodyMedium
                                                    ?.copyWith(
                                                  color: _getStatusColor(
                                                      item.status, themeData),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              Text(
                                                'progress.detail.submitTime'
                                                    .trParams({
                                                  'value':
                                                      formatProgressDateTime(
                                                    item.submitTime,
                                                  ),
                                                }),
                                                style: themeData
                                                    .textTheme.bodyMedium
                                                    ?.copyWith(
                                                  color: themeData.colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                              Text(
                                                progressController
                                                    .getBusinessContext(item),
                                                style: themeData
                                                    .textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: themeData.colorScheme
                                                      .onSurfaceVariant
                                                      .withValues(alpha: 0.8),
                                                ),
                                              ),
                                            ],
                                          ),
                                          trailing: progressController.isAdmin
                                              ? PopupMenuButton<String>(
                                                  icon: Icon(
                                                    Icons.more_vert,
                                                    color: themeData.colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                  onSelected: (value) {
                                                    if (value == 'edit') {
                                                      Get.toNamed(
                                                              Routes
                                                                  .progressDetailPage,
                                                              arguments: item)
                                                          ?.then((result) {
                                                        if (result == true) {
                                                          progressController
                                                              .fetchProgress();
                                                        }
                                                      });
                                                    } else if (value ==
                                                        'delete') {
                                                      _showDeleteConfirmationDialog(
                                                          context,
                                                          item.id!,
                                                          progressController,
                                                          themeData);
                                                    } else if (value.startsWith(
                                                        'update_')) {
                                                      final newStatus =
                                                          value.split('_')[1];
                                                      progressController
                                                          .updateProgressStatus(
                                                              item.id!,
                                                              newStatus);
                                                    }
                                                  },
                                                  itemBuilder: (context) => [
                                                    PopupMenuItem(
                                                      value: 'edit',
                                                      child: Text(
                                                        'progress.action.viewEdit'
                                                            .tr,
                                                        style: themeData
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                          color: themeData
                                                              .colorScheme
                                                              .onSurface,
                                                        ),
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'delete',
                                                      child: Text(
                                                        'progress.action.delete'
                                                            .tr,
                                                        style: themeData
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                          color: themeData
                                                              .colorScheme
                                                              .error,
                                                        ),
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'update_Pending',
                                                      child: Text(
                                                        'progress.action.setPending'
                                                            .tr,
                                                        style: themeData
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                          color: themeData
                                                              .colorScheme
                                                              .onSurface,
                                                        ),
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value:
                                                          'update_Processing',
                                                      child: Text(
                                                        'progress.action.setProcessing'
                                                            .tr,
                                                        style: themeData
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                          color: themeData
                                                              .colorScheme
                                                              .onSurface,
                                                        ),
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'update_Completed',
                                                      child: Text(
                                                        'progress.action.setCompleted'
                                                            .tr,
                                                        style: themeData
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                          color: themeData
                                                              .colorScheme
                                                              .onSurface,
                                                        ),
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'update_Archived',
                                                      child: Text(
                                                        'progress.action.setArchived'
                                                            .tr,
                                                        style: themeData
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                          color: themeData
                                                              .colorScheme
                                                              .onSurface,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : null,
                                          onTap: () => Get.toNamed(
                                                  Routes.progressDetailPage,
                                                  arguments: item)
                                              ?.then((result) {
                                            if (result == true) {
                                              progressController
                                                  .fetchProgress();
                                            }
                                          }),
                                        ),
                                      );
                                    },
                                  ),
              ),
            ],
          ),
        ),
      );
    });
  }

  void _showCreateProgressDialog(BuildContext context,
      ProgressController controller, ThemeData themeData) {
    final titleController = TextEditingController();
    final detailsController = TextEditingController();
    AppealRecordModel? selectedAppeal;
    AppDialog.showCustomDialog(
      context: context,
      theme: themeData,
      title: 'progress.dialog.submitTitle'.tr,
      content: StatefulBuilder(
        builder: (ctx, setState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: 'progress.field.title'.tr,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: detailsController,
                decoration: InputDecoration(
                  labelText: 'progress.field.detailsOptional'.tr,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Obx(
                () => DropdownButtonFormField<AppealRecordModel>(
                  decoration: InputDecoration(
                    labelText: 'progress.field.relatedAppealOptional'.tr,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  initialValue: selectedAppeal,
                  items: controller.appeals.map((appeal) {
                    return DropdownMenuItem(
                      value: appeal,
                      child: Text('progress.field.appealOption'.trParams({
                        'name': appeal.appellantName ?? 'common.unknown'.tr,
                        'id': '${appeal.appealId}',
                      })),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => selectedAppeal = value),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'common.cancel'.tr,
            style: themeData.textTheme.labelLarge?.copyWith(
              color: themeData.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            final title = titleController.text.trim();
            if (title.isEmpty) {
              AppSnackbar.showError(
                context,
                message: 'progress.validation.titleRequired'.tr,
                theme: themeData,
              );
              return;
            }
            controller.submitProgress(
              title,
              detailsController.text.isNotEmpty ? detailsController.text : null,
              appealId: selectedAppeal?.appealId,
            );
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: themeData.colorScheme.primary,
            foregroundColor: themeData.colorScheme.onPrimary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('common.submit'.tr),
        ),
      ],
    ).whenComplete(() {
      titleController.dispose();
      detailsController.dispose();
    });
  }

  Widget _buildFilterControls(BuildContext context,
      ProgressController controller, ThemeData themeData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: controller.statusCategories.map((status) {
            return Obx(() => FilterChip(
                  label: Text(localizeProgressStatus(status)),
                  selected: controller.filteredItems.any((item) =>
                      normalizeProgressStatusCode(item.status) ==
                      normalizeProgressStatusCode(status)),
                  onSelected: (selected) {
                    controller.filterByStatus(status);
                  },
                  selectedColor: themeData.colorScheme.primaryContainer,
                  checkmarkColor: themeData.colorScheme.onPrimaryContainer,
                  labelStyle: themeData.textTheme.bodyMedium?.copyWith(
                    color: themeData.colorScheme.onSurface,
                  ),
                ));
          }).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(Icons.date_range,
                    color: themeData.colorScheme.primary),
                label: Text(
                  'progress.filter.selectTimeRange'.tr,
                  style: themeData.textTheme.bodyMedium
                      ?.copyWith(color: themeData.colorScheme.primary),
                ),
                onPressed: () => _showDateRangePicker(controller, themeData),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: themeData.colorScheme.outline),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.clear, color: themeData.colorScheme.error),
              onPressed: () {
                controller.clearTimeRangeFilter();
                controller.fetchProgress();
              },
              tooltip: 'progress.filter.clearTooltip'.tr,
            ),
          ],
        ),
      ],
    );
  }

  void _showDateRangePicker(
      ProgressController controller, ThemeData themeData) async {
    final initialStartDate = DateTime.now().subtract(const Duration(days: 7));
    final initialEndDate = DateTime.now();

    final pickedRange = await showDateRangePicker(
      context: Get.context!,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: Get.locale ?? const Locale('en', 'US'),
      initialDateRange: DateTimeRange(
        start: initialStartDate,
        end: initialEndDate,
      ),
      builder: (context, child) {
        return Theme(
          data: themeData.copyWith(
            colorScheme: themeData.colorScheme.copyWith(
              primary: themeData.colorScheme.primary,
              onPrimary: themeData.colorScheme.onPrimary,
              surface: themeData.colorScheme.surface,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: themeData.colorScheme.primary,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedRange != null) {
      await controller.fetchProgressByTimeRange(
          pickedRange.start, pickedRange.end);
    }
  }

  void _showDeleteConfirmationDialog(BuildContext context, int progressId,
      ProgressController controller, ThemeData themeData) {
    AppDialog.showConfirmDialog(
      context: context,
      theme: themeData,
      title: 'progress.delete.confirmTitle'.tr,
      message: 'progress.delete.confirmMessage'.tr,
      confirmText: 'progress.action.delete'.tr,
      confirmColor: themeData.colorScheme.error,
      leadingIcon: Icons.warning_amber_rounded,
      onConfirmed: () => controller.deleteProgress(progressId),
    );
  }

  Color _getStatusColor(String? status, ThemeData themeData) {
    return progressStatusColor(status, themeData);
  }
}
