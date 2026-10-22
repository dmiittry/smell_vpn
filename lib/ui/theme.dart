import 'package:flutter/material.dart';

const mint = Color(0xFFA9C8EA);
const success = Color(0xFF66BB6A);
const failure = Color(0xFFFF6B6B);
const canvas = Color(0xFF181C21);
const panel = Color(0xFF1E232A);
const muted = Color(0xFF8D9CA8);
const line = Color(0xFF25323C);
const amber = Color(0xFFF2C078);

ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Roboto',
  brightness: Brightness.dark,
  scaffoldBackgroundColor: canvas,
  colorScheme: const ColorScheme.dark(
    primary: mint,
    onPrimary: canvas,
    secondary: amber,
    surface: panel,
    onSurface: Color(0xFFF0F4F7),
    error: failure,
    outline: line,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w600,
      letterSpacing: -1,
    ),
    headlineMedium: TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w600,
      letterSpacing: -.6,
    ),
    titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    bodyMedium: TextStyle(fontSize: 14, height: 1.55),
    bodySmall: TextStyle(fontSize: 12, color: muted, height: 1.5),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: canvas,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: mint),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      side: const BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: panel,
    indicatorColor: Color(0xFF344656),
    height: 74,
  ),
  dividerTheme: const DividerThemeData(color: line, thickness: 1),
);

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: panel,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.color = mint});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: color.withValues(alpha: .18)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: .6,
      ),
    ),
  );
}

class ErrorNotice extends StatelessWidget {
  const ErrorNotice(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF2C2025),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          color: Color(0xFFFF9898),
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Color(0xFFFFB6B6)),
          ),
        ),
      ],
    ),
  );
}
