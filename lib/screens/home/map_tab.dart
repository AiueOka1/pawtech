import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pawtech/providers/dog_provider.dart';
import 'package:pawtech/widgets/map_placeholder.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  String? _selectedDogId;
  String _geofenceLocation = 'current'; // Default to current location
  double _geofenceRadius = 100.0; // Default radius

  @override
  void initState() {
    super.initState();
    _loadGeofenceSettings();
  }

  Future<void> _loadGeofenceSettings() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      final map = (data?['geofenceSettings'] as Map<String, dynamic>?) ?? {};
      final savedLocation = map['location'] as String?;
      final savedRadius = (map['radius'] as num?)?.toDouble();

      if (!mounted) return;
      setState(() {
        if (savedLocation == 'current' || savedLocation == 'city_hall') {
          _geofenceLocation = savedLocation!;
        }
        if (savedRadius != null && savedRadius >= 50 && savedRadius <= 2000) {
          _geofenceRadius = savedRadius;
        }
      });
    } catch (e) {
      // Silent fail -> keep defaults
      debugPrint('Failed to load geofence settings: $e');
    }
  }

  Future<void> _saveGeofenceSettings() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(
            {
              'geofenceSettings': {
                'location': _geofenceLocation,
                'radius': _geofenceRadius,
              }
            },
            SetOptions(merge: true),
          );
    } catch (e) {
      debugPrint('Failed to save geofence settings: $e');
    }
  }

  void _showRadiusDialog() {
    showDialog(
      context: context,
      builder: (context) {
        double tempRadius = _geofenceRadius;
        final TextEditingController radiusController = TextEditingController(
          text: tempRadius.toInt().toString(),
        );
        bool useSlider = true; // Toggle between slider and manual input

        return AlertDialog(
          title: const Text('Set Geofence Radius'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Switch(
                        value: useSlider,
                        onChanged: (v) => setDialogState(() => useSlider = v),
                      ),
                      const SizedBox(width: 8),
                      Text(useSlider ? 'Use Slider' : 'Manual Input'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (useSlider) ...[
                    Slider(
                      value: tempRadius,
                      min: 50,
                      max: 2000,
                      divisions: 39,
                      label: '${tempRadius.toInt()}',
                      onChanged: (value) {
                        setDialogState(() {
                          tempRadius = value;
                          radiusController.text = value.toInt().toString();
                        });
                      },
                    ),
                  ] else ...[
                    TextField(
                      controller: radiusController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Radius (meters)',
                        hintText: 'Enter radius between 50-2000',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        suffixText: 'm',
                      ),
                      onChanged: (value) {
                        final parsed = double.tryParse(value);
                        if (parsed != null && parsed >= 50 && parsed <= 2000) {
                          setDialogState(() {
                            tempRadius = parsed;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Range: 50 - 2000 meters',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                // Validate manual input if using text field
                if (!useSlider) {
                  final inputValue = double.tryParse(radiusController.text);
                  if (inputValue == null || inputValue < 50 || inputValue > 2000) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a valid radius between 50-2000 meters'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  tempRadius = inputValue;
                }
                
                setState(() {
                  _geofenceRadius = tempRadius;
                });
                await _saveGeofenceSettings();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Set'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dogs = context.watch<DogProvider>().dogs;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  decoration: InputDecoration(
                    labelText: 'Select Dog',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  value: _selectedDogId,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Dogs'),
                    ),
                    ...dogs.map(
                      (dog) => DropdownMenuItem<String?>(
                        value: dog.id,
                        child: Text(dog.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedDogId = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _showRadiusDialog,
                child: const Text('Set Radius'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text('Geofence Location:'),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _geofenceLocation,
                items: const [
                  DropdownMenuItem(
                    value: 'current',
                    child: Text('Current Location'),
                  ),
                  DropdownMenuItem(
                    value: 'city_hall',
                    child: Text('City Hall Location'),
                  ),
                ],
                onChanged: (value) async {
                  if (value == null) return;
                  setState(() {
                    _geofenceLocation = value;
                  });
                  await _saveGeofenceSettings();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              RealMapView(
                selectedDogId: _selectedDogId,
                dogs: _selectedDogId == null
                    ? dogs
                    : dogs.where((dog) => dog.id == _selectedDogId).toList(),
                geofences: [], // 🛠 FIX: Pass empty list for now
                geofenceLocation: _geofenceLocation,
                geofenceRadius: _geofenceRadius,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
