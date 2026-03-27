import 'package:final_assignment_front/features/dashboard/controllers/manager_dashboard_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/manager/pages/main_process/appeal_management.dart';
import 'package:final_assignment_front/features/dashboard/views/manager/pages/main_process/deduction_management.dart';
import 'package:final_assignment_front/features/dashboard/views/manager/pages/main_process/driver_list.dart';
import 'package:final_assignment_front/features/dashboard/views/manager/pages/main_process/fine_list.dart';
import 'package:final_assignment_front/features/dashboard/views/manager/pages/main_process/offense_list.dart';
import 'package:final_assignment_front/features/dashboard/views/manager/pages/main_process/vehicle_list.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ManagerBusinessProcessing extends StatefulWidget {
  const ManagerBusinessProcessing({super.key});

  @override
  State<ManagerBusinessProcessing> createState() =>
      _ManagerBusinessProcessingState();
}

class _ManagerBusinessProcessingState extends State<ManagerBusinessProcessing> {
  late DashboardController controller;

  final List<Map<String, dynamic>> businessOptions = [
    {
      'titleKey': 'manager.business.appeal',
      'icon': Icons.gavel,
      'route': const AppealManagementAdmin(),
    },
    {
      'titleKey': 'manager.business.deduction',
      'icon': Icons.score,
      'route': const DeductionManagement(),
    },
    {
      'titleKey': 'manager.business.driver',
      'icon': Icons.person,
      'route': const DriverList(),
    },
    {
      'titleKey': 'manager.business.fine',
      'icon': Icons.payment,
      'route': const FineList(),
    },
    {
      'titleKey': 'manager.business.vehicle',
      'icon': Icons.directions_car,
      'route': const VehicleList(),
    },
    {
      'titleKey': 'manager.business.offense',
      'icon': Icons.warning,
      'route': const OffenseList(),
    },
  ];

  @override
  void initState() {
    super.initState();
    try {
      controller = Get.find<DashboardController>();
    } catch (e) {
      debugPrint('DashboardController not found: $e');
      controller = Get.put(DashboardController());
    }
  }

  void _navigateToBusiness(Widget route) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => route),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeData = controller.currentBodyTheme.value;
      final colorScheme = themeData.colorScheme;

      return DashboardPageTemplate(
        theme: themeData,
        title: 'manager.business.title'.tr,
        pageType: DashboardPageType.manager,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        onThemeToggle: controller.toggleBodyTheme,
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 4 / 3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: businessOptions.length,
            itemBuilder: (context, index) {
              final option = businessOptions[index];
              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _navigateToBusiness(option['route'] as Widget),
                child: Ink(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: colorScheme.primaryContainer
                              .withValues(alpha: 0.6),
                          child: Icon(
                            option['icon'] as IconData,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          (option['titleKey'] as String).tr,
                          style: themeData.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'manager.business.enter'.tr,
                          style: themeData.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    });
  }
}
