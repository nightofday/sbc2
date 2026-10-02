import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/widgets/common/app_dialog.dart';

void main() {
  testWidgets(
    'a controller disposed after the dialog call is not used while closing',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  final controller = TextEditingController();
                  await showPrototypeDialog<void>(
                    context: context,
                    title: 'Line',
                    content: StatefulBuilder(
                      builder: (_, _) => TextField(controller: controller),
                    ),
                    actions: [
                      Builder(
                        builder: (dialogContext) => TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  );
                  controller.dispose();
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '50');
      await tester.tap(find.text('Save'));
      // Step through the closing transition frame by frame.
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNothing);
    },
  );
}
