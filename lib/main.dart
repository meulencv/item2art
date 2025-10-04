import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'services/supabase_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> _loadEnv() async {
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('✅ .env loaded');
  } catch (e) {
    debugPrint('⚠️ .env not found, trying .env.example. Error: $e');
    try {
      await dotenv.load(fileName: '.env.example');
      debugPrint('✅ .env.example loaded as fallback (using sample values)');
    } catch (e2) {
      debugPrint('❌ Unable to load any environment configuration: $e2');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _loadEnv();

  // Initialize Supabase (don't abort the app on failure, just log)
  try {
    await SupabaseService.initialize();
  } catch (e) {
    debugPrint('⚠️ Supabase not initialized: $e');
  }

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const Item2ArtApp());
}

class Item2ArtApp extends StatelessWidget {
  const Item2ArtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'item2art',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.purple,
        scaffoldBackgroundColor: const Color(0xFF0f0c29),
        fontFamily: 'SF Pro Display',
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
