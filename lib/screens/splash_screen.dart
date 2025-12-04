import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../config/app_theme.dart';
import 'home_screen.dart';

/// Splash Screen
/// 
/// Displays the app logo on a black background.
/// Automatically navigates to the home screen after the configured duration.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    // Setup animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutBack,
      ),
    );
    
    // Start animation
    _animationController.forward();
    
    // Navigate to home after splash duration
    _navigateToHome();
  }

  Future<void> _navigateToHome() async {
    await Future.delayed(
      Duration(milliseconds: AppConfig.splashDuration),
    );
    
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.splashBackground,
      body: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              color: AppTheme.splashBackground,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Expanded(
                  child: Center(
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        child: _buildLogo(),
                      ),
                    ),
                  ),
                ),
                
                // Branding text at bottom
                Padding(
                  padding: const EdgeInsets.only(bottom: 50),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: _buildBrandingText(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLogo() {
    return Image.asset(
      'assets/images/logo.png',
      width: 200,
      height: 200,
      fit: BoxFit.contain,
    );
  }

  Widget _buildBrandingText() {
    // Sin texto, solo el logo
    return const SizedBox.shrink();
  }
}
