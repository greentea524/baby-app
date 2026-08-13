import 'package:flutter/services.dart';

/// Formatters for the app's numeric fields.
///
/// The point of these is the minus sign. Amounts and durations are quantities
/// — there is no such thing as minus 40 ml — and the security rules now
/// refuse a negative one (#22). Since a sheet closes without waiting for the
/// write (#21), that refusal would arrive as a snackbar minutes later, on a
/// screen that has moved on, with nothing left to explain it. Far cheaper to
/// make the character untypeable than to explain its consequences.
///
/// Not validation: a field can still be left empty or hold something
/// unparseable, and the forms handle that themselves.

/// Digits and a decimal point — millilitres, kilograms, centimetres.
///
/// The point stays a point whatever the locale, because that is what
/// `double.parse` accepts and how the field is read back.
final positiveDecimalInput = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
];

/// Digits only — whole minutes.
final wholeNumberInput = <TextInputFormatter>[
  FilteringTextInputFormatter.digitsOnly,
];
