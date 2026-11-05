import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hakka/main.dart';

Finder digitBox(int position) => find.byKey(Key('otp_digit_$position'));

EditableText _editable(WidgetTester tester, int position) =>
    tester.widget<EditableText>(
      find.descendant(
        of: digitBox(position),
        matching: find.byType(EditableText),
      ),
    );

String digitAt(WidgetTester tester, int position) =>
    _editable(tester, position).controller.text;

String allDigits(WidgetTester tester) =>
    [for (var i = 1; i <= 6; i++) digitAt(tester, i)].join();

bool isFocused(WidgetTester tester, int position) =>
    _editable(tester, position).focusNode.hasFocus;

Color boxColor(WidgetTester tester, int position) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(
      of: digitBox(position),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return (container.decoration! as BoxDecoration).color!;
}

String statusText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('otp_status'))).data!;

bool submitEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('otp_submit'))).enabled;

bool resendEnabled(WidgetTester tester) =>
    tester.widget<TextButton>(find.byKey(const Key('otp_resend'))).enabled;

Future<void> pumpOtpScreen(WidgetTester tester) async {
  await tester.pumpWidget(const HakkaApp());
  await tester.pump(); // apply autofocus
}

/// Types into whichever box has focus, like the on-screen keyboard does.
Future<void> typeDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    tester.testTextInput.enterText(digit);
    await tester.pump();
  }
}

Future<void> submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('otp_submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the copy, six empty boxes and focuses the first', (
    tester,
  ) async {
    await pumpOtpScreen(tester);

    expect(find.text(OtpCopy.title), findsOneWidget);
    expect(find.text(OtpCopy.subtitle), findsOneWidget);
    expect(find.text(OtpCopy.resendPrompt), findsOneWidget);
    expect(find.text(OtpCopy.submit), findsOneWidget);
    for (var i = 1; i <= 6; i++) {
      expect(digitBox(i), findsOneWidget);
      expect(digitAt(tester, i), isEmpty);
    }
    expect(find.text(OtpCopy.placeholder), findsNWidgets(6));
    expect(find.text('0'), findsNothing);
    expect(isFocused(tester, 1), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(_editable(tester, 1).keyboardType, TextInputType.number);
  });

  testWidgets('boxes use the filled, focused and empty colours', (
    tester,
  ) async {
    await pumpOtpScreen(tester);
    await typeDigits(tester, '21');

    const colors = OtpColors.light;
    expect(boxColor(tester, 1), colors.digitFilledBg);
    expect(boxColor(tester, 2), colors.digitFilledBg);
    expect(boxColor(tester, 3), colors.digitFocusedBg);
    expect(boxColor(tester, 4), colors.digitEmptyBg);
  });

  testWidgets('typing a digit moves focus to the next box', (tester) async {
    await pumpOtpScreen(tester);

    await typeDigits(tester, '7');

    expect(digitAt(tester, 1), '7');
    expect(isFocused(tester, 2), isTrue);
  });

  testWidgets('non-digits are rejected', (tester) async {
    await pumpOtpScreen(tester);

    await tester.enterText(digitBox(1), 'a');
    await tester.pump();

    expect(digitAt(tester, 1), isEmpty);
    expect(isFocused(tester, 1), isTrue);
  });

  testWidgets('backspace on an empty box clears the previous digit', (
    tester,
  ) async {
    await pumpOtpScreen(tester);
    await typeDigits(tester, '12');
    expect(isFocused(tester, 3), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(digitAt(tester, 1), '1');
    expect(digitAt(tester, 2), isEmpty);
    expect(isFocused(tester, 2), isTrue);
  });

  testWidgets('pasting text fills all six boxes with its digits', (
    tester,
  ) async {
    await pumpOtpScreen(tester);

    await tester.enterText(digitBox(1), 'Your code is 482913');
    await tester.pump();

    expect(allDigits(tester), '482913');
    expect(submitEnabled(tester), isTrue);
  });

  testWidgets('Submit is disabled until all six digits are filled', (
    tester,
  ) async {
    await pumpOtpScreen(tester);
    expect(submitEnabled(tester), isFalse);

    await typeDigits(tester, '12345');
    expect(submitEnabled(tester), isFalse);

    await typeDigits(tester, '6');
    expect(submitEnabled(tester), isTrue);
  });

  testWidgets('123456 shows the success message', (tester) async {
    await pumpOtpScreen(tester);
    await typeDigits(tester, '123456');

    await submit(tester);

    expect(statusText(tester), OtpCopy.success);
    expect(find.text("You're in."), findsOneWidget);
  });

  testWidgets('a wrong code shows the error, clears and refocuses box 1', (
    tester,
  ) async {
    await pumpOtpScreen(tester);
    await typeDigits(tester, '654321');

    await submit(tester);

    expect(statusText(tester), OtpCopy.error);
    expect(find.text("That code didn't work. Try again."), findsOneWidget);
    expect(allDigits(tester), isEmpty);
    expect(isFocused(tester, 1), isTrue);
    expect(submitEnabled(tester), isFalse);
  });

  testWidgets('Resend counts down from 30 s, then restarts when tapped', (
    tester,
  ) async {
    await pumpOtpScreen(tester);
    expect(find.text('Resend in 0:30'), findsOneWidget);
    expect(resendEnabled(tester), isFalse);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resend in 0:29'), findsOneWidget);

    await tester.pump(const Duration(seconds: 29));
    expect(find.text(OtpCopy.resend), findsOneWidget);
    expect(resendEnabled(tester), isTrue);

    await tester.tap(find.byKey(const Key('otp_resend')));
    await tester.pump();
    expect(find.text('Resend in 0:30'), findsOneWidget);
    expect(resendEnabled(tester), isFalse);
  });

  testWidgets('each box is announced as "Digit N of 6"', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpOtpScreen(tester);

    for (var i = 1; i <= 6; i++) {
      expect(
        tester.getSemantics(digitBox(i)),
        isSemantics(
          label: 'Digit $i of 6',
          identifier: 'otp_digit_$i',
          isTextField: true,
          isFocused: i == 1,
        ),
      );
    }
    semantics.dispose();
  });

  testWidgets('uses the dark palette in dark mode', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpOtpScreen(tester);
    await typeDigits(tester, '2');

    const colors = OtpColors.dark;
    expect(boxColor(tester, 1), colors.digitFilledBg);
    expect(boxColor(tester, 2), colors.digitFocusedBg);
    expect(boxColor(tester, 3), colors.digitEmptyBg);
    final sheet = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.text(OtpCopy.title),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((sheet.decoration as BoxDecoration).color, colors.sheet);
  });
}
