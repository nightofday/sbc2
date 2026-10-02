import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/widgets/common/app_dialog.dart';
import 'package:sbc_management_system/widgets/common/data_table_card.dart';
import 'package:sbc_management_system/widgets/common/responsive_filter_bar.dart';
import 'package:sbc_management_system/widgets/common/summary_card.dart';
import 'package:sbc_management_system/widgets/layout/app_page.dart';

void main() {
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

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
