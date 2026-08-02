import 'package:flutter/material.dart';

/// Cores de visualização de dados.
///
/// As duas colunas (clara e escura) são conjuntos escolhidos e validados
/// contra a superfície em que cada uma renderiza — não é a paleta clara
/// invertida. A *ordem* dos slots é o mecanismo de segurança para daltonismo,
/// então atribua sempre em ordem fixa (slot 1, 2, 3...) e nunca cicle.
@immutable
class VizColors extends ThemeExtension<VizColors> {
  const VizColors({
    required this.surface,
    required this.page,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.inkMuted,
    required this.gridline,
    required this.baseline,
    required this.hairline,
    required this.series,
    required this.sequential,
    required this.good,
    required this.warning,
    required this.critical,
  });

  final Color surface;
  final Color page;
  final Color inkPrimary;
  final Color inkSecondary;
  final Color inkMuted;
  final Color gridline;
  final Color baseline;
  final Color hairline;

  /// Ordem fixa: azul, laranja, água, amarelo, magenta, verde, violeta, vermelho.
  final List<Color> series;

  /// Rampa sequencial de **um hue só**, do menos para o mais.
  ///
  /// Para grandeza contínua — quantas partidas num dia. Nunca arco-íris: cor
  /// diferente sugere categoria diferente, e aqui é a mesma coisa em
  /// quantidades diferentes.
  ///
  /// No claro ela escurece; no escuro ela clareia. "Mais" tem de se afastar da
  /// superfície nos dois casos, e inverter a rampa clara no escuro faria o
  /// valor alto sumir no fundo.
  final List<Color> sequential;

  final Color good;
  final Color warning;
  final Color critical;

  /// Cor categórica do slot [i] (0-indexado). Nunca gera cor nova: passando
  /// de 8 séries o chamador deve dobrar a cauda em "Outros" ou facetar.
  Color serie(int i) => series[i.clamp(0, series.length - 1)];

  static const light = VizColors(
    surface: Color(0xFFFCFCFB),
    page: Color(0xFFF9F9F7),
    inkPrimary: Color(0xFF0B0B0B),
    inkSecondary: Color(0xFF52514E),
    inkMuted: Color(0xFF898781),
    gridline: Color(0xFFE1E0D9),
    baseline: Color(0xFFC3C2B7),
    hairline: Color(0x1A0B0B0B),
    series: [
      Color(0xFF2A78D6), // 1 azul
      Color(0xFFEB6834), // 2 laranja
      Color(0xFF1BAF7A), // 3 água
      Color(0xFFEDA100), // 4 amarelo
      Color(0xFFE87BA4), // 5 magenta
      Color(0xFF008300), // 6 verde
      Color(0xFF4A3AA7), // 7 violeta
      Color(0xFFE34948), // 8 vermelho
    ],
    // Azul, passos 250 → 700: escurece conforme cresce.
    sequential: [
      Color(0xFF86B6EF),
      Color(0xFF3987E5),
      Color(0xFF1C5CAB),
      Color(0xFF0D366B),
    ],
    good: Color(0xFF006300),
    warning: Color(0xFFFAB219),
    critical: Color(0xFFD03B3B),
  );

  static const dark = VizColors(
    surface: Color(0xFF1A1A19),
    page: Color(0xFF0D0D0D),
    inkPrimary: Color(0xFFFFFFFF),
    inkSecondary: Color(0xFFC3C2B7),
    inkMuted: Color(0xFF898781),
    gridline: Color(0xFF2C2C2A),
    baseline: Color(0xFF383835),
    hairline: Color(0x1AFFFFFF),
    series: [
      Color(0xFF3987E5),
      Color(0xFFD95926),
      Color(0xFF199E70),
      Color(0xFFC98500),
      Color(0xFFD55181),
      Color(0xFF008300),
      Color(0xFF9085E9),
      Color(0xFFE66767),
    ],
    // Mesma rampa azul, percorrida ao contrário: no fundo escuro é clareando
    // que o valor alto se destaca.
    sequential: [
      Color(0xFF184F95),
      Color(0xFF2A78D6),
      Color(0xFF5598E7),
      Color(0xFF9EC5F4),
    ],
    good: Color(0xFF0CA30C),
    warning: Color(0xFFFAB219),
    critical: Color(0xFFD03B3B),
  );

