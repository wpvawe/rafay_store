import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/images/logo.png',
                width: 140,
                height: 140,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Rafay Store',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            CircularProgressIndicator(color: cs.onPrimary),
          ],
        ),
      ),
    );
  }
}
