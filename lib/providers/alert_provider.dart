import 'package:flutter/material.dart';
import 'package:pawtech/models/alert.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AlertProvider with ChangeNotifier {
  List<Alert> _alerts = [];
  bool _isLoading = false;
  String? _error;

  List<Alert> get alerts => [..._alerts];
  List<Alert> get unreadAlerts => _alerts.where((a) => !a.isRead).toList();
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get unreadCount => unreadAlerts.length;

  // Firestore reference
  final CollectionReference<Map<String, dynamic>> _col =
      FirebaseFirestore.instance.collection('alerts');

  Future<void> fetchAlerts() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final snap = await _col.orderBy('timestamp', descending: true).get();
      _alerts = snap.docs.map((doc) {
        final d = doc.data();
        return Alert(
          id: d['id'] as String,
          dogId: d['dogId'] as String,
          dogName: d['dogName'] as String,
          type: d['type'] as String,
          message: d['message'] as String,
          location: Map<String, dynamic>.from(d['location'] ?? {}),
          timestamp: d['timestamp'] as String,
          isRead: (d['isRead'] as bool?) ?? false,
        );
      }).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addAlert(Alert alert) async {
    try {
      // Use the client-generated id so UI can reference it immediately
      await _col.doc(alert.id).set(alert.toJson());
      _alerts.insert(0, alert);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> markAlertAsRead(String alertId) async {
    try {
      await _col.doc(alertId).update({'isRead': true});
      final i = _alerts.indexWhere((a) => a.id == alertId);
      if (i != -1) {
        _alerts[i] = Alert(
          id: _alerts[i].id,
          dogId: _alerts[i].dogId,
          dogName: _alerts[i].dogName,
          type: _alerts[i].type,
          message: _alerts[i].message,
          location: _alerts[i].location,
          timestamp: _alerts[i].timestamp,
          isRead: true,
        );
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> markAllAlertsAsRead() async {
    try {
      final unread = _alerts.where((a) => !a.isRead).toList();
      final batch = FirebaseFirestore.instance.batch();
      for (final a in unread) {
        batch.update(_col.doc(a.id), {'isRead': true});
      }
      await batch.commit();

      _alerts = _alerts
          .map((a) => Alert(
                id: a.id,
                dogId: a.dogId,
                dogName: a.dogName,
                type: a.type,
                message: a.message,
                location: a.location,
                timestamp: a.timestamp,
                isRead: true,
              ))
          .toList();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteAlert(String alertId) async {
    try {
      await _col.doc(alertId).delete();
      _alerts.removeWhere((a) => a.id == alertId);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  List<Alert> getAlertsForDog(String dogId) {
    return _alerts.where((alert) => alert.dogId == dogId).toList();
  }

  void createGeofenceWarningAlert(
    String dogId,
    String dogName,
    Map<String, dynamic> location,
  ) {
    final newAlert = Alert(
      id: 'alert_${DateTime.now().millisecondsSinceEpoch}',
      dogId: dogId,
      dogName: dogName,
      type: 'geofence_warning',
      message: '$dogName is approaching the boundary of the safe zone!',
      location: location,
      timestamp: DateTime.now().toIso8601String(),
      isRead: false,
    );
    addAlert(newAlert);
  }

  void createGeofenceBreachAlert(
    String dogId,
    String dogName,
    Map<String, dynamic> location,
  ) {
    final newAlert = Alert(
      id: 'alert_${DateTime.now().millisecondsSinceEpoch}',
      dogId: dogId,
      dogName: dogName,
      type: 'geofence_breach',
      message: '$dogName has left the designated safe zone!',
      location: location,
      timestamp: DateTime.now().toIso8601String(),
      isRead: false,
    );
    addAlert(newAlert);
  }
}
