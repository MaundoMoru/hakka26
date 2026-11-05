import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const HakkaApp());

/// Checks a code with the backend. Returns true when the code is valid.
typedef OtpVerifier = Future<bool> Function(String code);

/// The code the challenge treats as valid. Stands in for a real backend check.
const demoValidCode = '123456';

Future<bool> demoVerifier(String code) async => code == demoValidCode;

class HakkaApp extends StatelessWidget {
  const HakkaApp({super.key, this.verifier = demoVerifier});

  final OtpVerifier verifier;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'hakkahakka26',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: OtpScreen(verifier: verifier),
    );
  }

  static ThemeData _theme(Brightness brightness) => ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: OtpColors.light.buttonBg,
      brightness: brightness,
    ),
  );
}

// ---------------------------------------------------------------------------
// Copy and colours
// ---------------------------------------------------------------------------

abstract final class OtpCopy {
  static const title = 'Enter your code';
  static const subtitle = 'A 6-digit code has been sent to your phone.';
  static const resendPrompt = "Didn't receive the code? ";
  static const resend = 'Resend';
  static const submit = 'Submit';
  static const success = "You're in.";
  static const error = "That code didn't work. Try again.";
  static const placeholder = '–';

  static String resendIn(String time) => 'Resend in $time';
  static String digitLabel(int position, int length) =>
      'Digit $position of $length';
}

/// The OTP palette from assets/colours.json, for light and dark mode.
class OtpColors {
  const OtpColors({
    required this.sheet,
    required this.scrim,
    required this.textPrimary,
    required this.textSecondary,
    required this.digitFilledBg,
    required this.digitFilledText,
    required this.digitFocusedBg,
    required this.digitFocusedOutline,
    required this.digitEmptyBg,
    required this.digitEmptyOutline,
    required this.digitPlaceholder,
    required this.buttonBg,
    required this.buttonText,
    required this.buttonDisabledBg,
    required this.link,
    required this.success,
    required this.error,
  });

  final Color sheet;
  final Color scrim;
  final Color textPrimary;
  final Color textSecondary;
  final Color digitFilledBg;
  final Color digitFilledText;
  final Color digitFocusedBg;
  final Color digitFocusedOutline;
  final Color digitEmptyBg;
  final Color digitEmptyOutline;
  final Color digitPlaceholder;
  final Color buttonBg;
  final Color buttonText;
  final Color buttonDisabledBg;
  final Color link;
  final Color success;
  final Color error;

  static const light = OtpColors(
    sheet: Color(0xFFFFFFFF),
    scrim: Color(0x99000000),
    textPrimary: Color(0xFF111111),
    textSecondary: Color(0xFF5F6368),
    digitFilledBg: Color(0xFF12361B),
    digitFilledText: Color(0xFFFFFFFF),
    digitFocusedBg: Color(0xFFFFFFFF),
    digitFocusedOutline: Color(0xFF111111),
    digitEmptyBg: Color(0xFFF1F1F1),
    digitEmptyOutline: Color(0xFFE0E0E0),
    digitPlaceholder: Color(0xFF9E9E9E),
    buttonBg: Color(0xFF12361B),
    buttonText: Color(0xFFFFFFFF),
    buttonDisabledBg: Color(0xFFC9D1CB),
    link: Color(0xFF12361B),
    success: Color(0xFF1B7F3A),
    error: Color(0xFFC62828),
  );

  static const dark = OtpColors(
    sheet: Color(0xFF161A17),
    scrim: Color(0xCC000000),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xFFB0B5B1),
    digitFilledBg: Color(0xFF2E7D45),
    digitFilledText: Color(0xFFFFFFFF),
    digitFocusedBg: Color(0xFF161A17),
    digitFocusedOutline: Color(0xFFF5F5F5),
    digitEmptyBg: Color(0xFF262B27),
    digitEmptyOutline: Color(0xFF353B36),
    digitPlaceholder: Color(0xFF6F7570),
    buttonBg: Color(0xFF2E7D45),
    buttonText: Color(0xFFFFFFFF),
    buttonDisabledBg: Color(0xFF2A302B),
    link: Color(0xFF7BC795),
    success: Color(0xFF7BC795),
    error: Color(0xFFEF9A9A),
  );

  static OtpColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum OtpStatus { idle, verifying, success, error }

