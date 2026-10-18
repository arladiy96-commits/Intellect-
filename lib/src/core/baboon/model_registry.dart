/// Metadata only. This module does not spend tokens, send data, or change the
/// active provider. Automatic provider switching requires explicit user budgets
/// and permissions and will be connected in a later update.
enum BaboonModelSkill { chat, reasoning, coding, vision, offline }

class BaboonModelInfo {
  final String id;
  final String title;
  final Set<BaboonModelSkill> skills;
  final bool requiresNetwork;

  const BaboonModelInfo({required this.id, required this.title,
    required this.skills, required this.requiresNetwork});
}

class BaboonModelRegistry {
  BaboonModelRegistry();
  final Map<String, BaboonModelInfo> _models = {};

  Iterable<BaboonModelInfo> get models => _models.values;
  void register(BaboonModelInfo model) {
    if (_models.containsKey(model.id)) throw StateError('Модель уже зарегистрирована: ${model.id}');
    _models[model.id] = model;
  }

  List<BaboonModelInfo> candidates(BaboonModelSkill skill,
      {required Set<String> availableIds, required bool allowNetwork}) => [
    for (final model in _models.values)
      if (model.skills.contains(skill) && availableIds.contains(model.id) &&
          (allowNetwork || !model.requiresNetwork)) model,
  ];
}
