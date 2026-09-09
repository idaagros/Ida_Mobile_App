// lib/models/user_model.dart

// ─── Module definitions ────────────────────────────────────────────────────
//
// RULES:
// 1. Key must exactly match what dashboard_screen.dart checks with _can()
// 2. Only list modules that have a real working screen
// 3. Adding a new entry here automatically shows it in the admin user form
//    so admin can grant access to existing users without any code change

const List<Map<String, String>> kModuleDefinitions = [
  // ── Working screens ──────────────────────────────────────────────────────
  {
    'key': 'electricity',
    'label': 'Electricity Meter Reading',
    'description': 'Submit and view daily electricity meter readings',
    'route': '/electricity',
    'icon': 'electric_bolt',
  },
  {
    'key': 'tractor',
    'label': 'Factory Tractor Hours Reading',
    'description': 'Submit daily tractor meter readings and hours',
    'route': '/tractor',
    'icon': 'agriculture',
  },
  {
    'key': 'labour',
    'label': 'Labour Management',
    'description': 'Add, edit and view labour attendance records',
    'route': '/labour',
    'icon': 'people',
  },
  {
    'key': 'factory',
    'label': 'Factory Run Hours',
    'description': 'Log machine start/stop times and downtime',
    'route': '/factory',
    'icon': 'factory',
  },
  {
    'key': 'farm_attendance',
    'label': 'Farm Attendance',
    'description': 'Record daily attendance and wages for farm field workers',
    'route': '/farm-attendance',
    'icon': 'payments',
  },
  {
    'key': 'farm_tractor',
    'label': 'Farm Tractor',
    'description':
        'Assign tractor field work and log hours, diesel and billing',
    'route': '/farm-tractor',
    'icon': 'agriculture',
  },
  {
    'key': 'agri',
    'label': 'Crop Planning',
    'description':
        'Manage crop masters, orchard blocks and agronomy schedule templates',
    'route': '/agri',
    'icon': 'eco',
  },
  {
    'key': 'machine',
    'label': 'Machine Hours Reading',
    'description': 'Submit daily machine meter readings',
    'route': '/machine',
    'icon': 'precision_manufacturing',
  },
  {
    'key': 'machine_pf',
    'label': 'Power Factor Reading',
    'description': 'Submit daily Power Factor (PF) meter readings',
    'route': '/machine-pf',
    'icon': 'bolt',
  },
  {
    'key': 'outward_register',
    'label': 'Outward Sales Register',
    'description': 'Log truck dispatches: weighment, bhada, invoice & agent',
    'route': '/outward-register',
    'icon': 'local_shipping',
  },
  {
    'key': 'machine_maintenance',
    'label': 'Machine Maintenance',
    'description': 'Machine maintenance schedule, alerts & history',
    'route': '/machine-maintenance',
    'icon': 'precision_manufacturing',
  },
  {
    'key': 'tractor_maintenance',
    'label': 'Tractor Maintenance',
    'description': 'Maintenance schedule, alerts & history',
    'route': '/tractor-maintenance',
    'icon': 'build_circle',
  },
  // ── Planned screens (visible to admin, grantable in advance) ─────────────
  {
    'key': 'daily_report',
    'label': 'Daily Reports',
    'description': 'Submit and review daily field activity logs',
    'route': '/reports',
    'icon': 'assignment',
  },
  {
    'key': 'reports_analytics',
    'label': 'Reports & Analytics',
    'description': 'View charts, summaries, and data exports',
    'route': '/analytics',
    'icon': 'bar_chart',
  },
  {
    'key': 'payroll',
    'label': 'Payroll',
    'description': 'Manage worker wages and deductions',
    'route': '/payroll',
    'icon': 'payments',
  },
  // ── Administrative modules ─────────────────────────────────────────────
  {
    'key': 'transport',
    'label': 'Transport Directory',
    'description': 'View and manage the transporter contact directory',
    'route': '/transport',
    'icon': 'local_shipping',
  },
  {
    'key': 'passwords',
    'label': 'Password Manager',
    'description':
        'Access the secure credential store (OTP required for non-admins)',
    'route': '/passwords',
    'icon': 'vpn_key',
  },
];

