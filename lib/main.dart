import "dart:async" show StreamSubscription;
import "dart:convert" show jsonDecode;
import "dart:math" as math;
import "package:flutter/material.dart";
import "package:flutter_compass/flutter_compass.dart";
import "package:location/location.dart";
import "package:vector_math/vector_math.dart" show Vector2, radians;
import "package:http/http.dart" as http;

const biggerFont = TextStyle(fontSize: 24);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Vector2? _target;
  final List<Vector2> _placesCache = [];
  final _random = math.Random();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "TokoThere",
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _target != null ? _getCompass() : Container(),
            ElevatedButton(
                onPressed: () => _fetchLocation(),
                child: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("Locate Place", style: biggerFont),
                )),
          ],
        ),
      ),
    );
  }

  // Uses this query:
  // [out:json][timeout:10];
  // (
  //   node(around:$DISTANCE,$LAT,$LON)[name];
  // );
  // out skel noids;
  Future<void> _fetchLocation() async {
    if (_placesCache.isNotEmpty) {
      _chooseRandom();
      return;
    }

    final current = await Location.instance.getLocation();
    const distance = 1000;
    final response = await http.get(Uri.parse(
        "https://overpass-api.de/api/interpreter?data=%5Bout%3Ajson%5D%5Btimeout%3A10%5D%3B%28node%28around%3A$distance%2C${current.latitude}%2C${current.longitude}%29%5Bname%5D%3B%29%3Bout%20skel%20noids%3B"));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      for (final node in data["elements"]) {
        _placesCache.add(Vector2(node["lon"], node["lat"]));
      }
      _chooseRandom();
    } else {
      throw Exception("Failed to fetch");
    }
  }

  void _chooseRandom() {
    if (_placesCache.isEmpty) return;
    setState(() {
      _target = _placesCache[_random.nextInt(_placesCache.length)];
    });
  }

  Widget _getCompass() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 64.0),
      child: Compass(
        target: _target!,
      ),
    );
  }
}

class Compass extends StatefulWidget {
  const Compass({
    super.key,
    required this.target,
  });

  final Vector2 target;

  @override
  State<Compass> createState() => _CompassState();
}

class _CompassState extends State<Compass> {
  Vector2 _current = Vector2.zero();
  StreamSubscription<LocationData>? _locationStream;

  @override
  void initState() {
    _locationStream =
        Location.instance.onLocationChanged.listen((LocationData location) {
      _current = Vector2(location.longitude!, location.latitude!);
    });
    super.initState();
  }

  @override
  void dispose() {
    _locationStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CompassEvent>(
      stream: FlutterCompass.events,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('Error reading heading: ${snapshot.error}');
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        double? northDir = snapshot.data!.heading;
        if (northDir == null) {
          return const Center(
            child: Text("Device does not have sensors!"),
          );
        }

        northDir = radians(northDir);
        final diffCoords = widget.target - _current;
        final targetDir = math.atan2(diffCoords.y, diffCoords.x);
        final diffKM = Vector2(
            40075 * diffCoords.x * math.cos(diffCoords.y) / 360,
            diffCoords.y * 111.32);

        return Material(
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          color: Colors.black26,
          elevation: 4.0,
          child: Container(
            padding: const EdgeInsets.all(16.0),
            alignment: Alignment.center,
            child: Column(
              children: [
                Transform.rotate(
                    angle: targetDir - northDir - math.pi / 2,
                    child: const Icon(Icons.arrow_right_alt,
                        size: 275, color: Colors.white)),
                Transform.translate(
                  offset: const Offset(0, -15),
                  child: Text("${(diffKM.length * 1000).round()}m",
                      style: biggerFont),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
