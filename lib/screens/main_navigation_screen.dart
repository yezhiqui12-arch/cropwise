import 'package:flutter/material.dart';
import '../widgets/app_side_menu_drawer.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/top_header.dart';
import 'boundary_map_screen.dart';
import 'home_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const Center(child: Text('Guided Scouting / Assess Screen')),
    const Center(child: Text('Edge AI Camera Viewfinder')),
    const BoundaryMapScreen(),
    const Center(child: Text('DA-BPI RAG AI Assistant')),
  ];

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
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
