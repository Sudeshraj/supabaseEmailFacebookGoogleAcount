import 'package:flutter/material.dart';

// ============================================================
// GLOBAL ROUTE OBSERVERS
// ------------------------------------------------------------
// Centralized route observers used across the app.
//
// Why a separate file?
//   • Single source of truth
//   • Imported by both `main.dart` (to register with GoRouter)
//     and `customer_dashboard.dart` (to subscribe as RouteAware)
//   • Avoids circular imports (dashboard ← main.dart)
//   • Extensible — add more observers here as the app grows
//     (e.g., ownerRouteObserver, barberRouteObserver, etc.)
// ============================================================

/// Used by CustomerDashboard to auto-refresh when returning
/// from child routes (Settings, Bookings, Salon Profile, etc.)
final RouteObserver<ModalRoute<void>> dashboardRouteObserver =
    RouteObserver<ModalRoute<void>>();

// ============================================================
// FUTURE OBSERVERS (add here as needed)
// ------------------------------------------------------------
// final RouteObserver<ModalRoute<void>> ownerRouteObserver =
//     RouteObserver<ModalRoute<void>>();
//
// final RouteObserver<ModalRoute<void>> barberRouteObserver =
//     RouteObserver<ModalRoute<void>>();
// ============================================================