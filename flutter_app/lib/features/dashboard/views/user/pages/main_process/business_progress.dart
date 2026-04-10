import 'package:final_assignment_front/features/dashboard/controllers/user_dashboard_screen_controller.dart';
import 'package:final_assignment_front/features/dashboard/views/shared/widgets/dashboard_page_template.dart';
import 'package:final_assignment_front/features/dashboard/views/user/pages/main_process/fine_information.dart';
import 'package:final_assignment_front/features/dashboard/views/user/pages/main_process/online_processing_progress.dart';
import 'package:final_assignment_front/features/dashboard/views/user/pages/main_process/user_appeal.dart';
import 'package:final_assignment_front/features/dashboard/views/user/pages/main_process/user_offense_list_page.dart';
import 'package:final_assignment_front/features/dashboard/views/user/pages/main_process/vehicle_management.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BusinessProgressPage extends StatefulWidget {
  const BusinessProgressPage({super.key});

  @override
  State<BusinessProgressPage> createState() => _BusinessProgressPageState();
}

class _BusinessProgressPageState extends State<BusinessProgressPage> {
  final UserDashboardController controller =
      Get.find<UserDashboardController>();

  late final List<Map<String, dynamic>> businessOptions = [
    {
      'title': 'business.menu.offenseDetail',
      'icon': Icons.info,
      'route': const UserOffenseListPage(),
    },
    {
      'title': 'business.menu.finePayment',
      'icon': Icons.payment,
      'route': const FineInformationPage(),
    },
    {
      'title': 'business.menu.userAppeal',
      'icon': Icons.gavel,
      'route': const UserAppealPage(),
    },
    {
      'title': 'business.menu.onlineProcessingProgress',
      'icon': Icons.timeline,
      'route': const OnlineProcessingProgress(),
    },
    {
      'title': 'business.menu.vehicleManagement',
      'icon': Icons.directions_car,
      'route': const VehicleManagement(),
    },
  ];

  void _navigateToBusiness(Widget route) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => route),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => DashboardPageTemplate(
        theme: controller.currentBodyTheme.value,
        title: 'business.menu.title'.tr,
        pageType: DashboardPageType.user,
        onThemeToggle: controller.toggleBodyTheme,
        bodyIsScrollable: true,
        padding: EdgeInsets.zero,
        body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: businessOptions.length,
          itemBuilder: (context, index) {
            final option = businessOptions[index];
            return Column(
              children: [
                ListTile(
                  leading: Icon(option['icon'], color: Colors.blue),
                  title: Text((option['title'] as String).tr),
                  trailing:
                      const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                  onTap: () => _navigateToBusiness(option['route'] as Widget),
                ),
                if (index < businessOptions.length - 1)
                  const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }
}