/// Owns the OTP entry: the digits, which box has focus, and verification.
///
/// The widgets only render this state and forward user input to it.
class OtpController extends ChangeNotifier {
  OtpController({required this.verifier, this.length = 6})
    : _digits = List.filled(length, ''),
      fields = List.generate(length, (_) => _DigitFieldController()) {
    focusNodes = List.generate(
      length,
      (index) => FocusNode(
        debugLabel: 'otp_digit_${index + 1}',
        onKeyEvent: (_, event) => _handleKey(index, event),
      ),
    );
  }

  final OtpVerifier verifier;
  final int length;
  final List<String> _digits;
  final List<TextEditingController> fields;
  late final List<FocusNode> focusNodes;

  OtpStatus _status = OtpStatus.idle;
  bool _disposed = false;

  OtpStatus get status => _status;
  String get code => _digits.join();
  bool get isComplete => _digits.every((digit) => digit.isNotEmpty);
  bool get canSubmit => isComplete && _status != OtpStatus.verifying;

  /// Box [index] changed: a digit was typed or deleted, or digits were pasted.
  void onFieldChanged(int index, String digits) {
    if (digits.isEmpty) {
      _digits[index] = '';
    } else if (digits.length == 1) {
      _digits[index] = digits;
      _focus(index + 1);
    } else {
      // A paste: a whole code fills every box, a partial one fills from here.
      final start = digits.length >= length ? 0 : index;
      final pasted = digits.substring(
        0,
        (length - start).clamp(0, digits.length),
      );
      for (var i = 0; i < pasted.length; i++) {
        _digits[start + i] = pasted[i];
      }
      _focus(start + pasted.length);
    }
    _afterEdit();
  }

  Future<void> submit() async {
    if (!canSubmit) return;
    _setStatus(OtpStatus.verifying);

    final valid = await verifier(code);
    if (_disposed) return;

    if (valid) {
      for (final node in focusNodes) {
        node.unfocus();
      }
      _setStatus(OtpStatus.success);
    } else {
      _digits.fillRange(0, length, '');
      _syncFields();
      _focus(0);
      _setStatus(OtpStatus.error);
    }
  }

  /// Hides the success or error message, e.g. after a new code is requested.
  void dismissStatus() {
    if (_status == OtpStatus.success || _status == OtpStatus.error) {
      _setStatus(OtpStatus.idle);
    }
  }

  /// Backspace on an empty box moves back and clears the previous digit.
  KeyEventResult _handleKey(int index, KeyEvent event) {
    final isBackspace =
        event is! KeyUpEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace;
    if (!isBackspace || index == 0 || _digits[index].isNotEmpty) {
      return KeyEventResult.ignored;
    }
    _digits[index - 1] = '';
    _focus(index - 1);
    _afterEdit();
    return KeyEventResult.handled;
  }

  void _afterEdit() {
    _syncFields();
    if (_status == OtpStatus.success || _status == OtpStatus.error) {
      _status = OtpStatus.idle;
    }
    notifyListeners();
  }

  void _syncFields() {
    for (var i = 0; i < length; i++) {
      if (fields[i].text != _digits[i]) fields[i].text = _digits[i];
    }
  }

  void _focus(int index) =>
      focusNodes[index.clamp(0, length - 1)].requestFocus();

  void _setStatus(OtpStatus status) {
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final field in fields) {
      field.dispose();
    }
    for (final node in focusNodes) {
      node.dispose();
    }
    super.dispose();
  }
}

