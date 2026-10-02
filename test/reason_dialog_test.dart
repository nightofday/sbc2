import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/widgets/common/app_dialog.dart';

void main() {
  testWidgets('a void needs a reason and keeps it when the action fails', (
    tester,
  ) async {
    final reasons = <String>[];
    var failNext = true;
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showReasonDialog(
                  context: context,
                  title: 'Void Release SO-1',
                  message: 'This returns the stock.',
                  confirmLabel: 'Void Release',
                  onConfirm: (reason) async {
                    reasons.add(reason);
                    if (failNext) {
                      failNext = false;
                      return 'Only a posted stock release can be voided';
                    }
                    return null;
                  },
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Void Release'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a reason.'), findsOneWidget);
    expect(reasons, isEmpty);

    await tester.enterText(find.byType(TextField), '  Wrong item  ');
    await tester.tap(find.text('Void Release'));
    await tester.pumpAndSettle();
    expect(
      find.text('Only a posted stock release can be voided'),
      findsOneWidget,
    );
    expect(find.text('  Wrong item  '), findsOneWidget);

    await tester.tap(find.text('Void Release'));
    await tester.pumpAndSettle();

    expect(reasons, ['Wrong item', 'Wrong item']);
    expect(result, isTrue);
    expect(find.text('Void Release SO-1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling a void reports that nothing was done', (
    tester,
  ) async {
    var called = false;
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showReasonDialog(
                  context: context,
                  title: 'Void Expense',
                  message: 'This keeps the expense on record.',
                  confirmLabel: 'Void Expense',
                  onConfirm: (reason) async {
                    called = true;
                    return null;
                  },
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(result, isFalse);
  });
}
