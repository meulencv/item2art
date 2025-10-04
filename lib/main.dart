import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'services/supabase_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> _loadEnv() async {
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('✅ .env cargado');
  } catch (e) {
    debugPrint('⚠️ No se encontró .env, intentando .env.example. Error: $e');
    try {
      await dotenv.load(fileName: '.env.example');
      debugPrint(
        '✅ .env.example cargado como fallback (usa valores de ejemplo)',
      );
    } catch (e2) {
      debugPrint('❌ No se pudo cargar ninguna configuración de entorno: $e2');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _loadEnv();

  // Inicializar Supabase (no abortar app si falla, solo loguear)
  try {
    await SupabaseService.initialize();
  } catch (e) {
    debugPrint('⚠️ Supabase no inicializado: $e');
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
