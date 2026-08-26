import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Geofence position error: $e');
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to get current GPS location.')),
        );
      }
      return false;
    }

    try {
      final url = '${ApiService.baseUrl}/globals/branch-geo-settings';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final locations = data['locations'] as List?;
        if (locations != null && locations.isNotEmpty) {
          for (var loc in locations) {
            final lat = loc['latitude'];
            final lng = loc['longitude'];
            final radiusStr = loc['radius'];
            final radius = (radiusStr is num) ? radiusStr.toDouble() : 100.0;
            
            if (lat != null && lng != null) {
              final double latD = (lat is num) ? lat.toDouble() : double.parse(lat.toString());
              final double lngD = (lng is num) ? lng.toDouble() : double.parse(lng.toString());
              
              final distance = Geolocator.distanceBetween(
                position.latitude, position.longitude,
                latD, lngD
              );
              
              if (distance <= radius) {
                return true; // Inside a branch!
              }
            }
          }
          
          if (!silent && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You are not inside any branch location circle.')),
            );
          }
          return false;
        }
      }
    } catch (e) {
      debugPrint('Geofence API error: $e');
    }

    if (!silent && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to verify location against branch circles.')),
      );
    }
    return false;
  }
}