/// Keeps a box's digit selected, so typing or pasting replaces it rather than
/// landing next to it.
class _DigitFieldController extends TextEditingController {
  @override
  set value(TextEditingValue newValue) {
    super.value = newValue.text.isEmpty
        ? newValue
        : newValue.copyWith(
            selection: TextSelection(
              baseOffset: 0,
              extentOffset: newValue.text.length,
            ),
            composing: TextRange.empty,
          );
  }
}

/// Counts down until another code may be requested.
class ResendCountdown extends ChangeNotifier {
  ResendCountdown({this.duration = const Duration(seconds: 30)});

  final Duration duration;
  Timer? _timer;
  int _secondsLeft = 0;

  bool get isRunning => _secondsLeft > 0;

  /// Time left as M:SS, e.g. 0:09.
  String get label =>
      '${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')}';

  void start() {
    _timer?.cancel();
    _secondsLeft = duration.inSeconds;
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _secondsLeft--;
      if (_secondsLeft <= 0) timer.cancel();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.verifier});

  final OtpVerifier verifier;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  late final _otp = OtpController(verifier: widget.verifier);
  final _resend = ResendCountdown()..start();

  void _requestNewCode() {
    _otp.dismissStatus();
    _resend.start();
  }

  @override
  void dispose() {
    _otp.dispose();
    _resend.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = OtpColors.of(context);
    return Scaffold(
      backgroundColor: colors.sheet,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ExcludeSemantics(child: _BackdropPage()),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: ColoredBox(color: colors.scrim),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 72),
              child: OtpSheet(
                otp: _otp,
                resend: _resend,
                onResend: _requestNewCode,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bottom sheet holding the OTP form.
class OtpSheet extends StatelessWidget {
  const OtpSheet({
    super.key,
    required this.otp,
    required this.resend,
    required this.onResend,
  });

  final OtpController otp;
  final ResendCountdown resend;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    final colors = OtpColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 36, bottom: 16),
                  child: Column(
                    children: [
                      Image.asset(
                        'assets/thamani-logo.png',
                        height: 64,
                        semanticLabel: 'Thamani logo',
                      ),
                      const SizedBox(height: 24),
                      Semantics(
                        header: true,
                        child: Text(
                          OtpCopy.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        OtpCopy.subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 32),
                      OtpInput(controller: otp),
                      const SizedBox(height: 16),
                      OtpStatusMessage(controller: otp),
                      const SizedBox(height: 8),
                      ResendLine(countdown: resend, onResend: onResend),
                    ],
                  ),
                ),
              ),
              SubmitButton(controller: otp),
            ],
          ),
        ),
      ),
    );
  }
}

/// Six circular digit boxes.
class OtpInput extends StatelessWidget {
  const OtpInput({super.key, required this.controller});