// ─── Sector categorization ──────────────────────────────────────────────
//
// Agreed design: every module belongs to exactly one business sector,
// except a small cross-cutting set (passwords, plus admin/settings
// screens that aren't module-gated at all — Manage Users, Language,
// Logout) that stays visible regardless of which sector is selected.
//
// 'passwords' deliberately appears in NEITHER list below — it's the
// one module-gated screen that's cross-cutting, so it's excluded from
// both sector checks and always shown on its own.
const List<String> kFactoryModuleKeys = [
  'electricity',
  'tractor',
  'labour',
  'factory',
  'machine',
  'machine_pf',
  'outward_register',
  'daily_report',
  'reports_analytics',
  'payroll',
  'transport',
  'machine_maintenance',
  'tractor_maintenance',
];

const List<String> kAgricultureModuleKeys = [
  'farm_attendance',
  'farm_tractor',
  'agri',
];

// ─── AppUser ───────────────────────────────────────────────────────────────

// ─── Permission entries ──────────────────────────────────────────────────
//
// Mirrors the backend's exact format (see src/middleware/auth.js) —
// historically a flat list of module-key strings ("has access", no
// view/edit distinction — master-data editing was ALWAYS admin-only
// everywhere). Now a list of {module, level} objects, level =
// 'view'|'edit'. An old-format string entry reads as level='view' —
// deliberate, so no existing grant silently gains edit rights just
// because this code shipped.
//
// parsePermissions() is the ONE safe way to read a raw permissions
// list from JSON — a naive `List<String>.from(json['permissions'])`
// THROWS the instant any entry is a {module,level} object rather than
// a plain string. Every call site that used to do that cast directly
// (api_service.dart, dashboard_screen.dart) needs to go through this
// instead.
class PermissionEntry {
  final String module;
  final String level; // 'view' | 'edit'
  const PermissionEntry(this.module, this.level);

  Map<String, String> toJson() => {'module': module, 'level': level};
}

List<PermissionEntry> parsePermissions(dynamic raw) {
  if (raw is! List) return [];
  return raw
      .map<PermissionEntry?>((p) {
        if (p is String) return PermissionEntry(p, 'view');
        if (p is Map)
          return PermissionEntry('${p['module']}', '${p['level'] ?? 'view'}');
        return null;
      })
      .whereType<PermissionEntry>()
      .toList();
}

bool hasModuleAccess(List<PermissionEntry> perms, String moduleKey) =>
    perms.any((p) => p.module == moduleKey);

bool hasEditAccess(List<PermissionEntry> perms, String moduleKey) =>
    perms.any((p) => p.module == moduleKey && p.level == 'edit');

class AppUser {
  final String? id;
  final String username;
  final String displayName;
  final bool isAdmin;
  final bool isActive;
  final List<PermissionEntry> permissions;

  const AppUser({
    this.id,
    required this.username,
    required this.displayName,
    this.isAdmin = false,
    this.isActive = true,
    required this.permissions,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id']?.toString(),
        username: json['username'] ?? '',
        displayName: json['display_name'] ?? json['name'] ?? '',
        isAdmin: json['is_admin'] == true || json['role'] == 'admin',
        isActive: json['is_active'] ?? true,
        permissions: parsePermissions(json['permissions']),
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'username': username,
        'display_name': displayName,
        'is_admin': isAdmin,
        'is_active': isActive,
        'permissions':
            isAdmin ? [] : permissions.map((p) => p.toJson()).toList(),
      };

  List<Map<String, String>> get accessibleModules {
    if (isAdmin) return List.from(kModuleDefinitions);
    return kModuleDefinitions
        .where((m) => hasModuleAccess(permissions, m['key']!))
        .toList();
  }

  bool canAccess(String moduleKey) =>
      isAdmin || hasModuleAccess(permissions, moduleKey);

  bool canEdit(String moduleKey) =>
      isAdmin || hasEditAccess(permissions, moduleKey);

  AppUser copyWith({
    String? username,
    String? displayName,
    bool? isActive,
    List<PermissionEntry>? permissions,
  }) =>
      AppUser(
        id: id,
        username: username ?? this.username,
        displayName: displayName ?? this.displayName,
        isAdmin: isAdmin,
        isActive: isActive ?? this.isActive,
        permissions: permissions ?? this.permissions,
      );
}
