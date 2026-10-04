import 'package:flutter/material.dart';

import '../utils/format.dart';

/// Tipo de um item avulso do hobby.
enum ExtraKind {
  sleeves('sleeves', 'Sleeves', Icons.style_outlined),
  playmat('playmat', 'Playmat', Icons.crop_landscape),
  organizador('organizador', 'Organizador / insert', Icons.inventory_2_outlined),
  acessorio('acessorio', 'Acessório', Icons.extension_outlined),
  outro('outro', 'Outro', Icons.category_outlined);

  const ExtraKind(this.db, this.label, this.icon);

  /// Valor gravado no banco — não muda nunca, mesmo que o rótulo mude.
  final String db;
  final String label;
  final IconData icon;

  static ExtraKind fromDb(String? v) =>
      ExtraKind.values.firstWhere((k) => k.db == v, orElse: () => ExtraKind.outro);
}

/// Compra avulsa do hobby que **não pertence a um jogo**: um kit de sleeves
/// para usar em vários jogos, um playmat, uma caixa organizadora.
///
/// Fica fora da tabela de jogos de propósito. Como jogo, ele entraria na
/// estante, no custo por partida e no "nunca jogado" — e um playmat não se
/// joga. Como gasto, ele entra onde importa: no custo do mês, na linha do
/// tempo de gastos e em "em que você gastou".
class Extra {
  const Extra({
    this.id,
    required this.name,
    this.kind = ExtraKind.outro,
    this.price = 0,
    this.purchaseDate,
    this.notes,
  });

  final int? id;
  final String name;
  final ExtraKind kind;
  final double price;
  final DateTime? purchaseDate;
  final String? notes;

  /// Sleeves avulsos somam junto com os sleeves dos jogos; o resto, com os
  /// acessórios.
  bool get isSleeve => kind == ExtraKind.sleeves;

  Extra copyWith({
    String? name,
    ExtraKind? kind,
    double? price,
    DateTime? purchaseDate,
    bool clearPurchaseDate = false,
    String? notes,
  }) =>
      Extra(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        price: price ?? this.price,
        purchaseDate: clearPurchaseDate ? null : (purchaseDate ?? this.purchaseDate),
        notes: notes ?? this.notes,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'kind': kind.db,
        'price': price,
        'purchase_date': purchaseDate == null ? null : isoData(purchaseDate!),
        'notes': (notes == null || notes!.trim().isEmpty) ? null : notes!.trim(),
      };

  factory Extra.fromMap(Map<String, Object?> m) => Extra(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        kind: ExtraKind.fromDb(m['kind'] as String?),
        price: (m['price'] as num?)?.toDouble() ?? 0,
        purchaseDate: parseIsoData(m['purchase_date'] as String?),
        notes: m['notes'] as String?,
      );
}
