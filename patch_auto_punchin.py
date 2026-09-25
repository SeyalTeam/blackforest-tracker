import re

filepath = "/Users/castromurugan/Documents/Blackforest/tracker/lib/profile_page.dart"
with open(filepath, "r") as f:
    content = f.read()

# 1. Add _autoPunchInFired to state variables
content = content.replace(
    "bool _autoPunchOutFired = false; // prevents double-fire on same geofence exit",
    "bool _autoPunchOutFired = false; // prevents double-fire on same geofence exit\n  bool _autoPunchInFired = false;"
)

# 2. Update _fetchAttendance start/stop watcher logic
old_watcher_logic = """      // Start or stop the geofence watcher based on session state
      if (activeSessionFound) {
        _autoPunchOutFired = false; // reset so a fresh punch-in can trigger auto punch-out
        _startGeofenceWatcher();
      } else {
        _stopGeofenceWatcher();
      }"""
new_watcher_logic = """      // Start or stop the geofence watcher based on session state
      if (activeSessionFound) {
        _autoPunchOutFired = false; // reset so a fresh punch-in can trigger auto punch-out
      } else {
        // When there's no active session, we still want the watcher to run for auto punch-in
      }
      _startGeofenceWatcher();"""
content = content.replace(old_watcher_logic, new_watcher_logic)

# 3. Modify _submitPunchIn signature and calls
content = content.replace(
    "Future<void> _submitPunchIn() async {",
    "Future<void> _submitPunchIn({bool isAuto = false}) async {"
)
content = content.replace(
    "await _punchIn(mediaId);",
    "await _punchIn(mediaId, isAuto: isAuto);"
)
content = content.replace(
    "onPressed: _isProcessingPunch ? null : _submitPunchIn,",
    "onPressed: _isProcessingPunch ? null : () => _submitPunchIn(isAuto: false),"
)

# 4. Modify _punchIn signature and payload
content = content.replace(
    "Future<void> _punchIn(String mediaId) async {",
    "Future<void> _punchIn(String mediaId, {bool isAuto = false}) async {"
)
new_payload = """    final newActivity = {
      'type': 'session',
      'punchIn': now.toUtc().toIso8601String(),
      'status': 'active',
      'capturedImage': mediaId,
      'punchInType': isAuto ? 'auto' : 'manual',
      if (position != null) 'latitude': position.latitude,
      if (position != null) 'longitude': position.longitude,
    };"""
old_payload = """    final newActivity = {
      'type': 'session',
      'punchIn': now.toUtc().toIso8601String(),
      'status': 'active',
      'capturedImage': mediaId,
      if (position != null) 'latitude': position.latitude,
      if (position != null) 'longitude': position.longitude,
    };"""
content = content.replace(old_payload, new_payload)

# 5. Modify _startGeofenceWatcher and add _autoCaptureAndPunchIn
old_start_geofence = """  void _startGeofenceWatcher() {
    // Already running — don't create a second timer
    if (_geofenceTimer != null && (_geofenceTimer!.isActive)) return;

    _geofenceTimer?.cancel();
    _geofenceTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (!mounted || !_hasActiveSession || _autoPunchOutFired) return;

      final isInside = await GeofenceUtil.isInsideAnyBranch(context, silent: true);
      if (!isInside && mounted && _hasActiveSession && !_autoPunchOutFired) {
        _autoPunchOutFired = true;
        await _autoPunchOut();
      }
    });
  }"""
new_start_geofence = """  void _startGeofenceWatcher() {
    // Already running — don't create a second timer
    if (_geofenceTimer != null && (_geofenceTimer!.isActive)) return;

    _geofenceTimer?.cancel();
    _geofenceTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (!mounted) return;

      final isInside = await GeofenceUtil.isInsideAnyBranch(context, silent: true);
      
      if (_hasActiveSession) {
        if (!isInside && mounted && !_autoPunchOutFired) {
          _autoPunchOutFired = true;
          await _autoPunchOut();
        }
      } else {
        if (isInside && mounted && !_autoPunchInFired) {
          _autoPunchInFired = true;
          await _autoCaptureAndPunchIn();
        } else if (!isInside) {
          _autoPunchInFired = false;
        }
      }
    });
  }

  Future<void> _autoCaptureAndPunchIn() async {
    if (_hasActiveSession || _isProcessingPunch) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Auto punch-in triggered. Please take a selfie.'),
          backgroundColor: Colors.blue[600],
          duration: const Duration(seconds: 4),
        ),
      );
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    if (!mounted) return;
    final XFile? capturedFile = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraPage(cameras: cameras, isFaceCapture: true),
      ),
    );

    if (capturedFile != null) {
      setState(() {
        _capturedPunchInPhoto = File(capturedFile.path);
      });
      await _submitPunchIn(isAuto: true);
    } else {
      // If they canceled the camera, let's reset the flag so they can be prompted again
      // when they leave and re-enter, or we could leave it true so it doesn't prompt continuously
      // while they remain inside. Leaving it true is safer so we don't spam.
    }
  }"""
content = content.replace(old_start_geofence, new_start_geofence)

with open(filepath, "w") as f:
    f.write(content)

print("Patch applied")
