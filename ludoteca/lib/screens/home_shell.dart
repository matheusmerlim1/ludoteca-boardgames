import 'package:flutter/material.dart';

import '../services/update_service.dart';
import '../widgets/update_dialog.dart';
import 'collection_screen.dart';
import 'costs_screen.dart';
import 'settings_screen.dart';
import 'wishlist_screen.dart';

/// Casca do app: as três áreas de navegação.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _procurarAtualizacao());
  }

  /// A cada abertura, consulta a página de releases. Sem rede ou sem versão
  /// nova, fica calado — o botão em Ajustes mostra o motivo se pedirem.
  Future<void> _procurarAtualizacao() async {
    final service = UpdateService();
    try {
      final nova = await service.checkForUpdate();
      if (nova != null && mounted) {
        await showUpdateDialog(context, nova, service: service);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack preserva o scroll e os filtros de cada aba ao trocar.
      body: IndexedStack(
        index: _index,
        children: [
          const CollectionScreen(),
          const WishlistScreen(),
          CostsScreen(onVerColecao: () => setState(() => _index = 0)),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Coleção',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Quero',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart),
            label: 'Custos',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}
