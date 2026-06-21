import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'models/customer_model.dart';
import 'models/demand_item_model.dart';
import 'models/supplier_model.dart';
import 'models/udhaar_entry_model.dart';
import 'providers/auth_provider.dart';
import 'screens/admin/ai_chat_screen.dart';
import 'screens/admin/user_management_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/pending_approval_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/customer/add_edit_customer_screen.dart';
import 'screens/customer/customer_list_screen.dart';
import 'screens/demand/add_edit_demand_screen.dart';
import 'screens/demand/category_management_screen.dart';
import 'screens/demand/demand_list_screen.dart';
import 'screens/demand/pricing_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/supplier/add_edit_supplier_screen.dart';
import 'screens/supplier/supplier_detail_screen.dart';
import 'screens/suppliers/supplier_list_screen.dart';
import 'screens/udhaar/add_edit_udhaar_screen.dart';
import 'screens/udhaar/contact_ledger_screen.dart';
import 'screens/udhaar/udhaar_list_screen.dart';
import 'widgets/scaffold_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildRouter(BuildContext context) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: context.read<AuthProvider>(),
    redirect: (context, state) {
      final auth = context.read<AuthProvider>();
      final loc = state.fullPath ?? '';

      switch (auth.status) {
        case AuthStatus.unknown:
          return loc == '/splash' ? null : '/splash';

        case AuthStatus.unauthenticated:
          final okWhenUnauth = loc == '/login' || loc == '/signup';
          return okWhenUnauth ? null : '/login';

        case AuthStatus.pendingApproval:
          return loc == '/pending' ? null : '/pending';

        case AuthStatus.authenticated:
          final isOnAuthScreen = loc == '/login' ||
              loc == '/signup' ||
              loc == '/splash' ||
              loc == '/pending';
          if (isOnAuthScreen) return '/home';

          if (loc == '/admin/users' &&
              !(auth.currentUser?.isAdmin ?? false)) {
            return '/home';
          }

          final isViewer = auth.currentUser?.isViewer ?? false;
          if (isViewer) {
            const restrictedRoutes = [
              '/suppliers',
              '/supplier/detail',
              '/supplier/add',
              '/supplier/edit',
              '/udhaar',
              '/udhaar/add',
              '/udhaar/edit',
              '/contact/ledger',
              '/customers',
              '/customer/add',
              '/customer/edit',
              '/demand/add',
              '/demand/edit',
              '/demand/categories',
              '/demand/pricing',
            ];
            if (restrictedRoutes.contains(loc)) return '/home';
          }

          return null;
      }
    },
    routes: [
      // ── Auth & splash screens ────────────────────────────────────────────
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(
          path: '/pending',
          builder: (_, __) => const PendingApprovalScreen()),

      // ── Admin ────────────────────────────────────────────────────────────
      GoRoute(
        path: '/admin/users',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const UserManagementScreen(),
      ),
      GoRoute(
        path: '/admin/ai-chat',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AiChatScreen(),
      ),

      // ── Demand sub-screens ───────────────────────────────────────────────
      GoRoute(
        path: '/demand/add',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AddEditDemandScreen(),
      ),
      GoRoute(
        path: '/demand/edit',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => AddEditDemandScreen(
          existingItem: state.extra as DemandItemModel?,
        ),
      ),
      GoRoute(
        path: '/demand/categories',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const CategoryManagementScreen(),
      ),
      GoRoute(
        path: '/demand/pricing',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const PricingScreen(),
      ),

      // ── Supplier sub-screens ─────────────────────────────────────────────
      GoRoute(
        path: '/supplier/detail',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) {
          final supplier = state.extra;
          if (supplier is! SupplierModel) {
            return const Scaffold(body: Center(child: Text('Invalid route')));
          }
          return SupplierDetailScreen(supplier: supplier);
        },
      ),
      GoRoute(
        path: '/supplier/add',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AddEditSupplierScreen(),
      ),
      GoRoute(
        path: '/supplier/edit',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => AddEditSupplierScreen(
          existingSupplier: state.extra as SupplierModel?,
        ),
      ),

      // ── Udhaar sub-screens ───────────────────────────────────────────────
      GoRoute(
        path: '/udhaar/add',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => AddEditUdhaarScreen(
          prefilledContact: state.extra is PrefilledContact
              ? state.extra as PrefilledContact
              : null,
        ),
      ),
      GoRoute(
        path: '/udhaar/edit',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => AddEditUdhaarScreen(
          existingEntry: state.extra as UdhaarEntryModel?,
        ),
      ),

      // ── Per-contact udhaar ledger ─────────────────────────────────────────
      GoRoute(
        path: '/contact/ledger',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) {
          final args = state.extra;
          if (args is! ContactLedgerArgs) {
            return const Scaffold(body: Center(child: Text('Invalid route')));
          }
          return ContactLedgerScreen(args: args);
        },
      ),

      // ── Customer sub-screens ─────────────────────────────────────────────
      GoRoute(
        path: '/customer/add',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AddEditCustomerScreen(),
      ),
      GoRoute(
        path: '/customer/edit',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => AddEditCustomerScreen(
          existingCustomer: state.extra as CustomerModel?,
        ),
      ),

      // ── Main tabs (persistent nav bar via ShellRoute) ────────────────────
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return ScaffoldShell(
            location: state.fullPath ?? '/home',
            child: child,
          );
        },
        routes: [
          GoRoute(
              path: '/demand', builder: (_, __) => const DemandListScreen()),
          GoRoute(
              path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(
              path: '/udhaar', builder: (_, __) => const UdhaarListScreen()),
          GoRoute(
              path: '/suppliers',
              builder: (_, __) => const SupplierListScreen()),
          GoRoute(
              path: '/customers',
              builder: (_, __) => const CustomerListScreen()),
        ],
      ),
    ],
  );
}
