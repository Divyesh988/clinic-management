/// Represents a semantic application version with an optional build number.
/// Format: `major.minor.patch+buildNumber` (e.g., `1.0.0+1`, `1.1.0+2`).
class AppVersion implements Comparable<AppVersion> {
  final int major;
  final int minor;
  final int patch;
  final int buildNumber;
  final String rawVersion;

  const AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.buildNumber = 0,
    required this.rawVersion,
  });

  /// Parses a version string like "1.0.0", "1.0.0+1", or "v1.0.0".
  /// If [buildNumber] is provided separately (e.g. from PackageInfo), it overrides
  /// or defaults if not present in the string.
  factory AppVersion.parse(String versionString, [int? explicitBuildNumber]) {
    final clean = versionString.trim().replaceFirst(RegExp(r'^[vV]'), '');
    int parsedBuild = explicitBuildNumber ?? 0;
    String baseVersion = clean;

    if (clean.contains('+')) {
      final parts = clean.split('+');
      baseVersion = parts[0];
      if (explicitBuildNumber == null && parts.length > 1) {
        parsedBuild = int.tryParse(parts[1]) ?? 0;
      }
    }

    final segments = baseVersion.split('.');
    final int major = segments.isNotEmpty ? (int.tryParse(segments[0]) ?? 0) : 0;
    final int minor = segments.length > 1 ? (int.tryParse(segments[1]) ?? 0) : 0;
    final int patch = segments.length > 2 ? (int.tryParse(segments[2]) ?? 0) : 0;

    return AppVersion(
      major: major,
      minor: minor,
      patch: patch,
      buildNumber: parsedBuild,
      rawVersion: versionString,
    );
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return buildNumber.compareTo(other.buildNumber);
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;
  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppVersion &&
          runtimeType == other.runtimeType &&
          major == other.major &&
          minor == other.minor &&
          patch == other.patch &&
          buildNumber == other.buildNumber;

  @override
  int get hashCode => Object.hash(major, minor, patch, buildNumber);

  String get displayString => '$major.$minor.$patch${buildNumber > 0 ? ' (build $buildNumber)' : ''}';

  @override
  String toString() => '$major.$minor.$patch+$buildNumber';
}
