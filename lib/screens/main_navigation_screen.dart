import 'package:flutter/material.dart';
import '../widgets/app_side_menu_drawer.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/top_header.dart';
import 'boundary_map_screen.dart';
import 'fields_screen.dart';
import 'home_screen.dart';
import 'scan/scan_landing_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const HomeScreen(),
      const Center(child: Text('Assessment records are not available yet.')),
      ScanLandingScreen(
        onRegisterField: _openFields,
        onCompleteFieldOutline: () => _selectDestination(3),
      ),
      const BoundaryMapScreen(),
      const Center(child: Text('WormWise Bot is not available yet.')),
    ];
  }

  void _selectDestination(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
  }

  void _openFields() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const FieldsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isHome = _currentIndex == 0;
    return Scaffold(
      appBar: isHome ? const TopHeader(key: Key('home_top_header')) : null,
      drawer: isHome
          ? const AppSideMenuDrawer(key: Key('home_side_menu'))
          : null,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: _selectDestination,
      ),
    );
  }
}
