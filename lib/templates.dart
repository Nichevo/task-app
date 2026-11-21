import 'models.dart';

/// Item 114 F: starter project templates for supply-chain analysis work. Offsets are days from
/// the deadline; each step comes after the one before it.
List<ChecklistTemplate> starterTemplates() {
  ChecklistTemplate make(String name, List<String> tags, String label, List<(String, int, int?, int?)> steps) {
    final tpl = ChecklistTemplate.create(name, [for (final s in steps) s.$1])
      ..dateLabel = label
      ..tags.addAll(tags);
    for (var i = 0; i < steps.length; i++) {
      final (title, offset, days, minutes) = steps[i];
      tpl.items.add(TemplateStep(title: title, offset: offset, days: days, minutes: minutes, after: [if (i > 0) i - 1]));
    }
    return tpl;
  }

  return [
    make('Demand forecast', ['forecast'], 'hand-over date', [
      ('Agree scope, items and forecast horizon', -20, 1, null),
      ('Pull sales history, promotions and stock-outs', -19, 2, null),
      ('Clean the data: outliers, stock-outs, new items', -17, 2, null),
      ('Baseline models: naive, moving average, ETS', -15, 2, null),
      ('Try ML: gradient boosting with calendar and promo features', -13, 3, null),
      ('Backtest and pick a model (WAPE, bias)', -8, 2, null),
      ('Write up the forecast and its accuracy', -4, 2, null),
      ('Hand over and set up the monthly refresh', 0, 1, null),
    ]),
    make('Safety stock and reorder points', ['inventory'], 'go-live date', [
      ('Pick the items and service level targets', -15, 1, null),
      ('Pull demand and lead time history', -14, 2, null),
      ('Work out demand and lead time variability', -12, 2, null),
      ('Calculate safety stock and reorder points', -8, 2, null),
      ('Compare with current settings and stock cost', -5, 1, null),
      ('Review with the planners', -3, 1, null),
      ('Load the new parameters', 0, 1, null),
    ]),
    make('Late supplier delivery prediction', ['ml', 'suppliers'], 'presentation date', [
      ('Define "late" and what to predict', -26, 1, null),
      ('Pull purchase order and receipt history', -25, 2, null),
      ('Build features: supplier, lane, lead time, season, quantity', -22, 3, null),
      ('Baseline: each supplier\'s on-time rate', -18, 1, null),
      ('Train a classifier (logistic regression, gradient boosting)', -17, 3, null),
      ('Check precision, recall and calibration', -12, 2, null),
      ('Explain the drivers (feature importance, SHAP)', -10, 2, null),
      ('Alert or dashboard for buyers', -6, 3, null),
      ('Present the results', 0, 1, null),
    ]),
    make('Quick analysis request', ['analysis'], 'due date', [
      ('Clarify the question and who needs it', -2, null, 30),
      ('Get the data', -2, null, 60),
      ('Analyse', -1, null, 180),
      ('Chart and one-page summary', 0, null, 60),
      ('Send it and file the work', 0, null, 30),
    ]),
  ];
}
