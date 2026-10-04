import '../utils/format.dart';

/// Uma ideia de melhoria do próprio app.
///
/// Mora no app, e não num bloco de notas fora, porque a ideia aparece no meio
/// do uso — "isto aqui devia ser assim" acontece com o celular na mão, e uma
/// anotação que exige trocar de aplicativo simplesmente não é feita.
///
/// [done] existe para a lista continuar servindo depois: o que já foi
/// implementado desce em vez de sumir, para você não sugerir a mesma coisa duas
/// vezes nem ficar em dúvida se aquilo chegou a ser pedido.
class Suggestion {
  const Suggestion({
    this.id,
    required this.text,
    required this.createdAt,
    this.done = false,
  });

  final int? id;
  final String text;
  final DateTime createdAt;
  final bool done;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'text': text,
        'created_at': isoData(createdAt),
        'done': done ? 1 : 0,
      };

  factory Suggestion.fromMap(Map<String, Object?> m) => Suggestion(
        id: m['id'] as int?,
        text: (m['text'] as String?) ?? '',
        createdAt: parseIsoData(m['created_at'] as String?) ?? DateTime.now(),
        done: (m['done'] as int? ?? 0) == 1,
      );
}