  @override
  VizColors copyWith({
    Color? surface,
    Color? page,
    Color? inkPrimary,
    Color? inkSecondary,
    Color? inkMuted,
    Color? gridline,
    Color? baseline,
    Color? hairline,
    List<Color>? series,
    List<Color>? sequential,
    Color? good,
    Color? warning,
    Color? critical,
  }) {
    return VizColors(
      surface: surface ?? this.surface,
      page: page ?? this.page,
      inkPrimary: inkPrimary ?? this.inkPrimary,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      inkMuted: inkMuted ?? this.inkMuted,
      gridline: gridline ?? this.gridline,
      baseline: baseline ?? this.baseline,
      hairline: hairline ?? this.hairline,
      series: series ?? this.series,
      sequential: sequential ?? this.sequential,
      good: good ?? this.good,
      warning: warning ?? this.warning,
      critical: critical ?? this.critical,
    );
  }

  @override
  VizColors lerp(ThemeExtension<VizColors>? other, double t) {
    if (other is! VizColors) return this;
    return VizColors(
      surface: Color.lerp(surface, other.surface, t)!,
      page: Color.lerp(page, other.page, t)!,
      inkPrimary: Color.lerp(inkPrimary, other.inkPrimary, t)!,
      inkSecondary: Color.lerp(inkSecondary, other.inkSecondary, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      gridline: Color.lerp(gridline, other.gridline, t)!,
      baseline: Color.lerp(baseline, other.baseline, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      series: t < 0.5 ? series : other.series,
      sequential: t < 0.5 ? sequential : other.sequential,
      good: Color.lerp(good, other.good, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      critical: Color.lerp(critical, other.critical, t)!,
    );
  }
}

/// Atalho: `context.viz.serie(0)`.
extension VizContext on BuildContext {
  VizColors get viz => Theme.of(this).extension<VizColors>()!;
}

const _fontFallback = <String>['Roboto', 'sans-serif'];

ThemeData buildTheme(Brightness brightness) {
  final viz = brightness == Brightness.light ? VizColors.light : VizColors.dark;
  final isLight = brightness == Brightness.light;

  final scheme = ColorScheme.fromSeed(
    seedColor: viz.series[0],
    brightness: brightness,
  ).copyWith(
    surface: viz.page,
    primary: viz.series[0],
    error: viz.critical,
  );

  final base = ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: viz.page,
  );

  return base.copyWith(
    extensions: [viz],
    textTheme: base.textTheme
        .apply(
          fontFamilyFallback: _fontFallback,
          bodyColor: viz.inkPrimary,
          displayColor: viz.inkPrimary,
        )
        .copyWith(
          // Números grandes usam figuras proporcionais (o padrão).
          // `tabular-nums` fica reservado para colunas de tabela e eixos.
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: viz.inkPrimary,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: viz.inkPrimary,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(color: viz.inkSecondary),
          labelSmall: base.textTheme.labelSmall?.copyWith(color: viz.inkMuted),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: viz.page,
      surfaceTintColor: Colors.transparent,
      foregroundColor: viz.inkPrimary,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: viz.inkPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: viz.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: viz.hairline),
      ),
    ),
    dividerTheme: DividerThemeData(color: viz.gridline, thickness: 1, space: 1),
    chipTheme: ChipThemeData(
      backgroundColor: viz.surface,
      selectedColor: viz.series[0].withValues(alpha: isLight ? 0.12 : 0.24),
      side: BorderSide(color: viz.hairline),
      labelStyle: TextStyle(color: viz.inkPrimary, fontSize: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: viz.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: viz.gridline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: viz.gridline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: viz.series[0], width: 2),
      ),
      labelStyle: TextStyle(color: viz.inkSecondary),
      hintStyle: TextStyle(color: viz.inkMuted),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: viz.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: viz.series[0].withValues(alpha: isLight ? 0.12 : 0.24),
      elevation: 0,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 12, color: viz.inkSecondary),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: viz.inkSecondary,
      titleTextStyle: TextStyle(fontSize: 15, color: viz.inkPrimary),
      subtitleTextStyle: TextStyle(fontSize: 13, color: viz.inkSecondary),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
