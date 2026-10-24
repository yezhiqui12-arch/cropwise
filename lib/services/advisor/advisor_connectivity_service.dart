import 'dart:io';

import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

enum AdvisorConnectionStatus { checking, online, offline }

/// Reports verified internet reachability for the Guide.
///
/// This deliberately checks usable internet access rather than treating a
/// Wi-Fi or mobile-network interface as proof that online services can be
/// reached.
abstract interface class AdvisorConnectivityService {
  Future<AdvisorConnectionStatus> check();

  Stream<AdvisorConnectionStatus> get statusChanges;
}

class InternetAdvisorConnectivityService implements AdvisorConnectivityService {
  InternetAdvisorConnectivityService({InternetConnection? connection})
    : _connection = connection ?? InternetConnection();

  final InternetConnection _connection;

  @override
  Future<AdvisorConnectionStatus> check() async {
    try {
      if (await _connection.hasInternetAccess ||
          await _canResolveOnlineGuide()) {
        return AdvisorConnectionStatus.online;
      }
      return AdvisorConnectionStatus.offline;
    } catch (_) {
      return AdvisorConnectionStatus.offline;
    }
  }

  @override
  Stream<AdvisorConnectionStatus> get statusChanges =>
      _connection.onStatusChange.asyncMap((status) async {
        if (status == InternetStatus.connected ||
            await _canResolveOnlineGuide()) {
          return AdvisorConnectionStatus.online;
        }
        return AdvisorConnectionStatus.offline;
      }).distinct();

  Future<bool> _canResolveOnlineGuide() async {
    try {
      final addresses = await InternetAddress.lookup(
        'generativelanguage.googleapis.com',
      );
      return addresses.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
