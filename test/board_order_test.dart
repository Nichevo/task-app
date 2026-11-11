import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/kanban_page.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/task_list.dart';

/// Item 92: moving a task on the board must not reshuffle the columns.
void main() {
  List<String> column(AppStore s, String stageId) => boardColumnOrder(
        sortTasks([for (final t in s.data.boardTasks) if (t.stageId == stageId) t], s.data, DateTime.now()),
        s.data,
      ).map((t) => t.title).toList();

  test('a moved task goes to the top of its new column; the others keep their places', () async {
    final s = AppStore();
    s.data.sort = ListSort.due;
    final now = DateTime.now();
    for (final (i, name) in ['a', 'b', 'c', 'd'].indexed) {
      final t = s.addTask(name)..dueAt = now.add(Duration(days: 4 - i)); // d is due first
      s.setOnBoard(t, true, stage: s.data.stage('doing'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    // Newest arrival first, whatever the due dates.
    expect(column(s, 'doing'), ['d', 'c', 'b', 'a']);

    final b = s.data.active.firstWhere((t) => t.title == 'b');
    for (final to in ['next', 'backlog']) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      s.moveToStage(b, s.data.stage(to)!, how: MoveHow.swiped);
      expect(column(s, 'doing'), ['d', 'c', 'a']); // the column it left doesn't reshuffle
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
    s.moveToStage(b, s.data.stage('doing')!, how: MoveHow.swiped);
    expect(column(s, 'doing'), ['b', 'd', 'c', 'a']);

    // The setting brings back the list's sort.
    s.data.boardSortLikeList = true;
    expect(column(s, 'doing'), ['d', 'c', 'b', 'a']);
    final back = AppData.fromJson(s.data.toJson());
    expect(back.boardSortLikeList, isTrue);
    expect(AppData().boardSortLikeList, isFalse);
  });
}
