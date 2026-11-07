import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/update_service.dart';
import '../state/collection_store.dart';
import '../widgets/play_timer.dart';
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

  /// A cada abertura: primeiro conta o que mudou, se o app acabou de ser
  /// atualizado; depois consulta a página de releases e, havendo versão nova,
  /// já baixa e abre o instalador. Sem rede ou sem versão nova, fica calado —
  /// o botão em Ajustes mostra o motivo se pedirem.
  Future<void> _procurarAtualizacao() async {
    final service = UpdateService();
    final repo = context.read<CollectionStore>().repository;
    try {
      final instalada = await service.installedVersion();
      final vista = await repo.getSetting(_chaveVersaoVista);
      if (vista != instalada) {
        await repo.setSetting(_chaveVersaoVista, instalada);
      }
      // Sem registro anterior é a primeira abertura (ou a primeira desde que
      // o registro existe): não há "antes" para comparar.
      if (vista != null && UpdateService.isNewer(instalada, vista)) {
        final r = await service.releaseOf(instalada);
        if (r != null && mounted) {
          await showNovidadesDialog(context,
              version: instalada, notes: r.notes);
        }
      }
    } catch (_) {}

    try {
      final nova = await service.checkForUpdate();
      if (nova != null && mounted) {
        await showUpdateDialog(context, nova,
            service: service, automatico: true);
      }
    } catch (_) {}
  }

  /// Última versão que já abriu neste aparelho.
  static const _chaveVersaoVista = 'versao_vista';

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
      // A faixa do cronômetro fica junto da navegação: aparece em qualquer
      // aba enquanto há partida cronometrada.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PartidaEmAndamentoBar(),
          NavigationBar(
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
        ],
      ),
    );
  }
}