  final OtpController controller;

  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) {
    final length = controller.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final diameter = ((constraints.maxWidth - _gap * (length - 1)) / length)
            .clamp(36.0, 52.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < length; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              OtpDigitBox(
                key: Key('otp_digit_${i + 1}'),
                position: i + 1,
                length: length,
                diameter: diameter,
                field: controller.fields[i],
                focusNode: controller.focusNodes[i],
                autofocus: i == 0,
                onChanged: (digits) => controller.onFieldChanged(i, digits),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// One digit box. Filled: dark green with a white digit. Focused: sheet
/// colour with a dark outline. Empty: light grey with a dash placeholder.
class OtpDigitBox extends StatelessWidget {
  const OtpDigitBox({
    super.key,
    required this.position,
    required this.length,
    required this.diameter,
    required this.field,
    required this.focusNode,
    required this.onChanged,
    this.autofocus = false,
  });

  final int position;
  final int length;
  final double diameter;
  final TextEditingController field;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = OtpColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([focusNode, field]),
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        final filled = field.text.isNotEmpty;
        final (background, outline, digitColor) = focused
            ? (
                colors.digitFocusedBg,
                colors.digitFocusedOutline,
                colors.textPrimary,
              )
            : filled
            ? (
                colors.digitFilledBg,
                colors.digitFilledBg,
                colors.digitFilledText,
              )
            : (
                colors.digitEmptyBg,
                colors.digitEmptyOutline,
                colors.textPrimary,
              );

        return Semantics(
          identifier: 'otp_digit_$position',
          label: OtpCopy.digitLabel(position, length),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: diameter,
            height: diameter,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: background,
              border: Border.all(color: outline, width: focused ? 1.5 : 1),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!filled)
                  ExcludeSemantics(
                    child: Text(
                      OtpCopy.placeholder,
                      style: TextStyle(
                        fontSize: 18,
                        color: colors.digitPlaceholder,
                      ),
                    ),
                  ),
                TextSelectionTheme(
                  data: const TextSelectionThemeData(
                    selectionColor: Colors.transparent,
                  ),
                  child: TextField(
                    controller: field,
                    focusNode: focusNode,
                    autofocus: autofocus,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    autofillHints: position == 1
                        ? const [AutofillHints.oneTimeCode]
                        : null,
                    textAlign: TextAlign.center,
                    showCursor: false,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: digitColor,
                    ),
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                    ),
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Success or error after Submit; announced to screen readers when it changes.
class OtpStatusMessage extends StatelessWidget {
  const OtpStatusMessage({super.key, required this.controller});

  final OtpController controller;

  @override
  Widget build(BuildContext context) {
    final colors = OtpColors.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final (message, color) = switch (controller.status) {
          OtpStatus.success => (OtpCopy.success, colors.success),
          OtpStatus.error => (OtpCopy.error, colors.error),
          OtpStatus.idle || OtpStatus.verifying => ('', colors.textSecondary),
        };
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 20),
          child: Semantics(
            liveRegion: true,
            child: Text(
              message,
              key: const Key('otp_status'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "Didn't receive the code? Resend", disabled during the countdown.
class ResendLine extends StatelessWidget {
  const ResendLine({
    super.key,
    required this.countdown,
    required this.onResend,
  });

  final ResendCountdown countdown;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    final colors = OtpColors.of(context);
    return ListenableBuilder(
      listenable: countdown,
      builder: (context, _) {
        final waiting = countdown.isRunning;
        return Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              OtpCopy.resendPrompt,
              style: TextStyle(fontSize: 14, color: colors.textSecondary),
            ),
            TextButton(
              key: const Key('otp_resend'),
              onPressed: waiting ? null : onResend,
              style: TextButton.styleFrom(
                foregroundColor: colors.link,
                disabledForegroundColor: colors.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(48, 48),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(
                waiting ? OtpCopy.resendIn(countdown.label) : OtpCopy.resend,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Full-width rounded Submit, enabled once all six digits are in.
class SubmitButton extends StatelessWidget {
  const SubmitButton({super.key, required this.controller});

  final OtpController controller;

  @override
  Widget build(BuildContext context) {
    final colors = OtpColors.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton(
          key: const Key('otp_submit'),
          onPressed: controller.canSubmit ? controller.submit : null,
          style: FilledButton.styleFrom(
            backgroundColor: colors.buttonBg,
            foregroundColor: colors.buttonText,
            disabledBackgroundColor: colors.buttonDisabledBg,
            disabledForegroundColor: colors.buttonText,
            shape: const StadiumBorder(),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          child: const Text(OtpCopy.submit),
        ),
      ),
    );
  }
}

/// The sign-in page behind the sheet, dimmed and blurred by the scrim.
class _BackdropPage extends StatelessWidget {
  const _BackdropPage();

  @override
  Widget build(BuildContext context) {
    final colors = OtpColors.of(context);
    Widget bar(double height) => Container(
      height: height,
      decoration: BoxDecoration(
        color: colors.digitEmptyBg,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
    return ColoredBox(
      color: colors.sheet,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Text(
                'Welcome back',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, color: colors.textPrimary),
              ),
              const SizedBox(height: 32),
              bar(52),
              const SizedBox(height: 16),
              bar(52),
              const Spacer(),
              bar(56),
            ],
          ),
        ),
      ),
    );
  }
}
