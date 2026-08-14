import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_data_mode.dart';
import '../widgets/app_side_menu_drawer.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/top_header.dart';
import 'boundary_map_screen.dart';
import 'fields_screen.dart';
import 'home_screen.dart';
import 'scan/scan_landing_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({
    super.key,
    this.initialIndex = 0,
    this.onExitTestMode,
    this.onClearTestMode,
  });

  final int initialIndex;
  final VoidCallback? onExitTestMode;
  final Future<void> Function()? onClearTestMode;

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _currentIndex;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
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
    final dataMode =
        context.watch<AppDataMode?>() ?? const AppDataMode.production();
    final isHome = _currentIndex == 0;
    return Scaffold(
      appBar: isHome ? const TopHeader(key: Key('home_top_header')) : null,
      drawer: isHome
          ? const AppSideMenuDrawer(key: Key('home_side_menu'))
          : null,
      body: Column(
        children: [
          if (dataMode.isTestMode)
            Material(
              key: const Key('permanent_test_data_indicator'),
              color: const Color(0xFF8B1E1E),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'TEST DATA · Separate from farmer records',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('clear_test_mode_button'),
                        onPressed: widget.onClearTestMode,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Clear'),
                      ),
                      IconButton(
                        key: const Key('exit_test_mode_button'),
                        tooltip: 'Exit test mode',
                        onPressed: widget.onExitTestMode,
                        color: Colors.white,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(index: _currentIndex, children: _screens),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: _selectDestination,
      ),
    );
  }
}
