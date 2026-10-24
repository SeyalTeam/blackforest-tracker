import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';

class GeofenceResult {
  final bool isInside;
  final bool isOutside;
  final Position? position;
  final String? branchName;
  final String? branchId;
  final double? distance;
  final double? radius;
  final double? accuracy;
  final String? errorMessage;
  final bool hasError;

  const GeofenceResult({
    required this.isInside,
    this.isOutside = false,
    this.position,
    this.branchName,
    this.branchId,
    this.distance,
    this.radius,
    this.accuracy,
    this.errorMessage,
    this.hasError = false,
  });
}

class GeofenceUtil {
  static Map<String, dynamic>? _cachedBranchGeoSettings;
  static DateTime? _lastBranchSettingsFetch;

  /// Checks whether the device is inside any branch geofence circle.
  /// Can be called from any background or foreground service without a BuildContext.
  static Future<GeofenceResult> checkLocationAndGeofence({
    Position? existingPosition,
  }) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('GeofenceUtil: Location services are disabled.');
      return const GeofenceResult(
        isInside: false,
        isOutside: false,
        hasError: true,
        errorMessage: 'Location services are disabled. Please enable GPS.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('GeofenceUtil: Location permissions denied.');
        return const GeofenceResult(
          isInside: false,
          isOutside: false,
          hasError: true,
          errorMessage: 'Location permissions are denied.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('GeofenceUtil: Location permissions permanently denied.');
      return const GeofenceResult(
        isInside: false,
        isOutside: false,
        hasError: true,
        errorMessage: 'Location permissions are permanently denied.',
      );
    }

    Position? position = existingPosition;
    if (position == null) {
      try {
        // First try high accuracy GPS fix
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 6));
      } catch (e) {
        debugPrint('GeofenceUtil getCurrentPosition high accuracy failed/timeout: $e. Trying medium...');
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
            ),
          ).timeout(const Duration(seconds: 4));
        } catch (_) {
          try {
            final last = await Geolocator.getLastKnownPosition();
            if (last != null && last.timestamp != null) {
              final age = DateTime.now().difference(last.timestamp);
              // Only accept last known if it was recorded within last 2 minutes
              if (age.inMinutes < 2) {
                position = last;
                debugPrint('GeofenceUtil: Using recent lastKnownPosition (${age.inSeconds}s old).');
              } else {
                debugPrint('GeofenceUtil: Ignoring stale lastKnownPosition (${age.inMinutes}m old).');
              }
            }
          } catch (_) {}
        }
      }
    }

    if (position == null) {
      debugPrint('GeofenceUtil: Failed to get any fresh GPS position.');
      return const GeofenceResult(
        isInside: false,
        isOutside: false,
        hasError: true,
        errorMessage: 'Failed to get current GPS location.',
      );
    }

    debugPrint(
        'GeofenceUtil: Got position (${position.latitude}, ${position.longitude}) with accuracy: ${position.accuracy.toStringAsFixed(1)}m');

    try {
      Map<String, dynamic>? data;
      final now = DateTime.now();
      // Use cached settings if fetched within last 10 minutes
      if (_cachedBranchGeoSettings != null &&
          _lastBranchSettingsFetch != null &&
          now.difference(_lastBranchSettingsFetch!).inMinutes < 10) {
        data = _cachedBranchGeoSettings;
      } else {
        try {
          data = await ApiService.instance
              .fetchBranchGeoSettings()
              .timeout(const Duration(seconds: 6));
          _cachedBranchGeoSettings = data;
          _lastBranchSettingsFetch = now;
        } catch (e) {
          debugPrint('GeofenceUtil: Network fetch for branch settings failed ($e), falling back to cache.');
          data = _cachedBranchGeoSettings;
        }
      }

      if (data == null) {
        debugPrint('GeofenceUtil: No branch settings available from network or cache.');
        return GeofenceResult(
          isInside: false,
          isOutside: false,
          position: position,
          accuracy: position.accuracy,
          hasError: true,
          errorMessage: 'Unable to load branch settings. Check network connection.',
        );
      }

      final locations = data['locations'] as List?;
      if (locations != null && locations.isNotEmpty) {
        double nearestDistance = double.infinity;
        double nearestRadius = 100.0;
        String? nearestBranchName;
        String? nearestBranchId;

        bool anyInside = false;
        bool allOutside = true;
        String? matchedBranchName;
        String? matchedBranchId;
        double? matchedDistance;
        double? matchedEffectiveRadius;

        for (var loc in locations) {
          final lat = loc['latitude'];
          final lng = loc['longitude'];
          final radiusStr = loc['radius'];
          final radius = (radiusStr is num) ? radiusStr.toDouble() : 100.0;
          
          // Indoor GPS drift tolerance:
          // Base tolerance is 60m. If accuracy uncertainty is > 30m, add the delta smoothly up to 60m.
          final double extraAccuracy = (position.accuracy > 30.0)
              ? (position.accuracy - 30.0).clamp(0.0, 60.0)
              : 0.0;
          final double effectiveRadius = radius + 60.0 + extraAccuracy;
          // Exit hysteresis: requires user to be an additional 40m beyond the entry circle
          final double exitRadius = effectiveRadius + 40.0;

          if (lat != null && lng != null) {
            final double latD =
                (lat is num) ? lat.toDouble() : double.parse(lat.toString());
            final double lngD =
                (lng is num) ? lng.toDouble() : double.parse(lng.toString());

            final distance = Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              latD,
              lngD,
            );

            final branchName = loc['name'] ?? loc['branchName'] ?? '';
            final branchId = (loc['branch'] is Map ? loc['branch']['id'] : loc['branch'])?.toString() ??
                loc['branchId']?.toString() ?? '';

            if (distance < nearestDistance) {
              nearestDistance = distance;
              nearestRadius = effectiveRadius;
              nearestBranchName = branchName;
              nearestBranchId = branchId;
            }

            if (distance <= effectiveRadius) {
              anyInside = true;
              allOutside = false;
              matchedBranchName = branchName;
              matchedBranchId = branchId;
              matchedDistance = distance;
              matchedEffectiveRadius = effectiveRadius;
              break;
            } else if (distance <= exitRadius) {
              // In the hysteresis buffer zone (between effectiveRadius and exitRadius).
              // Neither triggers a new punch in nor triggers an auto punch out.
              allOutside = false;
            }
          }
        }

        if (anyInside) {
          debugPrint(
              'GeofenceUtil: INSIDE branch "$matchedBranchName"! distance: ${matchedDistance?.toStringAsFixed(1)}m <= effective: ${matchedEffectiveRadius?.toStringAsFixed(1)}m');
          return GeofenceResult(
            isInside: true,
            isOutside: false,
            position: position,
            accuracy: position.accuracy,
            branchName: matchedBranchName,
            branchId: matchedBranchId,
            distance: matchedDistance,
            radius: matchedEffectiveRadius,
          );
        }

        // Only confirm outside if all branches are beyond exitRadius AND GPS accuracy is reliable (<= 100m)
        final bool confirmedOutside = allOutside && (position.accuracy <= 100.0);

        debugPrint(
            'GeofenceUtil: OUTSIDE evaluation -> isInside: false, isOutside: $confirmedOutside, nearest: ${nearestDistance.toStringAsFixed(1)}m, accuracy: ${position.accuracy.toStringAsFixed(1)}m');

        return GeofenceResult(
          isInside: false,
          isOutside: confirmedOutside,
          position: position,
          accuracy: position.accuracy,
          branchName: nearestBranchName,
          branchId: nearestBranchId,
          distance: nearestDistance,
          radius: nearestRadius,
          errorMessage:
              'Not inside any branch. Nearest is ${nearestDistance.toStringAsFixed(1)}m away.',
        );
      }
    } catch (e) {
      debugPrint('GeofenceUtil API error: $e');
      return GeofenceResult(
        isInside: false,
        isOutside: false,
        position: position,
        accuracy: position.accuracy,
        hasError: true,
        errorMessage: 'Geofence API error: $e',
      );
    }

    return GeofenceResult(
      isInside: false,
      isOutside: false,
      position: position,
      accuracy: position?.accuracy,
      hasError: true,
      errorMessage: 'Unable to verify location against branch circles.',
    );
  }

  /// Backward-compatible check that can accept an optional BuildContext for snackbars.
  static Future<bool> isInsideAnyBranch(
    BuildContext? context, {
    bool silent = false,
    Position? position,
  }) async {
    final result = await checkLocationAndGeofence(existingPosition: position);

    if (!result.isInside && !silent && context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Not inside any branch area.'),
        ),
      );
    }

    return result.isInside;
  }
}
