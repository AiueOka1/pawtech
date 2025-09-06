import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pawtech/models/user.dart' as local_user;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;

Future<void> fetchAndStoreFcmToken(String handlerId) async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(handlerId)
          .update({'fcmToken': token});
      // print('FCM token saved: $token');
    }
  } catch (e) {
    // print('Error saving FCM token: $e');
  }
}

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

Future<void> _initLocalNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  
  // Add iOS-specific settings
  const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  
  const InitializationSettings initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings, // Add this line
  );
  
  await _localNotifications.initialize(initSettings);
  
  // Request iOS permissions
  await _localNotifications
      .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, badge: true, sound: true);
}

class AuthProvider with ChangeNotifier {
  final fb_auth.FirebaseAuth _auth = fb_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  local_user.User? _currentUser;
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;
  bool _creatingUser = false; // NEW: prevent race during registration

  local_user.User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;
  String? get error => _error;

  AuthProvider() {
    // Ensure init runs after construction (and outside the current build phase)
    Future.microtask(_init);
  }

  void _safeNotify() {
    if (!hasListeners) return;
    // Always schedule notify after the current frame to avoid setState-during-build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) notifyListeners();
    });
  }

  Future<void> _init() async {
    if (_isInitialized) return;

    if (kIsWeb) {
      await _auth.setPersistence(fb_auth.Persistence.LOCAL);
    }

    await _checkCurrentUser(); // This will schedule notifications safely

    _auth.authStateChanges().listen((fb_auth.User? firebaseUser) async {
      if (_creatingUser) return;
      if (firebaseUser == null) {
        _currentUser = null;
      } else {
        await _loadUserData(firebaseUser.uid);
      }
      _safeNotify();
    });

    _isInitialized = true;
  }

  // Remove the separate initialize() duplication (optional keep as wrapper)
  Future<void> initialize() async => _init();

  Future<void> _checkCurrentUser() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      await _loadUserData(firebaseUser.uid);
    }
    _safeNotify();
  }

  Future<void> _saveTokenOnRefresh() async {
    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        try {
          await _firestore.collection('users').doc(uid).update({
            'fcmToken': token,
          });
        } catch (_) {}
      }
    });
  }

  Future<void> _loadUserData(String uid) async {
    _isLoading = true;
    _safeNotify();

    try {
      final doc = await _firestore.collection('users').doc(uid).get();

      if (!doc.exists) {
        debugPrint('User doc not found yet for uid=$uid (will retry later).');
        return;
      }

      final data = doc.data()!;
      _currentUser = local_user.User(
        id: uid,
        name: data['name'],
        email: data['email'],
        role: data['role'] ?? 'Handler',
        department: data['department'],
        profileImageUrl: data['profileImageUrl'],
        phoneNumber: data['phoneNumber'],
        badgeNumber: data['badgeNumber'],
        assignedDogIds: List<String>.from(data['assignedDogIds'] ?? []),
      );

      await _saveTokenOnRefresh();
    } catch (e) {
      _error = e.toString();
      debugPrint('Load user data failed: $e');
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  Future<void> _showLoginNotification() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'login_channel',
      'Login Notifications',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);
    await _localNotifications.show(
      0,
      'Login Successful',
      'Welcome back!',
      notificationDetails,
    );
  }

  Future<bool> login(String email, String password) async {
    if (!_isInitialized) await _init();
    _isLoading = true;
    _error = null;
    _safeNotify();
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _initLocalNotifications();
      await _showLoginNotification();
      await FirebaseMessaging.instance.requestPermission(
          alert: true, badge: true, sound: true);
      await fetchAndStoreFcmToken(result.user!.uid);
      return true;
    } on fb_auth.FirebaseAuthException catch (e, st) {
      debugPrint('FirebaseAuthException: $e\n$st');
      _error = e.message;
      return false;
    } catch (e, st) {
      debugPrint('Generic login error: $e\n$st');
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  Future<bool> register(
    String name,
    String email,
    String password,
    String department,
    String phoneNumber,
    String badgeNumber,
  ) async {
    _isLoading = true;
    _error = null;
    _creatingUser = true;
    _safeNotify();
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final newUser = local_user.User(
        id: result.user!.uid,
        name: name,
        email: email,
        role: 'Handler',
        department: department,
        // force png to avoid platform image-decoding errors
        profileImageUrl: 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&format=png',
        phoneNumber: phoneNumber,
        badgeNumber: badgeNumber,
        assignedDogIds: [],
      );
      await _firestore.collection('users').doc(result.user!.uid).set({
        'name': name,
        'email': email,
        'role': 'Handler',
        'department': department,
        'profileImageUrl': newUser.profileImageUrl,
        'phoneNumber': phoneNumber,
        'badgeNumber': badgeNumber,
        'assignedDogIds': [],
        'createdAt': FieldValue.serverTimestamp(),
      });
      _currentUser = newUser;
      await FirebaseMessaging.instance.requestPermission(
          alert: true, badge: true, sound: true);
      await fetchAndStoreFcmToken(result.user!.uid);
      return true;
    } on fb_auth.FirebaseAuthException catch (e) {
      _error = e.message;
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _creatingUser = false;
      _isLoading = false;
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        // schedule load (will safely notify)
        _loadUserData(uid);
      } else {
        _safeNotify();
      }
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    _currentUser = null;
    _safeNotify();
  }

  Future<void> updateProfile(local_user.User updatedUser) async {
    _isLoading = true;
    _safeNotify();

    try {
      await _firestore.collection('users').doc(updatedUser.id).update({
        'name': updatedUser.name,
        'department': updatedUser.department,
        'phoneNumber': updatedUser.phoneNumber,
        'badgeNumber': updatedUser.badgeNumber,
        'profileImageUrl': updatedUser.profileImageUrl,
      });

      _currentUser = updatedUser;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }
}