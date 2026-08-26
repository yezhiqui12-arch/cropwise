import 'package:flutter/material.dart';
import '../models/assessment_state.dart';

class WormWiseProvider extends ChangeNotifier {
  AssessmentState _currentState =
      AssessmentState.ready; // Default to State 1: No Assessment on app launch

  // In-progress metrics
  int _currentStops = 3;
  final int _totalStops = 5;
  int _photosCaptured = 15;
  int _healthyCount = 42;
  int _suspectedFawCount = 8;
  int _minutesRemaining = 6;

  // Completed metrics
  int _completedPhotos = 25;
  int _completedHealthy = 62;
  int _completedSuspected = 8;
  int _infestationPercent = 28;
  String _damageSeverity = 'Low';
  String _estScoutTime = '12m';
  final String _lastSyncedTime = 'Today, 9:45 AM';

  // Getters
  AssessmentState get currentState => _currentState;

  int get currentStops => _currentStops;
  int get totalStops => _totalStops;
  int get photosCaptured => _photosCaptured;
  int get healthyCount => _healthyCount;
  int get suspectedFawCount => _suspectedFawCount;
  int get minutesRemaining => _minutesRemaining;

  int get completedPhotos => _completedPhotos;
  int get completedHealthy => _completedHealthy;
  int get completedSuspected => _completedSuspected;
  int get infestationPercent => _infestationPercent;
  String get damageSeverity => _damageSeverity;
  String get estScoutTime => _estScoutTime;
  String get lastSyncedTime => _lastSyncedTime;

  // State Switcher (for demoing all 3 states)
  void setAssessmentState(AssessmentState newState) {
    _currentState = newState;
    notifyListeners();
  }

  void startAssessment() {
    _currentState = AssessmentState.inProgress;
    _currentStops = 1;
    _photosCaptured = 5;
    _healthyCount = 12;
    _suspectedFawCount = 2;
    _minutesRemaining = 12;
    notifyListeners();
  }

  void completeAssessment() {
    _currentState = AssessmentState.completed;
    _completedPhotos = 25;
    _completedHealthy = 62;
    _completedSuspected = 8;
    _infestationPercent = 28;
    _damageSeverity = 'Low';
    _estScoutTime = '12m';
    notifyListeners();
  }

  void resetToReady() {
    _currentState = AssessmentState.ready;
    notifyListeners();
  }
}
