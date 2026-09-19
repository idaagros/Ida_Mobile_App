// lib/services/geo_utils.dart
//
// Mirrors backend/src/services/geoUtils.js's polygonAreaAcres exactly
// (same equirectangular-projection + shoelace-formula approach), so
// the live area shown while drawing a boundary on the phone matches
// what the server will compute and store on save — no surprise
// mismatch after saving. There are now three independent
// implementations of this same small formula (backend Node, web JS,
// this Dart one) — all deliberately kept in sync rather than shared,
// since each runs in a completely different runtime.
import 'dart:math';

const double _earthRadiusM = 6378137;
const double _sqmPerAcre = 4046.8564224;

double _toRad(double deg) => deg * pi / 180;

/// points: ordered list of [lng, lat] pairs (same order GeoJSON uses),
/// NOT required to be explicitly closed (first == last).
double polygonAreaAcres(List<List<double>> points) {
  if (points.length < 3) return 0;
  final meanLat = points.map((p) => p[1]).reduce((a, b) => a + b) / points.length;
  final cosLat = cos(_toRad(meanLat));
  final projected = points
      .map((p) => [
            _toRad(p[0]) * _earthRadiusM * cosLat, // x
            _toRad(p[1]) * _earthRadiusM, // y
          ])
      .toList();
  double area = 0;
  for (var i = 0; i < projected.length; i++) {
    final j = (i + 1) % projected.length;
    area += projected[i][0] * projected[j][1] - projected[j][0] * projected[i][1];
  }
  final sqm = area.abs() / 2;
  return sqm / _sqmPerAcre;
}
