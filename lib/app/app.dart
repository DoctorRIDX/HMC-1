import 'package:flutter/material.dart';

import '../features/save/save_data.dart';
import '../ui/menu_screens.dart';

// Muted, street-level palette (no neon): black, bone white, dried-blood red.
const Color kInk = Color(0xFF0B0B0B);
const Color kBone = Color(0xFFE9E2CF);
const Color kBlood = Color(0xFF8F1A1A);
const Color kBloodLt = Color(0xFFC4473F);
const Color kMoney = Color(0xFF4F9E4F);
const String kScript = 'Chorus';

class HmcApp extends StatelessWidget {
  const HmcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HMC: 1',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: kScript,
        colorScheme: const ColorScheme.dark(primary: kBlood, surface: kInk),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: MenuScreen(repo: SaveRepository(PrefsStore())),
    );
  }
}
