import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:baby_app/core/router/app_router.dart';
import 'package:baby_app/data/models/appointment.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/appointments/next_appointment_button.dart';

/// Home's visit pill switches to the Visits tab (#41). It used to push a
/// second copy of the screen over the shell, hiding the bottom bar.
void main() {
  testWidgets('the pill switches tabs rather than stacking a screen', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => Scaffold(
            body: shell,
            bottomNavigationBar: const Text('bottom bar'),
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => Scaffold(
                    appBar: AppBar(
                      actions: [
                        NextAppointmentButton(now: DateTime(2026, 7, 30, 9)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoutes.appointments,
                  builder: (context, state) =>
                      const Scaffold(body: Text('visits tab')),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appointmentsProvider.overrideWith(
            (ref) => Stream.value([
              Appointment(
                id: 'a1',
                at: DateTime(2026, 8, 6, 14),
                kind: AppointmentKind.checkup,
              ),
            ]),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NextAppointmentLabel));
    await tester.pumpAndSettle();

    expect(find.text('visits tab'), findsOneWidget);
    expect(find.text('bottom bar'), findsOneWidget);
    // Nothing to go back to: it is a tab, not a page on top.
    expect(router.canPop(), isFalse);
  });
}
