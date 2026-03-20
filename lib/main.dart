import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'controllers/theme_controller.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/role_select_screen.dart';
import 'screens/client/client_home_screen.dart';
import 'screens/technician/technician_home_screen.dart';
import 'screens/technician/task_detail_screen.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/admin/quotation_detail_screen.dart';
import 'theme/app_theme.dart';
import 'dart:async';
import 'services/notification_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorWidget.builder = (FlutterErrorDetails details) => Material(
        color: Colors.red.shade900,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              details.exceptionAsString(),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      );

  // FCM: تسجيل معالج الخلفية + تهيئة Firebase قبل runApp (مطلوب لسلوك موثوق عند إغلاق التطبيق)
  if (!kIsWeb) {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('Firebase early init failed: $e');
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => ThemeController()),
      ],
      child: const EasyTechApp(),
    ),
  );

  if (kIsWeb) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().setNavigatorKey(navigatorKey);
      NotificationService().processPendingNotification();
    });
  } else {
    unawaited(Future(() async {
      try {
        await NotificationService().initialize();
      } catch (e) {
        debugPrint('NotificationService init failed: $e');
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationService().setNavigatorKey(navigatorKey);
        NotificationService().processPendingNotification();
      });
    }));
  }
}

class EasyTechApp extends StatelessWidget {
  const EasyTechApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'easytecheg',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeController.isDark ? ThemeMode.dark : ThemeMode.light,
      initialRoute: '/splash',
      routes: {
        '/splash': (_) => const SplashScreen(),
        '/login': (_) => const LoginScreen(),
        '/role-select': (_) => const RoleSelectScreen(),
        '/client': (_) => const ClientHomeScreen(),
        '/technician': (_) => const TechnicianHomeScreen(),
        '/task-detail': (ctx) {
          final id = ModalRoute.of(ctx)?.settings.arguments;
          final taskId = id is int ? id : (id != null ? int.tryParse(id.toString()) : null);
          if (taskId == null) return const SizedBox.shrink();
          return TaskDetailScreen(task: {'id': taskId});
        },
        '/quotation-detail': (ctx) {
          final id = ModalRoute.of(ctx)?.settings.arguments;
          final qId = id is int ? id : (id != null ? int.tryParse(id.toString()) : null);
          if (qId == null) return const SizedBox.shrink();
          return QuotationDetailScreen(quotationId: qId);
        },
        '/admin': (ctx) {
          final auth = Provider.of<AuthProvider>(ctx, listen: false);
          if (!auth.canAccessAdmin) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ctx.mounted) {
                Navigator.of(ctx).pushReplacementNamed('/role-select');
              }
            });
            return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFFD4920A))));
          }
          return const AdminHomeScreen();
        },
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

    try {
      final auth = context.read<AuthProvider>();
      await auth.checkAuth().timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (auth.isLoggedIn) {
        await NotificationService().getAndSaveFcmToken().timeout(const Duration(seconds: 10));
        unawaited(NotificationService().updateBadgeFromServer());
        if (mounted) Navigator.pushReplacementNamed(context, '/role-select');
      } else {
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (_) {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppThemeDecorations.gradientBackground(context),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ThemeToggleLogo(size: 120),
              const SizedBox(height: 32),
              CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
