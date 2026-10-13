import 'models.dart';

enum Permission {
  readTag,
  writeTag,
  formatTag,
  lockTag,
  viewAuditLog,
  manageSigningKey,
  manageUsers,
}

const Map<Role, Set<Permission>> _matrix = {
  Role.owner: {
    Permission.readTag,
    Permission.writeTag,
    Permission.formatTag,
    Permission.lockTag,
    Permission.viewAuditLog,
    Permission.manageSigningKey,
    Permission.manageUsers,
  },
  Role.technicalManager: {
    Permission.readTag,
    Permission.writeTag,
    Permission.formatTag,
    Permission.lockTag,
  },
  Role.operator: {Permission.readTag},
};

/// UI gate only. The backend must enforce the same matrix on every API call.
bool can(Role role, Permission p) => _matrix[role]?.contains(p) ?? false;
