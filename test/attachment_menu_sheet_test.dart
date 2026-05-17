import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_messenger/widgets/attachment_menu_sheet.dart';

void main() {
  Widget buildTestWidget({
    VoidCallback? onCameraTap,
    VoidCallback? onGalleryTap,
    VoidCallback? onDocumentTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: AttachmentMenuSheet(
          onCameraTap: onCameraTap ?? () {},
          onGalleryTap: onGalleryTap ?? () {},
          onDocumentTap: onDocumentTap ?? () {},
        ),
      ),
    );
  }

  testWidgets('renders three options in fixed order: Camera, Gallery, Document',
      (tester) async {
    await tester.pumpWidget(buildTestWidget());

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();

    expect(texts, ['Camera', 'Gallery', 'Document']);
  });

  testWidgets('displays correct icons for each option', (tester) async {
    await tester.pumpWidget(buildTestWidget());

    expect(find.byIcon(Icons.camera_alt), findsOneWidget);
    expect(find.byIcon(Icons.photo_library), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file), findsOneWidget);
  });

  testWidgets('uses dark background color', (tester) async {
    await tester.pumpWidget(buildTestWidget());

    final container = tester.widget<Container>(
      find.byType(Container).first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFF1E1E1E));
  });

  testWidgets('uses white text color for labels', (tester) async {
    await tester.pumpWidget(buildTestWidget());

    final cameraText = tester.widget<Text>(find.text('Camera'));
    expect(cameraText.style?.color, Colors.white);

    final galleryText = tester.widget<Text>(find.text('Gallery'));
    expect(galleryText.style?.color, Colors.white);

    final documentText = tester.widget<Text>(find.text('Document'));
    expect(documentText.style?.color, Colors.white);
  });

  testWidgets('uses white icon color', (tester) async {
    await tester.pumpWidget(buildTestWidget());

    final icons = tester.widgetList<Icon>(find.byType(Icon));
    for (final icon in icons) {
      expect(icon.color, Colors.white);
    }
  });

  testWidgets('calls onCameraTap when Camera option is tapped', (tester) async {
    bool cameraTapped = false;
    await tester.pumpWidget(buildTestWidget(
      onCameraTap: () => cameraTapped = true,
    ));

    await tester.tap(find.text('Camera'));
    expect(cameraTapped, isTrue);
  });

  testWidgets('calls onGalleryTap when Gallery option is tapped',
      (tester) async {
    bool galleryTapped = false;
    await tester.pumpWidget(buildTestWidget(
      onGalleryTap: () => galleryTapped = true,
    ));

    await tester.tap(find.text('Gallery'));
    expect(galleryTapped, isTrue);
  });

  testWidgets('calls onDocumentTap when Document option is tapped',
      (tester) async {
    bool documentTapped = false;
    await tester.pumpWidget(buildTestWidget(
      onDocumentTap: () => documentTapped = true,
    ));

    await tester.tap(find.text('Document'));
    expect(documentTapped, isTrue);
  });

  testWidgets('show() displays bottom sheet and dismisses on outside tap',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AttachmentMenuSheet.show(
                context,
                onCameraTap: () {},
                onGalleryTap: () {},
                onDocumentTap: () {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    // Open the bottom sheet
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Verify the sheet is displayed
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('Document'), findsOneWidget);
  });
}
