import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/role_select_screen.dart';
import 'screens/client/client_home_screen.dart';
import 'screens/technician/technician_home_screen.dart';
import 'screens/admin/admin_home_screen.dart';
import 'utils/app_theme.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase - check if already initialized to avoid duplicate-app error
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
      ],
      child: const EasyTechApp(),
    ),
  );
}

class EasyTechApp extends StatelessWidget {
  const EasyTechApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Easy Tech',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      initialRoute: '/splash',
      routes: {
        '/splash': (_) => const SplashScreen(),
        '/login': (_) => const LoginScreen(),
        '/role-select': (_) => const RoleSelectScreen(),
        '/client': (_) => const ClientHomeScreen(),
        '/technician': (_) => const TechnicianHomeScreen(),
        '/admin': (_) => const AdminHomeScreen(),
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;

    final auth = context.read<AuthProvider>();
    await auth.checkAuth();

    if (!mounted) return;

    if (auth.isLoggedIn) {
      Navigator.pushReplacementNamed(context, '/role-select');
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Center(
                child: Text(
                  'ET',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'EASY TECH',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 14,
                letterSpacing: 5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'إدارة المنزل الذكي',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          ],
        ),
      ),
    );
  }
}
