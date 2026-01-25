import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// מסך התחברות
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService.instance;
  bool _isLoading = false;
  String? _errorMessage;

  /// התחברות עם Google
  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _authService.signInWithGoogle();

    if (mounted) {
      setState(() => _isLoading = false);

      if (!result.success && result.errorMessage != null) {
        setState(() => _errorMessage = result.errorMessage);
        _showErrorSnackBar(result.errorMessage!);
      }
    }
  }

  /// התחברות כאורח
  Future<void> _signInAsGuest() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _authService.signInAnonymously();

    if (mounted) {
      setState(() => _isLoading = false);

      if (!result.success && result.errorMessage != null) {
        setState(() => _errorMessage = result.errorMessage);
        _showErrorSnackBar(result.errorMessage!);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F23),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // לוגו ושם האפליקציה
              _buildHeader(theme),

              const Spacer(flex: 2),

              // כפתורי התחברות
              _buildSignInButtons(theme),

              const SizedBox(height: 24),

              // הודעת שגיאה
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),

              const Spacer(),

              // תנאי שימוש
              _buildTermsText(theme),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// בונה את הכותרת והלוגו
  Widget _buildHeader(ThemeData theme) {
    return Column(
      children: [
        // לוגו
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.secondary,
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.4),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.search,
            color: Colors.white,
            size: 48,
          ),
        ),
        const SizedBox(height: 24),

        // שם האפליקציה
        Text(
          'The Hunter',
          style: theme.textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),

        // תיאור
        Text(
          'חפש כל קובץ במכשיר שלך',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.grey.shade400,
          ),
        ),
      ],
    );
  }

  /// בונה כפתורי התחברות
  Widget _buildSignInButtons(ThemeData theme) {
    return Column(
      children: [
        // כפתור Google
        _buildGoogleButton(theme),
        const SizedBox(height: 16),

        // מפריד
        Row(
          children: [
            Expanded(child: Divider(color: Colors.grey.shade700)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'או',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
            Expanded(child: Divider(color: Colors.grey.shade700)),
          ],
        ),
        const SizedBox(height: 16),

        // כפתור אורח
        _buildGuestButton(theme),
      ],
    );
  }

  /// כפתור התחברות עם Google
  Widget _buildGoogleButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _signInWithGoogle,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Google Icon
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Image.network(
                      'https://www.google.com/favicon.ico',
                      width: 24,
                      height: 24,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.g_mobiledata,
                        color: Colors.red,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// כפתור המשך כאורח
  Widget _buildGuestButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: _isLoading ? null : _signInAsGuest,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_outline,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            const Text(
              'Continue as Guest',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// טקסט תנאי שימוש
  Widget _buildTermsText(ThemeData theme) {
    return Text(
      'בהתחברות אתה מסכים לתנאי השימוש ומדיניות הפרטיות',
      style: TextStyle(
        color: Colors.grey.shade600,
        fontSize: 12,
      ),
      textAlign: TextAlign.center,
    );
  }
}
