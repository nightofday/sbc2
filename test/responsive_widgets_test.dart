import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/widgets/common/app_dialog.dart';
import 'package:sbc_management_system/widgets/common/data_table_card.dart';
import 'package:sbc_management_system/widgets/common/responsive_filter_bar.dart';
import 'package:sbc_management_system/widgets/common/summary_card.dart';
import 'package:sbc_management_system/widgets/layout/app_page.dart';

void main() {
  testWidgets('a wide table stacks on a phone so its action is on screen', (
    tester,
  ) async {
    _setViewport(tester, const Size(360, 700));
    await tester.pumpWidget(_wideTable());

    final button = tester.getRect(find.widgetWithText(OutlinedButton, 'Void'));
    expect(button.left, greaterThanOrEqualTo(0));
    expect(button.right, lessThanOrEqualTo(360));
    // Each value is labelled with its column heading.
    expect(find.text('Status'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a tablet the table stacks instead of scrolling sideways', (
    tester,
  ) async {
    _setViewport(tester, const Size(700, 700));
    await tester.pumpWidget(_wideTable());

    final button = tester.getRect(find.widgetWithText(OutlinedButton, 'Void'));
    expect(button.right, lessThanOrEqualTo(700));
    expect(find.text('Status'), findsOneWidget);
    // Values sit two across rather than one per line.
    expect(
      tester.getTopLeft(find.text('Released to service counter')).dx,
      greaterThan(tester.getTopLeft(find.text('10/2 9:18 PM')).dx + 200),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the same table stays a table on a wide screen', (tester) async {
    _setViewport(tester, const Size(1200, 700));
    await tester.pumpWidget(_wideTable());

    final document = tester.getTopLeft(find.text('SO-1'));
    final button = tester.getTopLeft(
      find.widgetWithText(OutlinedButton, 'Void'),
    );
    // Columns sit side by side on one row.
    expect(button.dx, greaterThan(document.dx + 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter bar stacks controls on narrow screens', (tester) async {
    _setViewport(tester, const Size(360, 700));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: ResponsiveFilterBar(
              primary: SizedBox(key: Key('primary'), height: 48),
              filters: [
                SizedBox(key: Key('filter-one'), height: 48),
                SizedBox(key: Key('filter-two'), height: 48),
              ],
              filterWidths: [180, 180],
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.byKey(const Key('filter-one'))).dy,
      greaterThan(tester.getTopLeft(find.byKey(const Key('primary'))).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('filter-two'))).dy,
      greaterThan(tester.getTopLeft(find.byKey(const Key('filter-one'))).dy),
    );

    tester.view.physicalSize = const Size(1000, 700);
    await tester.pump();

    final primaryTop = tester.getTopLeft(find.byKey(const Key('primary'))).dy;
    expect(
      tester.getTopLeft(find.byKey(const Key('filter-one'))).dy,
      primaryTop,
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('filter-two'))).dy,
      primaryTop,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('page cards and wide tables remain usable on a phone', (
    tester,
  ) async {
    _setViewport(tester, const Size(320, 640));
    await tester.pumpWidget(
      MaterialApp(
        home: AppPage(
          title: 'Responsive Prototype Page',
          subtitle: 'A long subtitle that still needs to fit a narrow phone.',
          action: ElevatedButton(
            onPressed: () {},
            child: const Text('Create New Transaction'),
          ),
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SummaryCardGrid(
                  children: [
                    SummaryCard(
                      label: 'Net Sales',
                      value: '₱999,999,999.99',
                      subtitle: 'Current report period',
                      accentColor: Colors.red,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DataTableCard(
                  headers: const [
                    'Document',
                    'Supplier',
                    'Reference',
                    'Employee',
                  ],
                  rows: const [
                    [
                      Text('GR-1001'),
                      Text('Street Bowl Grocery Supplier'),
                      Text('LONG-REFERENCE-1000001'),
                      Text('Prototype Manager'),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Create New Transaction'), findsOneWidget);
    expect(find.text('₱999,999,999.99'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dialog can hold content that adapts to its width', (
    tester,
  ) async {
    _setViewport(tester, const Size(1280, 800));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showPrototypeDialog(
                context: context,
                title: 'Adaptive Dialog',
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LayoutBuilder(
                      builder: (_, constraints) =>
                          Text('Width ${constraints.maxWidth.round()}'),
                    ),
                  ],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // AlertDialog measured intrinsic size, which a LayoutBuilder cannot
    // answer, and the purchase order form went blank after adding an item.
    expect(tester.takeException(), isNull);
    expect(find.text('Width 520'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('prototype dialogs scroll instead of overflowing', (
    tester,
  ) async {
    _setViewport(tester, const Size(320, 640));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showPrototypeDialog<void>(
                  context: context,
                  title: 'Long Responsive Transaction Dialog',
                  width: 900,
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int index = 0; index < 10; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            decoration: InputDecoration(
                              labelText: 'Required field ${index + 1}',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Long Responsive Transaction Dialog'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

Widget _wideTable() {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DataTableCard(
          headers: const [
            'Document',
            'Date',
            'Purpose',
            'Reference',
            'Items',
            'Status',
            'Action',
          ],
          rows: [
            [
              const Text('SO-1'),
              const Text('10/2 9:18 PM'),
              const Text('Released to service counter'),
              const Text('—'),
              const Text('1'),
              const Text('POSTED'),
              OutlinedButton(onPressed: () {}, child: const Text('Void')),
            ],
          ],
        ),
      ),
    ),
  );
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
