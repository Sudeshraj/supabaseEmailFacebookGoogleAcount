import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class CompanyLocationScreen extends StatefulWidget {
  final void Function(String address, double lat, double lng) onNext;
  final PageController controller;

  const CompanyLocationScreen({
    super.key,
    required this.onNext,
    required this.controller,
  });

  @override
  State<CompanyLocationScreen> createState() => _CompanyLocationScreenState();
}

class _CompanyLocationScreenState extends State<CompanyLocationScreen> {
  GoogleMapController? mapController;
  LatLng? _selectedLatLng;
  String? _selectedAddress;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    Position pos = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(accuracy: LocationAccuracy.high),
    );

    setState(() {
      _selectedLatLng = LatLng(pos.latitude, pos.longitude);
      _loading = false;
    });
  }

  Future<void> _onMapTap(LatLng latLng) async {
    setState(() {
      _selectedLatLng = latLng;
      _selectedAddress = null;
    });

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      );
      if (placemarks.isNotEmpty) {
        Placemark p = placemarks.first;
        setState(() {
          _selectedAddress =
              "${p.street}, ${p.locality}, ${p.administrativeArea}, ${p.country}";
        });
      }
    } catch (e) {
      debugPrint("Error reverse geocoding: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double maxWidth = screenWidth > 700 ? 480 : double.infinity;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            widget.controller.previousPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.ease,
            );
          },
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1877F3)),
            )
          : SafeArea(
              child: Center(
                child: Container(
                  width: maxWidth,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: screenWidth > 700
                        ? const Color(0xFF131C27)
                        : Colors.transparent,
                    borderRadius: screenWidth > 700
                        ? BorderRadius.circular(16)
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Select your company location",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Move and tap on the map to set your company address.",
                        style: TextStyle(fontSize: 15, color: Colors.white70),
                      ),
                      const SizedBox(height: 16),

                      // 🗺️ Map View
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: GoogleMap(
                            onMapCreated: (controller) =>
                                mapController = controller,
                            initialCameraPosition: CameraPosition(
                              target:
                                  _selectedLatLng ??
                                  const LatLng(7.8731, 80.7718),
                              zoom: 15,
                            ),
                            onTap: _onMapTap,
                            markers: _selectedLatLng != null
                                ? {
                                    Marker(
                                      markerId: const MarkerId("selected"),
                                      position: _selectedLatLng!,
                                    ),
                                  }
                                : {},
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ✅ View selected details (Address + Lat + Lng)
                      if (_selectedLatLng != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_selectedAddress != null)
                                Text(
                                  "📍 $_selectedAddress",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                  ),
                                ),
                              // const SizedBox(height: 4),
                              // Text(
                              //   "🌐 Latitude: ${_selectedLatLng!.latitude.toStringAsFixed(6)}",
                              //   style: const TextStyle(
                              //     color: Colors.white70,
                              //     fontSize: 14,
                              //   ),
                              // ),
                              // Text(
                              //   "🌐 Longitude: ${_selectedLatLng!.longitude.toStringAsFixed(6)}",
                              //   style: const TextStyle(
                              //     color: Colors.white70,
                              //     fontSize: 14,
                              //   ),
                              // ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 24),

                      // ✅ Confirm Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _selectedLatLng != null
                              ? () => widget.onNext(
                                  _selectedAddress ?? "No address found",
                                  _selectedLatLng!.latitude,
                                  _selectedLatLng!.longitude,
                                )
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1877F3),
                            disabledBackgroundColor: Colors.white12,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          child: const Text(
                            "Confirm location",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
