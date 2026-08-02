import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'state/collection_store.dart';
import 'theme.dart';

void main() {
  runApp(const LudotecaApp());
}

class LudotecaApp extends StatelessWidget {
  const LudotecaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CollectionStore()..load(),
      child: MaterialApp(
        title: 'Ludoteca',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        // Segue o tema do sistema. Os dois modos são conjuntos de cor
        // escolhidos e validados contra a superfície de cada um.
        themeMode: ThemeMode.system,
        home: const HomeShell(),
      ),
    );
  }
}
