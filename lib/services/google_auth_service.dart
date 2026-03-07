import 'package:google_sign_in/google_sign_in.dart';
import 'api_service.dart';

class GoogleAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    // Web Client ID من Firebase Console (client_type: 3)
    serverClientId: '621394137104-dagkle6rgirjgnm7ksm9n065vnjmmk5e.apps.googleusercontent.com',
  );

  /// تسجيل الدخول بحساب Google
  /// يرجع بيانات المستخدم عند النجاح أو null عند الإلغاء
  static Future<Map<String, dynamic>?> signIn() async {
    try {
      // تسجيل الخروج أولاً لضمان ظهور نافذة اختيار الحساب
      await _googleSignIn.signOut();

      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) return null; // المستخدم ألغى العملية

      // إرسال بيانات Google للـ backend لإنشاء/تحديث الحساب
      final result = await ApiService.mutate(
        'auth.googleAuth',
        input: {
          'googleId': account.id,
          'email': account.email,
          'name': account.displayName ?? account.email,
          'avatarUrl': account.photoUrl,
        },
      );

      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// تسجيل الخروج من Google
  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }
}
