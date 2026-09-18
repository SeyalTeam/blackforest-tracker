import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';

class GeofenceUtil {
  static Future<bool> isInsideAnyBranch(BuildContext context, {bool silent = false}) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled. Please enable GPS.')),
        );
      }
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!silent && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied.')),
          );
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are permanently denied.')),
        );
      }
      return false;
    }

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('Geofence getCurrentPosition error: $e. Trying last known position...');
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }

    if (position == null) {
      debugPrint('Geofence: Failed to get any GPS position.');
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to get current GPS location.')),
        );
      }
      return false;
    }

    try {
      final data = await ApiService.instance.fetchBranchGeoSettings();
      final locations = data['locations'] as List?;
      if (locations != null && locations.isNotEmpty) {
        double nearestDistance = double.infinity;
        double nearestRadius = 100.0;
        for (var loc in locations) {
          final lat = loc['latitude'];
          final lng = loc['longitude'];
          final radiusStr = loc['radius'];
          final radius = (radiusStr is num) ? radiusStr.toDouble() : 100.0;
          // Add 30m indoor GPS drift tolerance
          final effectiveRadius = radius + 30.0;
          
          if (lat != null && lng != null) {
            final double latD = (lat is num) ? lat.toDouble() : double.parse(lat.toString());
            final double lngD = (lng is num) ? lng.toDouble() : double.parse(lng.toString());
            
            final distance = Geolocator.distanceBetween(
              position.latitude, position.longitude,
              latD, lngD
            );
            
            if (distance < nearestDistance) {
              nearestDistance = distance;
              nearestRadius = effectiveRadius;
            }
            
            if (distance <= effectiveRadius) {
              debugPrint('Geofence: INSIDE branch! distance: ${distance.toStringAsFixed(1)}m <= effective radius: ${effectiveRadius}m');
              return true; // Inside a branch!
            }
          }
        }
        debugPrint('Geofence: OUTSIDE all branches. Nearest: ${nearestDistance.toStringAsFixed(1)}m, allowed radius: ${nearestRadius}m');
        
        if (!silent && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Not inside any branch. Nearest is ${nearestDistance.toStringAsFixed(1)}m away.')),
          );
        }
        return false;
      }
    } catch (e) {
      debugPrint('Geofence API error: $e');
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Geofence Error: $e')),
        );
      }
      return false;
    }

    if (!silent && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to verify location against branch circles.')),
      );
    }
    return false;
  }
}
